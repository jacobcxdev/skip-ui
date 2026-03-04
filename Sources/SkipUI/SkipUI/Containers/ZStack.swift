// Copyright 2023–2025 Skip
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
#if SKIP
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
#elseif canImport(CoreGraphics)
import struct CoreGraphics.CGRect
import struct CoreGraphics.CGSize
#endif

// SKIP @bridge
public struct ZStack : View, Renderable {
    let alignment: Alignment
    let content: ComposeBuilder
    let isBridged: Bool

    public init(alignment: Alignment = .center, @ViewBuilder content: () -> any View) {
        self.alignment = alignment
        self.content = ComposeBuilder.from(content)
        self.isBridged = false
    }

    // SKIP @bridge
    public init(horizontalAlignmentKey: String, verticalAlignmentKey: String, bridgedContent: any View) {
        self.alignment = Alignment(horizontal: HorizontalAlignment(key: horizontalAlignmentKey), vertical: VerticalAlignment(key: verticalAlignmentKey))
        self.content = ComposeBuilder.from { bridgedContent }
        self.isBridged = true
    }

    #if SKIP
    @Composable override func Render(context: ComposeContext) {
        let renderables = content.Evaluate(context: context, options: 0).filter { !$0.isSwiftUIEmptyView }

        let retainedState = rememberRetainedAnimatedItemsState()
        let animation = Animation.current(isAnimating: retainedState.isAnimating)
        retainedState.sync(renderables: renderables, animation: animation, keyExtractor: { renderable, index in effectiveAnimatedKey(renderable: renderable, index: index) })
        let retainedItems = retainedState.orderedItems()

        let contentContext = context.content()
        ComposeContainer(eraseAxis: true, modifier: context.modifier) { modifier in
            Box(modifier: modifier, contentAlignment: alignment.asComposeAlignment()) {
                for i in 0..<retainedItems.size {
                    let item = retainedItems[i]
                    androidx.compose.runtime.key(item.key) {
                        AnimatedVisibility(
                            visibleState: item.visibility,
                            enter: resolvedEnter(item: item, axis: .overlay),
                            exit: resolvedExit(item: item, axis: .overlay),
                            label: "ZStackItem"
                        ) {
                            item.renderable.Render(context: contentContext)
                        }
                    }
                }
            }
        }
    }
    #else
    public var body: some View {
        stubView()
    }
    #endif
}

/*
/// An overlaying container that you can use in conditional layouts.
///
/// This layout container behaves like a ``ZStack``, but conforms to the
/// ``Layout`` protocol so you can use it in the conditional layouts that you
/// construct with ``AnyLayout``. If you don't need a conditional layout, use
/// ``ZStack`` instead.
@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
@frozen public struct ZStackLayout : Layout {
    /// The alignment of subviews.
    public var alignment: Alignment { get { fatalError() } }

    /// Creates a stack with the specified alignment.
    ///
    /// - Parameters:
    ///   - alignment: The guide for aligning the subviews in this stack
    ///     on both the x- and y-axes.
    @inlinable public init(alignment: Alignment = .center) { fatalError() }

    /// The type defining the data to animate.
    public typealias AnimatableData = EmptyAnimatableData
    public var animatableData: AnimatableData { get { fatalError() } set { } }

    /// Cached values associated with the layout instance.
    ///
    /// If you create a cache for your custom layout, you can use
    /// a type alias to define this type as your data storage type.
    /// Alternatively, you can refer to the data storage type directly in all
    /// the places where you work with the cache.
    ///
    /// See ``makeCache(subviews:)-23agy`` for more information.
    public typealias Cache = Void

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        fatalError()
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        fatalError()
    }
}

@available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
extension ZStackLayout : Sendable {
}
*/
#endif
