// @copyright André Trettin

#if !os(tvOS)
import QuickLook
#endif
import SwiftUI

public struct ItemSelection: Equatable, Hashable, Codable {
    public init(itemId: UUID, entryId: UUID?) {
        self.itemId = itemId
        self.entryId = entryId
    }
    public let itemId: UUID
    public let entryId: UUID?
}

public struct ShowQuickLook<Content: View>: View {
    public init(listController: any ListControllable, windowId: String, canQuickLook: @escaping (ItemRowModel) -> Bool, @ViewBuilder content: @escaping (ItemRowModel) -> Content) {
        self.listController = listController
        self.windowId = windowId
        self.canQuickLook = canQuickLook
        self.content = content
    }
    
    let listController: any ListControllable
    let windowId: String
    let canQuickLook: (ItemRowModel) -> Bool
    let content: (ItemRowModel) -> Content
    
    @State private var hasItem: Bool = false
    @State private var showItem: Bool = false
    
#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) var openWindow
#endif
    
    public var body: some View {
        ImageOverlayButton(icon: "book\(showItem ? ".fill" : "")") {
#if os(visionOS) || os(macOS)
            guard let selection = listController.model.selectedItem?.model else { return }
            openWindow(id: windowId, value: ItemSelection(itemId: selection.itemId, entryId: selection.entryId))
#else
            withAnimation {
                showItem.toggle()
            }
#endif
        }
        .disabled(!hasItem)
        .sheetFullScreen(isPresented: $showItem) {
            content(listController.model.selectedItem?.model ?? ItemRowModel(itemId: UUID(), typeId: .none))
        }
        .onChange(of: listController.model.selectedItem, initial: true) {
            guard let item = listController.model.selectedItem else { return }
            withAnimation { hasItem <=> canQuickLook(item.model) }
        }
    }
}
