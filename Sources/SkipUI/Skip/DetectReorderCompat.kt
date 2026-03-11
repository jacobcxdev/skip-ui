// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
//
// Compatibility shim for standalone long-press drag handle detection.
// Uses LocalReorderableItemPosition (provided by ReorderableCollectionItem)
// so that drag handles can be placed outside ReorderableCollectionItemScope.
package sh.calvin.reorderable

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.unit.IntSize
import kotlinx.coroutines.launch

/**
 * Makes this element a long-press drag handle for a reorderable item.
 *
 * This standalone modifier can be used anywhere inside a [ReorderableItem]'s content tree,
 * without requiring [ReorderableCollectionItemScope] as a receiver. It relies on
 * [LocalReorderableItemPosition] which is provided automatically by [ReorderableCollectionItem].
 *
 * @param state The reorderable state
 * @param key The key of the item this handle belongs to
 * @param enabled Whether drag is enabled
 */
fun Modifier.detectReorderAfterLongPress(
    state: ReorderableLazyCollectionState<*>,
    key: Any,
    enabled: Boolean = true,
): Modifier = composed {
    val itemPositionProvider = LocalReorderableItemPosition.current
    var handleOffset by remember { mutableStateOf(Offset.Zero) }
    var handleSize by remember { mutableStateOf(IntSize.Zero) }
    val coroutineScope = rememberCoroutineScope()

    onGloballyPositioned {
        handleOffset = it.positionInRoot()
        handleSize = it.size
    }.draggable(
        key1 = state,
        enabled = enabled && (state.isItemDragging(key).value || !state.isAnyItemDragging),
        dragGestureDetector = DragGestureDetector.LongPress,
        onDragStarted = {
            coroutineScope.launch {
                val itemPos = itemPositionProvider?.invoke() ?: Offset.Zero
                val relativeOffset = handleOffset - itemPos
                val handleCenter = Offset(
                    relativeOffset.x + handleSize.width / 2f,
                    relativeOffset.y + handleSize.height / 2f
                )
                state.onDragStart(key, handleCenter)
            }
        },
        onDragStopped = {
            state.onDragStop()
        },
        onDrag = { change, dragAmount ->
            change.consume()
            state.onDrag(dragAmount)
        }
    )
}
