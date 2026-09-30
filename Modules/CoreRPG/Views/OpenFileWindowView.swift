// @copyright André Trettin

import SwiftUI

// Moved out of Model/OpenFileWindowModel.swift: views don't belong in Model/. See CODE_AUDIT_19 §9.25.

struct OpenFileViewerViewModifier: ViewModifier {
    let model: any ItemDataAccessible
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
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
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
            // iPhones never open a second window, whatever their size class; an iPad in
            // compact Split View still can. See CODE_AUDIT_19 §5.16.
            if supportsMultipleWindows {
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
#if os(visionOS)
        // SpaceRPG has no 2D window on visionOS — its 3D objects only appear
        // in the ImmersiveSpace (SceneId.spaceViewer), placed in the space in
        // front of the user rather than in a windowed viewer.
        if module == .space {
            Task {
                await scenesManager.openSpaceViewer(selection: ItemSelection(itemId: model.itemId, entryId: model.entryId))
            }
            return
        }
        scenesManager.openWindow(SceneId(rawValue: windowId), selection: WindowItemSelection(itemId: model.itemId, entryId: model.entryId))
#elseif os(macOS)
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
