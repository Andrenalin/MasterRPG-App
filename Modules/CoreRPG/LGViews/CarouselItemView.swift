// @copyright André Trettin

import SwiftUI

public struct CarouselItemView<Content: View>: View {
    public init(root: any ItemRootControllable, model: any ItemDataAccessable, selection: GroupItemSelectionModel, @ViewBuilder content: () -> Content) {
        self.root = root
        self.model = model
        self.selection = selection
        self.content = content()
    }
    
    let root: ItemRootControllable
    let model: any ItemDataAccessable
    let selection: GroupItemSelectionModel
    let content: Content
    
    @Environment(\.appSizeMode) private var appSizeMode
    @Environment(\.navigator) private var navigator
    
    @State private var showSelection = false
    
    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack {
                itemView(itemId: model.id, selectedItemId: nil)
                
                ForEach(model.entries, id: \.self.id) { entry in
                    if let item = root.itemControllable.itemSync(for: entry.childId) {
                        itemView(itemId: item.id, selectedItemId: item.id)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    withAnimation { root.editControllable.removeGroup(childId: item.id) }
                                } label: {
                                    Image(systemName: "minus")
                                        .foregroundStyle(.white)
                                        .padding(10)
                                        .background(.red, in: Circle())
                                }
                                .buttonStyle(.plain)
#if !os(visionOS)
                                .glassEffect(.regular.interactive())
#endif
                            }
                    }
                }
                
                dropItemView
            }
        }
    }
}

private extension CarouselItemView {
    @ViewBuilder
    var dropItemView: some View {
        DropItemModuleArea(module: root.configurable.module, contentView: {
            areaButton
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
    
    var areaButton: some View {
        VStack {
            if appSizeMode == .regular {
                Text("Drop \(root.configurable.module.title)", bundle: .module)
                
                Image(systemName: "square.and.arrow.down")
                    .imageScale(.large)
            }
            Button {
                withAnimation { showSelection.toggle() }
                //navigator.navigate(to: SelectionModuleRoute.selection, method: .managedSheet)
            } label: {
                VStack {
                    Text("Select", bundle: .module)
                    if appSizeMode == .compact {
                        Text(root.configurable.module.title)
                        Image(systemName: "checkmark.circle")
                            .imageScale(.large)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 100)
        .frame(height: 100)
        .sheet(isPresented: $showSelection) {
            SelectionModuleRoute.selection
                .environment(root.rootController)
                .environment(root.itemSelectionModel)
        }
        .onChange(of: showSelection) {
            guard showSelection == false, let itemId = root.itemSelectionModel.itemId else { return }
            linkHandler(name: "", itemId: itemId, entryId: nil)
            root.itemSelectionModel.resetSelection(itemId: nil)
        }
    }
    
    func linkHandler(name: String, itemId: UUID, entryId: UUID?) {
        withAnimation { root.editControllable.addGroup(childId: itemId) }
    }
    
    func itemView(itemId: UUID, selectedItemId: UUID?) -> some View {
        content
            .environment(GroupItemSelectionModel(selectedItem: itemId))
            .frame(height: 110)
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
            .dropDestination(for: root.configurable.module, handler: linkHandler(name:itemId:entryId:))
            .padding(1)
    }
}
