// Copyright 2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE

/// Controls how font sizes respond to the system's text size settings.
///
/// - ``native``: Uses the platform's native font scaling (Android `sp`, iOS DynamicType).
///   This is the default. Layout may diverge between platforms at non-default text sizes.
/// - ``appleCompatible``: Maps the system font scale to the nearest iOS Dynamic Type
///   category and returns Apple's per-style sizes. Use this when cross-platform layout
///   fidelity is more important than platform convention.
public enum DynamicTypeMode : Int, Hashable, Sendable {
    case native = 0 // For bridging
    case appleCompatible = 1 // For bridging
}

extension View {
    public func dynamicTypeMode(_ mode: DynamicTypeMode) -> some View {
        #if SKIP
        return environment(\.dynamicTypeMode, mode)
        #else
        return self
        #endif
    }
}

#endif
