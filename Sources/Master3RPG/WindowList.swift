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
                appModel.pdfRoot.viewController.windowViewer(root: appModel.pdfRoot, selection: selection ?? WindowItemSelection(itemId: UUID()))
                    .modifier(WindowListSetUpViewModifier(model: appModel, module: .pdf))
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

struct WindowListSetUpViewModifier: ViewModifier {
    let model: AppModel
    let module: NetworkModules
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .tint(module.tint)
            .handlesExternalEvents(preferring: [], allowing: [])
#if os(iOS)
            .environment(\.colorScheme, model.settingsModel.appColorScheme.colorScheme(for: colorScheme))
#endif
    }
}

#endif
