// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

struct ItemFileImporterView: View {
    let root: any ItemRootControllable
    let model: any ItemDataAccessable
    let fileTypes: [UTType]
    let isInitial: Bool
    
    var body: some View {
        Group {
            if isInitial {
                initialStyle
            } else {
                overlayStyle
            }
        }
    }
    
    @ViewBuilder
    private var initialStyle: some View {
        HStack {
            fileImporterContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .opacity(1)
        .transition(.scale)
    }
    
    @ViewBuilder
    private var overlayStyle: some View {
        HStack(alignment: .bottom, spacing: 0) {
            filePathDisplay
                .zIndex(0)

            Spacer(minLength: 20)

            fileImporterContent
                .zIndex(100)
        }
    }
    
    @ViewBuilder
    private var fileImporterContent: some View {
        if root.viewControllable.fileImporterViewType == .file {
            FileImporterView(
                editControllable: root.editControllable,
                fileTypes: fileTypes,
                itemId: model.id
            )
            .applyIf(isInitial) {
                $0.padding(32)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.tint, lineWidth: 2)
                    }
            }
        } else {
            root.viewControllable.fileImporterView(
                for: model.id,
                preopen: isInitial,
                layoutDown: !isInitial
            )
        }
    }
    
    @ViewBuilder
    private var filePathDisplay: some View {
        if !isInitial {
            HStack {
                Text(model.url?.path(percentEncoded: false) ?? 
                     String(localized: "No file is set", bundle: .module).localizedString)
                    .font(.callout)
            }
            .padding(.vertical)
#if !os(visionOS)
            .glassEffectAll(.regular.interactive())
#endif
        }
    }
}

#Preview("File Importer") {
    ItemFileImporterView(
        root: ItemRootController.fake,
        model: FakeItemModel.empty,
        fileTypes: [],
        isInitial: true
    )
}
