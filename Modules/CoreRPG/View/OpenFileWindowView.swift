// @copyright André Trettin

import CoreExternalRPG
import SwiftUI

@MainActor @Observable
public final class OpenFileWindowModel {
    public init(showItem: Bool = false, itemId: UUID = UUID(), entryId: UUID? = nil, url: URL? = nil) {
        self.showItem = showItem
        self.itemId = itemId
        self.entryId = entryId
        self.url = url
    }
    
    public var showItem: Bool = false
    public var itemId: UUID = UUID()
    public var entryId: UUID?
    public var url: URL?
}

public struct OpenFileWindowView: View {
    public init(model: OpenFileWindowModel, module: NetworkModules, windowId: String, route: any NavigationDestination) {
        self.model = model
        self.module = module
        self.windowId = windowId
        self.route = route
    }
    
    let model: OpenFileWindowModel
    let module: NetworkModules
    let windowId: String
    let route: any NavigationDestination
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
#if !os(tvOS)
    @Environment(\.openWindow) private var openWindow
#endif
    
    @Environment(\.navigator) private var navigator
    
    public var body: some View {
        HStack {
            GlassButton {
#if os(visionOS) || os(macOS)
                openWindow(id: windowId, value: ItemSelectionModel(itemId: model.itemId, entryId: model.entryId))
#elseif os(iOS)
                if horizontalSizeClass == .compact {
                    navigator.navigate(to: route, method: .cover)
                } else {
                    withAnimation { model.showItem.toggle() }
                }
#else
                withAnimation { model.showItem.toggle() }
#endif
            } label: {
                Image(systemName: module.icon)
            }
            .disabled(model.url == nil)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onChange(of: model.url) {
            guard model.url == nil else { return }
            withAnimation { model.showItem <=> false }
        }
    }
}

