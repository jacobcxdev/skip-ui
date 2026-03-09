// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
package skip.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring.DampingRatioNoBouncy
import androidx.compose.animation.core.Spring.StiffnessHigh
import androidx.compose.animation.core.Spring.StiffnessLow
import androidx.compose.animation.core.Spring.StiffnessMedium
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitDragOrCancellation
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitTouchSlopOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.BiasAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt


/**
 * Data class holding extracted swipe action info.
 */
data class SwipeActionData(
    val label: String?,
    val iconName: String?,
    val role: Int?,       // ButtonRole raw value: 1=destructive, 2=cancel, 3=confirm, 4=close
    val tint: Any?,       // skip.ui.Color? — resolved to Compose color at render time
    val action: () -> Unit
) {
    val isDestructive: Boolean get() = role == 1

    /** Resolve the action's background color. Must be called from @Composable context. */
    @Composable
    fun resolveColor(): Color {
        return when {
            tint != null -> (tint as? skip.ui.Color)?.colorImpl() ?: Color(0xFF8E8E93.toInt())
            isDestructive -> Color(0xFFFF3B30.toInt())  // iOS system red
            else -> Color(0xFF8E8E93.toInt())           // iOS system grey
        }
    }
}

/** Post-gesture animation target. */
private sealed class SettleAction {
    object Close : SettleAction()
    data class Detent(val target: Float) : SettleAction()
    data class Trigger(val target: Float, val actions: kotlin.collections.List<SwipeActionData>) : SettleAction()
    object None : SettleAction()
}

private const val ACTION_BUTTON_WIDTH_DP = 74
private const val MAX_BUTTON_WIDTH_DP = 120
private const val MAX_DETENT_RATIO = 0.50f
// iOS uses 50pt/s threshold (from _swipeRecognizerEnded disassembly: 0x4049000000000000 = 50.0)
private const val FLING_VELOCITY_THRESHOLD_DP = 50

// iOS confirmation distance constants (from UISwipeOccurrence disassembly, build 23D8133)
private const val NON_DESTRUCTIVE_RATIO = 0.525f
private const val NON_DESTRUCTIVE_MIN_GAP_DP = 20
private const val DESTRUCTIVE_TRAILING_INSET_DP = 64
private const val DESTRUCTIVE_LEADING_INSET_DP = 29

private val SETTLE_SPRING = spring<Float>(dampingRatio = DampingRatioNoBouncy, stiffness = StiffnessLow)
private val SNAP_SPRING = spring<Float>(dampingRatio = DampingRatioNoBouncy, stiffness = StiffnessHigh)
internal val COLLAPSE_SPRING = spring<Float>(dampingRatio = DampingRatioNoBouncy, stiffness = StiffnessMedium)

/**
 * Compute the iOS-faithful completion threshold (confirmationDistance) in pixels.
 *
 * Non-destructive: max(cellWidth × 0.525, openThreshold + 20dp)
 * Destructive trailing: cellWidth - 64dp
 * Destructive leading: cellWidth - 29dp
 *
 * Source: UISwipeOccurrence confirmationDistanceForPrimaryActionInSwipeActionPullView:
 */
private fun completionThresholdPx(
    rowWidthPx: Int,
    detentPx: Float,
    firstIsDestructive: Boolean,
    isLeadingEdge: Boolean,
    nonDestructiveMinGapPx: Float,
    destructiveLeadingInsetPx: Float,
    destructiveTrailingInsetPx: Float
): Float {
    return if (firstIsDestructive) {
        val insetPx = if (isLeadingEdge) destructiveLeadingInsetPx else destructiveTrailingInsetPx
        (rowWidthPx - insetPx).coerceIn(detentPx, rowWidthPx.toFloat())
    } else {
        maxOf(
            rowWidthPx * NON_DESTRUCTIVE_RATIO,
            detentPx + nonDestructiveMinGapPx
        ).coerceAtMost(rowWidthPx.toFloat())
    }
}

/**
 * Wraps content with a height-growth animation from 0 to full over [durationMillis] ms.
 * Used for newly inserted items during a destructive delete so that survivors
 * with tween(0) placement track the growth frame-by-frame.
 */
@Composable
internal fun HeightGrowthBox(
    durationMillis: Int = 350,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val fraction = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        fraction.animateTo(1f, androidx.compose.animation.core.tween(durationMillis = durationMillis))
    }
    Box(
        modifier = modifier
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints)
                val h = (placeable.height * fraction.value).roundToInt().coerceAtLeast(0)
                layout(placeable.width, h) {
                    placeable.placeRelative(0, 0)
                }
            }
            .clipToBounds()
    ) {
        content()
    }
}

/**
 * iOS-faithful swipe actions container for List rows.
 *
 * Three-state model: rest → detent → dismissed.
 * Supports multiple actions per edge, role-based colouring, tint overrides,
 * allowsFullSwipe control, and single-revealed-row coordination.
 */
@Composable
fun SwipeActionsBox(
    trailingActions: kotlin.collections.List<SwipeActionData>,
    leadingActions: kotlin.collections.List<SwipeActionData>,
    allowsFullSwipeTrailing: Boolean = true,
    allowsFullSwipeLeading: Boolean = true,
    modifier: Modifier = Modifier,
    activeSwipeKey: MutableState<Any?>,
    onDestructiveDeleteStart: (Any?) -> Unit,
    onDestructiveDeleteEnd: () -> Unit,
    itemKey: Any?,
    isReordering: Boolean = false,
    listState: LazyListState? = null,
    content: @Composable () -> Unit
) {
    val offsetX = remember(itemKey) { Animatable(0f) }
    var dragOffsetX by remember { mutableFloatStateOf(0f) }
    var isDragging by remember { mutableStateOf(false) }
    var rowWidthPx by remember { mutableIntStateOf(0) }
    var isActioning by remember { mutableStateOf(false) }
    var isSettling by remember { mutableStateOf(false) }
    val layoutDirection = LocalLayoutDirection.current
    val currentIsReordering by rememberUpdatedState(isReordering)
    val scope = rememberCoroutineScope()
    val heightFraction = remember(itemKey) { Animatable(1f) }
    var completionThreshold by remember { mutableFloatStateOf(Float.MAX_VALUE) }

    // Unified visual offset: drag state during drag, animatable during settle
    val visualOffset by remember { derivedStateOf { if (isDragging) dragOffsetX else offsetX.value } }
    val isRevealed by remember { derivedStateOf { visualOffset != 0f } }

    // Which edge is active based on offset direction
    val activeEdge by remember(layoutDirection) {
        derivedStateOf {
            when {
                visualOffset < 0f -> if (layoutDirection == LayoutDirection.Ltr) skip.ui.HorizontalEdge.trailing else skip.ui.HorizontalEdge.leading
                visualOffset > 0f -> if (layoutDirection == LayoutDirection.Ltr) skip.ui.HorizontalEdge.leading else skip.ui.HorizontalEdge.trailing
                else -> null
            }
        }
    }

    // Coordination: single-revealed-row
    LaunchedEffect(itemKey) {
        snapshotFlow { activeSwipeKey.value }
            .collect { activeKey ->
                if (activeKey != null && activeKey != itemKey && !isActioning && !isDragging) {
                    offsetX.animateTo(0f, SETTLE_SPRING)
                }
            }
    }

    // Coordination: scroll-dismissal
    LaunchedEffect(listState) {
        if (listState == null) return@LaunchedEffect
        snapshotFlow { listState.isScrollInProgress }
            .collect { scrolling ->
                if (scrolling && isRevealed && !isActioning && !isDragging && !isSettling) {
                    offsetX.animateTo(0f, SETTLE_SPRING)
                    if (activeSwipeKey.value == itemKey) activeSwipeKey.value = null
                }
            }
    }

    // Coordination: rotation/resize
    LaunchedEffect(itemKey) {
        snapshotFlow { rowWidthPx }
            .drop(1)
            .collect {
                if (isRevealed && !isActioning && !isDragging && !isSettling) {
                    offsetX.snapTo(0f)
                    if (activeSwipeKey.value == itemKey) activeSwipeKey.value = null
                }
            }
    }

    // Cleanup on disposal
    DisposableEffect(itemKey) {
        onDispose {
            if (activeSwipeKey.value == itemKey) activeSwipeKey.value = null
        }
    }

    Box(
        modifier
            .fillMaxWidth()
            .onSizeChanged { size -> rowWidthPx = size.width }
            // Height collapse for destructive actions: reduces reported height
            // without scaling content. Combined with clipToBounds, content is
            // clipped from bottom as the row collapses — matching iOS behavior
            // where row height animates to zero concurrently with the slide-off.
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints)
                val fraction = heightFraction.value
                val h = (placeable.height * fraction).roundToInt().coerceAtLeast(0)
                layout(placeable.width, h) {
                    placeable.placeRelative(0, 0)
                }
            }
            .clipToBounds()
            .semantics {
                customActions = (trailingActions + leadingActions).map { action ->
                    CustomAccessibilityAction(action.label ?: "Action") { action.action(); true }
                }
            }
    ) {
        // Layer 1: Action buttons background
        val currentActiveEdge = activeEdge
        if (currentActiveEdge != null) {
            val rawActions = if (currentActiveEdge == skip.ui.HorizontalEdge.trailing) trailingActions else leadingActions
            val allowsFullSwipe = if (currentActiveEdge == skip.ui.HorizontalEdge.trailing) allowsFullSwipeTrailing else allowsFullSwipeLeading
            // Clamp action count to fit row width (drop actions furthest from swipe edge)
            val abwPx = with(androidx.compose.ui.platform.LocalDensity.current) { ACTION_BUTTON_WIDTH_DP.dp.toPx() }
            val maxVisibleActions = if (rowWidthPx > 0 && abwPx > 0f) {
                (rowWidthPx / abwPx).toInt().coerceAtLeast(1)
            } else Int.MAX_VALUE
            val actions = if (rawActions.size > maxVisibleActions) rawActions.subList(0, maxVisibleActions) else rawActions
            ActionsBackground(
                actions = actions,
                revealPx = abs(visualOffset),
                rowWidthPx = rowWidthPx,
                isInCompletionZone = isActioning || (allowsFullSwipe && completionThreshold < Float.MAX_VALUE && abs(visualOffset) >= completionThreshold),
                onActionTap = { actionIndex ->
                    if (isRevealed && !isActioning) {
                        isActioning = true
                        val sign = if (visualOffset < 0f) -1f else 1f
                        val action = actions[actionIndex]
                        scope.launch {
                            try {
                                // Slide-off animation
                                val animJob = launch {
                                    offsetX.animateTo(sign * rowWidthPx.toFloat(), SETTLE_SPRING)
                                }
                                if (action.isDestructive) {
                                    // Signal list to use faster placement spring on surviving items
                                    onDestructiveDeleteStart(itemKey)
                                    try {
                                        // Destructive: collapse height concurrently with slide-off.
                                        // isActioning=true triggers zone c visual (full-width red,
                                        // label pinned to leading edge) via completionProgress spring.
                                        // Defer action.action() until BOTH animations complete so
                                        // the composable stays alive during the exit animation.
                                        val heightJob = launch { heightFraction.animateTo(0f, COLLAPSE_SPRING) }
                                        animJob.join()
                                        heightJob.join()
                                        try {
                                            action.action()
                                        } catch (e: Exception) {
                                            if (e is CancellationException) throw e
                                        }
                                    } finally {
                                        onDestructiveDeleteEnd()
                                    }
                                } else {
                                    // Non-destructive: fire action immediately, then reset
                                    try {
                                        action.action()
                                    } catch (e: Exception) {
                                        if (e is CancellationException) throw e
                                    }
                                    animJob.join()
                                    isActioning = false
                                    offsetX.snapTo(0f)
                                    if (activeSwipeKey.value == itemKey) activeSwipeKey.value = null
                                }
                            } catch (e: CancellationException) {
                                isActioning = false
                                throw e
                            }
                        }
                    }
                },
                edge = currentActiveEdge,
                layoutDirection = layoutDirection
            )
        }

        // Layer 2: Row content, offset horizontally
        Box(
            Modifier
                .offset { IntOffset(visualOffset.roundToInt(), 0) }
                .pointerInput(itemKey, layoutDirection) {
                    val actionButtonWidthPx = ACTION_BUTTON_WIDTH_DP.dp.toPx()
                    val flingVelocityThresholdPx = FLING_VELOCITY_THRESHOLD_DP.dp.toPx()
                    val nonDestructiveMinGapPx = NON_DESTRUCTIVE_MIN_GAP_DP.dp.toPx()
                    val destructiveTrailingInsetPx = DESTRUCTIVE_TRAILING_INSET_DP.dp.toPx()
                    val destructiveLeadingInsetPx = DESTRUCTIVE_LEADING_INSET_DP.dp.toPx()

                    coroutineScope {
                        val gestureScope = this
                        while (isActive) {
                            if (rowWidthPx <= 0) {
                                awaitPointerEventScope { awaitFirstDown() }
                                continue
                            }

                            val settle: SettleAction = try { awaitPointerEventScope {
                                if (currentIsReordering || isActioning) {
                                    awaitFirstDown()
                                    return@awaitPointerEventScope SettleAction.None
                                }

                                val down = awaitFirstDown(requireUnconsumed = false)
                                isActioning = false

                                val hasTrailing = trailingActions.isNotEmpty()
                                val hasLeading = leadingActions.isNotEmpty()
                                val slopPx = viewConfiguration.touchSlop

                                // Touch slop: accumulate displacement until it exceeds
                                // the platform's scaled touch slop.
                                var cumulativeX = 0f
                                var cumulativeY = 0f
                                var dragStarted = false
                                var slopDirectionX = 0f
                                var slopChange: androidx.compose.ui.input.pointer.PointerInputChange? = null

                                while (true) {
                                    val event = awaitPointerEvent()
                                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                    if (!change.pressed) break

                                    val delta = change.positionChange()
                                    cumulativeX += delta.x
                                    cumulativeY += delta.y

                                    if (abs(cumulativeX) > slopPx || abs(cumulativeY) > slopPx) {
                                        if (abs(cumulativeX) > abs(cumulativeY)) {
                                            // Horizontal drag
                                            val isLtr = layoutDirection == LayoutDirection.Ltr
                                            val towardTrailing = if (isLtr) cumulativeX < 0 else cumulativeX > 0
                                            val towardLeading = !towardTrailing
                                            val canSwipe = (towardTrailing && hasTrailing) || (towardLeading && hasLeading) || isRevealed
                                            if (canSwipe) {
                                                slopDirectionX = cumulativeX
                                                change.consume()
                                                dragStarted = true
                                                slopChange = change
                                            }
                                        }
                                        // Either way (horizontal accepted or vertical rejected), break slop loop
                                        break
                                    }
                                }

                                if (slopChange == null || !dragStarted) {
                                    if (isRevealed) return@awaitPointerEventScope SettleAction.Close
                                    return@awaitPointerEventScope SettleAction.None
                                }

                                // Drag phase
                                val velocityTracker = VelocityTracker()
                                activeSwipeKey.value = itemKey
                                val dragSign = if (offsetX.value != 0f) {
                                    if (offsetX.value < 0f) -1f else 1f
                                } else {
                                    if (slopDirectionX < 0f) -1f else 1f
                                }

                                // Don't apply slopDirectionX — preserves touch slop dead zone.
                                // The settle logic handles tiny swipes via >= startAbsOffset.
                                dragOffsetX = offsetX.value
                                isDragging = true

                                // Remember where gesture started (rest=0 vs detent=detentPx)
                                val startAbsOffset = abs(offsetX.value)

                                // Pre-compute thresholds for resistance + settle
                                val isLtr = layoutDirection == LayoutDirection.Ltr
                                val rawActiveActions = if (dragSign < 0f) {
                                    if (isLtr) trailingActions else leadingActions
                                } else {
                                    if (isLtr) leadingActions else trailingActions
                                }
                                // Clamp action count to fit row width
                                val maxActions = (rowWidthPx / actionButtonWidthPx).toInt().coerceAtLeast(1)
                                val activeActions = if (rawActiveActions.size > maxActions) rawActiveActions.subList(0, maxActions) else rawActiveActions

                                val detentPx = (actionButtonWidthPx * activeActions.size).toInt()
                                    .coerceAtMost((rowWidthPx * MAX_DETENT_RATIO).toInt()).toFloat()

                                // Compute iOS-faithful completion threshold
                                val firstIsDestructive = activeActions.firstOrNull()?.isDestructive ?: false
                                val isLeadingEdge = if (isLtr) dragSign > 0f else dragSign < 0f
                                val completionPx = completionThresholdPx(
                                    rowWidthPx, detentPx, firstIsDestructive, isLeadingEdge,
                                    nonDestructiveMinGapPx, destructiveLeadingInsetPx, destructiveTrailingInsetPx
                                )
                                // Update state for composable body's isInCompletionZone
                                completionThreshold = completionPx

                                val touchDownX = down.position.x
                                val slopDistance = slopPx

                                // Helper: has the drag offset reached the completion threshold?
                                // Uses absolute offset (matching iOS confirmationDistance).
                                fun isFingerInZoneC(rawOff: Float): Boolean {
                                    return abs(rawOff) >= completionPx
                                }

                                // Finger position tracked 1:1. Visual lags by slopDistance
                                // until the finger enters zone (c), which pins the row
                                // boundary to the finger via a spring animation.
                                //
                                // Uses SIGNED adjustment added to rawOffset:
                                //   dragOffsetX = rawOffset + signedAdjustment
                                //
                                // Before zone (c): signedAdj = -dragSign * slopDistance
                                //   (visual lags finger by slopDistance)
                                // After zone (c) spring: signedAdj = dragSign * fingerToEdgeDist
                                //   (row boundary pinned to finger screen position)
                                //
                                // Once pinned, stays pinned for the gesture — no slop
                                // reintroduction. The rawOffset clamp expands so the finger
                                // can drag all the way back to fully close the swipe.
                                //
                                // Include cumulativeX: the finger displacement consumed
                                // during slop detection that rawOffset must account for.
                                var rawOffset = offsetX.value + cumulativeX

                                // Distance from touch point to the revealed edge of the row:
                                // dragSign < 0 → row moves left → right edge revealed
                                // dragSign > 0 → row moves right → left edge revealed
                                val fingerToEdgeDist = if (dragSign < 0f) {
                                    rowWidthPx - touchDownX
                                } else {
                                    touchDownX
                                }

                                // Signed adjustment: added to rawOffset to compute visual.
                                // Pre-pin: -dragSign * slopDistance (visual lags finger)
                                // Post-pin: dragSign * fingerToEdgeDist (boundary at finger)
                                var signedAdjustment = -dragSign * slopDistance
                                var edgePinned = false
                                var catchUpJob: kotlinx.coroutines.Job? = null

                                var dragChange: androidx.compose.ui.input.pointer.PointerInputChange? = slopChange
                                while (dragChange != null && dragChange.pressed) {
                                    val delta = dragChange.positionChange().x
                                    dragChange.consume()
                                    velocityTracker.addPosition(dragChange.uptimeMillis, dragChange.position)

                                    // Update raw finger offset (1:1 with finger, clamped).
                                    // After edge-pinning, expand clamp so the finger can
                                    // drag past the touch-down point to fully close the swipe.
                                    val newRaw = rawOffset + delta
                                    rawOffset = if (dragSign < 0f) {
                                        val max = if (edgePinned) fingerToEdgeDist else 0f
                                        newRaw.coerceIn(-rowWidthPx.toFloat(), max)
                                    } else {
                                        val min = if (edgePinned) -fingerToEdgeDist else 0f
                                        newRaw.coerceIn(min, rowWidthPx.toFloat())
                                    }

                                    // Edge-pinning: when finger enters zone (c), spring
                                    // the row boundary to the finger's screen position.
                                    // Once pinned, stays pinned for this gesture (no slop
                                    // reintroduction). The expanded rawOffset clamp allows
                                    // dragging all the way back to fully close.
                                    if (!edgePinned && isFingerInZoneC(rawOffset)) {
                                        edgePinned = true
                                        catchUpJob?.cancel()
                                        val target = dragSign * fingerToEdgeDist
                                        catchUpJob = gestureScope.launch {
                                            animate(
                                                initialValue = signedAdjustment,
                                                targetValue = target,
                                                animationSpec = SNAP_SPRING
                                            ) { adj, _ ->
                                                signedAdjustment = adj
                                                dragOffsetX = if (dragSign < 0f) {
                                                    (rawOffset + adj).coerceIn(-rowWidthPx.toFloat(), 0f)
                                                } else {
                                                    (rawOffset + adj).coerceIn(0f, rowWidthPx.toFloat())
                                                }
                                            }
                                        }
                                    }

                                    // Visual offset = rawOffset + signedAdjustment
                                    // Clamp to valid direction: trailing never positive,
                                    // leading never negative.
                                    dragOffsetX = if (dragSign < 0f) {
                                        (rawOffset + signedAdjustment).coerceIn(-rowWidthPx.toFloat(), 0f)
                                    } else {
                                        (rawOffset + signedAdjustment).coerceIn(0f, rowWidthPx.toFloat())
                                    }

                                    dragChange = awaitDragOrCancellation(dragChange.id)
                                }
                                // Cancel catch-up animation on release
                                catchUpJob?.cancel()

                                // Release: settle decision uses RAW offset (actual finger
                                // displacement) for threshold comparison, not visual offset.
                                val velocity = velocityTracker.calculateVelocity().x
                                val absRaw = abs(rawOffset)
                                val allowsFullSwipeDir = if (dragSign < 0f) {
                                    if (isLtr) allowsFullSwipeTrailing else allowsFullSwipeLeading
                                } else {
                                    if (isLtr) allowsFullSwipeLeading else allowsFullSwipeTrailing
                                }

                                // iOS velocity checks (from _swipeRecognizerEnded disassembly):
                                // - 50pt/s threshold determines "high velocity" vs positional
                                // - Fling AWAY from rest → snap to detent (NOT trigger)
                                // - Fling TOWARD rest → return to start anchor
                                // - Only zone C position triggers the primary action
                                val isHighVelocity = abs(velocity) > flingVelocityThresholdPx
                                val velocityTowardAction = (velocity * dragSign) > 0
                                val fingerInZoneC = isFingerInZoneC(rawOffset)

                                when {
                                    activeActions.isEmpty() -> SettleAction.Close
                                    // Position past confirmation → trigger (iOS: confirmed state)
                                    allowsFullSwipeDir && fingerInZoneC ->
                                        SettleAction.Trigger(dragSign * rowWidthPx.toFloat(), activeActions)
                                    // High velocity away from rest → snap to detent (NOT trigger!)
                                    isHighVelocity && velocityTowardAction ->
                                        SettleAction.Detent(dragSign * detentPx)
                                    // High velocity toward rest → return to start anchor
                                    isHighVelocity -> {
                                        if (startAbsOffset >= detentPx * 0.5f)
                                            SettleAction.Detent(dragSign * detentPx)
                                        else
                                            SettleAction.Close
                                    }
                                    // Low velocity, past half detent → snap to detent
                                    // (iOS: openThreshold * 0.5 from _swipeRecognizerEnded)
                                    absRaw >= detentPx * 0.5f -> SettleAction.Detent(dragSign * detentPx)
                                    // Below half detent → close
                                    else -> SettleAction.Close
                                }
                            } } catch (ce: CancellationException) {
                                throw ce
                            } catch (_: Exception) {
                                SettleAction.Close
                            }

                            // Settle phase — sync offsetX from drag, switch visual, then animate
                            when (settle) {
                                is SettleAction.Close -> launch {
                                    try {
                                        isSettling = true
                                        offsetX.snapTo(dragOffsetX)
                                        isDragging = false
                                        offsetX.animateTo(0f, SETTLE_SPRING)
                                        if (activeSwipeKey.value == itemKey) activeSwipeKey.value = null
                                    } finally {
                                        isSettling = false
                                    }
                                }
                                is SettleAction.Detent -> launch {
                                    try {
                                        isSettling = true
                                        offsetX.snapTo(dragOffsetX)
                                        isDragging = false
                                        offsetX.animateTo(settle.target, SETTLE_SPRING)
                                    } finally {
                                        isSettling = false
                                    }
                                }
                                is SettleAction.Trigger -> launch {
                                    isActioning = true
                                    try {
                                        offsetX.snapTo(dragOffsetX)
                                        isDragging = false
                                        val firstAction = settle.actions.first()
                                        // Slide-off animation
                                        val animJob = launch {
                                            offsetX.animateTo(settle.target, SETTLE_SPRING)
                                        }
                                        if (firstAction.isDestructive) {
                                            // Signal list to use faster placement spring on surviving items
                                            onDestructiveDeleteStart(itemKey)
                                            try {
                                                // Destructive: collapse height concurrently, defer
                                                // action until animations complete so composable
                                                // stays alive during exit animation.
                                                val heightJob = launch { heightFraction.animateTo(0f, COLLAPSE_SPRING) }
                                                animJob.join()
                                                heightJob.join()
                                                try {
                                                    firstAction.action()
                                                } catch (e: Exception) {
                                                    if (e is CancellationException) throw e
                                                }
                                            } finally {
                                                onDestructiveDeleteEnd()
                                            }
                                        } else {
                                            // Non-destructive: fire action immediately, then reset
                                            try {
                                                firstAction.action()
                                            } catch (e: Exception) {
                                                if (e is CancellationException) throw e
                                            }
                                            animJob.join()
                                            isActioning = false
                                            offsetX.snapTo(0f)
                                            if (activeSwipeKey.value == itemKey) activeSwipeKey.value = null
                                        }
                                    } catch (e: CancellationException) {
                                        isActioning = false
                                        isDragging = false
                                        throw e
                                    }
                                }
                                SettleAction.None -> {
                                    isDragging = false
                                }
                            }
                        }
                    }
                }
        ) {
            content()
        }
    }
}

/**
 * Background layer showing action buttons when row is swiped.
 *
 * Unified layout: a single weighted Row handles both normal and completion
 * states. Animated properties drive the transition rather than binary switches:
 *
 * - labelOpacity: proportional fade-in from closed (0) to detent (1)
 * - completionProgress: 0→1 spring animation when entering zone (c)
 * - BiasAlignment: smooth label slide from centre to row-side edge
 * - Weight: first action expands, others shrink during completion
 */
@Composable
private fun BoxScope.ActionsBackground(
    actions: kotlin.collections.List<SwipeActionData>,
    revealPx: Float,
    rowWidthPx: Int,
    isInCompletionZone: Boolean,
    onActionTap: (Int) -> Unit,
    edge: skip.ui.HorizontalEdge,
    layoutDirection: LayoutDirection
) {
    if (actions.isEmpty() || revealPx <= 0f) return

    // Determine visual side (physically right = trailing visual)
    val isTrailingVisual = (edge == skip.ui.HorizontalEdge.trailing && layoutDirection == LayoutDirection.Ltr) ||
            (edge == skip.ui.HorizontalEdge.leading && layoutDirection == LayoutDirection.Rtl)
    val alignment = if (isTrailingVisual) Alignment.CenterEnd else Alignment.CenterStart

    // Completion progress: SNAP_SPRING matches edge-pinning spring
    val completionProgress by animateFloatAsState(
        targetValue = if (isInCompletionZone) 1f else 0f,
        animationSpec = SNAP_SPRING,
        label = "completionProgress"
    )

    // Detent width for label fade-in calculation
    val density = androidx.compose.ui.platform.LocalDensity.current
    val actionButtonWidthPx = with(density) { ACTION_BUTTON_WIDTH_DP.dp.toPx() }
    val detentPx = (actionButtonWidthPx * actions.size)
        .coerceAtMost(rowWidthPx * MAX_DETENT_RATIO)

    // Label opacity: proportional fade-in from closed to detent
    val labelOpacity = if (detentPx > 0f) (revealPx / detentPx).coerceIn(0f, 1f) else 1f

    // Row-side bias direction: the edge physically closest to the sliding
    // row content. BiasAlignment respects layout direction — adjust for RTL.
    val rowSideBias = run {
        val ltrBias = if (isTrailingVisual) -1f else 1f
        if (layoutDirection == LayoutDirection.Ltr) ltrBias else -ltrBias
    }

    Box(
        modifier = Modifier.matchParentSize(),
        contentAlignment = alignment
    ) {
        // Full-width background for completion zone (covers area beyond Row)
        if (completionProgress > 0f && actions.isNotEmpty()) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .background(actions[0].resolveColor().copy(alpha = completionProgress))
            )
        }

        val revealDp = with(density) { revealPx.toDp() }
        Row(
            modifier = Modifier
                .fillMaxHeight()
                .width(revealDp),
            horizontalArrangement = Arrangement.Start
        ) {
            for ((index, action) in actions.withIndex()) {
                val bgColor = action.resolveColor()
                val isFirst = index == 0

                // Weight: first action expands in completion zone, others shrink
                val buttonWeight = if (isFirst) {
                    1f + completionProgress * (actions.size - 1).toFloat()
                } else {
                    (1f - completionProgress).coerceAtLeast(0.01f)
                }

                // Opacity: all labels fade in with swipe; non-first also fade out in completion
                val actionAlpha = if (isFirst) labelOpacity else labelOpacity * (1f - completionProgress)

                // Alignment: first action label slides from centre to row-side edge
                val horizontalBias = if (isFirst) completionProgress * rowSideBias else 0f

                Box(
                    modifier = Modifier
                        .fillMaxHeight()
                        .weight(buttonWeight)
                        .background(bgColor)
                        .clipToBounds()
                        .clickable { onActionTap(index) },
                    contentAlignment = BiasAlignment(horizontalBias = horizontalBias, verticalBias = 0f)
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                        modifier = Modifier
                            .requiredWidth(ACTION_BUTTON_WIDTH_DP.dp)
                            .scale(labelOpacity)
                            .padding(horizontal = if (isFirst) 16.dp * completionProgress else 0.dp)
                    ) {
                        val iconVector = action.iconName?.let { Image.composeImageVector(named = it) as? ImageVector }
                        if (iconVector != null) {
                            Icon(
                                imageVector = iconVector,
                                contentDescription = action.label,
                                tint = Color.White.copy(alpha = actionAlpha)
                            )
                        }
                        if (action.label != null) {
                            Text(
                                text = action.label,
                                color = Color.White.copy(alpha = actionAlpha),
                                fontSize = androidx.compose.ui.unit.TextUnit(12f, androidx.compose.ui.unit.TextUnitType.Sp),
                                maxLines = 1
                            )
                        }
                    }
                }
            }
        }
    }
}
