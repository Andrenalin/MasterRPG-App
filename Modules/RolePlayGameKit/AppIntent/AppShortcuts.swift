import AppIntents

@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NavigateIntent(),
            phrases: [
                "Navigate in \(.applicationName)",
                "Navigate to \(\.$navigationOption) in \(.applicationName)"
            ],
            shortTitle: "Navigate",
            systemImageName: "arrowshape.forward"
        )
//        AppShortcut(
//            intent: ClosestLandmarkIntent(),
//            phrases: [
//                "Find closest landmark in \(.applicationName)"
//            ],
//            shortTitle: "Find Closest",
//            systemImageName: "location"
//        )
    }
}
