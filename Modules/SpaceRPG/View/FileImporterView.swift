// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.usdz]) { result in
            guard let url = try? result.get() else { return }
            root.editController.resetFile(url: url, in: model)
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
        
    }
    .environment(SpaceRootModel(modelContext: modelContext))
}
