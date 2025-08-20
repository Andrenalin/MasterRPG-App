// @copyright André Trettin

import SwiftData
import SwiftUI

public struct CarouselItemView<EditController: OldEditControllable, Content: View>: View {
    public init(model: EditController.Model, editController: EditController, selection: GroupItemSelectionModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.editController = editController
        self.selection = selection
        self.content = content()
    }
    
    let model: EditController.Model
    let editController: EditController
    let selection: GroupItemSelectionModel
    let content: Content

    @Environment(\.modelContext) private var modelContext

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                itemView(item: model, selectedItem: nil)

                ForEach(model.entries) { entry in
                    if let item = EditController.Model.model(modelContext: modelContext, id: entry.childId) {
                        itemView(item: item, selectedItem: item)
                            .overlay(alignment: .topTrailing) {
                                GlassButton {
                                    withAnimation { editController.removeGroup(childId: item.id, model: model) }
                                } label: {
                                    Image(systemName: "minus")
                                        .foregroundStyle(.white, .red)
                                        .padding(6)
                                        .background(.regularMaterial, in: Circle())
                                }
                            }
                    }
                }

                dropPhotoView
            }
        }
    }
    
    @ViewBuilder
    var dropPhotoView: some View {
        DropItemArea {
            VStack {
                Text("Drop \(EditController.Model.typeId.title)", bundle: .module)

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
            guard link.module == EditController.Model.typeId else { return }
            withAnimation { editController.addGroup(childId: link.itemId, model: model) }
        }
        return true
    }
    
    func itemView(item: EditController.Model, selectedItem: EditController.Model?) -> some View {
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
