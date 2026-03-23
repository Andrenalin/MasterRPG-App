// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import RolePlayGameKit
import AudioRPG
import GameRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import SwiftUI
import WeatherRPG

struct TabRootView: View {
    let appModel: AppModel
    let editorOnly: Bool

    @Environment(\.appSizeMode) private var appSizeMode

    var body: some View {

        layout
            .onChange(of: appSizeMode) { oldValue, newValue in
                appModel.resetNavigation()
            }
    }
    
    private var layout: AppRootType {
        valueFor(iOS: appSizeMode == .compact ? .tabbed : .split, macOS: .tabbedSplit, tvOS: .tabbed, visionOS: .tabbedExtSplit)
    }
}

#Preview {
    TabRootView(appModel: .preview, editorOnly: false)
}
