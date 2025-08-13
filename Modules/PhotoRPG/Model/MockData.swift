// @copyright André Trettin

import CoreRPG
import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()
    static let emptyFolderId = UUID()
    static let albumId = UUID()
        
    func body(content: Content, context: ModelContainer) -> some View {
        content
            .modifier(MockRootViewModifier(modelContext: context.mainContext))
            .modelContainer(context)
    }
    static func makeSharedContext() async throws -> ModelContainer {
        let container = try! ModelContainer(
            for: PhotoDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        guard try! container.mainContext.fetch(FetchDescriptor<PhotoDataModel>()).isEmpty else {
            print("*** Empty ***")
            return container
        }
        let model1 = PhotoDataModel(
            id: previewId,
            name: "Mega Nice Photo",
            information: "A lot of information about this photo",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)

        let model2 = PhotoDataModel(
            id: previewId2,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)

        let model3 = PhotoDataModel(
            id: previewId3,
            name: "Zauberer",
            information: "A photo of a wizard.",
            category: .adventure,
            tags: ["NPC", "Wizward", "Schwarzmagier"]
        )
        container.mainContext.insert(model3)

        // --- BEGIN Additional Mock Data ---
        // Folder hierarchy
        let folderId = UUID()
        let subfolderId = UUID()
        let folder = PhotoDataModel(
            id: folderId,
            name: "Project Folder",
            information: "A folder holding subfolders and photos.",
            category: .folder,
            tags: ["Folder", "Project"]
        )
        let subfolder = PhotoDataModel(
            id: subfolderId,
            name: "Subfolder",
            information: "A subfolder inside the main folder.",
            category: .folder,
            tags: ["Subfolder"]
        )
        let folderPhoto = PhotoDataModel(
            id: UUID(),
            name: "Folder Photo",
            information: "A photo inside the folder.",
            category: .adventure,
            tags: ["InFolder"],
            parentId: folderId
        )
        let subfolderPhoto = PhotoDataModel(
            id: UUID(),
            name: "Subfolder Photo",
            information: "A photo inside the subfolder.",
            category: .adventure,
            tags: ["InSubfolder"],
            parentId: subfolderId
        )
        // Attach photos to folder and subfolder
        folder.reset(entries: [PhotoEntryDataModel(index: 0, childId: subfolderId), PhotoEntryDataModel(index: 1, childId: folderPhoto.id)])
        subfolder.reset(entries: [PhotoEntryDataModel(index: 0, childId: subfolderPhoto.id)])
        container.mainContext.insert(folder)
        container.mainContext.insert(subfolder)
        container.mainContext.insert(folderPhoto)
        container.mainContext.insert(subfolderPhoto)

        // Album with photos
        let albumPhoto1 = PhotoDataModel(
            id: UUID(),
            name: "Album Photo 1",
            information: "A photo in the album.",
            category: .character,
            tags: ["Album"]
        )
        let albumPhoto2 = PhotoDataModel(
            id: UUID(),
            name: "Album Photo 2",
            information: "Another album photo.",
            category: .adventure,
            tags: ["Album"]
        )
        let album = PhotoDataModel(
            id: albumId,
            name: "My Album",
            information: "This is a test album.",
            category: .album,
            tags: ["Album"],
            entries: [PhotoEntryDataModel(index: 0, childId: albumPhoto1.id), PhotoEntryDataModel(index: 1, childId: albumPhoto2.id)]
        )
        container.mainContext.insert(album)
        container.mainContext.insert(albumPhoto1)
        container.mainContext.insert(albumPhoto2)

        // Additional standalone photos
        let photoX = PhotoDataModel(
            id: UUID(),
            name: "Extra Photo",
            information: "Just another example photo.",
            category: .adventure,
            tags: ["Extra"]
        )
        let photoY = PhotoDataModel(
            id: UUID(),
            name: "Standalone Photo",
            information: "Not in any folder or album.",
            category: .character,
            tags: ["Standalone"]
        )
        let emptyfolder = PhotoDataModel(
            id: emptyFolderId,
            name: "Empty Folder",
            information: "This is empty for testing the new drop / add.",
            category: .folder,
            tags: ["Folder", "Test"]
        )

        container.mainContext.insert(photoX)
        container.mainContext.insert(photoY)
        container.mainContext.insert(emptyfolder)
        // --- END Additional Mock Data ---

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
            .environment(CacheItemListModel())
            .environment(DeviceRotationModel())
            .environment(ListModel())
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
