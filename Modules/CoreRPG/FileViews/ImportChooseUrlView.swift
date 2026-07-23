// @copyright André Trettin

import SwiftUI

struct ImportChooseUrlView: View {
    @Binding var showImportFileChooser: Bool
    @Binding var loadUrl: URL?
    @Binding var proposedUrl: URL?
    let urlProvider: (any ExampleUrlProvider)?
    let isSaveGame: Bool
    @Bindable var importModel: ItemDataImportModel

    var body: some View {
        VStack(spacing: 20) {
            if let proposedUrl {
                GroupBox {
                    VStack(alignment: .leading) {
                        Label {
                            Text(verbatim: proposedUrl.lastPathComponent)
                                .lineLimit(2)
                        } icon: {
                            Image(systemName: "doc.badge.arrow.up")
                        }

                        Button {
                            loadUrl = proposedUrl
                            self.proposedUrl = nil
                        } label: {
                            Label {
                                Text("Review Import", bundle: .module)
                            } icon: {
                                Image(systemName: "checkmark.shield")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("File Ready to Import", bundle: .module)
                }
            }

            Button {
                showImportFileChooser = true
            } label: {
                Label {
                    Text("Choose file", bundle: .module)
                } icon: {
                    Image(systemName: "doc.text")
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 20)

            if !isSaveGame {
                GroupBoxTV {
                    VStack(spacing: 20) {
                        Button {
                            loadUrl = urlProvider?.urlExampleData(isGerman: false)
                        } label: {
                            Label { Text("English Data", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
                        }
                        .padding(.top, 12)

                        Button {
                            loadUrl = urlProvider?.urlExampleData(isGerman: true)
                        } label: {
                            Label { Text("German Data", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
                        }

                        Text("Explanation data packages to see how the app works. It explain with real data how to use and add data.", bundle: .module)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("Import Prebundled Examples", bundle: .module)
                }
                .padding(.bottom, 20)

                Picker(selection: $importModel.importMode) {
                    Label { Text("Merge", bundle: .module) } icon: { Image(systemName: "arrow.triangle.merge") }
                        .tag(ImportMode.merge)
                    Label { Text("Overwrite", bundle: .module) } icon: { Image(systemName: "exclamationmark.triangle") }
                        .tag(ImportMode.overwrite)
                    Label { Text("Manual", bundle: .module) } icon: { Image(systemName: "list.bullet.clipboard") }
                        .tag(ImportMode.manual)
                } label: {
                    Text("Import Mode", bundle: .module)
                }
                .pickerStyle(.menu)
            }
        }
        .disabled(showImportFileChooser)
    }
}

#Preview {
    @Previewable @State var showImportFileChooser = false
    @Previewable @State var loadUrl: URL?
    @Previewable @State var proposedUrl: URL?
    ImportChooseUrlView(
        showImportFileChooser: $showImportFileChooser,
        loadUrl: $loadUrl,
        proposedUrl: $proposedUrl,
        urlProvider: FakeExampleUrlProvider(),
        isSaveGame: false,
        importModel: ItemDataImportModel()
    )
    .padding()
}
