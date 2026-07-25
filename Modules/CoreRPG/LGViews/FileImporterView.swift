// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public struct FileImporterView: View {
    public init(editControllable: any EditControllable, fileTypes: [UTType], itemId: UUID, isProminent: Bool = true) {
        self.editControllable = editControllable
        self.fileTypes = fileTypes
        self.itemId = itemId
        self.isProminent = isProminent
    }
    
    let editControllable: any EditControllable
    let fileTypes: [UTType]
    let itemId: UUID
    let isProminent: Bool
    
    @State private var showImporter = false
    @State private var showRemoteURLImporter = false
    
    public var body: some View {
#if !os(tvOS)
        if !fileTypes.isEmpty {
            HStack {
                GlassButton(isProminent: isProminent) {
                    showImporter.toggle()
                } label: {
                    Label {
                        Text("Import File", bundle: .module)
                    } icon: {
                        Image(systemName: "folder")
                            .symbolVariant(showImporter ? .fill : .none)
                            .imageScale(isProminent ? .large : .medium)
                            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                    }
                    .labelStyle(.iconOnly)
                }

                GlassButton(isProminent: isProminent) {
                    showRemoteURLImporter.toggle()
                } label: {
                    Label {
                        Text("Import URL", bundle: .module)
                    } icon: {
                        Image(systemName: "link.badge.plus")
                            .symbolVariant(showRemoteURLImporter ? .circle.fill : .none)
                            .imageScale(isProminent ? .large : .medium)
                            .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: fileTypes) { result in
                guard let url = try? result.get() else { return }
                Task {
                    await editControllable.resetFile(url: url, itemId: itemId)
                }
            }
            .remoteFileURLImporter(
                isPresented: $showRemoteURLImporter,
                editControllable: editControllable,
                itemId: itemId
            )
        }
#endif
    }
}

public extension View {
    func remoteFileURLImporter(
        isPresented: Binding<Bool>,
        editControllable: any EditControllable,
        itemId: UUID
    ) -> some View {
        modifier(
            RemoteFileURLImporterModifier(
                isPresented: isPresented,
                editControllable: editControllable,
                itemId: itemId
            )
        )
    }
}

private struct RemoteFileURLImporterModifier: ViewModifier {
    @Binding var isPresented: Bool
    let editControllable: any EditControllable
    let itemId: UUID

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
                        await editControllable.resetFile(
                            url: remoteURL,
                            itemId: itemId
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
              url.isSupportedRemoteFileURL else {
            return nil
        }
        return url
    }
}

#Preview {
    FileImporterView(
        editControllable: FakeEditController.fake,
        fileTypes: [.data],
        itemId: UUID()
    )
    .padding()
}
