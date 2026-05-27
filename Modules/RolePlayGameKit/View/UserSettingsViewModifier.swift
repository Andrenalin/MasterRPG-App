// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct UserSettingsViewModifier: ViewModifier {
    public init(appModel: AppModel) {
        self.appModel = appModel
        self.settingsModel = appModel.settingsModel
    }
    
    let appModel: AppModel
    let settingsModel: AppSettingsModel

    @Environment(\.colorScheme) private var colorScheme

    public func body(content: Content) -> some View {
        content
#if os(iOS)
            .applyIf(settingsModel.appColorScheme != .system) {
                $0.environment(\.colorScheme, settingsModel.appColorScheme.colorScheme(for: colorScheme))
            }
#endif
    }
}

