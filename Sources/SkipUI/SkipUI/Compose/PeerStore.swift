// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.RememberObserver
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.currentCompositeKeyHash
import androidx.compose.runtime.staticCompositionLocalOf

// MARK: - Cache key

/// Composite key for looking up a cached Swift peer in a PeerStore.
///
/// - `namespace`: ForEach instance UUID or TabView route (scopes siblings)
/// - `itemKey`: data-level identity (ForEach element id, lazy item key)
/// - `viewSlotKey`: fully-qualified Kotlin type name (distinguishes same-position siblings of different types)
public struct PeerCacheKey: Hashable {
    public let namespace: AnyHashable?
    public let itemKey: AnyHashable
    public let viewSlotKey: String
}

// MARK: - Cache entry

/// A single cached peer with its lifecycle functions.
public class PeerEntry {
    public let peer: Long
    public var inputsHash: Long?
    public let retainFn: (Long) -> Void
    public let releaseFn: (Long) -> Void

    public init(peer: Long, inputsHash: Long?, retainFn: @escaping (Long) -> Void, releaseFn: @escaping (Long) -> Void) {
        self.peer = peer
        self.inputsHash = inputsHash
        self.retainFn = retainFn
        self.releaseFn = releaseFn
    }
}

// MARK: - PeerStore

/// Parent-scoped cache that outlives individual item compositions.
///
/// Created by lazy containers (LazyVStack, LazyHStack, LazyVGrid, LazyHGrid)
/// and TabView, then provided to children via `LocalPeerStore`.
/// `rememberViewPeer()` looks up / inserts peers here instead of using
/// composition-scoped `remember { SwiftPeerHandle }`.
public class PeerStore: RememberObserver {
    private var entries: [PeerCacheKey: PeerEntry] = [:]

    public func lookup(_ key: PeerCacheKey) -> PeerEntry? {
        let result = entries[key]
        android.util.Log.d("ComposeIdentity", "[PeerStore] lookup: key={ns=\(String(describing: key.namespace)), item=\(key.itemKey), slot=\(key.viewSlotKey)} result=\(result != nil ? "HIT" : "MISS")")
        return result
    }

    public func insert(_ key: PeerCacheKey, _ entry: PeerEntry) {
        android.util.Log.d("ComposeIdentity", "[PeerStore] insert: key={ns=\(String(describing: key.namespace)), item=\(key.itemKey), slot=\(key.viewSlotKey)} peer=\(entry.peer)")
        // Store is a real owner — retain so GC finaliser can't free peer while store holds it.
        entry.retainFn(entry.peer)
        entries[key] = entry
    }

    /// Remove a single entry and release its peer.
    public func evict(_ key: PeerCacheKey) {
        android.util.Log.d("ComposeIdentity", "[PeerStore] evict: key={ns=\(String(describing: key.namespace)), item=\(key.itemKey), slot=\(key.viewSlotKey)}")
        if let entry = entries.removeValue(forKey: key) {
            entry.releaseFn(entry.peer)
        }
    }

    /// Evict all peers in the given namespace whose item keys are not in `activeKeys`.
    /// Called from ForEach's SideEffect after data changes.
    public func cleanup(namespace: AnyHashable?, activeKeys: Set<AnyHashable>) {
        let staleKeys = entries.keys.filter { key in
            key.namespace == namespace && !activeKeys.contains(key.itemKey)
        }
        for key in staleKeys {
            evict(key)
        }
    }

    // RememberObserver — release all peers when the store's composition scope is disposed.
    public override func onRemembered() {}
    public override func onAbandoned() { releaseAll() }
    public override func onForgotten() { releaseAll() }

    private func releaseAll() {
        android.util.Log.d("ComposeIdentity", "[PeerStore] releaseAll: count=\(entries.count)")
        for (_, entry) in entries {
            entry.releaseFn(entry.peer)
        }
        entries.removeAll()
    }
}

// MARK: - CompositionLocals

/// The PeerStore provided by the nearest lazy container or TabView.
public let LocalPeerStore = staticCompositionLocalOf<PeerStore?> { nil }

/// The data-level item key for the current item (set by IdentityKeyModifier or lazy container).
public let LocalPeerStoreItemKey = staticCompositionLocalOf<AnyHashable?> { nil }

/// The namespace for the current scope (set by ForEach or TabView route).
public let LocalPeerStoreNamespace = staticCompositionLocalOf<AnyHashable?> { nil }

// MARK: - Namespace path (removed)
// PeerNamespacePath struct was removed in Plan 16.
// Its Hashable conformance didn't survive Kotlin transpilation (object identity instead of structural equality).
// Namespaces are now composed as Strings in PeerStoreNamespaceModifier.Render.

// MARK: - PeerStoreNamespaceModifier

/// Wraps lazy-produced renderables to provide a namespace via CompositionLocal.
/// Applied by ForEach on items produced during `produceLazyItems`.
final class PeerStoreNamespaceModifier: RenderModifier {
    let namespace: AnyHashable

    init(namespace: AnyHashable) {
        self.namespace = namespace
        super.init(role: .unspecified)
    }

    @Composable override func Render(content: Renderable, context: ComposeContext) {
        let parentNamespace = LocalPeerStoreNamespace.current
        let currentNormalized = composeBundleNormalizedKey(for: namespace)
        let combinedNamespace: AnyHashable
        if let parentNamespace {
            // String concatenation: structural equality guaranteed in Kotlin
            let combined = "\(parentNamespace)/\(currentNormalized)"
            combinedNamespace = combined
        } else {
            combinedNamespace = currentNormalized
        }
        // SKIP INSERT: val providedNamespace = LocalPeerStoreNamespace provides combinedNamespace
        CompositionLocalProvider(providedNamespace) {
            content.Render(context: context)
        }
    }
}

// MARK: - SwiftPeerHandle

/// Shared peer handle used by the fallback path (no PeerStore in scope).
/// Retains the peer on init, releases on composition disposal.
/// Previously generated per-view by the transpiler; now shared here.
public class SwiftPeerHandle: RememberObserver {
    public var peer: Long
    private let retainFn: (Long) -> Void
    private let releaseFn: (Long) -> Void

    public init(peer: Long, retainFn: @escaping (Long) -> Void, releaseFn: @escaping (Long) -> Void) {
        self.peer = peer
        self.retainFn = retainFn
        self.releaseFn = releaseFn
        retainFn(peer)
    }

    /// Transfer ownership from a stale (bridge-created) peer to the cached peer.
    /// Retains cached peer for the new Kotlin object, releases stale peer.
    public func swapFrom(stale: Long) {
        retainFn(peer)
        releaseFn(stale)
    }

    public override func onRemembered() {}
    public override func onAbandoned() { releaseFn(peer) }
    public override func onForgotten() { releaseFn(peer) }
}

// MARK: - rememberViewPeer

/// Central peer remembering function called from transpiler-generated code.
///
/// When a PeerStore and item key are available (lazy containers, TabView),
/// uses the store for peer caching that survives composition disposal.
/// Otherwise falls back to composition-scoped `remember { SwiftPeerHandle }`.
///
/// - Parameters:
///   - slotKey: Fully-qualified Kotlin type name for this view.
///   - peer: The fresh peer pointer from the bridge.
///   - retainFn: Swift_retain function reference.
///   - releaseFn: Swift_release function reference.
///   - inputsHash: Hash of constructor params (Phase 2 mixed views only).
///   - refreshPeerFn: Swift_refreshPeer function reference (Phase 2 only).
/// - Returns: The peer pointer to use (cached or fresh).
@Composable
public func rememberViewPeer(
    slotKey: String,
    peer: Long,
    retainFn: @escaping (Long) -> Void,
    releaseFn: @escaping (Long) -> Void,
    inputsHash: Long? = nil,
    refreshPeerFn: ((Long, Long) -> Void)? = nil
) -> Long {
    let store = LocalPeerStore.current
    let itemKey = LocalPeerStoreItemKey.current
    let namespace = LocalPeerStoreNamespace.current

    android.util.Log.d("ComposeIdentity", "[rememberViewPeer] store=\(store != nil) itemKey=\(String(describing: itemKey)) itemKeyType=\(itemKey != nil ? String(describing: type(of: itemKey!)) : "nil") namespace=\(String(describing: namespace)) slotKey=\(slotKey)")

    if let store {
        // When no explicit item key is provided (e.g. bridged views whose body runs
        // on the Swift side where #if SKIP is false), fall back to Compose's
        // currentCompositeKeyHash — a position-stable identifier unique per call site.
        // SKIP INSERT: val _compositeKey: Any = currentCompositeKeyHash
        let effectiveItemKey: AnyHashable = itemKey ?? _compositeKey
        let cacheKey = PeerCacheKey(namespace: namespace, itemKey: effectiveItemKey, viewSlotKey: slotKey)
        if let cached = store.lookup(cacheKey) {
            retainFn(cached.peer)       // ownership for current Kotlin object
            if let inputsHash, cached.inputsHash != inputsHash, let refreshPeerFn {
                refreshPeerFn(cached.peer, peer)
                cached.inputsHash = inputsHash
            }
            releaseFn(peer)             // drop fresh bridge peer
            return cached.peer
        } else {
            store.insert(cacheKey, PeerEntry(peer: peer, inputsHash: inputsHash,
                                             retainFn: retainFn, releaseFn: releaseFn))
            return peer
        }
    }

    // Fallback: existing remember-based behaviour
    let handle: SwiftPeerHandle
    if let inputsHash {
        handle = remember(inputsHash) { SwiftPeerHandle(peer: peer, retainFn: retainFn, releaseFn: releaseFn) }
    } else {
        handle = remember { SwiftPeerHandle(peer: peer, retainFn: retainFn, releaseFn: releaseFn) }
    }
    if handle.peer != peer {
        handle.swapFrom(stale: peer)
    }
    return handle.peer
}

#endif
#endif
