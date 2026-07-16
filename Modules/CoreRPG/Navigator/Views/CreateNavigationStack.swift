//
//  CreateNavigationStack.swift
//  Navigator
//

import SwiftUI

@MainActor
struct CreateNavigationStack<Content: View>: View {
    @Environment(\.navigator) private var parent
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss

    @LazyState private var navigator: Navigator

    private let sceneName: String?
    private let content: (Navigator) -> Content

    init(name: String?, sceneName: String?, content: @escaping (Navigator) -> Content) {
        self._navigator = .init(wrappedValue: Navigator(owner: .stack, name: name))
        self.sceneName = sceneName
        self.content = content
    }

    var body: some View {
        let _ = {
            parent.addChild(navigator, dismissible: isPresented ? dismiss : nil)
        }()
        NavigationStack(path: Bindable(navigator).path) {
            content(navigator)
                .navigationDestination(for: AnyNavigationDestination.self) { destination in
                    navigator.mappedNavigationView(for: destination.wrapped)
                }
                .environment(\.navigator, navigator)
        }
        .modifier(NavigationPresentationModifiers(navigator: navigator))
        .modifier(NavigationSceneRestorationModifier(navigator: navigator, name: sceneName))
        .environment(\.navigator, navigator)
        .onAppear {
            Navigator.set(current: navigator)
        }
    }
}

#Preview {
    CreateNavigationStack(name: "Preview", sceneName: nil) { _ in
        Text(verbatim: "Created navigation")
    }
}
