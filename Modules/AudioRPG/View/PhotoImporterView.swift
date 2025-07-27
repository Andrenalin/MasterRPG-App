// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PhotoImporterView: View {
    let model: AudioDataModel
    let prominent: Bool

    var body: some View {
        contentView
    }
    
    @ViewBuilder
    var contentView: some View {
        FileImporterView(model: model, prominent: prominent)
    }
}

struct FileImporterView: View {
    let model: AudioDataModel
    let prominent: Bool

    @Environment(AudioRootModel.self) private var root
    @State private var showImporter = false
    
    var body: some View {
#if !os(tvOS)
        GlassButton(isProminent: prominent) {
            showImporter.toggle()
        } label: {
            Image(systemName: "folder\(showImporter ? ".fill" : "")")
                .imageScale(prominent ? .large : .medium)
        }
        .contentTransition(.symbolEffect(.replace.wholeSymbol))
        .fileImporter(isPresented: $showImporter, allowedContentTypes: FileController.fileTypes) { result in
            guard let url = try? result.get() else { return }
            root.editController.resetPhoto(url: url, in: model)
        }
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    VStack {
        Color
            .teal
            .frame(width: 256, height: 256)
            .overlay(FileImporterView(model: models[0], prominent: false), alignment: .top)

        PhotoImporterView(model: models[0], prominent: true)
    }
}
