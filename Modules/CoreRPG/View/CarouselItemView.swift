// @copyright André Trettin

import SwiftData
import SwiftUI

public struct CarouselItemView<Content: View>: View {
    public init(root: any ItemRootControllable, model: ItemDataModel, selection: GroupItemSelectionModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.root = root
        self.selection = selection
        self.content = content()
    }
    
    let model: ItemDataModel
    let root: ItemRootControllable
    let selection: GroupItemSelectionModel
    let content: Content

    @Environment(\.modelContext) private var modelContext

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                itemView(item: model, selectedItem: nil)

                ForEach(model.entries) { entry in
                    if let item = ItemDataModel.model(modelContext: modelContext, id: entry.childId) {
                        itemView(item: item, selectedItem: item)
                            .overlay(alignment: .topTrailing) {
                                GlassButton {
                                    withAnimation { root.editControllable.removeGroup(childId: item.id, model: model) }
                                } label: {
                                    Image(systemName: "minus")
                                        .foregroundStyle(.white, .red)
                                        .padding(6)
                                        .background(.regularMaterial, in: Circle())
                                }
                            }
                    }
                }

                dropItemView
            }
        }
    }
    
    @ViewBuilder
    var dropItemView: some View {
        DropItemArea {
            VStack {
                Text("Drop \(root.module.title)", bundle: .module)

                Image(systemName: "square.and.arrow.down")
                    .imageScale(.large)
            }
        } dropAction: { links in
            addLinks(links: links)
        }
        .padding(.horizontal, 12)
        .frame(height: 128)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.accentColor.secondary, lineWidth: 2)
        }
    }
    
    private func addLinks(links: [LinkData]) -> Bool {
        links.forEach { link in
            guard link.module == root.module else { return }
            withAnimation { root.editControllable.addGroup(childId: link.itemId, model: model) }
        }
        return true
    }
    
    func itemView(item: ItemDataModel, selectedItem: ItemDataModel?) -> some View {
        content
            .environment(GroupItemSelectionModel(selectedItem: item.id))
            .frame(height: 128)
            .onTapGesture {
                withAnimation { selection.selectedItem = selectedItem?.id }
            }
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            .overlay {
                if model.url != nil {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(selection.selectedItem == selectedItem?.id ? Color.accentColor : Color.clear, lineWidth: 4)
                }
            }
#if !os(tvOS)
            .dropDestination(for: LinkData.self) { items, _ in
                _ = addLinks(links: items)
            }
#endif
    }
}
