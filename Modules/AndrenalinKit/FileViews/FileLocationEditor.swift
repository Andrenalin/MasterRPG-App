// @copyright André Trettin

import SwiftUI

public struct FileLocationEditor: View {
    public init(editController: any EditControllable, fileStore: FileUrlDataController, fileUrlBinding: Binding<FileUrl?>) {
        self.editController = editController
        self.fileStore = fileStore
        self.fileUrlBinding = fileUrlBinding
    }

    let editController: any EditControllable
    let fileStore: FileUrlDataController
    let fileUrlBinding: Binding<FileUrl?>

    @State private var location: FileLocation?

    @State private var newLocation: FileLocation?
    @State private var showPanel = false
    @State private var fileError: Error?

    @State private var name: String = ""
    @State private var hasAccess = false
    @State private var fileDownloaded: Bool?

    enum FileOperationErrors: Error {
        case changeLocationError
    }

    public var body: some View {
        Group {
            LabeledContent {
                locationView
            } label: {
                Text("Location", bundle: .module)
            }

            LabeledContent {
                filePathView
            } label: {
                Text("Path", bundle: .module)
            }
        }
        .onChange(of: fileUrlBinding.wrappedValue, initial: true) {
            withAnimation {
                location <=> fileUrlBinding.wrappedValue?.location
            }
            Task {
                await loadAsyncData()
            }
        }
        .task {
            let newName = await nameModel
            withAnimation { name = newName }
        }
    }
}

private extension FileLocationEditor {
    func loadAsyncData() async {
        guard let fileUrl = fileUrlBinding.wrappedValue else {
            hasAccess = false
            fileDownloaded = false
            return
        }
        hasAccess = await fileStore.hasAccess(for: fileUrl)
        fileDownloaded = await fileStore.fileDownloaded(for: fileUrl)
    }

    var locationView: some View {
        HStack {
            if fileUrlBinding.wrappedValue != nil {
                Picker(selection: fileLocation) {
                    ForEach(FileLocation.allCases) { location in
                        Text(location.text)
                            .tag(location)
                    }
                } label: {
                    Text("Location", bundle: .module)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            } else {
                Text("No file choosen", bundle: .module)
            }

            FileBrowserPickerView(shown: $showPanel, pickerType: .save, fileNameSuggestion: name, types: fileStore.fileTypes) { url in
                guard let url, let newLocation else {
                    newLocation = nil
                    return
                }
                changeLocation(to: newLocation, newUrl: url)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    
    private var nameModel: String {
        get async {
            guard let model = editController.editorModel.currentListItem?.model else { return "" }
            let name = await editController.itemControllable.name(model: model)
            var fileExtension = fileStore.filenameExtension
            if let urlExtension = fileUrlBinding.wrappedValue?.fileExtension, !urlExtension.isEmpty {
                fileExtension = urlExtension
            }
            return "\(name).\(fileExtension)"
        }
    }

    private var fileLocation: Binding<FileLocation> {
        Binding {
            fileUrlBinding.wrappedValue?.location ?? .other
        } set: { newValue in
            guard newValue != fileUrlBinding.wrappedValue?.location else { return }
            if newValue == .other || newValue == .icloud {
                newLocation = newValue
                showPanel.toggle()
                return
            }
            changeLocation(to: newValue, newUrl: nil)
        }
    }

    var filePathView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                if let fileUrl = fileUrlBinding.wrappedValue {
                    Image(systemName: "\(hasAccess ? "lock.open" : "lock")")

                    Image(systemName: downloadIcon(for: fileUrl))

                    Text("\(fileUrl.rawUrl.relativePath)")
                } else {
                    Text("No file", bundle: .module)
                }
            }
        }
    }

    func downloadIcon(for fileUrl: FileUrl) -> String {
        guard let downloaded = fileDownloaded else { return "icloud.slash" }
        return downloaded ? "checkmark.icloud" : "xmark.icloud"
    }

    func changeLocation(to newLocation: FileLocation, newUrl: URL?) {
        guard let fileUrl = fileUrlBinding.wrappedValue else { return }
        Task {
            do {
                guard let updatedUrl = try await fileStore.change(fileUrl: fileUrl, to: newLocation, newUrl: newUrl) else {
                    fileError = FileOperationErrors.changeLocationError
                    return
                }
                fileUrlBinding.wrappedValue = updatedUrl
                editController.save(with: String(localized: "File path").localizedString)
            } catch {
                fileError = error
            }
        }
    }
}
