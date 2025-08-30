// @copyright André Trettin

import SwiftUI
import SwiftData

struct MockData: PreviewModifier {
    static let previewId = UUID()
    static let previewId2 = UUID()
    static let previewId3 = UUID()
    static let folderId = UUID()
    static let playlistId = UUID()


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
            name: "Mega Nice Photo",
            information: "A lot of information about this photo",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)
        
        let model2 = ItemDataModel(
            id: previewId2,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)
        
        let model3 = ItemDataModel(
            id: previewId3,
            name: "Zauberer",
            information: "A photo of a wizard.",
            category: .adventure,
            tags: ["NPC", "Wizward", "Schwarzmagier"]
        )
        container.mainContext.insert(model3)

        // --- BEGIN Additional Mock Data ---
        // Folder hierarchy
        let subfolderId1 = UUID()
        let subfolderId2 = UUID()
        let audioIdRoot1 = UUID()
        let audioIdRoot2 = UUID()
        let audioIdSub1 = UUID()
        let audioIdSub2 = UUID()
        let audioIdSub3 = UUID()

        // Root folder
        let rootFolder = ItemDataModel(
            id: folderId,
            name: "Root Folder",
            information: "Root Audio Folder",
            category: .folder,
            tags: ["Root"],
            entries: [
                EntryDataModel(index: 0, parentId: folderId, childId: subfolderId1),
                EntryDataModel(index: 1, parentId: folderId, childId: subfolderId2),
                EntryDataModel(index: 2, parentId: folderId, childId: audioIdRoot1),
                EntryDataModel(index: 3, parentId: folderId, childId: audioIdRoot2)
            ]
        )
        container.mainContext.insert(rootFolder)

        // Subfolder 1
        let subfolder1 = ItemDataModel(
            id: subfolderId1,
            name: "Subfolder 1",
            information: "Subfolder 1 with audio",
            category: .folder,
            tags: ["Sub1"],
            parentId: folderId,
            entries: [EntryDataModel(index: 0, parentId: subfolderId1, childId: audioIdSub1), EntryDataModel(index: 1, parentId: subfolderId1, childId: audioIdSub2)]
        )
        container.mainContext.insert(subfolder1)

        // Subfolder 2
        let subfolder2 = ItemDataModel(
            id: subfolderId2,
            name: "Subfolder 2",
            information: "Another folder with sound",
            category: .folder,
            tags: ["Sub2"],
            parentId: folderId,
            entries: [EntryDataModel(index: 0, parentId: subfolderId2, childId: audioIdSub3)]
        )
        container.mainContext.insert(subfolder2)

        // Audio in root
        let rootAudio1 = ItemDataModel(
            id: audioIdRoot1,
            name: "Root Sound 1",
            information: "Root folder audio 1",
            category: .music,
            tags: ["Root", "SFX"],
            parentId: folderId
        )
        container.mainContext.insert(rootAudio1)
        let rootAudio2 = ItemDataModel(
            id: audioIdRoot2,
            name: "Root Sound 2",
            information: "Root folder audio 2",
            category: .music,
            tags: ["Root", "Music"],
            parentId: folderId
        )
        container.mainContext.insert(rootAudio2)

        // Audio in subfolders
        let audioSub1 = ItemDataModel(
            id: audioIdSub1,
            name: "Sub 1 Audio 1",
            information: "An audio in subfolder 1",
            category: .music,
            tags: ["Sub1", "SFX"],
            parentId: subfolderId1
        )
        container.mainContext.insert(audioSub1)
        let audioSub2 = ItemDataModel(
            id: audioIdSub2,
            name: "Sub 1 Audio 2",
            information: "Second audio in subfolder 1",
            category: .music,
            tags: ["Sub1", "Music"],
            parentId: subfolderId1
        )
        container.mainContext.insert(audioSub2)
        let audioSub3 = ItemDataModel(
            id: audioIdSub3,
            name: "Sub 2 Audio 1",
            information: "Audio in subfolder 2",
            category: .music,
            tags: ["Sub2", "Ambience"],
            parentId: subfolderId2
        )
        container.mainContext.insert(audioSub3)

        // Playlist containing everything from root and all folders
        let playlist = ItemDataModel(
            id: playlistId,
            name: "All Sounds Playlist",
            information: "Playlist from root to all folders",
            category: .playlist,
            tags: ["Playlist", "All"],
            entries: [
                EntryDataModel(index: 0, parentId: playlistId, childId: audioIdRoot1),
                EntryDataModel(index: 1, parentId: playlistId, childId: audioIdRoot2),
                EntryDataModel(index: 2, parentId: playlistId, childId: audioIdSub1),
                EntryDataModel(index: 3, parentId: playlistId, childId: audioIdSub2),
                EntryDataModel(index: 4, parentId: playlistId, childId: audioIdSub3)
            ]
        )
        container.mainContext.insert(playlist)
        // --- END Additional Mock Data ---

        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        self._root = State(wrappedValue: FakeItemRootController(modelContext: modelContext, module: .audio))
    }
    
    @State private var root: FakeItemRootController
    
    func body(content: Content) -> some View {
        content.environment(root)
            .environment(root.searchModel)
            .environment(root.listControllable.listModel)
            .environment(root.listDisplayModel)
            .environment(CacheItemListModel())
            .environment(DeviceRotationModel())
            .environment(TabTitleModel())
            .environment(rootController)
#if os(macOS)
            .frame(width: 800, height: 600)
#endif
    }
    
    var rootController: ItemRootController {
        ItemRootController(module: root.module, listDisplayModel: root.listDisplayModel, searchModel: root.searchModel, itemSelectionModel: root.itemSelectionModel, cacheControllable: root.cacheControllable, editControllable: root.editControllable, itemControllable: root.itemControllable, listControllable: root.listControllable, listLinkControllable: root.listLinkControllable, viewControllable: root.viewControllable)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    static var mockData: Self = .modifier(MockData())
}
