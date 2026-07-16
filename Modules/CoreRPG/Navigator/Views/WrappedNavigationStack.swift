//
//  WrappedNavigationStack.swift
//  Navigator
//

import SwiftUI

@MainActor
struct WrappedNavigationStack<Content: View>: View {
    var navigator: Navigator
    let sceneName: String?
    let content: Content

    init(navigator: Navigator, sceneName: String?, content: Content) {
        self.navigator = navigator
        self.sceneName = sceneName
        self.content = content
    }

    var body: some View {
        NavigationStack(path: Bindable(navigator).path) {
            content
                .navigationDestination(for: AnyNavigationDestination.self) { destination in
                    navigator.mappedNavigationView(for: destination.wrapped)
                }
        }
        .modifier(NavigationSceneRestorationModifier(navigator: navigator, name: sceneName))
        .onAppear {
            Navigator.set(current: navigator)
        }
    }
}

#Preview {
    WrappedNavigationStack(
        navigator: Navigator(owner: .stack, name: "Preview"),
        sceneName: nil,
        content: Text(verbatim: "Wrapped navigation")
    )
}
