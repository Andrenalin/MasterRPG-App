// @copyright André Trettin

import CoreRPG
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: SpaceDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        let model1 = SpaceDataModel(
            id: previewId,
            name: "Mega Nice",
            information: "A lot of information about this item",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)
        
        return container
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
