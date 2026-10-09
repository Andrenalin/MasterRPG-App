// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public struct FileImporterView: View {
    public init(editControllable: any EditControllable, fileTypes: [UTType], itemId: UUID, module: NetworkModules) {
        self.editControllable = editControllable
        self.fileTypes = fileTypes
        self.itemId = itemId
        self.module = module
    }

    let editControllable: any EditControllable
    let fileTypes: [UTType]
    let itemId: UUID
    let module: NetworkModules

    @State private var showImporter = false
    @State private var showRemoteUrlImporter = false
    /// A picker failure, shown instead of being dropped: a failed pick looked like nothing
    /// happened. See CODE_AUDIT_Folder §8.6.
    @State private var pickerError: String?
    @State private var replacementConfirmation = FileReplacementConfirmation()

    public var body: some View {
#if !os(tvOS)
        if !fileTypes.isEmpty {
            HStack {
                Button {
                    showImporter.toggle()
                } label: {
                    Label {
                        Text(importFileTitle)
                    } icon: {
                        Image(systemName: "folder")
                            .symbolVariant(showImporter ? .fill : .none)
                            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                    }
                }
                .selectedRoundButton(title: importFileTitle, module: module, isSelected: showImporter)

                Button {
                    showRemoteUrlImporter.toggle()
                } label: {
                    Label {
                        Text(importUrlTitle)
                    } icon: {
                        Image(systemName: "link.badge.plus")
                            .symbolVariant(showRemoteUrlImporter ? .circle.fill : .none)
                            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                    }
                }
                .selectedRoundButton(title: importUrlTitle, module: module, isSelected: showRemoteUrlImporter)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: fileTypes) { result in
                switch result {
                case .success(let url):
                    Task {
                        await replacementConfirmation.resetFile(url: url, itemId: itemId, editControllable: editControllable)
                    }
                case .failure(let error):
                    pickerError = error.localizedDescription
                }
            }
            .alert(
                Text("File Not Imported", bundle: .module),
                isPresented: Binding {
                    pickerError != nil
                } set: { isPresented in
                    if !isPresented { pickerError = nil }
                }
            ) {
                Button(String(localized: "OK", bundle: .module), role: .cancel) {
                    pickerError = nil
                }
            } message: {
                Text(verbatim: pickerError ?? "")
            }
            .remoteFileURLImporter(
                isPresented: $showRemoteUrlImporter,
                editControllable: editControllable,
                itemId: itemId,
                replacementConfirmation: replacementConfirmation
            )
            .fileReplacementAlert(replacementConfirmation)
        }
#endif
    }

    private var importFileTitle: String {
        String(localized: "Import File", bundle: .module)
    }

    private var importUrlTitle: String {
        String(localized: "Import URL", bundle: .module)
    }
}

public extension View {
    /// - Parameter replacementConfirmation: Asks what happens to the file the item already
    ///   has; the caller shows its alert with `fileReplacementAlert(_:)`.
    func remoteFileURLImporter(
        isPresented: Binding<Bool>,
        editControllable: any EditControllable,
        itemId: UUID,
        replacementConfirmation: FileReplacementConfirmation
    ) -> some View {
        modifier(
            RemoteFileURLImporterModifier(
                isPresented: isPresented,
                editControllable: editControllable,
                itemId: itemId,
                replacementConfirmation: replacementConfirmation
            )
        )
    }
}

private struct RemoteFileURLImporterModifier: ViewModifier {
    @Binding var isPresented: Bool
    let editControllable: any EditControllable
    let itemId: UUID
    let replacementConfirmation: FileReplacementConfirmation

    @State private var remoteURLText = ""

    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content
            .alert(
                Text("Import from URL", bundle: .module),
                isPresented: $isPresented
            ) {
                TextField(
                    text: $remoteURLText,
                    prompt: Text(verbatim: "https://example.com/file")
                ) {
                    Text("File URL", bundle: .module)
                }
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
#endif
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) {
                    remoteURLText = ""
                }
                Button(String(localized: "Import", bundle: .module)) {
                    guard let remoteURL else { return }
                    remoteURLText = ""
                    Task {
                        await replacementConfirmation.resetFile(
                            url: remoteURL,
                            itemId: itemId,
                            editControllable: editControllable
                        )
                    }
                }
                .disabled(remoteURL == nil)
            } message: {
                Text(
                    "Enter an HTTP or HTTPS URL. The original URL stays with the item and the file is cached when it is used.",
                    bundle: .module
                )
            }
#endif
    }

    private var remoteURL: URL? {
        let value = remoteURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              url.isSupportedRemoteFileUrl else {
            return nil
        }
        return url
    }
}

#Preview {
    FileImporterView(
        editControllable: FakeEditController.fake,
        fileTypes: [.data],
        itemId: UUID(),
        module: .pdf
    )
    .padding()
}
