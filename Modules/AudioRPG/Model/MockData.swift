// @copyright André Trettin

import CoreRPG
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
            for: AudioDataModel.self, TagDataModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        
        guard try! container.mainContext.fetch(FetchDescriptor<AudioDataModel>()).isEmpty else {
            return container
        }
        let model1 = AudioDataModel(
            id: previewId,
            name: "Mega Nice Photo",
            information: "A lot of information about this photo",
            category: .adventure,
            tags: ["Example", "Title", "Ouside"]
        )
        container.mainContext.insert(model1)
        
        let model2 = AudioDataModel(
            id: previewId2,
            name: "Albert",
            information: "The is an example photo and the information is also set here",
            category: .character,
            tags: ["Player", "Mega", "Gnome"]
        )
        container.mainContext.insert(model2)
        
        let model3 = AudioDataModel(
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
        let rootFolder = AudioDataModel(
            id: folderId,
            name: "Root Folder",
            information: "Root Audio Folder",
            category: .folder,
            tags: ["Root"],
            entries: [
                AudioEntryDataModel(index: 0, childId: subfolderId1),
                AudioEntryDataModel(index: 1, childId: subfolderId2),
                AudioEntryDataModel(index: 2, childId: audioIdRoot1),
                AudioEntryDataModel(index: 3, childId: audioIdRoot2)
            ]
        )
        container.mainContext.insert(rootFolder)

        // Subfolder 1
        let subfolder1 = AudioDataModel(
            id: subfolderId1,
            name: "Subfolder 1",
            information: "Subfolder 1 with audio",
            category: .folder,
            tags: ["Sub1"],
            parentId: folderId,
            entries: [AudioEntryDataModel(index: 0, childId: audioIdSub1), AudioEntryDataModel(index: 1, childId: audioIdSub2)]
        )
        container.mainContext.insert(subfolder1)

        // Subfolder 2
        let subfolder2 = AudioDataModel(
            id: subfolderId2,
            name: "Subfolder 2",
            information: "Another folder with sound",
            category: .folder,
            tags: ["Sub2"],
            parentId: folderId,
            entries: [AudioEntryDataModel(index: 0, childId: audioIdSub3)]
        )
        container.mainContext.insert(subfolder2)

        // Audio in root
        let rootAudio1 = AudioDataModel(
            id: audioIdRoot1,
            name: "Root Sound 1",
            information: "Root folder audio 1",
            category: .music,
            tags: ["Root", "SFX"],
            parentId: folderId
        )
        container.mainContext.insert(rootAudio1)
        let rootAudio2 = AudioDataModel(
            id: audioIdRoot2,
            name: "Root Sound 2",
            information: "Root folder audio 2",
            category: .music,
            tags: ["Root", "Music"],
            parentId: folderId
        )
        container.mainContext.insert(rootAudio2)

        // Audio in subfolders
        let audioSub1 = AudioDataModel(
            id: audioIdSub1,
            name: "Sub 1 Audio 1",
            information: "An audio in subfolder 1",
            category: .music,
            tags: ["Sub1", "SFX"],
            parentId: subfolderId1
        )
        container.mainContext.insert(audioSub1)
        let audioSub2 = AudioDataModel(
            id: audioIdSub2,
            name: "Sub 1 Audio 2",
            information: "Second audio in subfolder 1",
            category: .music,
            tags: ["Sub1", "Music"],
            parentId: subfolderId1
        )
        container.mainContext.insert(audioSub2)
        let audioSub3 = AudioDataModel(
            id: audioIdSub3,
            name: "Sub 2 Audio 1",
            information: "Audio in subfolder 2",
            category: .music,
            tags: ["Sub2", "Ambience"],
            parentId: subfolderId2
        )
        container.mainContext.insert(audioSub3)

        // Playlist containing everything from root and all folders
        let playlist = AudioDataModel(
            id: playlistId,
            name: "All Sounds Playlist",
            information: "Playlist from root to all folders",
            category: .playlist,
            tags: ["Playlist", "All"],
            entries: [
                AudioEntryDataModel(index: 0, childId: audioIdRoot1),
                AudioEntryDataModel(index: 1, childId: audioIdRoot2),
                AudioEntryDataModel(index: 2, childId: audioIdSub1),
                AudioEntryDataModel(index: 3, childId: audioIdSub2),
                AudioEntryDataModel(index: 4, childId: audioIdSub3)
            ]
        )
        container.mainContext.insert(playlist)
        // --- END Additional Mock Data ---

        return container
    }
}

struct MockRootViewModifier: ViewModifier {
    init(modelContext: ModelContext) {
        self._root = State(wrappedValue: AudioRootModel(modelContext: modelContext))
    }
    
    @State private var root: AudioRootModel
    
    func body(content: Content) -> some View {
        content.environment(root)
            .environment(root.searchModel)
            .environment(root.listModel)
            .environment(root.listDisplayModel)
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
