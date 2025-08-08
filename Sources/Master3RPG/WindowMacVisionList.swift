// @copyright André Trettin

#if os(visionOS) || os(macOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI
import PdfRPG

struct WindowMacVisionList: Scene {
    let appModel: AppModel
    
    var body: some Scene {
        Group {
            WindowGroup("Pdf Viewer", id: WindowIdentifier.pdfViewer.rawValue, for: ItemSelectionModel.self) { $selection in
                appModel.pdfRoot.viewController.pdfWindow(selection: selection ?? ItemSelectionModel(itemId: UUID()))
                    .accentColor(Color.accentColor)
                        .tint(Color.accentColor)
                        .frame(minWidth: 600, minHeight: 400)
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            //.defaultWindowPlacementAll( .below(WindowIdentifier.game.rawValue))
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
}
#endif
