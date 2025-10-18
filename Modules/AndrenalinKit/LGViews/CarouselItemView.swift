// @copyright André Trettin

import SwiftData
import SwiftUI

public struct CarouselItemView<Content: View>: View {
    public init(root: any ItemRootControllable, model: any ItemDataAccessable, selection: GroupItemSelectionModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.root = root
        self.selection = selection
        self.content = content()
    }
    
    let model: any ItemDataAccessable
    let root: ItemRootControllable
    let selection: GroupItemSelectionModel
    let content: Content

    @Environment(\.modelContext) private var modelContext

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                itemView(itemId: model.id, selectedItemId: nil)

                ForEach(model.entries, id: \.self.id) { entry in
                    if let item = root.itemControllable.itemSync(for: entry.id) {
                        itemView(itemId: item.id, selectedItemId: item.id)
                            .overlay(alignment: .topTrailing) {
                                GlassButton {
                                    withAnimation { root.editControllable.removeGroup(childId: item.id) }
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
        DropItemModuleArea(module: root.module, contentView: {
            VStack {
                Text("Drop \(root.module.title)", bundle: .module)

                Image(systemName: "square.and.arrow.down")
                    .imageScale(.large)
            }
            .padding(.horizontal, 12)
            .frame(height: 128)
        }, dropAction: linkHandler(name:itemId:entryId:))
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.accentColor.tertiary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.accentColor.secondary, lineWidth: 2)
        }
        .padding(1)
    }
    
    func linkHandler(name: String, itemId: UUID, entryId: UUID?) {
        withAnimation { root.editControllable.addGroup(childId: itemId) }
    }
    
    func itemView(itemId: UUID, selectedItemId: UUID?) -> some View {
        content
            .environment(GroupItemSelectionModel(selectedItem: itemId))
            .frame(height: 128)
            .onTapGesture {
                withAnimation { selection.selectedItem = selectedItemId }
            }
            .clipShape(.rect(cornerRadius: 20, style: .continuous))
            .overlay {
                if model.url != nil {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(selection.selectedItem == selectedItemId ? Color.accentColor : Color.clear, lineWidth: 4)
                }
            }
            .dropDestination(for: root.module, handler: linkHandler(name:itemId:entryId:))
    }
}
