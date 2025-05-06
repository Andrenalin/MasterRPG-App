// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public struct FolderSettingsEditor: View {
    public init(fileStore: FileUrlDataController) {
        self.fileStore = fileStore
    }
    
    let fileStore: FileUrlDataController
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selection: FileUrlViewModel.ID?
    @State private var sortOrder = [KeyPathComparator(\FileUrlViewModel.name)]
    
    @State private var showFolderSelector = false
    
    public var body: some View {
        NavigationStack {
            VStack {
                folderrActionBarView
                    .padding(.top, valueFor(iOS: 0, macOS: 12, tvOS: 0, visionOS: 0))
                
#if os(macOS)
                folderTableView
#else
                folderListView
#endif
            }
            .navigationTitle(Text("Folder Settings", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

private extension FolderSettingsEditor {
    var folderrActionBarView: some View {
        HStack {
            selectButtonView(id: selection)
                .disabled(selection == nil)
            
            Spacer()
            
            Button {
                withAnimation { showFolderSelector.toggle() }
            } label: {
                Image(systemName: "folder.badge.plus")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.green, .teal)
            }
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
#if !os(tvOS)
        .fileImporter(isPresented: $showFolderSelector, allowedContentTypes: [.folder]) { result in
            guard let selectedFolder = try? result.get() else { return }
            Task {
                let _ = selectedFolder.startAccessingSecurityScopedResource()
                defer { selectedFolder.stopAccessingSecurityScopedResource() }
                try? await fileStore.addFolder(url: selectedFolder)
            }
        }
#endif
    }

    @MainActor
    var folderListView: some View {
        List(selection: $selection) {
            ForEach(fileStore.model.folders) { folder in
                VStack {
                    HStack {
                        if folder.id == fileStore.model.defaultCloudPath {
                            Image(systemName: "checkmark.rectangle.stack")
                                .imageScale(.large)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.green, .teal)
                                .transition(.symbolEffect(.disappear))
                        }
                        
                        Image(systemName: folder.type.icon)
                            .imageScale(.large)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.green, .teal)
                        
                        Text(folder.name)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(folder.path)
                        .lineLimit(3)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    contextMenuView
                        .disabled(selection == nil)
                }
#if !os(tvOS)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    selectButtonView(id: folder.id)
                }
#endif
            }
            .onDelete(perform: remove(indexSet:))
        }
        .listStyle(.plain)
        .tint(colorScheme == .dark ? .blue.opacity(0.4) : .indigo.opacity(0.8))
    }
    
#if os(macOS)
    var folderTableView: some View {
        Table(fileStore.model.folders, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { fileViewModel in
                HStack {
                    if fileViewModel.id == fileStore.model.defaultCloudPath {
                        Image(systemName: "checkmark.rectangle.stack")
                            .imageScale(.large)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.green, .teal)
                            .transition(.symbolEffect(.disappear))
                    }
                    
                    Text(fileViewModel.name)
                }
            }
            .width(250)
            
            TableColumn("Type", value: \.type) { fileViewModel in
                Image(systemName: fileViewModel.type.icon)
                    .imageScale(.large)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.green, .teal)
                    .padding(4)
            }
            .width(52)
            
            TableColumn("Path", value: \.path)
                .width(min: 160)
        }
        .onChange(of: sortOrder) {
            fileStore.model.sortOrder = sortOrder
            fileStore.model.folders.sort(using: sortOrder)
        }
        .contextMenu {
            contextMenuView
                .disabled(selection == nil)
        }
        .onDeleteCommand {
            removeSelectedFolder()
        }
    }
#endif
    
    @ViewBuilder
    var contextMenuView: some View {
        selectButtonView(id: selection)
        
        Divider()
        
        Button(role: .destructive) {
            guard let folder = selection, let index = fileStore.model.folders.firstIndex(where: { $0.id == folder }) else { return }
            withAnimation { _ = fileStore.model.folders.remove(at: index) }
        } label: {
            Label {
                Text("Remove", bundle: .module)
            } icon: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
    }
    
    func selectButtonView(id: UUID?) -> some View {
        Button {
            withAnimation { fileStore.model.defaultCloudPath = fileStore.model.defaultCloudPath == id ? nil : id }
            withAnimation { selection = nil }
        } label: {
            Label {
                Text("Select Default Path", bundle: .module)
            } icon: {
                Image(systemName: "checkmark.rectangle.stack")
            }
        }
    }
    
    func remove(indexSet: IndexSet) {
        let ids = indexSet.map { fileStore.model.folders[$0].id }
        for id in ids {
            Task {
                await fileStore.removeFolder(id: id)
            }
        }
    }
    
    func removeSelectedFolder() {
        guard let folder = selection else { return }
        Task {
            await fileStore.removeFolder(id: folder)
        }
    }
}

#Preview {
    FolderSettingsEditor(fileStore: .empty())
}
