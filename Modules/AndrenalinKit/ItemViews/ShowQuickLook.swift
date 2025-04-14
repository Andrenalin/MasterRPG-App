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
    public init(listController: any ListControllable, windowId: String, useInternal: Bool, useSelection: ItemRowModel?, canQuickLook: @escaping (ItemRowModel) -> Bool, @ViewBuilder content: @escaping (ItemRowModel) -> Content) {
        self.listController = listController
        self.windowId = windowId
        self.useInternal = useInternal
        self.useSelection = useSelection
        self.canQuickLook = canQuickLook
        self.content = content
    }

    let listController: any ListControllable
    let windowId: String
    let useInternal: Bool
    let useSelection: ItemRowModel?
    let canQuickLook: (ItemRowModel) -> Bool
    let content: (ItemRowModel) -> Content

    @State private var hasItem: Bool = false
    @State private var showItem: Bool = false

    @State private var selected: URL?

#if os(visionOS) || os(macOS)
    @Environment(\.openWindow) var openWindow
#endif

    public var body: some View {
        VStack(alignment: .trailing) {
            ImageOverlayButton(icon: "book\(showItem ? ".fill" : "")") {
                guard let selection = useSelection ?? listController.model.selectedItem?.model else { return }

#if os(visionOS) || os(macOS)
                openWindow(id: windowId, value: ItemSelection(itemId: selection.itemId, entryId: selection.entryId))
#elseif os(tvOS)
                withAnimation { showItem.toggle() }
#else
                withAnimation {
                    if useInternal {
                        showItem.toggle()
                    } else {
                        Task {
                            selected = await listController.itemControllable.loadableUrl(for: selection)
                        }
                    }
                }
#endif
            }
#if os(visionOS)
            .applyIf(!useInternal) { content in
                content
                    .onDrag {
                        guard let selected else {
                            return NSItemProvider()
                        }
                        return NSItemProvider(contentsOf: selected) ?? NSItemProvider()
                    }
            }
#endif
            .disabled(!hasItem)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .sheetFullScreen(isPresented: $showItem) {
            content(useSelection ?? listController.model.selectedItem?.model ?? ItemRowModel(itemId: UUID(), typeId: .none))
        }
        .onChange(of: listController.model.selectedItem, initial: true) {
            guard useSelection == nil, let item = listController.model.selectedItem else { return }
            withAnimation { hasItem <=> canQuickLook(item.model) }
            if hasItem {
                Task {
                    selected = await listController.itemControllable.loadableUrl(for: item.model)
                }
            }
        }
    }
}
