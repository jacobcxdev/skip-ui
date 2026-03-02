// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.expandHorizontally
import androidx.compose.animation.shrinkHorizontally
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
#endif

#if SKIP
enum RetainedAnimatedAxis {
    case vertical
    case horizontal
    case overlay
}

class RetainedAnimatedItem {
    let key: Any
    var renderable: Renderable
    let visibility: MutableTransitionState<Bool>
    var transition: Transition?
    var animation: Animation?
    var previousOrder: Int

    init(key: Any, renderable: Renderable, visibility: MutableTransitionState<Bool>, transition: Transition?, animation: Animation?, previousOrder: Int) {
        self.key = key
        self.renderable = renderable
        self.visibility = visibility
        self.transition = transition
        self.animation = animation
        self.previousOrder = previousOrder
    }
}

class RetainedAnimatedItemsState {
    var items: kotlin.collections.MutableMap<Any, RetainedAnimatedItem> = mutableMapOf()
    var previousOrderedKeys: kotlin.collections.MutableList<Any> = mutableListOf()
    var hasEstablishedBaseline: Bool = false

    var isAnimating: Bool {
        return items.values.any { !$0.visibility.isIdle }
    }

    /// Core sync algorithm. Call once per recomposition before rendering.
    /// Not @Composable — reads Animation.current() state but does not emit nodes.
    func sync(renderables: kotlin.collections.List<Renderable>, animation: Animation?, keyExtractor: (Renderable, Int) -> Any) {
        var currentKeys = mutableListOf<Any>()
        var seenKeys = mutableSetOf<Any>()

        // Step 1: Walk current renderables, extract and disambiguate keys
        for i in 0..<renderables.size {
            let renderable = renderables[i]
            var key = keyExtractor(renderable, i)
            if !seenKeys.add(key) {
                android.util.Log.w("RetainedAnimatedItems", "Duplicate key \(key) at index \(i), disambiguating")
                key = "\(key)_dup\(i)"
                seenKeys.add(key)
            }
            currentKeys.add(key)
        }

        let currentKeySet = currentKeys.toSet()

        // Step 2: Process current renderables — update existing, create new
        for i in 0..<renderables.size {
            let renderable = renderables[i]
            let key = currentKeys[i]
            if let existing = items[key] {
                // Update renderable in case it changed
                existing.renderable = renderable
                if existing.visibility.targetState == false {
                    // Re-insertion: cancel exit by flipping targetState back to true
                    existing.visibility.targetState = true
                    if let animation {
                        existing.animation = animation
                        existing.transition = TransitionModifier.transition(for: renderable)
                    }
                } else {
                    // Update transition in case modifier changed
                    existing.transition = TransitionModifier.transition(for: renderable)
                }
            } else {
                // New item
                let initialVisible: Bool
                let startAnimation: Animation?
                if hasEstablishedBaseline, let animation {
                    initialVisible = false
                    startAnimation = animation
                } else {
                    initialVisible = true
                    startAnimation = nil
                }
                let visibility = MutableTransitionState(initialVisible)
                if !initialVisible {
                    visibility.targetState = true
                }
                let item = RetainedAnimatedItem(
                    key: key,
                    renderable: renderable,
                    visibility: visibility,
                    transition: TransitionModifier.transition(for: renderable),
                    animation: startAnimation,
                    previousOrder: i
                )
                items[key] = item
            }
        }

        // Step 3: Mark removed items for exit or collect for immediate removal
        var immediateRemovalKeys = mutableListOf<Any>()
        for (key, item) in items {
            if !currentKeySet.contains(key) && item.visibility.targetState == true {
                if let animation {
                    item.visibility.targetState = false
                    item.animation = animation
                } else {
                    immediateRemovalKeys.add(key)
                }
            }
        }
        for key in immediateRemovalKeys {
            items.remove(key)
        }

        // Step 4: Prune completed exits
        let toRemove = items.entries.filter { e in
            let v = e.value.visibility
            return v.isIdle && !v.currentState && !v.targetState
        }.map { $0.key }
        for key in toRemove {
            items.remove(key)
        }

        // Step 5: Update order for surviving items
        for i in 0..<currentKeys.size {
            items[currentKeys[i]]?.previousOrder = i
        }

        previousOrderedKeys = mergeRetainedOrder(currentKeys: currentKeys, priorOrderedKeys: previousOrderedKeys)
        hasEstablishedBaseline = true
    }

    /// Returns items in display order: current items + exiting items positioned
    /// before their next surviving right neighbour.
    func orderedItems() -> kotlin.collections.List<RetainedAnimatedItem> {
        var result = mutableListOf<RetainedAnimatedItem>()
        for key in previousOrderedKeys {
            if let item = items[key] {
                result.add(item)
            }
        }
        return result
    }

    /// Merge exiting keys into the ordered key list, anchored before next
    /// surviving right neighbour.
    private func mergeRetainedOrder(currentKeys: kotlin.collections.List<Any>, priorOrderedKeys: kotlin.collections.List<Any>) -> kotlin.collections.MutableList<Any> {
        let currentKeySet = currentKeys.toSet()
        // Collect exiting keys from prior order that are still in items (exit in progress)
        let exitingKeys = priorOrderedKeys.filter { !currentKeySet.contains($0) && items[$0] != nil }
        if exitingKeys.size == 0 {
            return currentKeys.toMutableList()
        }

        // For each exiting key, find its anchor: the first current key that appeared
        // after it in the previous order
        var result = currentKeys.toMutableList()
        for exitKey in exitingKeys.reversed() {
            let priorIndex = priorOrderedKeys.indexOf(exitKey)
            // Find the first current key that was to the right of exitKey in prior order
            var anchorIndex: Int = result.size
            for j in (priorIndex + 1)..<priorOrderedKeys.size {
                let candidate = priorOrderedKeys[j]
                let idx = result.indexOf(candidate)
                if idx >= 0 {
                    anchorIndex = idx
                    break
                }
            }
            result.add(anchorIndex, exitKey)
        }
        return result
    }
}

/// Extract the effective animation key for a renderable at a given index.
/// Priority: `.id` TagModifier value (as String) > `identityKey` > positional index.
func effectiveAnimatedKey(renderable: Renderable, index: Int) -> Any {
    if let idValue = TagModifier.on(content: renderable, role: .id)?.value {
        return normalizeKey(idValue)
    }
    if let identityKey = renderable.identityKey {
        return identityKey
    }
    return index
}

/// Materialise the enter transition for an item, using its snapshot or axis default.
@Composable func resolvedEnter(item: RetainedAnimatedItem, axis: RetainedAnimatedAxis) -> EnterTransition {
    let transition = item.transition
    let animation = item.animation
    if let transition, let animation {
        let spec = animation.asAnimationSpec()
        return transition.asEnterTransition(spec: spec)
    }
    // Axis-aware defaults
    switch axis {
    case .vertical:
        return fadeIn() + expandVertically()
    case .horizontal:
        return fadeIn() + expandHorizontally()
    case .overlay:
        return fadeIn()
    }
}

/// Materialise the exit transition for an item, using its snapshot or axis default.
@Composable func resolvedExit(item: RetainedAnimatedItem, axis: RetainedAnimatedAxis) -> ExitTransition {
    let transition = item.transition
    let animation = item.animation
    if let transition, let animation {
        let spec = animation.asAnimationSpec()
        return transition.asExitTransition(spec: spec)
    }
    // Axis-aware defaults
    switch axis {
    case .vertical:
        return fadeOut() + shrinkVertically()
    case .horizontal:
        return fadeOut() + shrinkHorizontally()
    case .overlay:
        return fadeOut()
    }
}

/// @Composable factory — call inside a Render method to get a remembered state instance.
@Composable func rememberRetainedAnimatedItemsState() -> RetainedAnimatedItemsState {
    return remember { RetainedAnimatedItemsState() }
}
#endif
#endif
