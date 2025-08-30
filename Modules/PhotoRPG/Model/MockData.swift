// @copyright André Trettin

import CoreRPG
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()
    static let folderId = UUID()
    static let emptyFolderId = UUID()
    static let albumId = UUID()
        
    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: ItemDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        guard try! container.mainContext.fetch(FetchDescriptor<ItemDataModel>()).isEmpty else {
            return container
        }
        let model1 = ItemDataModel(
            id: previewId,
            module: .photo,
            name: "Mega Nice Photo",
            information: "A lot of information about this photo",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)

        let model2 = ItemDataModel(
            id: previewId2,
            module: .photo,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)

        let model3 = ItemDataModel(
            id: previewId3,
            module: .photo,
            name: "Zauberer",
            information: "A photo of a wizard.",
            category: .adventure,
            tags: ["NPC", "Wizward", "Schwarzmagier"]
        )
        container.mainContext.insert(model3)
        
        let subfolderId = UUID()
        let folder = ItemDataModel(
            id: folderId,
            module: .photo,
            name: "Project Folder",
            information: "A folder holding subfolders and photos.",
            category: .folder,
            tags: ["Folder", "Project"]
        )
        container.mainContext.insert(folder)
        
        let subfolder = ItemDataModel(
            id: subfolderId,
            module: .photo,
            name: "Subfolder",
            information: "A subfolder inside the main folder.",
            category: .folder,
            tags: ["Subfolder"]
        )
        container.mainContext.insert(subfolder)

        let folderPhoto = ItemDataModel(
            id: UUID(),
            module: .photo,
            name: "Folder Photo",
            information: "A photo inside the folder.",
            category: .adventure,
            tags: ["InFolder"],
            parentId: folderId
        )
        container.mainContext.insert(folderPhoto)
        let subfolderPhoto = ItemDataModel(
            id: UUID(),
            module: .photo,
            name: "Subfolder Photo",
            information: "A photo inside the subfolder.",
            category: .adventure,
            tags: ["InSubfolder"],
            parentId: subfolderId
        )
        container.mainContext.insert(subfolderPhoto)
        
        // Attach photos to folder and subfolder
        folder.reset(entries: [EntryDataModel(index: 0, parentId: folderId, childId: subfolderId), EntryDataModel(index: 1, parentId: folderId, childId: folderPhoto.id)])
        subfolder.reset(entries: [EntryDataModel(index: 0, parentId: folderId, childId: subfolderPhoto.id)])

        // Album with photos
        let albumPhoto1 = ItemDataModel(
            id: UUID(),
            module: .photo,
            name: "Album Photo 1",
            information: "A photo in the album.",
            category: .character,
            tags: ["Album"]
        )
        container.mainContext.insert(albumPhoto1)
        let albumPhoto2 = ItemDataModel(
            id: UUID(),
            module: .photo,
            name: "Album Photo 2",
            information: "Another album photo.",
            category: .adventure,
            tags: ["Album"]
        )
        container.mainContext.insert(albumPhoto2)
        let album = ItemDataModel(
            id: albumId,
            module: .photo,
            name: "My Album",
            information: "This is a test album.",
            category: .album,
            tags: ["Album"],
            entries: [EntryDataModel(index: 0, parentId: albumId, childId: albumPhoto1.id), EntryDataModel(index: 1, parentId: albumId, childId: albumPhoto2.id)]
        )
        container.mainContext.insert(album)
                
        // Additional standalone photos
        let photoX = ItemDataModel(
            id: UUID(),
            module: .photo,
            name: "Extra Photo",
            information: "Just another example photo.",
            category: .adventure,
            tags: ["Extra"]
        )
        let photoY = ItemDataModel(
            id: UUID(),
            module: .photo,
            name: "Standalone Photo",
            information: "Not in any folder or album.",
            category: .character,
            tags: ["Standalone"]
        )
        let emptyfolder = ItemDataModel(
            id: emptyFolderId,
            module: .photo,
            name: "Empty Folder",
            information: "This is empty for testing the new drop / add.",
            category: .folder,
            tags: ["Folder", "Test"]
        )

        container.mainContext.insert(photoX)
        container.mainContext.insert(photoY)
        container.mainContext.insert(emptyfolder)

        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        self._root = State(wrappedValue: PhotoRootModel(modelContext: modelContext))
    }
    
    @State private var root: PhotoRootModel

    func body(content: Content) -> some View {
        content.environment(root)
            .environment(root.searchModel)
            .environment(root.listController.listModel)
            .environment(root.listDisplayModel)
            .environment(root.rootController)
            .environment(CacheItemListModel())
            .environment(DeviceRotationModel())
            .environment(TabTitleModel())
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
