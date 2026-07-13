// @copyright André Trettin

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
    let openFileWindowModel: OpenFileWindowModel
    let module: NetworkModules
    
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .secondaryActionAll) {
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
    }
}

struct OpenFileWindowView: View {
    let model: OpenFileWindowModel
    let module: NetworkModules
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    @Environment(ScenesManager.self) private var scenesManager

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
                    scenesManager.openWindow(SceneId(rawValue: windowId), selection: WindowItemSelection(itemId: model.itemId, entryId: model.entryId))
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
        scenesManager.openWindow(SceneId(rawValue: windowId), selection: WindowItemSelection(itemId: model.itemId, entryId: model.entryId))
#elseif os(iOS)
        if horizontalSizeClass == .compact, let route = model.route?(model.itemId) {
            navigator.navigate(to: route, method: .managedCover)
        } else {
            withAnimation { model.showItem.toggle() }
        }
#else
        withAnimation { model.showItem.toggle() }
#endif
    }
}

#Preview {
    OpenFileWindowView(
        model: OpenFileWindowModel(windowId: "preview-window", canShow: true, route: { _ in InternalRoute.removeAlert }),
        module: .adventure
    )
    .environment(ScenesManager())
}
