// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
#endif

extension View {
    public func swipeActions(edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true, @ViewBuilder content: () -> any View) -> any View {
        #if SKIP
        return ModifiedContent(content: self, modifier: SwipeActionsModifier(
            edge: edge,
            allowsFullSwipe: allowsFullSwipe,
            content: ComposeBuilder.from(content)
        ))
        #else
        return self
        #endif
    }
}

#if SKIP
final class SwipeActionsModifier: RenderModifier {
    let edge: HorizontalEdge
    let allowsFullSwipe: Bool
    let content: ComposeBuilder

    init(edge: HorizontalEdge, allowsFullSwipe: Bool, content: ComposeBuilder) {
        self.edge = edge
        self.allowsFullSwipe = allowsFullSwipe
        self.content = content
        super.init()
    }

    /// Collect all SwipeActionsModifiers for a given edge from a renderable's modifier chain.
    /// Returns (actions, allowsFullSwipe). allowsFullSwipe is AND'd across all modifiers for that edge.
    ///
    /// This method is @Composable because it calls ComposeBuilder.Evaluate,
    /// Text.localizedTextString(), and EnvironmentValues.shared.setValuesWithReturn.
    ///
    /// forEachModifier's closure parameter is NOT @Composable (Renderable.swift:44),
    /// so we use a two-phase approach: Phase 1 collects modifier instances (non-composable),
    /// Phase 2 processes them in the @Composable method body.
    @Composable static func extractActions(for renderable: Renderable, edge: HorizontalEdge, context: ComposeContext) -> (kotlin.collections.List<SwipeActionData>, Bool) {
        var actions = mutableListOf<SwipeActionData>()
        var allowsFullSwipe = true

        // Phase 1 (non-composable): collect SwipeActionsModifier instances
        var collectedModifiers = mutableListOf<SwipeActionsModifier>()
        renderable.forEachModifier { modifier in
            guard let sam = modifier as? SwipeActionsModifier, sam.edge == edge else { return nil }
            if !sam.allowsFullSwipe { allowsFullSwipe = false }
            collectedModifiers.add(sam)
            return nil
        }

        // Phase 2 (composable): process collected modifiers
        for sam in collectedModifiers {
            let renderables = sam.content.Evaluate(context: context, options: 0)
            for r in renderables {
                if let button = r.strip() as? Button {
                    var labelText: String? = nil
                    var iconName: String? = nil
                    var iconView: Image? = nil
                    let labelViews = button.label.Evaluate(context: context, options: 0)
                    for view in labelViews {
                        let stripped = view.strip()
                        if let label = stripped as? Label {
                            let titleViews = label.title.Evaluate(context: context, options: 0)
                            labelText = (titleViews.firstOrNull()?.strip() as? Text)?.localizedTextString()
                            let imageViews = label.image.Evaluate(context: context, options: 0)
                            if let img = imageViews.firstOrNull()?.strip() as? Image, case .system(let systemName) = img.image {
                                iconName = systemName
                                iconView = img
                            }
                        } else if let text = stripped as? Text {
                            labelText = text.localizedTextString()
                        } else if let img = stripped as? Image, case .system(let systemName) = img.image {
                            iconName = systemName
                            iconView = img
                        }
                    }

                    // Tint extraction — two-phase for EnvironmentModifier too
                    // Phase 2a: collect @Composable action closures (non-composable — just storing references)
                    var envModActions = mutableListOf<@Composable (EnvironmentValues) -> ComposeResult>()
                    r.forEachModifier { modifier in
                        if let envMod = modifier as? EnvironmentModifier, let action = envMod.action {
                            envModActions.add(action)
                        }
                        return nil
                    }
                    // Phase 2b: replay in composable context via setValuesWithReturn
                    let tintColor: Color? = EnvironmentValues.shared.setValuesWithReturn({ env in
                        for action in envModActions {
                            action(env)
                        }
                        return ComposeResult.ok
                    }, in: {
                        return EnvironmentValues.shared._tint
                    })

                    let actionData = SwipeActionData(
                        label: labelText,
                        iconName: iconName,
                        iconView: iconView,
                        role: button.role?.rawValue,
                        tint: tintColor,
                        action: { button.action() }
                    )
                    actions.add(actionData)
                }
            }
        }
        return (actions, allowsFullSwipe)
    }

    /// Returns true if the renderable has any SwipeActionsModifier attached.
    static func hasSwipeActions(_ renderable: Renderable) -> Bool {
        var found = false
        renderable.forEachModifier { modifier in
            if modifier is SwipeActionsModifier { found = true; return true }
            return nil
        }
        return found
    }
}
#endif

// Bridge method for Fuse mode — called from skip-fuse-ui
extension View {
    // SKIP @bridge
    public func swipeActions(bridgedEdge: Int, allowsFullSwipe: Bool, bridgedContent: any View) -> any View {
        #if SKIP
        return ModifiedContent(content: self, modifier: SwipeActionsModifier(
            edge: HorizontalEdge(rawValue: bridgedEdge) ?? .trailing,
            allowsFullSwipe: allowsFullSwipe,
            content: ComposeBuilder(view: bridgedContent)
        ))
        #else
        return self
        #endif
    }
}

#endif
