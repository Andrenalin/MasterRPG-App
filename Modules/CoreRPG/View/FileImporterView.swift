// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public struct FileImporterView<Model: Identifiable, EditController: OldEditControllable>: View where Model.ID == UUID, Model == EditController.Model {
    public init(model: Model, editController: EditController, fileTypes: [UTType], isProminent: Bool = true) {
        self.model = model
        self.editController = editController
        self.fileTypes = fileTypes
        self.isProminent = isProminent
    }
    
    let model: Model
    let editController: EditController
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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: fileTypes) { result in
            guard let url = try? result.get() else { return }
            editController.resetFile(url: url, in: model)
        }
#endif
    }
}
