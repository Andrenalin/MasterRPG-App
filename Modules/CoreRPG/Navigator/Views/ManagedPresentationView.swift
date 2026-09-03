//
//  ManagedPresentationView.swift
//  Navigator
//
//  Created by Michael Long on 1/22/25.
//

import SwiftUI

/// Allows presented views not in a navigation stack to be dismissed using a Navigator.
///
/// Also supports nested sheets and covers.
///
/// If you present sheets or covers in your own code, outside of `navigate(to:)`, and if those presented
/// views don't use ``ManagedNavigationStack``, then `ManagedPresentationView`  tells Navigator about them.
/// ```swift
/// Button("Present Page 3 via Sheet") {
///     showSettings = .page3
/// }
/// .sheet(item: $showSettings) { destination in
///     ManagedPresentationView {
///         destination()
///     }
/// }
/// ```
/// That in turn allows them to be manipulated or closed when performing deep linking actions like dismissAny().
///
/// One can also use the ``managedPresentationView(name:)`` modifier which does the same thing.
/// ```swift
/// .sheet(item: $showSettings) { destination in
///     destination()
///         .managedPresentationView()
/// }
/// ```
/// > Warning: Failure to tag presented views as such can lead to inconsistent deep linking and navigation behavior.
@MainActor
public struct ManagedPresentationView<Content: View>: View {

    @Environment(\.navigator) private var parent: Navigator
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    @LazyState private var navigator: Navigator

    private let content: Content
    private let themed: Bool

    /// Wraps presented content in a managed navigator-aware context.
    ///
    /// Use this whenever you present views outside of a managed navigation
    /// stack but still want them to participate in navigation and deep linking.
    ///
    /// ```swift
    /// .sheet(item: $destination) { destination in
    ///     ManagedPresentationView {
    ///         destination()
    ///     }
    /// }
    /// ```
    /// - Parameter themed: Paints the app's themed background behind `content`
    ///   (`themedSurface()`). Pass `false` for content that must stay visually
    ///   transparent behind whatever it draws itself — e.g. a live camera feed —
    ///   where an opaque background would otherwise silently stand in for content
    ///   that fails to render, rather than leaving the failure visible.
    public init(name: String? = nil, themed: Bool = true, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.themed = themed
        self._navigator = .init(wrappedValue: Navigator(owner: .presenter, name: name))
    }

    /// The view content configured with a dedicated `Navigator` and
    /// presentation environment.
    public var body: some View {
        let _ = {
            parent.addChild(navigator, dismissible: isPresented ? dismiss : nil)
        }()
        content
            .modifier(NavigationPresentationModifiers(navigator: navigator))
            .environment(\.navigator, navigator)
            .modifier(ThemedIf(themed: themed))
            .onAppear {
                navigator.set(current: navigator)
            }
    }

}

/// Applies `themedSurface()` only when `themed` is true — see
/// `ManagedPresentationView.init(name:themed:content:)`.
private struct ThemedIf: ViewModifier {
    let themed: Bool

    func body(content: Content) -> some View {
        if themed {
            content.themedSurface()
        } else {
            content
        }
    }
}
