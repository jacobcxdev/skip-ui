// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredHeightIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.PullRefreshState
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.Icon
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Path.Companion.combine
import androidx.compose.ui.graphics.PathOperation
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.zIndex
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.ReorderableLazyListState
import sh.calvin.reorderable.detectReorderAfterLongPress
import sh.calvin.reorderable.rememberReorderableLazyListState
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.outlined.Circle
#elseif canImport(CoreGraphics)
import struct CoreGraphics.CGFloat
#endif

/// Corner radius for list sections.
let listSectionCornerRadius = 8.0

/// Animation durations for list item transitions (milliseconds).
private let listPlacementDurationMs = 350
private let listFadeOutDurationMs = 300

// SKIP @bridge
// SKIP INSERT: @Stable // Otherwise Compose recomposes all internal @Composable funcs because 'this' is unstable
public final class List : View, Renderable {
    let fixedContent: ComposeBuilder?
    let forEach: ForEach?
    let itemTransformer: ((any Renderable) -> any Renderable)?
    let bridgedSelection: ListSelectionProxy?

    init(fixedContent: (any View)? = nil, identifier: ((Any) -> AnyHashable?)? = nil, itemTransformer: ((any Renderable) -> any Renderable)? = nil, indexRange: Range<Int>? = nil, indexedContent: ((Int) -> any View)? = nil, objects: (any RandomAccessCollection<Any>)? = nil, objectContent: ((Any) -> any View)? = nil, objectsBinding: Binding<any RandomAccessCollection<Any>>? = nil, objectsBindingContent: ((Binding<any RandomAccessCollection<Any>>, Int) -> any View)? = nil, editActions: EditActions = []) {
        if let fixedContent {
            self.fixedContent = fixedContent as? ComposeBuilder ?? ComposeBuilder(view: fixedContent)
        } else {
            self.fixedContent = nil
        }
        if let indexRange {
            self.forEach = ForEach(identifier: identifier, indexRange: { indexRange }, indexedContent: indexedContent)
        } else if let objects {
            self.forEach = ForEach(identifier: identifier, objects: objects, objectContent: objectContent)
        } else if let objectsBinding {
            self.forEach = ForEach(identifier: identifier, objectsBinding: objectsBinding, objectsBindingContent: objectsBindingContent, editActions: editActions)
        } else {
            self.forEach = nil
        }
        self.itemTransformer = itemTransformer
        self.bridgedSelection = nil
    }

    public convenience init(@ViewBuilder content: () -> any View) {
        self.init(fixedContent: content())
    }

    @available(*, unavailable)
    public convenience init(selection: Binding<Any>, @ViewBuilder content: () -> any View) {
        self.init(fixedContent: content())
    }

    // SKIP @bridge
    public init(bridgedContent: any View, bridgedSelection: ListSelectionProxy? = nil) {
        if let forEach = bridgedContent as? ForEach {
            self.fixedContent = nil
            self.forEach = forEach
        } else {
            self.fixedContent = ComposeBuilder.from { bridgedContent }
            self.forEach = nil
        }
        self.itemTransformer = nil
        self.bridgedSelection = bridgedSelection
    }

    #if SKIP
    // SKIP INSERT: @OptIn(ExperimentalMaterialApi::class)
    @Composable public override func Render(context: ComposeContext) {
        let style = EnvironmentValues.shared._listStyle ?? ListStyle.automatic
        let backgroundVisibility = EnvironmentValues.shared._scrollContentBackground ?? Visibility.visible
        let styling = ListStyling(style: style, backgroundVisibility: backgroundVisibility)
        let itemContext = context.content()

        // When we layout, extend into safe areas that are due to system bars, not into any app chrome
        let safeArea = EnvironmentValues.shared._safeArea
        var ignoresSafeAreaEdges: Edge.Set = [.top, .bottom]
        ignoresSafeAreaEdges.formIntersection(safeArea?.absoluteSystemBarEdges ?? [])
        ComposeContainer(scrollAxes: .vertical, modifier: context.modifier, fillWidth: true, fillHeight: true, then: Modifier.background(BackgroundColor(styling: styling, isItem: false))) { modifier in
            IgnoresSafeAreaLayout(expandInto: ignoresSafeAreaEdges, checkEdges: [.bottom], modifier: modifier) { safeAreaExpansion, safeAreaEdges in
                var containerModifier: Modifier
                let refreshing = remember { mutableStateOf(false) }
                let refreshAction = EnvironmentValues.shared.refresh
                let refreshState: PullRefreshState?
                if let refreshAction {
                    let refreshScope = rememberCoroutineScope()
                    let updatedAction = rememberUpdatedState(refreshAction)
                    refreshState = rememberPullRefreshState(refreshing.value, {
                        refreshScope.launch {
                            refreshing.value = true
                            updatedAction.value()
                            refreshing.value = false
                        }
                    })
                    containerModifier = modifier.pullRefresh(refreshState!)
                } else {
                    refreshState = nil
                    containerModifier = modifier
                }
                containerModifier = containerModifier.scrollDismissesKeyboardMode(EnvironmentValues.shared.scrollDismissesKeyboardMode)
                
                Box(modifier: containerModifier) {
                    let density = LocalDensity.current
                    let headerSafeAreaHeight = with(density) { safeAreaExpansion.top.toDp() }
                    let footerSafeAreaHeight = with(density) { safeAreaExpansion.bottom.toDp() }
                    RenderList(context: itemContext, styling: styling, arguments: ListArguments(headerSafeAreaHeight: headerSafeAreaHeight, footerSafeAreaHeight: footerSafeAreaHeight, safeAreaEdges: safeAreaEdges))
                    if let refreshState {
                        PullRefreshIndicator(refreshing.value, refreshState, Modifier.align(androidx.compose.ui.Alignment.TopCenter))
                    }
                }
            }
        }
    }

    @Composable private func RenderList(context: ComposeContext, styling: ListStyling, arguments: ListArguments) {
        let renderables: kotlin.collections.List<Renderable>
        if let forEach {
            renderables = forEach.EvaluateLazyItems(level: 0, context: context)
        } else if let fixedContent {
            renderables = fixedContent.EvaluateLazyItems(level: 0, context: context)
        } else {
            renderables = listOf()
        }

        var modifier = context.modifier
        if styling.style != .plain {
            modifier = modifier.padding(start: Self.horizontalInset.dp, end: Self.horizontalInset.dp)
        }
        modifier = modifier.fillMaxSize()

        let searchableState = EnvironmentValues.shared._searchableState
        let isSearchable = searchableState?.isOnNavigationStack == false

        let hasHeader = styling.style != ListStyle.plain || (!isSearchable && arguments.headerSafeAreaHeight.value > 0)
        let hasFooter = styling.style != ListStyle.plain || arguments.footerSafeAreaHeight.value > 0

        // Remember the factory because we use it in the remembered reorderable state
        let itemCollector = remember { mutableStateOf(LazyItemCollector()) }
        let moveTrigger = remember { mutableStateOf(0) }
        let listState = rememberLazyListState(initialFirstVisibleItemIndex = isSearchable && arguments.headerSafeAreaHeight.value <= 0 ? 1 : 0)
        let reorderableState = rememberReorderableLazyListState(lazyListState: listState, onMove: { from, to in
            guard itemCollector.value.canMove(from: from.index, to: to.index) else { return }
            // Trigger recompose on move, but don't read the trigger state until we're inside the list content to limit its scope
            itemCollector.value.move(from: from.index, to: to.index, trigger: { moveTrigger.value = $0 })
        })
        // Detect drag-end to commit the move (replaces old onDragEnd parameter).
        // All state mutation is inside LaunchedEffect to avoid composition-time side effects.
        let isDragging = reorderableState.isAnyItemDragging
        let wasDragging = remember { mutableStateOf(false) }
        LaunchedEffect(isDragging) {
            if !isDragging && wasDragging.value {
                itemCollector.value.commitMove()
            }
            wasDragging.value = isDragging
        }

        // Integrate with our scroll-to-top and ScrollViewReader
        let coroutineScope = rememberCoroutineScope()
        PreferenceValues.shared.contribute(context: context, key: ScrollToTopPreferenceKey.self, value: ScrollToTopAction(key: reorderableState.listState) {
            coroutineScope.launch {
                reorderableState.listState.animateScrollToItem(0)
            }
        })
        let scrollToID = ScrollToIDAction(key: reorderableState.listState) { id in
            if let itemIndex = itemCollector.value.index(for: id) {
                coroutineScope.launch {
                    if Animation.isInWithAnimation {
                        reorderableState.listState.animateScrollToItem(itemIndex)
                    } else {
                        reorderableState.listState.scrollToItem(itemIndex)
                    }
                }
            }
        }
        PreferenceValues.shared.contribute(context: context, key: ScrollToIDPreferenceKey.self, value: scrollToID)
        let isSystemBackground = styling.style != ListStyle.plain && styling.backgroundVisibility != Visibility.hidden
        // We contribute top bar preferences even without knowing we're safe area-adjacent for multiple reasons:
        // - When there is a search bar we may not be adjacent to the top safe area, but we should act like it
        // - An expanding nav bar can causes issues detecting safe area adjacency
        // - It is unlikely that anyone will use a grouped-style list that is not top-bar adjacent, so the top
        //   bar should always have the grouped-style system color
        PreferenceValues.shared.contribute(context: context, key: ToolbarPreferenceKey.self, value: ToolbarPreferences(isSystemBackground: isSystemBackground, scrollableState: listState, for: [ToolbarPlacement.navigationBar]))
        if arguments.safeAreaEdges.contains(Edge.Set.bottom) {
            PreferenceValues.shared.contribute(context: context, key: ToolbarPreferenceKey.self, value: ToolbarPreferences(isSystemBackground: isSystemBackground, scrollableState: listState, for: [ToolbarPlacement.bottomBar]))
            PreferenceValues.shared.contribute(context: context, key: TabBarPreferenceKey.self, value: ToolbarBarPreferences(isSystemBackground: isSystemBackground, scrollableState: listState))
        }

        // Suppress placement animation for the first 300ms after composition so that the initial
        // data load doesn't cause items to visually slide into position. After the guard period,
        // placement animation is always enabled — animateItem's fadeOutSpec (which controls
        // deletion fade-out) must never be disrupted by composition-time state mutations.
        let suppressPlacement = remember { mutableStateOf(true) }
        LaunchedEffect(Unit) {
            delay(300)
            suppressPlacement.value = false
        }

        let itemContext = context.content()
        let peerStore = remember { PeerStore() }
        let activeSwipeKey = remember { mutableStateOf<Any?>(nil) }
        let isDestructiveDeleteAnimating = remember { mutableStateOf(false) }
        // Animation policy: placement and fade-out are controlled independently.
        // - Placement: suppressed during unanimated data changes to prevent visual sliding
        // - Fade-out: always enabled so Compose retains animateItem parent-data for keyed
        //   item removal; only suppressed during swipe destructive deletes (SwipeActionsBox
        //   handles its own visual removal) and active search filtering
        let isSearching = EnvironmentValues.shared._searchableState?.isSearching.value == true
        let animatePlacement = !suppressPlacement.value && !isSearching
        let animateFadeOut = !isDestructiveDeleteAnimating.value && !isSearching
        // SKIP INSERT: val providedPeerStore = LocalPeerStore provides peerStore
        CompositionLocalProvider(providedPeerStore) {
        LazyColumn(state: reorderableState.listState, modifier: modifier) {
            // Read move trigger here so that a move will recompose list content
            let _ = moveTrigger.value
            // Initialize the factory context with closures that use the LazyListScope to generate items
            var startItemIndex = hasHeader ? 1 : 0 // Header inset
            if isSearchable {
                startItemIndex += 1 // Search field
            }
            itemCollector.value.initialize(
                startItemIndex: startItemIndex,
                item: { renderable, level in
                    item {
                        let itemModifier = Modifier.animateItem(fadeInSpec: nil, placementSpec: animatePlacement ? tween(durationMillis: listPlacementDurationMs) : nil, fadeOutSpec: animateFadeOut ? tween(durationMillis: listFadeOutDurationMs) : nil)
                        RenderItem(content: renderable, level: level, context: itemContext, modifier: itemModifier, styling: styling)
                    }
                },
                indexedItems: { range, identifier, offset, onDelete, onMove, level, factory in
                    let count = range.endExclusive - range.start
                    let key: ((Int) -> String)? = identifier == nil ? nil : { composeBundleNormalizedKey(for: identifier!(range.start + itemCollector.value.remapIndex($0, from: offset))) }
                    items(count: count, key: key) { index in
                        let keyValue = key?(index) // Key closure already remaps index
                        let index = itemCollector.value.remapIndex(index, from: offset)
                        let itemModifier = Modifier.animateItem(fadeInSpec: nil, placementSpec: animatePlacement ? tween(durationMillis: listPlacementDurationMs) : nil, fadeOutSpec: animateFadeOut ? tween(durationMillis: listFadeOutDurationMs) : nil)
                        let renderable = factory(index + range.start, itemContext)
                        let itemKey = keyValue ?? String(index + range.start)
                        // SKIP INSERT: val providedItemKey = LocalPeerStoreItemKey provides itemKey
                        let itemContent: @Composable () -> Void = {
                            CompositionLocalProvider(providedItemKey) {
                            RenderEditableItem(content: renderable, level: level, context: itemContext, modifier: itemModifier, styling: styling, key: keyValue, rawIdentifier: identifier?(range.start + index), index: index, onDelete: onDelete, onMove: onMove, reorderableState: reorderableState, activeSwipeKey: activeSwipeKey, isDestructiveDeleteAnimating: isDestructiveDeleteAnimating)
                            }
                        }
                        if onMove != nil, let keyValue {
                            ReorderableItem(state: reorderableState, key: keyValue, animateItemModifier: itemModifier) { isDragging in
                                let dragModifier = isDragging ? Modifier.shadow(animateDpAsState(8.dp).value) : Modifier
                                HeightGrowthBox(animateOnEnter: false, durationMillis: listPlacementDurationMs, modifier: dragModifier) { itemContent() }
                            }
                        } else {
                            itemContent()
                        }
                    }
                },
                objectItems: { objects, identifier, offset, onDelete, onMove, level, factory in
                    let key: (Int) -> String = { composeBundleNormalizedKey(for: identifier(objects[itemCollector.value.remapIndex($0, from: offset)])) }
                    items(count: objects.count, key: key) { index in
                        let keyValue = key(index) // Key closure already remaps index
                        let index = itemCollector.value.remapIndex(index, from: offset)
                        let itemModifier = Modifier.animateItem(fadeInSpec: nil, placementSpec: animatePlacement ? tween(durationMillis: listPlacementDurationMs) : nil, fadeOutSpec: animateFadeOut ? tween(durationMillis: listFadeOutDurationMs) : nil)
                        let renderable = factory(objects[index], itemContext)
                        let itemKey = keyValue
                        // SKIP INSERT: val providedItemKey = LocalPeerStoreItemKey provides itemKey
                        let itemContent: @Composable () -> Void = {
                            CompositionLocalProvider(providedItemKey) {
                            RenderEditableItem(content: renderable, level: level, context: itemContext, modifier: itemModifier, styling: styling, key: keyValue, rawIdentifier: identifier(objects[index]), index: index, onDelete: onDelete, onMove: onMove, reorderableState: reorderableState, activeSwipeKey: activeSwipeKey, isDestructiveDeleteAnimating: isDestructiveDeleteAnimating)
                            }
                        }
                        if onMove != nil {
                            ReorderableItem(state: reorderableState, key: keyValue, animateItemModifier: itemModifier) { isDragging in
                                let dragModifier = isDragging ? Modifier.shadow(animateDpAsState(8.dp).value) : Modifier
                                HeightGrowthBox(animateOnEnter: false, durationMillis: listPlacementDurationMs, modifier: dragModifier) { itemContent() }
                            }
                        } else {
                            itemContent()
                        }
                    }
                },
                objectBindingItems: { objectsBinding, identifier, offset, editActions, onDelete, onMove, level, factory in
                    let key: (Int) -> String = { composeBundleNormalizedKey(for: identifier(objectsBinding.wrappedValue[itemCollector.value.remapIndex($0, from: offset)])) }
                    items(count: objectsBinding.wrappedValue.count, key: key) { index in
                        let keyValue = key(index) // Key closure already remaps index
                        let index = itemCollector.value.remapIndex(index, from: offset)
                        let itemModifier = Modifier.animateItem(fadeInSpec: nil, placementSpec: animatePlacement ? tween(durationMillis: listPlacementDurationMs) : nil, fadeOutSpec: animateFadeOut ? tween(durationMillis: listFadeOutDurationMs) : nil)
                        let renderable = factory(objectsBinding, index, itemContext)
                        let itemKey = keyValue
                        // SKIP INSERT: val providedItemKey = LocalPeerStoreItemKey provides itemKey
                        let itemContent: @Composable () -> Void = {
                            CompositionLocalProvider(providedItemKey) {
                            RenderEditableItem(content: renderable, level: level, context: itemContext, modifier: itemModifier, styling: styling, objectsBinding: objectsBinding, key: keyValue, rawIdentifier: identifier(objectsBinding.wrappedValue[index]), index: index, editActions: editActions, onDelete: onDelete, onMove: onMove, reorderableState: reorderableState, activeSwipeKey: activeSwipeKey, isDestructiveDeleteAnimating: isDestructiveDeleteAnimating)
                            }
                        }
                        if onMove != nil {
                            ReorderableItem(state: reorderableState, key: keyValue, animateItemModifier: itemModifier) { isDragging in
                                let dragModifier = isDragging ? Modifier.shadow(animateDpAsState(8.dp).value) : Modifier
                                HeightGrowthBox(animateOnEnter: false, durationMillis: listPlacementDurationMs, modifier: dragModifier) { itemContent() }
                            }
                        } else {
                            itemContent()
                        }
                    }
                },
                sectionHeader: { content in
                    let headerRenderables = content.size == 0 ? listOf(EmptyView()) : content
                    let firstRenderable = (renderables.firstOrNull() as? LazySectionHeader)?.content.firstOrNull()
                    let isTop = firstRenderable === headerRenderables.firstOrNull()
                    for renderable in headerRenderables {
                        if styling.style == .plain {
                            stickyHeader { _ in
                                RenderSectionHeader(content: renderable, context: itemContext, styling: styling, isTop: isTop)
                            }
                        } else {
                            item {
                                RenderSectionHeader(content: renderable, context: itemContext, styling: styling, isTop: isTop)
                            }
                        }
                    }
                },
                sectionFooter: { content in
                    let footerRenderables = content.size == 0 ? listOf(EmptyView()) : content
                    for renderable in footerRenderables {
                        item {
                            RenderSectionFooter(content: renderable, context: itemContext, styling: styling)
                        }
                    }
                }
            )

            if isSearchable {
                item {
                    RenderSearchField(state: searchableState!, context: context, styling: styling, safeAreaHeight: arguments.headerSafeAreaHeight)
                }
            }
            if hasHeader {
                let hasTopSection = renderables.firstOrNull() is LazySectionHeader
                item {
                    RenderHeader(styling: styling, safeAreaHeight: isSearchable ? 0.dp : arguments.headerSafeAreaHeight, hasTopSection: hasTopSection)
                }
            }
            for renderable in renderables {
                if let factory = renderable as? LazyItemFactory, factory.shouldProduceLazyItems() {
                    factory.produceLazyItems(collector: itemCollector.value, modifiers: listOf(), level: 0)
                } else {
                    itemCollector.value.item(renderable, 0)
                }
            }
            if hasFooter {
                let hasBottomSection = renderables.lastOrNull() is LazySectionFooter
                item {
                    RenderFooter(styling: styling, safeAreaHeight: arguments.footerSafeAreaHeight, hasBottomSection: hasBottomSection)
                }
            }
        }
        } // closes CompositionLocalProvider(LocalPeerStore provides peerStore)
    }

    private static let horizontalInset = 16.0
    private static let verticalInset = 16.0
    private static let minimumItemHeight = 32.0
    private static let horizontalItemInset = 16.0
    private static let verticalItemInset = 8.0
    private static let levelInset = 24.0

    static func contentModifier(level: Int) -> Modifier {
        return Modifier.padding(start: (horizontalItemInset + level * levelInset).dp, end: horizontalItemInset.dp, top: verticalItemInset.dp, bottom: verticalItemInset.dp).fillMaxWidth().requiredHeightIn(min: minimumItemHeight.dp)
    }

    @Composable static func RenderSeparator(level: Int) {
        androidx.compose.material3.Divider(modifier: Modifier.padding(start: (horizontalItemInset + level * levelInset).dp).fillMaxWidth(), color: Color.separator.colorImpl())
    }

    @Composable static func RenderItemContent(item: Renderable, context: ComposeContext, modifier: Modifier) {
        let badgeModifier = BadgeModifier.combined(for: item)
        let badge = badgeModifier.badge
        let (isListItem, listItemAction) = item.shouldRenderListItem(context: context)
        if isListItem {
            let actionModifier: Modifier
            if let listItemAction {
                let isDisabled = !EnvironmentValues.shared.isEnabled || item.forEachModifier { ($0 as? DisabledModifier)?.disabled } == true
                actionModifier = Modifier.clickable(onClick: listItemAction, enabled: !isDisabled)
            } else {
                actionModifier = Modifier
            }
            if let badge {
                Row(modifier: actionModifier.then(modifier), horizontalArrangement: Arrangement.SpaceBetween, verticalAlignment: androidx.compose.ui.Alignment.CenterVertically) {
                    Box(modifier: Modifier.weight(Float(1.0)), contentAlignment: androidx.compose.ui.Alignment.CenterStart) {
                        item.RenderListItem(context: context, modifiers: listOf())
                    }
                    RenderBadge(badge: badge, prominence: badgeModifier.prominence ?? .standard, context: context)
                }
            } else {
                Box(modifier: actionModifier.then(modifier), contentAlignment: androidx.compose.ui.Alignment.CenterStart) {
                    item.RenderListItem(context: context, modifiers: listOf())
                }
            }
        } else {
            if let badge {
                Row(modifier: modifier, horizontalArrangement: Arrangement.SpaceBetween, verticalAlignment: androidx.compose.ui.Alignment.CenterVertically) {
                    Box(modifier: Modifier.weight(Float(1.0)), contentAlignment: androidx.compose.ui.Alignment.CenterStart) {
                        item.Render(context: context)
                    }
                    RenderBadge(badge: badge, prominence: badgeModifier.prominence ?? .standard, context: context)
                }
            } else {
                Box(modifier: modifier, contentAlignment: androidx.compose.ui.Alignment.CenterStart) {
                    item.Render(context: context)
                }
            }
        }
    }

    @Composable private static func RenderBadge(badge: Text, prominence: BadgeProminence, context: ComposeContext) {
        let badgeColor: androidx.compose.ui.graphics.Color
        switch prominence {
        case .increased:
            badgeColor = Color.red.colorImpl()
        case .decreased:
            badgeColor = Color.secondary.colorImpl()
        default:
            badgeColor = Color.secondary.colorImpl()
        }
        EnvironmentValues.shared.setValues {
            $0.set_foregroundStyle(Color(colorImpl: { badgeColor }))
            return ComposeResult.ok
        } in: {
            badge.Compose(context: context)
        }
    }

    @Composable private func RenderItem(content: Renderable, level: Int, context: ComposeContext, modifier: Modifier = Modifier, styling: ListStyling, isItem: Bool = true) {
        guard !content.isSwiftUIEmptyView else {
            return
        }

        let itemRenderable = itemTransformer?(content) ?? content
        let listItemModifier = ListItemModifier.combined(for: itemRenderable)
        var itemModifier: Modifier = Modifier
        if listItemModifier?.background == nil {
            itemModifier = itemModifier.background(BackgroundColor(styling: styling.withStyle(ListStyle.plain), isItem: isItem))
        }

        // The given modifiers include elevation shadow for dragging, etc that need to go before the others
        let containerContext = context.content(modifier: modifier.then(itemModifier).then(context.modifier))
        let contentContext = context.content()
        let contentModifier = Self.contentModifier(level: level)
        let renderContainer: @Composable (ComposeContext) -> Void = { context in
            Column(modifier: context.modifier) {
                let placement = EnvironmentValues.shared._placement
                EnvironmentValues.shared.setValues {
                    $0.set_placement(placement.union(ViewPlacement.listItem))
                    return ComposeResult.ok
                } in: {
                    Self.RenderItemContent(item: itemRenderable, context: contentContext, modifier: contentModifier)
                }
                if listItemModifier?.separator != Visibility.hidden {
                    Self.RenderSeparator(level: level)
                }
            }
        }

        if let background = listItemModifier?.background {
            TargetViewLayout(context: containerContext, isOverlay: false, alignment: Alignment.center, target: renderContainer, dependent: {
                background.Compose(context: $0)
            })
        } else {
            renderContainer(containerContext)
        }
    }

    @Composable private func RenderEditableItem(content: Renderable, level: Int, context: ComposeContext, modifier: Modifier, styling: ListStyling, objectsBinding: Binding<RandomAccessCollection<Any>>? = nil, key: String?, rawIdentifier: Any? = nil, index: Int, editActions: EditActions = [], onDelete: ((IndexSet) -> Void)?, onMove: ((IndexSet, Int) -> Void)?, reorderableState: ReorderableLazyListState, activeSwipeKey: MutableState<Any?>, isDestructiveDeleteAnimating: MutableState<Bool>) {
        guard !content.isSwiftUIEmptyView else {
            return
        }
        guard let key else {
            RenderItem(content: content, level: level, context: context, modifier: modifier, styling: styling)
            return
        }
        let editActionsModifier = EditActionsModifier.combined(for: content)
        let isEditing = EnvironmentValues.shared._editMode?.wrappedValue.isEditing == true

        let isDeleteEnabled = (editActions.contains(.delete) || onDelete != nil) && editActionsModifier.isDeleteDisabled != true
        // Capability flags: whether the list supports move/selection at all (independent of isEditing)
        let hasMoveCap = (editActions.contains(.move) || onMove != nil) && editActionsModifier.isMoveDisabled != true
        let hasListSelectionCap = bridgedSelection != nil
        // Active flags: whether controls should be visible (gated on isEditing)
        let isMoveEnabled = hasMoveCap && isEditing
        let hasExplicitSwipeActions = SwipeActionsModifier.hasSwipeActions(content) && !isEditing
        let listSelection = isEditing ? bridgedSelection : nil
        guard isDeleteEnabled || isMoveEnabled || hasExplicitSwipeActions || listSelection != nil else {
            RenderItem(content: content, level: level, context: context, modifier: modifier, styling: styling)
            return
        }

        // Extract explicit swipe actions from the modifier chain
        var trailingActions: kotlin.collections.List<SwipeActionData> = listOf()
        var leadingActions: kotlin.collections.List<SwipeActionData> = listOf()
        var allowsFullSwipeTrailing = true
        var allowsFullSwipeLeading = true

        // Hoisted delete closure: stable call count for Compose, shared between swipe + edit branches
        let rememberedDeleteAction = rememberUpdatedState({
            if let onDelete {
                withAnimation { onDelete(IndexSet(integer: index)) }
            } else if let objectsBinding, objectsBinding.wrappedValue.count > index {
                withAnimation { (objectsBinding.wrappedValue as? RangeReplaceableCollection<Any>)?.remove(at: index) }
            }
        })

        if hasExplicitSwipeActions {
            let (trailing, trailingFull) = SwipeActionsModifier.extractActions(for: content, edge: .trailing, context: context)
            let (leading, leadingFull) = SwipeActionsModifier.extractActions(for: content, edge: .leading, context: context)
            trailingActions = trailing
            leadingActions = leading
            allowsFullSwipeTrailing = trailingFull
            allowsFullSwipeLeading = leadingFull
        } else if isDeleteEnabled && !isEditing {
            // Synthesise from onDelete (backward compat) — only when not in edit layout
            trailingActions = listOf(SwipeActionData(
                label: "Delete",
                iconName: "trash",
                role: 1,
                tint: nil,
                action: { rememberedDeleteAction.value() }
            ))
        }

        // ── Edit-mode transition infrastructure ──
        // All transition state lives OUTSIDE the `if showingEditChrome` guard so it persists
        // across edit-mode cycles. MutableTransitionState is initialised with `false` so that
        // enter animations always run (false→true transition) rather than starting at the
        // target state and producing no animation on re-entry after the block was disposed.
        let hasLeadingControl = hasListSelectionCap || isDeleteEnabled
        let hasTrailingHandle = hasMoveCap
        let wantsEditChrome = isEditing && (isDeleteEnabled || hasMoveCap || hasListSelectionCap)
        let editLeadingTransState = remember { MutableTransitionState(false) }
        editLeadingTransState.targetState = wantsEditChrome && hasLeadingControl
        let editTrailingTransState = remember { MutableTransitionState(false) }
        editTrailingTransState.targetState = wantsEditChrome && hasTrailingHandle
        // Capture animation intent when wantsEditChrome changes (true iff inside a withAnimation block).
        let animateEditTransition = remember { mutableStateOf(false) }
        let prevWantsEditChrome = remember { mutableStateOf(false) }
        if prevWantsEditChrome.value != wantsEditChrome {
            animateEditTransition.value = Animation.isInWithAnimation
            prevWantsEditChrome.value = wantsEditChrome
        }
        // Detect nil-toggle selection pattern: when hasListSelectionCap goes false→true
        // simultaneously with entering edit mode, this matches iOS List(selection: nil → binding)
        // structural reconfiguration which does NOT animate selection circles on enter.
        // When selection was already bound (always-bound pattern), leading controls animate.
        let prevHasListSelectionCap = remember { mutableStateOf(hasListSelectionCap) }
        let selectionWasAlreadyBound = prevHasListSelectionCap.value
        SideEffect { prevHasListSelectionCap.value = hasListSelectionCap }
        // Per-control animation flags
        let animateLeadingEnter = animateEditTransition.value && selectionWasAlreadyBound
        let animateLeadingExit = animateEditTransition.value
        let animateTrailingEnter = animateEditTransition.value
        let animateTrailingExit = animateEditTransition.value
        let editAnimDuration = 300
        // Animated content padding: as edit controls expand/shrink, content padding inversely
        // adjusts to match the normal rendering path's horizontalItemInset, preventing a visible
        // jump at the edit→normal rendering handoff.
        let normalStartPad = (Self.horizontalItemInset + Double(level) * Self.levelInset).dp
        let editLeadingPad = animateDpAsState(
            targetValue: (wantsEditChrome && hasLeadingControl) ? 0.dp : normalStartPad,
            animationSpec: (wantsEditChrome ? animateLeadingEnter : animateLeadingExit) ? tween(durationMillis: editAnimDuration) : snap()
        )
        let editTrailingPad = animateDpAsState(
            targetValue: (wantsEditChrome && hasTrailingHandle) ? 0.dp : Self.horizontalItemInset.dp,
            animationSpec: (wantsEditChrome ? animateTrailingEnter : animateTrailingExit) ? tween(durationMillis: editAnimDuration) : snap()
        )
        // Freeze whether we were showing a selection circle (vs delete circle) so content
        // remains stable during exit animation even when the selection binding goes nil.
        let wasShowingSelectionCircle = remember { mutableStateOf(false) }
        if wantsEditChrome {
            wasShowingSelectionCircle.value = bridgedSelection != nil
        }
        let showingEditChrome = wantsEditChrome
            || !editLeadingTransState.isIdle
            || !editTrailingTransState.isIdle
        if showingEditChrome {
            // Compose-side selection state for reactivity (JNI closures aren't observable by Compose).
            // Read external truth once per recomposition; freeze during exit (wantsEditChrome=false)
            // to prevent the selection circle from flipping to "unselected" during the fade-out.
            let externalSelected = listSelection?.isSelected(key) == true
            let selectedState: MutableState<Bool> = remember(key) { mutableStateOf(externalSelected) }
            SideEffect {
                if wantsEditChrome && selectedState.value != externalSelected {
                    selectedState.value = externalSelected
                }
            }
            let doToggle: () -> Void = {
                selectedState.value = !selectedState.value
                listSelection?.toggleSelection(key, rawIdentifier ?? key)
            }
            // iOS renders edit controls inside the row card (background stays full-width).
            // Extract background info to apply at full-row width instead of content-only width.
            let editItemRenderable = itemTransformer?(content) ?? content
            let editListItemModifier = ListItemModifier.combined(for: editItemRenderable)
            let editCustomBackground = editListItemModifier?.background
            let editRowBgColor = BackgroundColor(styling: styling.withStyle(ListStyle.plain), isItem: true)
            // Content modifier with animated horizontal padding (see editLeadingPad / editTrailingPad).
            let editContentModifier = Modifier.padding(start: editLeadingPad.value, end: editTrailingPad.value, top: Self.verticalItemInset.dp, bottom: Self.verticalItemInset.dp).fillMaxWidth().requiredHeightIn(min: Self.minimumItemHeight.dp)
            let editRow: @Composable (Modifier) -> Void = { innerModifier in
                // Guards use MutableTransitionState (currentState||targetState) so the
                // AnimatedVisibility stays composed during exit animation.
                let showLeadingControl = editLeadingTransState.currentState || editLeadingTransState.targetState
                let showTrailingHandle = editTrailingTransState.currentState || editTrailingTransState.targetState
                // Highlight selected rows with a subtle accent tint, matching iOS.
                // Clear immediately when exiting edit mode (before animation completes).
                var columnModifier = innerModifier.fillMaxWidth()
                if wantsEditChrome && wasShowingSelectionCircle.value && selectedState.value {
                    columnModifier = columnModifier.background(Color.accentColor.colorImpl().copy(alpha: Float(0.15)))
                }
                Column(modifier: columnModifier) {
                    Row(modifier: Modifier.fillMaxWidth(), verticalAlignment: androidx.compose.ui.Alignment.CenterVertically) {
                        // Leading control: selection circle or delete circle
                        if showLeadingControl {
                            AnimatedVisibility(
                                visibleState: editLeadingTransState,
                                enter: animateLeadingEnter ? expandHorizontally(animationSpec: tween(durationMillis: editAnimDuration), expandFrom: androidx.compose.ui.Alignment.Start) + fadeIn(animationSpec: tween(durationMillis: editAnimDuration)) : EnterTransition.None,
                                exit: animateLeadingExit ? shrinkHorizontally(animationSpec: tween(durationMillis: editAnimDuration), shrinkTowards: androidx.compose.ui.Alignment.Start) + fadeOut(animationSpec: tween(durationMillis: editAnimDuration)) : ExitTransition.None
                            ) {
                                if wasShowingSelectionCircle.value {
                                    let selected = selectedState.value
                                    Box(modifier: Modifier.size(44.dp).clickable(enabled: wantsEditChrome, onClick: doToggle), contentAlignment: androidx.compose.ui.Alignment.Center) {
                                        if selected {
                                            Icon(imageVector: Icons.Filled.CheckCircle, contentDescription: "Selected", modifier: Modifier.size(24.dp), tint: Color.accentColor.colorImpl())
                                        } else {
                                            Icon(imageVector: Icons.Outlined.Circle, contentDescription: "Unselected", modifier: Modifier.size(24.dp), tint: Color.secondary.colorImpl())
                                        }
                                    }
                                } else if isDeleteEnabled {
                                    Box(modifier: Modifier.size(44.dp).clickable(enabled: wantsEditChrome, onClick: { rememberedDeleteAction.value() }), contentAlignment: androidx.compose.ui.Alignment.Center) {
                                        Icon(imageVector: Icons.Filled.RemoveCircle, contentDescription: "Delete", modifier: Modifier.size(24.dp), tint: Color.red.colorImpl())
                                    }
                                }
                            }
                        }
                        Box(modifier: Modifier.weight(Float(1.0))) {
                            let placement = EnvironmentValues.shared._placement
                            EnvironmentValues.shared.setValues {
                                $0.set_placement(placement.union(ViewPlacement.listItem))
                                return ComposeResult.ok
                            } in: {
                                Self.RenderItemContent(item: editItemRenderable, context: context.content(), modifier: editContentModifier)
                            }
                            // Transparent overlay intercepts taps for selection, taking priority over the
                            // inner content's clickable (later in Box stacking = wins in Compose hit-test).
                            // Only active during edit mode (not during exit animation).
                            if wantsEditChrome, let listSelection {
                                Box(modifier: Modifier.matchParentSize().clickable(onClick: doToggle)) {}
                            }
                        }
                        // Trailing drag handle
                        if showTrailingHandle {
                            AnimatedVisibility(
                                visibleState: editTrailingTransState,
                                enter: animateTrailingEnter ? expandHorizontally(animationSpec: tween(durationMillis: editAnimDuration), expandFrom: androidx.compose.ui.Alignment.End) + fadeIn(animationSpec: tween(durationMillis: editAnimDuration)) : EnterTransition.None,
                                exit: animateTrailingExit ? shrinkHorizontally(animationSpec: tween(durationMillis: editAnimDuration), shrinkTowards: androidx.compose.ui.Alignment.End) + fadeOut(animationSpec: tween(durationMillis: editAnimDuration)) : ExitTransition.None
                            ) {
                                Box(modifier: Modifier.size(44.dp).detectReorderAfterLongPress(reorderableState, key: key), contentAlignment: androidx.compose.ui.Alignment.Center) {
                                    Icon(imageVector: Icons.Filled.DragHandle, contentDescription: "Reorder", modifier: Modifier.size(24.dp), tint: Color.secondary.colorImpl())
                                }
                            }
                        }
                    }
                    // Edit-mode separator with control-aligned indent
                    if editListItemModifier?.separator != Visibility.hidden {
                        let separatorStart = showLeadingControl ? 44.0 : (Self.horizontalItemInset + Double(level) * Self.levelInset)
                        androidx.compose.material3.Divider(modifier: Modifier.padding(start: separatorStart.dp).fillMaxWidth(), color: Color.separator.colorImpl())
                    }
                }
            }
            if let editCustomBackground {
                // Custom listRowBackground: render at full-row width via TargetViewLayout
                let containerContext = context.content(modifier: Modifier.fillMaxWidth().background(editRowBgColor).then(context.modifier))
                TargetViewLayout(context: containerContext, isOverlay: false, alignment: Alignment.center, target: { ctx in
                    editRow(ctx.modifier)
                }, dependent: { ctx in
                    editCustomBackground.Compose(context: ctx)
                })
            } else {
                // Default background: apply item background at full-row width
                editRow(Modifier.background(editRowBgColor))
            }
            return
        }

        let hasAnyActions = !trailingActions.isEmpty() || !leadingActions.isEmpty()
        if hasAnyActions {
            let itemContent: @Composable (Modifier) -> Void = {
                SwipeActionsBox(
                    trailingActions: trailingActions,
                    leadingActions: leadingActions,
                    allowsFullSwipeTrailing: allowsFullSwipeTrailing,
                    allowsFullSwipeLeading: allowsFullSwipeLeading,
                    modifier: $0,
                    activeSwipeKey: activeSwipeKey,
                    onDestructiveDeleteStart: { _ in
                        isDestructiveDeleteAnimating.value = true
                    },
                    onDestructiveDeleteEnd: {
                        isDestructiveDeleteAnimating.value = false
                    },
                    itemKey: key,
                    isReordering: reorderableState.isAnyItemDragging,
                    listState: reorderableState.listState
                ) {
                    RenderItem(content: content, level: level, context: context, styling: styling)
                }
            }
            itemContent(modifier)
        } else {
            RenderItem(content: content, level: level, context: context, modifier: modifier, styling: styling)
        }
    }

    @Composable private func RenderSectionHeader(content: Renderable, context: ComposeContext, styling: ListStyling, isTop: Bool) {
        if !isTop && styling.style != ListStyle.plain {
            // Vertical padding
            RenderFooter(styling: styling, safeAreaHeight: 0.dp, hasBottomSection: true)
        }
        let backgroundColor = BackgroundColor(styling: styling, isItem: false)
        let modifier = Modifier
            .zIndex(Float(0.5))
            .background(backgroundColor)
            .then(context.modifier)
        var contentModifier = Modifier.fillMaxWidth()
        if isTop && styling.style != .plain {
            contentModifier = contentModifier.padding(start: Self.horizontalItemInset.dp, top: 0.dp, end: Self.horizontalItemInset.dp, bottom: Self.verticalItemInset.dp)
        } else {
            contentModifier = contentModifier.padding(horizontal: Self.horizontalItemInset.dp, vertical: Self.verticalItemInset.dp)
        }
        Box(modifier: modifier, contentAlignment: androidx.compose.ui.Alignment.BottomCenter) {
            Column(modifier: Modifier.fillMaxWidth()) {
                EnvironmentValues.shared.setValues {
                    $0.set_listSectionHeaderStyle(styling.style)
                    return ComposeResult.ok
                } in: {
                    content.Render(context: context.content(modifier: contentModifier))
                }
            }
            if styling.style != ListStyle.plain {
                RenderRoundedCorners(isTop: true, fill: backgroundColor)
            }
        }
    }

    @Composable private func RenderSectionFooter(content: Renderable, context: ComposeContext, styling: ListStyling) {
        if styling.style == .plain {
            let footerContent: Renderable
            if let lazySectionFooter = content as? LazySectionFooter, !lazySectionFooter.content.any({ !$0.isSwiftUIEmptyView }) {
                // Replace an empty footer with an empty view for RenderItem handling
                footerContent = EmptyView()
            } else {
                footerContent = content
            }
            RenderItem(content: footerContent, level: 0, context: context, styling: styling, isItem: false)
        } else {
            let backgroundColor = BackgroundColor(styling: styling, isItem: false)
            let modifier = Modifier.offset(y: -1.dp) // Cover last row's divider
                .zIndex(Float(0.5))
                .background(backgroundColor)
                .then(context.modifier)
            let contentModifier = Modifier.fillMaxWidth().padding(horizontal: Self.horizontalItemInset.dp, vertical: Self.verticalItemInset.dp)
            Box(modifier: modifier, contentAlignment: androidx.compose.ui.Alignment.TopCenter) {
                Column(modifier: Modifier.fillMaxWidth().heightIn(min: 1.dp)) {
                    EnvironmentValues.shared.setValues {
                        $0.set_listSectionFooterStyle(styling.style)
                        return ComposeResult.ok
                    } in: {
                        content.Render(context: context.content(modifier: contentModifier))
                    }
                }
                RenderRoundedCorners(isTop: false, fill: backgroundColor)
            }
        }
    }

    /// - Warning: Only call for non-.plain styles or with a positive safe area height. This is distinct from having this function detect
    /// .plain and zero-height and return without rendering. That causes .plain style lists to have a weird rubber banding effect on overscroll.
    @Composable private func RenderHeader(styling: ListStyling, safeAreaHeight: Dp, hasTopSection: Bool) {
        var height = safeAreaHeight
        if styling.style != .plain {
            height += Self.verticalInset.dp
        }
        let backgroundColor = BackgroundColor(styling: styling, isItem: false)
        let modifier = Modifier.fillMaxWidth()
            .height(height)
            .zIndex(Float(0.5))
            .background(backgroundColor)
        Box(modifier: modifier, contentAlignment: androidx.compose.ui.Alignment.BottomCenter) {
            if !hasTopSection && styling.style != .plain {
                RenderRoundedCorners(isTop: true, fill: backgroundColor)
            }
        }
    }

    /// - Warning: Only call for non-.plain styles or with a positive safe area height. This is distinct from having this function detect
    /// .plain and zero-height and return without rendering. That causes .plain style lists to have a weird rubber banding effect on overscroll.
    @Composable private func RenderFooter(styling: ListStyling, safeAreaHeight: Dp, hasBottomSection: Bool) {
        var height = safeAreaHeight
        var offset = 0.dp
        if styling.style != .plain {
            height += Self.verticalInset.dp
            offset = -1.dp // Cover last row's divider
        }
        let backgroundColor = BackgroundColor(styling: styling, isItem: false)
        let modifier = Modifier.fillMaxWidth()
            .height(height)
            .offset(y: offset)
            .zIndex(Float(0.5))
            .background(backgroundColor)
        Box(modifier: modifier, contentAlignment: androidx.compose.ui.Alignment.TopCenter) {
            if !hasBottomSection && styling.style != .plain {
                RenderRoundedCorners(isTop: false, fill: backgroundColor)
            }
        }
    }

    @Composable private func RenderRoundedCorners(isTop: Bool, fill: androidx.compose.ui.graphics.Color) {
        let shape = GenericShape { size, _ in
            let rect = Rect(left: Float(0.0), top: Float(0.0), right: size.width, bottom: size.height)
            let rectPath = androidx.compose.ui.graphics.Path()
            rectPath.addRect(rect)
            let roundRect: RoundRect
            if isTop {
                roundRect = RoundRect(rect, topLeft: CornerRadius(size.height), topRight: CornerRadius(size.height))
            } else {
                roundRect = RoundRect(rect, bottomLeft: CornerRadius(size.height), bottomRight: CornerRadius(size.height))
            }
            let roundedRectPath = androidx.compose.ui.graphics.Path()
            roundedRectPath.addRoundRect(roundRect)
            addPath(combine(PathOperation.Difference, rectPath, roundedRectPath))
        }
        let offset = isTop ? listSectionCornerRadius.dp : -listSectionCornerRadius.dp
        let modifier = Modifier
            .fillMaxWidth()
            .height(listSectionCornerRadius.dp)
            .offset(y: offset)
            .clip(shape)
            .background(fill)
        Box(modifier: modifier)
    }

    @Composable private func RenderSearchField(state: SearchableState, context: ComposeContext, styling: ListStyling, safeAreaHeight: Dp) {
        var modifier = Modifier.background(BackgroundColor(styling: styling, isItem: false))
        if styling.style == ListStyle.plain {
            modifier = modifier.padding(top: Self.verticalInset.dp + safeAreaHeight, start: Self.horizontalInset.dp, end: Self.horizontalInset.dp, bottom: Self.verticalInset.dp)
        } else {
            modifier = modifier.padding(top: Self.verticalInset.dp + safeAreaHeight)
        }
        modifier = modifier.fillMaxWidth()
        SearchField(state: state, context: context.content(modifier: modifier))
    }

    @Composable private func BackgroundColor(styling: ListStyling, isItem: Bool) -> androidx.compose.ui.graphics.Color {
        if !isItem && styling.backgroundVisibility == Visibility.hidden {
            return Color.clear.colorImpl()
        } else if styling.style == ListStyle.plain {
            return Color.background.colorImpl()
        } else {
            return Color.systemBackground.colorImpl()
        }
    }
    #else
    public var body: some View {
        stubView()
    }
    #endif
}

#if SKIP
// Kotlin does not support generic constructor parameters, so we have to model many List constructors as functions

//extension List {
//    public init<Data, RowContent>(_ data: Data, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable
//}
public func List<ObjectType>(_ data: any RandomAccessCollection<ObjectType>, @ViewBuilder rowContent: (ObjectType) -> any View) -> List {
    return List(identifier: { ($0 as! Identifiable<Hashable>).id }, objects: data as! RandomAccessCollection<Any>, objectContent: { rowContent($0 as! ObjectType) })
}

//extension List {
//    public init<Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, ID, RowContent>, Data : RandomAccessCollection, ID : Hashable, RowContent : View
//}
public func List<ObjectType>(_ data: any RandomAccessCollection<ObjectType>, id: (ObjectType) -> AnyHashable?, @ViewBuilder rowContent: (ObjectType) -> any View) -> List where ObjectType: Any {
    return List(identifier: { id($0 as! ObjectType) }, objects: data as! RandomAccessCollection<Any>, objectContent: { rowContent($0 as! ObjectType) })
}
public func List(_ data: Range<Int>, id: ((Int) -> AnyHashable?)? = nil, @ViewBuilder rowContent: (Int) -> any View) -> List {
    return List(identifier: id == nil ? nil : { id!($0 as! Int) }, indexRange: data, indexedContent: rowContent)
}

//extension List {
//  public init<Data, RowContent>(_ data: Binding<Data>, editActions: EditActions /* <Data> */, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<IndexedIdentifierCollection<Data, Data.Element.ID>, Data.Element.ID, EditableCollectionContent<RowContent, Data>>, Data : MutableCollection, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable, Data.Index : Hashable
//}
public func List<Data, ObjectType>(_ data: Binding<Data>, editActions: EditActions = [], @ViewBuilder rowContent: (Binding<ObjectType>) -> any View) -> List where Data: RandomAccessCollection<ObjectType> {
    return List(identifier: { ($0 as! Identifiable<Hashable>).id }, objectsBinding: data as! Binding<RandomAccessCollection<Any>>, objectsBindingContent: { data, index in
        let binding = Binding<ObjectType>(get: { data.wrappedValue[index] as! ObjectType }, set: { (data.wrappedValue as! skip.lib.MutableCollection<ObjectType>)[index] = $0 })
        return rowContent(binding)
    }, editActions: editActions)
}

//extension List {
//  public init<Data, ID, RowContent>(_ data: Binding<Data>, id: KeyPath<Data.Element, ID>, editActions: EditActions /* <Data> */, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<IndexedIdentifierCollection<Data, ID>, ID, EditableCollectionContent<RowContent, Data>>, Data : MutableCollection, Data : RandomAccessCollection, ID : Hashable, RowContent : View, Data.Index : Hashable
//}
public func List<Data, ObjectType>(_ data: Binding<Data>, id: (ObjectType) -> AnyHashable?, editActions: EditActions = [], @ViewBuilder rowContent: (Binding<ObjectType>) -> any View) -> List where Data: RandomAccessCollection<ObjectType> {
    return List(identifier: { id($0 as! ObjectType) }, objectsBinding: data as! Binding<RandomAccessCollection<Any>>, objectsBindingContent: { data, index in
        let binding = Binding<ObjectType>(get: { data.wrappedValue[index] as! ObjectType }, set: { (data.wrappedValue as! skip.lib.MutableCollection<ObjectType>)[index] = $0 })
        return rowContent(binding)
    }, editActions: editActions)
}
#endif

struct ListStyling: Equatable {
    let style: ListStyle
    let backgroundVisibility: Visibility

    func withStyle(_ style: ListStyle) -> ListStyling {
        return ListStyling(style: style, backgroundVisibility: backgroundVisibility)
    }
}

#if SKIP
@Stable struct ListArguments: Equatable {
    let headerSafeAreaHeight: Dp
    let footerSafeAreaHeight: Dp
    let safeAreaEdges: Edge.Set
}
#endif

public struct ListStyle: RawRepresentable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let automatic = ListStyle(rawValue: 0) // For bridging

    @available(*, unavailable)
    public static let sidebar = ListStyle(rawValue: 1) // For bridging

    @available(*, unavailable)
    public static let insetGrouped = ListStyle(rawValue: 2) // For bridging

    @available(*, unavailable)
    public static let grouped = ListStyle(rawValue: 3) // For bridging

    @available(*, unavailable)
    public static let inset = ListStyle(rawValue: 4) // For bridging

    public static let plain = ListStyle(rawValue: 5) // For bridging
}

public enum ListItemTint {
    case fixed(Color)
    case preferred(Color)
    case monochrome
}

public enum ListSectionSpacing {
    case `default`
    case compact
    case custom(CGFloat)
}

extension View {
    // SKIP @bridge
    public func listRowBackground(_ view: (any View)?) -> any View {
        #if SKIP
        return ModifiedContent(content: self, modifier: ListItemModifier(background: view))
        #else
        return self
        #endif
    }
    
    public func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        #if SKIP
        return ModifiedContent(content: self, modifier: ListItemModifier(separator: visibility))
        #else
        return self
        #endif
    }

    // SKIP @bridge
    public func listRowSeparator(bridgedVisibility: Int, bridgedEdges: Int) -> any View {
        return listRowSeparator(Visibility(rawValue: bridgedVisibility) ?? .automatic, edges: VerticalEdge.Set(rawValue: bridgedEdges))
    }

    @available(*, unavailable)
    public func listRowSeparatorTint(_ color: Color?, edges: VerticalEdge.Set = .all) -> some View {
        return self
    }

    @available(*, unavailable)
    public func listSectionIndexVisibility(_ visibility: Visibility) -> some View {
        return self
    }

    @available(*, unavailable)
    public func listSectionSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View {
        return self
    }

    @available(*, unavailable)
    public func listSectionSeparatorTint(_ color: Color?, edges: VerticalEdge.Set = .all) -> some View {
        return self
    }

    public func listStyle(_ style: ListStyle) -> some View {
        #if SKIP
        return environment(\._listStyle, style, affectsEvaluate: false)
        #else
        return self
        #endif
    }

    // SKIP @bridge
    public func listStyle(bridgedStyle: Int) -> any View {
        return listStyle(ListStyle(rawValue: bridgedStyle))
    }

    // SKIP @bridge
    public func listItemTint(_ tint: Color?) -> any View {
        #if SKIP
        return environment(\._listItemTint, tint, affectsEvaluate: false)
        #else
        return self
        #endif
    }

    @available(*, unavailable)
    public func listItemTint(_ tint: ListItemTint?) -> some View {
        return self
    }

    @available(*, unavailable)
    public func listRowInsets(_ insets: EdgeInsets?) -> some View {
        return self
    }

    @available(*, unavailable)
    public func listRowSpacing(_ spacing: CGFloat?) -> some View {
        return self
    }

    @available(*, unavailable)
    public func listSectionSpacing(_ spacing: ListSectionSpacing) -> some View {
        return self
    }

    @available(*, unavailable)
    public func listSectionSpacing(_ spacing: CGFloat) -> some View {
        return self
    }

}

#if SKIP
final class ListItemModifier: RenderModifier {
    let background: View?
    let separator: Visibility?

    init(background: View? = nil, separator: Visibility? = nil) {
        self.background = background
        self.separator = separator
        super.init()
    }

    static func combined(for renderable: Renderable) -> ListItemModifier {
        var background: View? = nil
        var separator: Visibility? = nil
        renderable.forEachModifier {
            if let listItemModifier = $0 as? ListItemModifier {
                background = background ?? listItemModifier.background
                separator = separator ?? listItemModifier.separator
            }
            return nil
        }
        return ListItemModifier(background: background, separator: separator)
    }
}

final class BadgeModifier: RenderModifier {
    let badge: Text?
    let prominence: BadgeProminence?

    init(badge: Text? = nil, prominence: BadgeProminence? = nil) {
        self.badge = badge
        self.prominence = prominence
        super.init()
    }

    static func combined(for renderable: Renderable) -> BadgeModifier {
        var badge: Text? = nil
        var prominence: BadgeProminence? = nil
        renderable.forEachModifier {
            if let badgeModifier = $0 as? BadgeModifier {
                badge = badge ?? badgeModifier.badge
                prominence = prominence ?? badgeModifier.prominence
            }
            return nil
        }
        return BadgeModifier(badge: badge, prominence: prominence)
    }
}
#endif

#if false
/*
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension List {

    /// Creates a list that computes its rows on demand from an underlying
    /// collection of identifiable data, optionally allowing users to select
    /// multiple rows.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the list.
    ///   - selection: A binding to a set that identifies selected rows.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, RowContent>(_ data: Data, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable { fatalError() }

    /// Creates a hierarchical list that computes its rows on demand from an
    /// underlying collection of identifiable data, optionally allowing users to
    /// select multiple rows.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the list.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes an element
    ///     capable of having children that's currently childless, such as an
    ///     empty directory in a file system. On the other hand, if the property
    ///     at the key path is `nil`, then the outline group treats `data` as a
    ///     leaf in the tree, like a regular file in a file system.
    ///   - selection: A binding to a set that identifies selected rows.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(iOS 14.0, macOS 11.0, *)
//    @available(tvOS, unavailable)
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, RowContent>(_ data: Data, children: KeyPath<Data.Element, Data?>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == OutlineGroup<Data, Data.Element.ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable { fatalError() }

    /// Creates a list that identifies its rows based on a key path to the
    /// identifier of the underlying data, optionally allowing users to select
    /// multiple rows.
    ///
    /// - Parameters:
    ///   - data: The data for populating the list.
    ///   - id: The key path to the data model's identifier.
    ///   - selection: A binding to a set that identifies selected rows.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, ID, RowContent>, Data : RandomAccessCollection, ID : Hashable, RowContent : View { fatalError() }

    /// Creates a hierarchical list that identifies its rows based on a key path
    /// to the identifier of the underlying data, optionally allowing users to
    /// select multiple rows.
    ///
    /// - Parameters:
    ///   - data: The data for populating the list.
    ///   - id: The key path to the data model's identifier.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes a node capable
    ///     of having children that is currently childless, such as an empty
    ///     directory in a file system. On the other hand, if the property at the
    ///     key path is `nil`, then `data` is treated as a leaf node in the tree,
    ///     like a regular file in a file system.
    ///   - selection: A binding to a set that identifies selected rows.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(iOS 14.0, macOS 11.0, *)
//    @available(tvOS, unavailable)
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == OutlineGroup<Data, ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : RandomAccessCollection, ID : Hashable, RowContent : View { fatalError() }

    /// Creates a list that computes its views on demand over a constant range,
    /// optionally allowing users to select multiple rows.
    ///
    /// This instance only reads the initial value of `data` and doesn't need to
    /// identify views across updates. To compute views on demand over a dynamic
    /// range, use ``List/init(_:id:selection:rowContent:)-9a28m``.
    ///
    /// - Parameters:
    ///   - data: A constant range of data to populate the list.
    ///   - selection: A binding to a set that identifies selected rows.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS, unavailable)
//    @MainActor public init<RowContent>(_ data: Range<Int>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Int) -> RowContent) where Content == ForEach<Range<Int>, Int, HStack<RowContent>>, RowContent : View { fatalError() }

    /// Creates a list that computes its rows on demand from an underlying
    /// collection of identifiable data, optionally allowing users to select a
    /// single row.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the list.
    ///   - selection: A binding to a selected value.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS 10.0, *)
//    @MainActor public init<Data, RowContent>(_ data: Data, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, Data.Element.ID, RowContent>, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable { fatalError() }

    /// Creates a hierarchical list that computes its rows on demand from an
    /// underlying collection of identifiable data, optionally allowing users to
    /// select a single row.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the list.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes a node capable
    ///     of having children that is currently childless, such as an empty
    ///     directory in a file system. On the other hand, if the property at the
    ///     key path is `nil`, then `data` is treated as a leaf node in the tree,
    ///     like a regular file in a file system.
    ///   - selection: A binding to a selected value.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(iOS 14.0, macOS 11.0, *)
//    @available(tvOS, unavailable)
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, RowContent>(_ data: Data, children: KeyPath<Data.Element, Data?>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == OutlineGroup<Data, Data.Element.ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable { fatalError() }

    /// Creates a list that identifies its rows based on a key path to the
    /// identifier of the underlying data, optionally allowing users to select a
    /// single row.
    ///
    /// - Parameters:
    ///   - data: The data for populating the list.
    ///   - id: The key path to the data model's identifier.
    ///   - selection: A binding to a selected value.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS 10.0, *)
//    @MainActor public init<Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == ForEach<Data, ID, RowContent>, Data : RandomAccessCollection, ID : Hashable, RowContent : View { fatalError() }

    /// Creates a hierarchical list that identifies its rows based on a key path
    /// to the identifier of the underlying data, optionally allowing users to
    /// select a single row.
    ///
    /// - Parameters:
    ///   - data: The data for populating the list.
    ///   - id: The key path to the data model's identifier.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes a node capable
    ///     of having children that is currently childless, such as an empty
    ///     directory in a file system. On the other hand, if the property at the
    ///     key path is `nil`, then `data` is treated as a leaf node in the tree,
    ///     like a regular file in a file system.
    ///   - selection: A binding to a selected value.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(iOS 14.0, macOS 11.0, *)
//    @available(tvOS, unavailable)
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == OutlineGroup<Data, ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : RandomAccessCollection, ID : Hashable, RowContent : View { fatalError() }

    /// Creates a list that computes its views on demand over a constant range,
    /// optionally allowing users to select a single row.
    ///
    /// This instance only reads the initial value of `data` and doesn't need to
    /// identify views across updates. To compute views on demand over a dynamic
    /// range, use ``List/init(_:id:selection:rowContent:)-2r2u9``.
    ///
    /// - Parameters:
    ///   - data: A constant range of data to populate the list.
    ///   - selection: A binding to a selected value.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS, unavailable)
//    @MainActor public init<RowContent>(_ data: Range<Int>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Int) -> RowContent) where Content == ForEach<Range<Int>, Int, RowContent>, RowContent : View { fatalError() }
}

//@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
//extension List where SelectionValue == Never {
    /// Creates a hierarchical list that computes its rows on demand from an
    /// underlying collection of identifiable data.
    ///
    /// - Parameters:
    ///   - data: A collection of identifiable data for computing the list.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes a node capable
    ///     of having children that is currently childless, such as an empty
    ///     directory in a file system. On the other hand, if the property at the
    ///     key path is `nil`, then `data` is treated as a leaf node in the tree,
    ///     like a regular file in a file system.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(iOS 14.0, macOS 11.0, *)
//    @available(tvOS, unavailable)
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, RowContent>(_ data: Data, children: KeyPath<Data.Element, Data?>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == OutlineGroup<Data, Data.Element.ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable { fatalError() }

    /// Creates a hierarchical list that identifies its rows based on a key path
    /// to the identifier of the underlying data.
    ///
    /// - Parameters:
    ///   - data: The data for populating the list.
    ///   - id: The key path to the data model's identifier.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes a node capable
    ///     of having children that is currently childless, such as an empty
    ///     directory in a file system. On the other hand, if the property at the
    ///     key path is `nil`, then `data` is treated as a leaf node in the tree,
    ///     like a regular file in a file system.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(iOS 14.0, macOS 11.0, *)
//    @available(tvOS, unavailable)
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, ID, RowContent>(_ data: Data, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>, @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent) where Content == OutlineGroup<Data, ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : RandomAccessCollection, ID : Hashable, RowContent : View { fatalError() }
//}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension List {

    /// Creates a list that computes its rows on demand from an underlying
    /// collection of identifiable data, optionally allowing users to select
    /// multiple rows.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the list.
    ///   - selection: A binding to a set that identifies selected rows.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, RowContent>(_ data: Binding<Data>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, Data.Element.ID)>, Data.Element.ID, RowContent>, Data : MutableCollection, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable, Data.Index : Hashable { fatalError() }

    /// Creates a list that identifies its rows based on a key path to the
    /// identifier of the underlying data, optionally allowing users to select
    /// multiple rows.
    ///
    /// - Parameters:
    ///   - data: The data for populating the list.
    ///   - id: The key path to the data model's identifier.
    ///   - selection: A binding to a set that identifies selected rows.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, ID, RowContent>(_ data: Binding<Data>, id: KeyPath<Data.Element, ID>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, ID)>, ID, RowContent>, Data : MutableCollection, Data : RandomAccessCollection, ID : Hashable, RowContent : View, Data.Index : Hashable { fatalError() }

    /// Creates a list that computes its rows on demand from an underlying
    /// collection of identifiable data, optionally allowing users to select a
    /// single row.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the list.
    ///   - selection: A binding to a selected value.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, RowContent>(_ data: Binding<Data>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, Data.Element.ID)>, Data.Element.ID, RowContent>, Data : MutableCollection, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable, Data.Index : Hashable { fatalError() }

    /// Creates a list that identifies its rows based on a key path to the
    /// identifier of the underlying data, optionally allowing users to select a
    /// single row.
    ///
    /// - Parameters:
    ///   - data: The data for populating the list.
    ///   - id: The key path to the data model's identifier.
    ///   - selection: A binding to a selected value.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, ID, RowContent>(_ data: Binding<Data>, id: KeyPath<Data.Element, ID>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<LazyMapSequence<Data.Indices, (Data.Index, ID)>, ID, RowContent>, Data : MutableCollection, Data : RandomAccessCollection, ID : Hashable, RowContent : View, Data.Index : Hashable { fatalError() }
}

@available(iOS 15.0, macOS 12.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
extension List {

    /// Creates a hierarchical list that computes its rows on demand from a
    /// binding to an underlying collection of identifiable data, optionally
    /// allowing users to select multiple rows.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the list.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes an element
    ///     capable of having children that's currently childless, such as an
    ///     empty directory in a file system. On the other hand, if the property
    ///     at the key path is `nil`, then the outline group treats `data` as a
    ///     leaf in the tree, like a regular file in a file system.
    ///   - selection: A binding to a set that identifies selected rows.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @MainActor public init<Data, RowContent>(_ data: Binding<Data>, children: WritableKeyPath<Data.Element, Data?>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == OutlineGroup<Binding<Data>, Data.Element.ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : MutableCollection, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable { fatalError() }

    /// Creates a hierarchical list that identifies its rows based on a key path
    /// to the identifier of the underlying data, optionally allowing users to
    /// select multiple rows.
    ///
    /// - Parameters:
    ///   - data: The data for populating the list.
    ///   - id: The key path to the data model's identifier.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes a node capable
    ///     of having children that is currently childless, such as an empty
    ///     directory in a file system. On the other hand, if the property at the
    ///     key path is `nil`, then `data` is treated as a leaf node in the tree,
    ///     like a regular file in a file system.
    ///   - selection: A binding to a set that identifies selected rows.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @MainActor public init<Data, ID, RowContent>(_ data: Binding<Data>, id: KeyPath<Data.Element, ID>, children: WritableKeyPath<Data.Element, Data?>, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == OutlineGroup<Binding<Data>, ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : MutableCollection, Data : RandomAccessCollection, ID : Hashable, RowContent : View { fatalError() }

    /// Creates a hierarchical list that computes its rows on demand from a
    /// binding to an underlying collection of identifiable data, optionally
    /// allowing users to select a single row.
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the list.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes a node capable
    ///     of having children that is currently childless, such as an empty
    ///     directory in a file system. On the other hand, if the property at the
    ///     key path is `nil`, then `data` is treated as a leaf node in the tree,
    ///     like a regular file in a file system.
    ///   - selection: A binding to a selected value.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @MainActor public init<Data, RowContent>(_ data: Binding<Data>, children: WritableKeyPath<Data.Element, Data?>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == OutlineGroup<Binding<Data>, Data.Element.ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : MutableCollection, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable { fatalError() }

    /// Creates a hierarchical list that identifies its rows based on a key path
    /// to the identifier of the underlying data, optionally allowing users to
    /// select a single row.
    ///
    /// - Parameters:
    ///   - data: The data for populating the list.
    ///   - id: The key path to the data model's identifier.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes a node capable
    ///     of having children that is currently childless, such as an empty
    ///     directory in a file system. On the other hand, if the property at the
    ///     key path is `nil`, then `data` is treated as a leaf node in the tree,
    ///     like a regular file in a file system.
    ///   - selection: A binding to a selected value.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @MainActor public init<Data, ID, RowContent>(_ data: Binding<Data>, id: KeyPath<Data.Element, ID>, children: WritableKeyPath<Data.Element, Data?>, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == OutlineGroup<Binding<Data>, ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : MutableCollection, Data : RandomAccessCollection, ID : Hashable, RowContent : View { fatalError() }
}

//@available(iOS 15.0, macOS 12.0, *)
//@available(tvOS, unavailable)
//@available(watchOS, unavailable)
//extension List where SelectionValue == Never {

    /// Creates a hierarchical list that computes its rows on demand from a
    /// binding to an underlying collection of identifiable data.
    ///
    /// - Parameters:
    ///   - data: A collection of identifiable data for computing the list.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes a node capable
    ///     of having children that is currently childless, such as an empty
    ///     directory in a file system. On the other hand, if the property at the
    ///     key path is `nil`, then `data` is treated as a leaf node in the tree,
    ///     like a regular file in a file system.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @MainActor public init<Data, RowContent>(_ data: Binding<Data>, children: WritableKeyPath<Data.Element, Data?>, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == OutlineGroup<Binding<Data>, Data.Element.ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : MutableCollection, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable { fatalError() }

    /// Creates a hierarchical list that identifies its rows based on a key path
    /// to the identifier of the underlying data.
    ///
    /// - Parameters:
    ///   - data: The data for populating the list.
    ///   - id: The key path to the data model's identifier.
    ///   - children: A key path to a property whose non-`nil` value gives the
    ///     children of `data`. A non-`nil` but empty value denotes a node capable
    ///     of having children that is currently childless, such as an empty
    ///     directory in a file system. On the other hand, if the property at the
    ///     key path is `nil`, then `data` is treated as a leaf node in the tree,
    ///     like a regular file in a file system.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @MainActor public init<Data, ID, RowContent>(_ data: Binding<Data>, id: KeyPath<Data.Element, ID>, children: WritableKeyPath<Data.Element, Data?>, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == OutlineGroup<Binding<Data>, ID, RowContent, RowContent, DisclosureGroup<RowContent, OutlineSubgroupChildren>>, Data : MutableCollection, Data : RandomAccessCollection, ID : Hashable, RowContent : View { fatalError() }
//}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension List {

    /// Creates a list that computes its rows on demand from an underlying
    /// collection of identifiable, allows to edit the collection, and
    /// optionally allows users to select multiple rows.
    ///
    /// The following example creates a list to display a collection of favorite
    /// foods allowing the user to delete or move elements from the
    /// collection, and select multiple elements.
    ///
    ///     List(
    ///         $foods,
    ///         editActions: [.delete, .move],
    ///         selection: $selectedFoods
    ///     ) { $food in
    ///        HStack {
    ///            Text(food.name)
    ///            Toggle("Favorite", isOn: $food.isFavorite)
    ///        }
    ///     }
    ///
    /// Use ``View/deleteDisabled(_:)`` and ``View/moveDisabled(_:)``
    /// to disable respectively delete or move actions on a per-row basis.
    ///
    /// Explicit ``DynamicViewContent.onDelete(perform:)``,
    /// ``DynamicViewContent.onMove(perform:)``, or
    /// ``View.swipeActions(edge:allowsFullSwipe:content:)``
    /// modifiers will override any synthesized action
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing and to be edited by
    ///     the list.
    ///   - editActions: The edit actions that are synthesized on `data`.
    ///   - selection: A binding to a set that identifies selected rows.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, RowContent>(_ data: Binding<Data>, editActions: EditActions /* <Data> */, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<IndexedIdentifierCollection<Data, Data.Element.ID>, Data.Element.ID, EditableCollectionContent<RowContent, Data>>, Data : MutableCollection, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable, Data.Index : Hashable { fatalError() }

    /// Creates a list that computes its rows on demand from an underlying
    /// collection of identifiable, allows to edit the collection, and
    /// optionally allows users to select multiple rows.
    ///
    /// The following example creates a list to display a collection of favorite
    /// foods allowing the user to delete or move elements from the
    /// collection, and select multiple elements.
    ///
    ///     List(
    ///         $foods,
    ///         editActions: [.delete, .move],
    ///         selection: $selectedFoods
    ///     ) { $food in
    ///        HStack {
    ///            Text(food.name)
    ///            Toggle("Favorite", isOn: $food.isFavorite)
    ///        }
    ///     }
    ///
    /// Use ``View/deleteDisabled(_:)`` and ``View/moveDisabled(_:)``
    /// to disable respectively delete or move actions on a per-row basis.
    ///
    /// Explicit ``DynamicViewContent.onDelete(perform:)``,
    /// ``DynamicViewContent.onMove(perform:)``, or
    /// ``View.swipeActions(edge:allowsFullSwipe:content:)``
    /// modifiers will override any synthesized action
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing and to be edited by
    ///     the list.
    ///   - id: The key path to the data model's identifier.
    ///   - editActions: The edit actions that are synthesized on `data`.
    ///   - selection: A binding to a set that identifies selected rows.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, ID, RowContent>(_ data: Binding<Data>, id: KeyPath<Data.Element, ID>, editActions: EditActions /* <Data> */, selection: Binding<Set<SelectionValue>>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<IndexedIdentifierCollection<Data, ID>, ID, EditableCollectionContent<RowContent, Data>>, Data : MutableCollection, Data : RandomAccessCollection, ID : Hashable, RowContent : View, Data.Index : Hashable { fatalError() }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension List {

    /// Creates a list that computes its rows on demand from an underlying
    /// collection of identifiable data, allows to edit the collection, and
    /// optionally allowing users to select a single row.
    ///
    /// The following example creates a list to display a collection of favorite
    /// foods allowing the user to delete or move elements from the
    /// collection, and select a single elements.
    ///
    ///     List(
    ///         $foods,
    ///         editActions: [.delete, .move],
    ///         selection: $selectedFood
    ///     ) { $food in
    ///        HStack {
    ///            Text(food.name)
    ///            Toggle("Favorite", isOn: $food.isFavorite)
    ///        }
    ///     }
    ///
    /// Use ``View/deleteDisabled(_:)`` and ``View/moveDisabled(_:)``
    /// to disable respectively delete or move actions on a per-row basis.
    ///
    /// Explicit ``DynamicViewContent.onDelete(perform:)``,
    /// ``DynamicViewContent.onMove(perform:)``, or
    /// ``View.swipeActions(edge:allowsFullSwipe:content:)``
    /// modifiers will override any synthesized action
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the list.
    ///   - editActions: The edit actions that are synthesized on `data`.
    ///   - selection: A binding to a selected value.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, RowContent>(_ data: Binding<Data>, editActions: EditActions /* <Data> */, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<IndexedIdentifierCollection<Data, Data.Element.ID>, Data.Element.ID, EditableCollectionContent<RowContent, Data>>, Data : MutableCollection, Data : RandomAccessCollection, RowContent : View, Data.Element : Identifiable, Data.Index : Hashable { fatalError() }

    /// Creates a list that computes its rows on demand from an underlying
    /// collection of identifiable data, allows to edit the collection, and
    /// optionally allowing users to select a single row.
    ///
    /// The following example creates a list to display a collection of favorite
    /// foods allowing the user to delete or move elements from the
    /// collection, and select a single elements.
    ///
    ///     List(
    ///         $foods,
    ///         editActions: [.delete, .move],
    ///         selection: $selectedFood
    ///     ) { $food in
    ///        HStack {
    ///            Text(food.name)
    ///            Toggle("Favorite", isOn: $food.isFavorite)
    ///        }
    ///     }
    ///
    /// Use ``View/deleteDisabled(_:)`` and ``View/moveDisabled(_:)``
    /// to disable respectively delete or move actions on a per-row basis.
    ///
    /// Explicit ``DynamicViewContent.onDelete(perform:)``,
    /// ``DynamicViewContent.onMove(perform:)``, or
    /// ``View.swipeActions(edge:allowsFullSwipe:content:)``
    /// modifiers will override any synthesized action
    ///
    /// - Parameters:
    ///   - data: The identifiable data for computing the list.
    ///   - id: The key path to the data model's identifier.
    ///   - editActions: The edit actions that are synthesized on `data`.
    ///   - selection: A binding to a selected value.
    ///   - rowContent: A view builder that creates the view for a single row of
    ///     the list.
//    @available(watchOS, unavailable)
//    @MainActor public init<Data, ID, RowContent>(_ data: Binding<Data>, id: KeyPath<Data.Element, ID>, editActions: EditActions /* <Data> */, selection: Binding<SelectionValue?>?, @ViewBuilder rowContent: @escaping (Binding<Data.Element>) -> RowContent) where Content == ForEach<IndexedIdentifierCollection<Data, ID>, ID, EditableCollectionContent<RowContent, Data>>, Data : MutableCollection, Data : RandomAccessCollection, ID : Hashable, RowContent : View, Data.Index : Hashable { fatalError() }
}
 */
#endif
#endif
