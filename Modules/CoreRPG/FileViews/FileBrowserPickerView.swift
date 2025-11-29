// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public enum FileBrowserPickerType  {
    case open
    case save
    case saveDir
}

public struct FileBrowserPickerView: View {
    public init(shown: Binding<Bool>, pickerType: FileBrowserPickerType, fileNameSuggestion: String, types: [UTType] = [UTType.pdf], handler: @escaping (URL?) -> Void) {
        self._shown = shown
        self.pickerType = pickerType
        self.filenameSuggestion = fileNameSuggestion
        self.types = types
        self.handler = handler
    }

    @Binding var shown: Bool
    let pickerType: FileBrowserPickerType
    let filenameSuggestion: String
    let types: [UTType]
    let handler: (URL?) -> Void

    public var body: some View {
#if os(tvOS)
        EmptyView()
#else
        Color.clear.frame(width: 10, height: 10)
#if os(iOS) || os(visionOS)
            .sizedSheet(isPresented: $shown) {
                BrowserPicker(shown: $shown, pickerType: pickerType, fileName: filenameSuggestion, types: types, handler: handler)
            }
#else
            .onChange(of: shown) {
                if shown {
                    if pickerType == .save {
                        BrowserPicker.showSavePanel(shown: $shown, fileName: filenameSuggestion, types: types, save: handler)
                    } else {
                        BrowserPicker.showOpenPanel(shown: $shown, fileName: filenameSuggestion, types: types, load: handler)
                    }
                }
            }
#endif
#endif
    }
}

#if os(macOS)

enum BrowserPicker {
    @MainActor
    static func showOpenPanel(shown: Binding<Bool>, fileName: String, types: [UTType] = [UTType.pdf], load: (URL?) -> Void) {
        let fileUrl = URL(string: fileName)
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Choose a file"
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = types
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.canDownloadUbiquitousContents = true
        openPanel.canResolveUbiquitousConflicts = true
        openPanel.directoryURL = fileUrl

        let response = openPanel.runModal()

        guard let url = response == .OK ? openPanel.url : nil else {
            shown.wrappedValue = false
            return
        }

        load(url)
        shown.wrappedValue = false
    }

    @MainActor
    static func showSavePanel(shown: Binding<Bool>, fileName: String, types: [UTType] = [UTType.pdf], save: (URL?) -> Void) {
        let savePanel = NSSavePanel()
        savePanel.prompt = "Save into a file"
        savePanel.nameFieldStringValue = fileName
        savePanel.allowedContentTypes = types
        savePanel.canCreateDirectories = true
        savePanel.canSelectHiddenExtension = true
        savePanel.isExtensionHidden = false

        let response = savePanel.runModal()

        guard let url = response == .OK ? savePanel.url : nil else {
            shown.wrappedValue = false
            return
        }

        save(url)
        shown.wrappedValue = false
    }
}

#endif

#if os(iOS) || os(visionOS)

struct BrowserPicker: UIViewControllerRepresentable {
    @Binding var shown: Bool
    let pickerType: FileBrowserPickerType
    let fileName: String
    var types = [UTType.pdf]
    let handler: (URL?) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker: UIDocumentPickerViewController
        switch pickerType {
        case .open:
            picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        case .save:
            picker = UIDocumentPickerViewController(forExporting: types.compactMap { $0.referenceURL })
        case .saveDir:
            picker = UIDocumentPickerViewController(forExporting: types.compactMap { $0.referenceURL })
        }

        let url = URL(string: fileName)?.deletingLastPathComponent()
        _ = url?.startAccessingSecurityScopedResource()
        defer { url?.stopAccessingSecurityScopedResource() }
        
        picker.directoryURL = url
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.modalPresentationStyle = .automatic
        return picker
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, shown: $shown, handler: handler)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIDocumentPickerDelegate {
        let parent: BrowserPicker
        let shown: Binding<Bool>
        let handler: (URL?) -> Void

        init(parent: BrowserPicker, shown: Binding<Bool>, handler: @escaping (URL?) -> Void) {
            self.parent = parent
            self.handler = handler
            self.shown = shown
        }

        func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
            parent.dismiss()
            shown.wrappedValue = false
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            handler(urls.first)
            parent.dismiss()
            shown.wrappedValue = false
        }
    }
}

#endif
