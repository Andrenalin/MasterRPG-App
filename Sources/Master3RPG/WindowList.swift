// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI
import PdfRPG

struct WindowList: Scene {
    let appModel: AppModel
    
    var body: some Scene {
        Group {
            WindowGroup("Pdf Viewer", id: WindowIdentifier.pdfViewer.rawValue, for: WindowItemSelection.self) { $selection in
                appModel.pdfRoot.viewController.pdfWindow(root: appModel.pdfRoot, selection: selection ?? WindowItemSelection(itemId: UUID()))
                    .accentColor(.teal)
                    .tint(.teal)
                    .frame(minWidth: 600, minHeight: 400)
                    .handlesExternalEvents(preferring: [], allowing: [])
            }
            .windowResizability(.contentSize)
#if !os(iOS)
            .restorationBehavior(.disabled)
#endif
            .defaultWindowPlacementAll(.below(WindowIdentifier.game.rawValue))
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
}
#endif
