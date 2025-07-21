// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PhotoImporterView: View {
    let model: SpaceDataModel

    var body: some View {
        ViewThatFits {
            HStack(spacing: 40) {
                contentView
            }

            VStack(spacing: 40) {
                contentView
            }
        }
    }
    
    @ViewBuilder
    var contentView: some View {
        FileImporterView(model: model, size: 80)
    }
}

struct FileImporterView: View {
    let model: SpaceDataModel
    let size: CGFloat
    
    @Environment(SpaceRootModel.self) private var root
    
    @State private var showImporter = false
    
    init(model: SpaceDataModel, size: CGFloat = 24) {
        self.model = model
        self.size = size
    }
    
    var body: some View {
#if !os(tvOS)
        GlassButton {
            showImporter.toggle()
        } label: {
            Image(systemName: "folder\(showImporter ? ".fill" : "")")
                .font(.system(size: size))
                .padding(size / 3)
        }
        .contentTransition(.symbolEffect(.replace.wholeSymbol))
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
            guard let url = try? result.get() else { return }
            root.editController.resetPhoto(url: url, in: model)
        }
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [SpaceDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    VStack {
        Color
            .teal
            .frame(width: 256, height: 256)
            .overlay(FileImporterView(model: models[0]), alignment: .top)
        
        PhotoImporterView(model: models[0])
    }
    .environment(SpaceRootModel(modelContext: modelContext))
}
