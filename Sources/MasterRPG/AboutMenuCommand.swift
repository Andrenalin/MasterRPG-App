// @copyright André Trettin

#if os(macOS)
import SwiftUI

struct AboutMenuCommand: View {
    let title: String
    let options: [NSApplication.AboutPanelOptionKey: Any]

    var body: some View {
        Button(title) {
            NSApplication.shared
                .orderFrontStandardAboutPanel(options: options)
        }
    }
}

struct AboutPanelCommand: Commands {
    init(title: String, applicationName: String = Bundle.main.displayName, credits: String? = nil) {
        let options: [NSApplication.AboutPanelOptionKey: Any]
        if let credits {
            options = [
                .applicationName: applicationName,
                .credits: NSAttributedString(
                    string: credits,
                    attributes: [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                    ]
                )
            ]
        } else {
            options = [.applicationName: applicationName]
        }
        self.init(title: title, options: options)
    }

    init(title: String, options: [NSApplication.AboutPanelOptionKey: Any]) {
        self.title = title
        self.options = options
    }

    private let title: String
    private let options: [NSApplication.AboutPanelOptionKey: Any]

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            AboutMenuCommand(title: title, options: options)
        }
    }
}

public extension Bundle {
    var displayName: String {
        infoDictionary?["CFBundleDisplayName"] as? String ?? "-"
    }
}

#Preview {
    AboutMenuCommand(title: "About May Mapp", options: [:])
}

#endif
