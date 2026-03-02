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

    /// Structural identity key for container sibling loops.
    /// Set by ForEach via IdentityKeyModifier during Evaluate.
    /// nil = positional index fallback.
    ///
    /// forEachModifier propagation audit (Phase 18.1):
    /// - ModifiedContent: forwards (checks modifier, recurses into content) — correct
    /// - LazyLevelRenderable: forwards to content — correct
    /// - LazySectionHeader/Footer: does NOT forward, but only used in lazy contexts where identityKey is not consumed — safe
    /// - ViewRenderable: does NOT forward, but not placed inside ForEach-produced modifier chains — safe
    public var identityKey: Any? {
        let key = forEachModifier { ($0 as? IdentityKeyModifier)?.normalizedKey }
        android.util.Log.d("ComposeIdentity", "identityKey: renderable=\(type(of: self)) key=\(key ?? "nil") keyType=\(key.map { type(of: $0) } ?? "nil")")
        return key
    }

    /// Selection tag for Picker/TabView binding.
    /// Raw Swift value — compared in Swift, not Compose.
    public var selectionTag: Any? {
        TagModifier.on(content: self, role: .tag)?.value
    }

    /// Represent this `Renderable` as a `View`.
    public func asView() -> View {
        return self as? View ?? ComposeView(content: { self.Render($0) })
    }
}

/// Single normalisation function for identity keys. Called once at the producer.
/// Consumers never normalise — they receive already-safe values via `identityKey`.
///
/// Guarantees output is String, Int, or Long — types Compose can compare natively.
///
/// Optional unwrapping note: In Skip/Kotlin, Swift Optional is erased to Kotlin nullable.
/// `Optional.some(x)` becomes just `x`, so the raw value retains its underlying type.
/// Callers guard against nil before calling normalizeKey(), so no explicit Optional
/// unwrapping is needed here.
public func normalizeKey(_ raw: Any) -> Any {
    if raw is String || raw is Int || raw is Long {
        android.util.Log.d("ComposeIdentity", "normalizeKey: passthrough raw=\(raw) type=\(type(of: raw))")
        return raw
    }
    if let identifiable = raw as? any Identifiable {
        android.util.Log.d("ComposeIdentity", "normalizeKey: Identifiable raw=\(raw) → id=\(identifiable.id)")
        return normalizeKey(identifiable.id as Any)
    }
    if let rawRepresentable = raw as? any RawRepresentable {
        android.util.Log.d("ComposeIdentity", "normalizeKey: RawRepresentable raw=\(raw) → rawValue=\(rawRepresentable.rawValue)")
        return normalizeKey(rawRepresentable.rawValue as Any)
    }
    let result = "\(raw)"
    android.util.Log.d("ComposeIdentity", "normalizeKey: toString raw=\(raw) type=\(type(of: raw)) → \(result)")
    return result
}

/// New modifier carrying normalised identity. Transparent during rendering.
/// Travels through ModifiedContent chains; found via forEachModifier traversal.
/// Extends RenderModifier for full ModifierProtocol conformance.
final class IdentityKeyModifier: RenderModifier {
    let normalizedKey: Any  // String | Int | Long — guaranteed by normalizeKey()

    init(key: Any) {
        android.util.Log.d("ComposeIdentity", "IdentityKeyModifier.init: rawKey=\(key) type=\(type(of: key))")
        self.normalizedKey = normalizeKey(key)
        android.util.Log.d("ComposeIdentity", "IdentityKeyModifier.init: normalizedKey=\(normalizedKey) type=\(type(of: normalizedKey))")
        super.init(role: .unspecified)
    }

    @Composable override func Render(content: Renderable, context: ComposeContext) {
        // SKIP INSERT: val providedItemKey = LocalPeerStoreItemKey provides AnyHashable(normalizedKey)
        CompositionLocalProvider(providedItemKey) {
            content.Render(context: context)
        }
    }
}

#endif
#endif

