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
        }
    }
}

private extension FileLocationEditor {
    var locationView: some View {
        HStack {
            if let location {
                Text(location.text)
            } else {
                Text("No file choosen", bundle: .module)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var filePathView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                if let fileUrl = fileUrlBinding.wrappedValue {
                    Text("\(fileUrl.rawUrl.relativePath)")
                } else {
                    Text("No file", bundle: .module)
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var fileUrl: FileUrl? = FileUrl(fileId: UUID(), url: URL(string: "Hello File.pdf")!, location: .newCloud, module: "PDFS", relativeUrl: nil)
    FileLocationEditor(editController: FakeEditController.fake, fileStore: FileUrlDataController.empty(), fileUrlBinding: $fileUrl)
}
