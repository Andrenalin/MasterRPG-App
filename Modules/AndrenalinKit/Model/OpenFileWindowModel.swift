// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

@MainActor @Observable
public final class OpenFileWindowModel {
    public init() {}

    public init(windowId: String, canShow: Bool = false, route: @escaping (UUID) -> any NavigationDestination) {
        self.windowId = windowId
        self.canShow = canShow
        self.route = route
    }
    
    public var showItem: Bool = false
    public var itemId: UUID = UUID()
    public var entryId: UUID?
    public var url: URL?
    public var canShow: Bool = false
    
    public var windowId: String? = nil
    public var route: ((UUID) -> any NavigationDestination)?
    
    public var enabled: Bool {
        canShow || url != nil
    }
}

struct OpenFileViewerViewModifier: ViewModifier {
    let model: any ItemDataAccessable
    let module: NetworkModules
    
    @Environment(OpenFileWindowModel.self) private var openFileWindowModel
    @Environment(GroupItemSelectionModel.self) private var selection
    
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: secondaryMenuPlacement) {
                if !model.specialCategory && openFileWindowModel.showItem == false && openFileWindowModel.enabled {
                    OpenFileWindowView(model: openFileWindowModel, module: module)
                }
            }
        }
        .onChange(of: model.id, initial: true) {
            openFileWindowModel.itemId = model.id
            openFileWindowModel.url = model.url
        }
        .onChange(of: model.url) {
            openFileWindowModel.url = model.url
        }
        .onChange(of: selection.selectedItem) {
            openFileWindowModel.itemId = selection.selectedItem ?? model.id
        }
    }
    
    var secondaryMenuPlacement: ToolbarItemPlacement {
#if os(tvOS)
        .automatic
#else
        .secondaryAction
#endif
    }
}


struct OpenFileWindowView: View {
    let model: OpenFileWindowModel
    let module: NetworkModules
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    @Environment(\.navigator) private var navigator
    
    var body: some View {
        if let windowId = model.windowId {
            menuButton(windowId: windowId)
        }
    }
    
    @ViewBuilder
    func menuButton(windowId: String) -> some View {
        ControlGroup {
#if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                Button {
                    openWindow(id: windowId, value: WindowItemSelection(itemId: model.itemId, entryId: model.entryId))
                } label: {
                    Label {
                        Text("Open in Window", bundle: .module)
                    } icon: {
                        Image(systemName: "macwindow.badge.plus")
                    }
                }
            }
#endif
            
            Button {
                actionHandler(windowId: windowId)
            } label: {
                Label {
                    Text("View", bundle: .module)
                } icon: {
                    Image(systemName: module.icon)
                }
            }
        }
    }
    
    private func actionHandler(windowId: String) {
#if os(visionOS) || os(macOS)
        openWindow(id: windowId, value: WindowItemSelection(itemId: model.itemId, entryId: model.entryId))
#elseif os(iOS)
        if horizontalSizeClass == .compact, let route = model.route?(model.itemId) {
            navigator.navigate(to: route, method: .cover)
        } else {
            withAnimation { model.showItem.toggle() }
        }
#else
        withAnimation { model.showItem.toggle() }
#endif
    }
}
