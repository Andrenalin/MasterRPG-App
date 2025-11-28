// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct AdventureDetailEditor: View {
    let editController: EditController
    let model: AdventureModel

    @Environment(AdventureRootModel.self) private var root
    @Environment(\.wideMode) private var wideMode

    @State private var detailHeaderModel = DetailHeaderModel(minHeight: 144, maxHeight: 400, maxHeightFromScreenHeight: true)
    @State private var externalHeaderModel = ExternalHeaderModel()

    var body: some View {
        @Bindable var model = model
//        let _ = Self._printChanges()
//        let _ = print("AdventureDetailEditor: \(Unmanaged.passUnretained(editController.cacheItemListModel).toOpaque())")
        
        DetailEditor(editController: editController) {
            HeaderEditor(editController: editController)

            PhotoSelectionEditor(editController: editController)
            
            SpecialEditor(editController: editController)

#if !os(macOS)
            AdventureEntrySectionEditor(editController: editController)
#endif
        } headerView: {
            AdventureDetailHeader(editController: editController, model: model)
#if !os(macOS)
                .ignoresSafeArea(.container, edges: .top)
#endif
        } extHeaderView: {
            AdventureExternalHeader(editController: editController)
        } extContentView: {
#if !os(tvOS)
            AdventureEntryEditor(root: root, editController: editController)
#endif
        }
        .environment(detailHeaderModel)
        .environment(externalHeaderModel)
        .onChange(of: model.entries, initial: true) {
            externalHeaderModel.minHeight = Double(model.entries.count * 128)
        }
    }    
}

struct AdventureExternalHeader: View {
    let editController: EditController

    @Environment(ExternalHeaderModel.self) private var externalHeaderModel

    var body: some View {
        AdventureSheet(model: editController.model) {
            externalHeaderModel.showExtHeader = false
        }
    }
}

#Preview {
    AdventureDetailEditor(editController: .preview, model: .preview)
        .environment(AdventureRootModel.previewWithData)
        .environment(ListModel.preview)
}
