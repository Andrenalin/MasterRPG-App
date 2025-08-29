// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import SwiftData
import SwiftUI

struct PhotoDropChooseView: View {
    let model: ItemSelectionModel
    
    @Environment(PhotoRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    
    var body: some View {
        DropItemArea {
            Group {
                if let itemId = model.itemId, let item = root.itemController.modelSync(for: itemId) {
                    GroupedPhotoView(cacheController: root.cacheController, model: item)
                } else {
                    emptyDrop
                }
            }
            .frame(height: 128)
        } dropAction: { links in
            addLinks(links: links)
        }
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.accentColor.tertiary)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.accentColor.secondary, lineWidth: 2)
        }
        .padding(1)
        .overlay(alignment: .topTrailing) {
            Button(role: .destructive) {
                withAnimation {
                    model.selection = []
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .imageScale(.large)
                    .foregroundStyle(.white, .red, .red)
            }
#if !os(visionOS)
            .glassEffect()
#endif
            .opacity(model.itemId != nil ? 1.0 : 0.0)
        }
    }
    
    private var emptyDrop: some View {
        Button {
            root.itemSelectionModel = model
            navigator.navigate(to: SelectionPhotoRoute.selection, method: .managedSheet)
        } label: {
            VStack {
                if showDrop {
                    Text("Drop \(root.module.title)", bundle: .module)
                    
                    Image(systemName: "square.and.arrow.down")
                        .imageScale(.large)
                }
                Text("Choose \(root.module.title)", bundle: .module)
            }
            .padding(.horizontal, 12)
        }
    }
    
    private var showDrop: Bool {
#if os(iOS)
        horizontalSizeClass == .regular
#else
        true
#endif
    }
    
    private func addLinks(links: [LinkData]) -> Bool {
        model.selection = links.compactMap { link -> WindowItemSelection? in
            guard link.module == root.module else { return nil }
            return WindowItemSelection(itemId: link.itemId, entryId: link.entryId)
        }
        return true
    }
}

#Preview(traits: .mockData) {
    PhotoDropChooseView(model: ItemSelectionModel())
}
