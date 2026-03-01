// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
#endif

/// Renders content via Compose.
public protocol Renderable {
    #if SKIP
    @Composable func Render(context: ComposeContext)
    #endif
}

#if SKIP
extension Renderable {
    /// Whether this renderable specializes for list items.
    ///
    /// - Returns: A tuple containing whether this item specializes rendering for list items and any list item action it applies.
    ///     The given action will become a tap action on the entire list item cell.
    @Composable public func shouldRenderListItem(context: ComposeContext) -> (Bool, (() -> Void)?) {
        return (false, nil)
    }

    /// Render as a list item.
    @Composable public func RenderListItem(context: ComposeContext, modifiers: kotlin.collections.List<ModifierProtocol>) {
    }

    /// Whether this is an empty view.
    public final var isSwiftUIEmptyView: Bool {
        return strip() is EmptyView
    }

    /// Strip enclosing modifiers, etc.
    public func strip() -> Renderable {
        return self
    }

    /// Perform an action for every modifier.
    ///
    /// The first non-nil value will be returned.
    public func forEachModifier<R>(perform action: (ModifierProtocol) -> R?) -> R? {
        return nil
    }

    /// The Compose key for ForEach identity, if this renderable has a `.tag` modifier.
    ///
    /// Container rendering loops (Column, Row) should wrap iteration bodies with
    /// `androidx.compose.runtime.key(composeKey)` so that Compose matches items
    /// by key rather than by position when items are added or removed.
    public var composeKey: Any? {
        guard let raw = TagModifier.on(content: self, role: .tag)?.value else {
            return nil
        }
        return composeKeyValue(raw)
    }

    /// Represent this `Renderable` as a `View`.
    public func asView() -> View {
        return self as? View ?? ComposeView(content: { self.Render($0) })
    }
}

/// Convert a bridged value to a Compose-safe key.
///
/// Bridged tag values arrive as `SwiftHashable`, whose JNI-based `equals()` is
/// not compatible with Compose's internal key comparison. This converts to a
/// Kotlin-native type that Compose can compare reliably.
public func composeKeyValue(_ raw: Any) -> Any {
    let result: Any
    if raw is String || raw is Int || raw is Long {
        result = raw
    } else {
        let str = "\(raw)"
        // SwiftHashable.toString() calls through JNI to Swift's String(describing:),
        // which wraps Optional values as "Optional(...)". Strip the wrapper so keys
        // are clean and consistent.
        if str.hasPrefix("Optional("), str.hasSuffix(")") {
            result = String(str.dropFirst(9).dropLast(1))
        } else {
            result = str
        }
    }
    #if FUSE_IDENTITY_DEBUG
    android.util.Log.d("ComposeIdentity", "composeKeyValue: input=\(raw) type=\(type(of: raw)) output=\(result) type=\(type(of: result))")
    #endif
    return result
}

#endif
#endif

