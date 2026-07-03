// @copyright André Trettin

import AppIntents

public enum RPGShortcutCatalog {
    public static var navigate: AppShortcut {
        AppShortcut(
            intent: NavigateIntent(),
            phrases: [
                "Navigate around \(.applicationName)",
                "Navigate to \(\.$navigationOption) in \(.applicationName)"
            ],
            shortTitle: "Navigate",
            systemImageName: "arrowshape.forward"
        )
    }
}
