// @copyright André Trettin

import Combine
import SwiftUI

public struct SelectFolderSettingsEditor: View {
    public init(fileStore: FileUrlDataController) {
        self.fileStore = fileStore
    }
    
    let fileStore: FileUrlDataController
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var alertMessage = ""
    @State private var showValidationAlert = false
    
    @State private var showConvertSpinner = false
    
    @State private var sortOrder = [KeyPathComparator(\FileUrlViewModel.name)]
    @State private var selected = Set<FileUrlViewModel.ID>()
    
#if os(iOS) || os(visionOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
#else
    private var isCompact: Bool {
        false
    }
#endif
    
    public var body: some View {
        NavigationStack {
            VStack {
                actionsBarView
                    .padding()
                
#if os(macOS)
                tableView
#else
                fileListView
#endif
            }
            .task {
                Task { @MainActor in
                    await fileStore.fetch()
                }
            }
            .navigationTitle(Text("File Management", bundle: .module))
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
    
#if os(macOS)
    private var tableView: some View {
        Table(fileStore.fileUrls, selection: $selected, sortOrder: $sortOrder) {
            TableColumn(Text("Name", bundle: .module), value: \.name) { fileViewModel in
                HStack {
                    if isCompact {
                        Image(systemName: fileViewModel.type.icon)
                            .imageScale(.large)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.green, .teal)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fileViewModel.name)
                        if isCompact {
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(fileViewModel.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .width(min: 64)
            
            TableColumn(Text("Type", bundle: .module), value: \.type) { fileViewModel in
                Image(systemName: fileViewModel.type.icon)
                    .imageScale(.large)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.green, .teal)
                    .padding(4)
            }
            .width(52)
            
            TableColumn(Text("Data", bundle: .module), value: \.hasDataText) { fileViewModel in
                Text(String(localized: fileViewModel.hasDataLabel).localizedString)
            }
            .width(52)
            
            TableColumn(Text("Access", bundle: .module), value: \.hasAccessIcon) { fileViewModel in
                Image(systemName: fileViewModel.hasAccessIcon)
                    .imageScale(.large)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.green, .teal)
                    .padding(4)
            }
            .width(52)
            
            TableColumn(Text("Loaded", bundle: .module), value: \.isDownloadedIcon) { fileViewModel in
                Image(systemName: fileViewModel.isDownloadedIcon)
                    .imageScale(.large)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.green, .teal)
                    .padding(4)
            }
            .width(52)
            
            TableColumn(Text("Path", bundle: .module), value: \.path)
                .width(min: 160)
        }
        .onChange(of: sortOrder) {
            fileStore.model.sortOrder = sortOrder
            fileStore.fileUrls.sort(using: sortOrder)
        }
    }
#endif
    
    @MainActor
    var fileListView: some View {
        List(selection: $selected) {
            ForEach(fileStore.fileUrls) { folder in
                VStack {
                    HStack {
                        if folder.hasData {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(.green, .teal)
                                .transition(.symbolEffect(.disappear))
                        }
                        
                        Image(systemName: folder.hasAccessIcon)
                            .foregroundStyle(.green, .teal)
                        
                        Image(systemName: folder.isDownloadedIcon)
                            .foregroundStyle(.green, .teal)
                        
                        Text(folder.name)
                    }
                    .imageScale(.large)
                    .symbolRenderingMode(.palette)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(folder.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .tint(colorScheme == .dark ? .blue.opacity(0.4) : .indigo.opacity(0.8))
    }
    
    private var actionsBarView: some View {
        HStack {
            Button {
                showConvertSpinner.toggle()
                if selected.isEmpty {
                    Task {
                        await fileStore.fetch()
                        await fileStore.convertData()
                    }
                } else {
                    selected.forEach { id in
                        Task {
                            await fileStore.fetch()
                            await fileStore.convertData(fileId: id)
                        }
                    }
                }
                selected = []
            } label: {
                Label {
                    Text("Convert Data", bundle: .module)
                } icon: {
                    Image(systemName: "brain.head.profile")
                }
                .opacity(showConvertSpinner ? 0 : 1)
                .imageScale(.large)
                .overlay {
                    ProgressView()
                        .opacity(showConvertSpinner ? 1 : 0)
                }
            }
            .animation(.default, value: showConvertSpinner)
            .disabled(showConvertSpinner)
            .onChange(of: fileStore.processing, initial: true) {
                if fileStore.processing <= 0 {
                    showConvertSpinner = false
                }
            }
            
            Spacer()
            
            FileAccessSettingsEditor(store: fileStore)
        }
    }
}

#Preview {
    SelectFolderSettingsEditor(fileStore: .empty())
}
