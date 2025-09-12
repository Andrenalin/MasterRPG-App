// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public struct FileImporterView: View {
    public init(editControllable: any EditControllable, model: ItemDataModel, fileTypes: [UTType], isProminent: Bool = true) {
        self.editControllable = editControllable
        self.model = model
        self.fileTypes = fileTypes
        self.isProminent = isProminent
    }
    
    let editControllable: EditControllable
    let model: ItemDataModel
    let fileTypes: [UTType]
    let isProminent: Bool
    
    @State private var showImporter = false
    
    public var body: some View {
#if !os(tvOS)
        GlassButton(isProminent: isProminent) {
            showImporter.toggle()
        } label: {
            Image(systemName: "folder\(showImporter ? ".fill" : "")")
                .imageScale(isProminent ? .large : .medium)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
        }
        .background(.tint)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: fileTypes) { result in
            guard let url = try? result.get() else { return }
            editControllable.resetFile(url: url, in: model)
        }
#endif
    }
}
