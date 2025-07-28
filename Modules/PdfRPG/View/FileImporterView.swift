// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct FileImporterView: View {
    let model: PdfDataModel
    let prominent: Bool
    
    @Environment(PdfRootModel.self) private var root
    @State private var showImporter = false
    
    var body: some View {
#if !os(tvOS)
        GlassButton(isProminent: prominent) {
            showImporter.toggle()
        } label: {
            Image(systemName: "folder\(showImporter ? ".fill" : "")")
                .imageScale(prominent ? .large : .medium)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: FileController.fileTypes) { result in
            guard let url = try? result.get() else { return }
            root.editController.resetFile(url: url, in: model)
        }
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [PdfDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    VStack {
        Color
            .teal
            .frame(width: 256, height: 256)
            .overlay(FileImporterView(model: models[0], prominent: true), alignment: .top)
        
    }
}
