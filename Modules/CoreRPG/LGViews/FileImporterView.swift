// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public struct FileImporterView: View {
    public init(editControllable: any EditControllable, fileTypes: [UTType], itemId: UUID, isProminent: Bool = true) {
        self.editControllable = editControllable
        self.fileTypes = fileTypes
        self.itemId = itemId
        self.isProminent = isProminent
    }
    
    let editControllable: any EditControllable
    let fileTypes: [UTType]
    let itemId: UUID
    let isProminent: Bool
    
    @State private var showImporter = false
    
    public var body: some View {
#if !os(tvOS)
        if !fileTypes.isEmpty {
            GlassButton(isProminent: isProminent) {
                showImporter.toggle()
            } label: {
                Label {
                    Text("Import File", bundle: .module)
                } icon: {
                    Image(systemName: "folder")
                        .symbolVariant(showImporter ? .fill : .none)
                        .imageScale(isProminent ? .large : .medium)
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                }
                .labelStyle(.iconOnly)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: fileTypes) { result in
                guard let url = try? result.get() else { return }
                Task {
                    await editControllable.resetFile(url: url, itemId: itemId)
                }
            }
        }
#endif
    }
}

#Preview {
    FileImporterView(
        editControllable: FakeEditController.fake,
        fileTypes: [.data],
        itemId: UUID()
    )
    .padding()
}
