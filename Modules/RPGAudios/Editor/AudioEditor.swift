// @copyright André Trettin

import AndrenalinKit
import SwiftUI
internal import UniformTypeIdentifiers

struct AudioEditor: View {
    let editController: EditController
    
    @Environment(AudioRoot.self) private var root

    @State private var fileUrl: FileUrl?
    @State private var showImporter = false

    var body: some View {
        VStack {
            HStack {
                Button {
                    showImporter.toggle()
                } label: {
                    Label { Text(fileUrl == nil ? "Add Audio" : "Change Audio", bundle: .module) } icon: { Image(systemName: fileUrl == nil ? "waveform.path.badge.plus" : "music.quarternote.3") }
#if os(tvOS)
                        .opacity(0)
#endif
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
#if !os(tvOS)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio]) { result in
            guard let url = try? result.get() else { return }
            editController.resetAudio(url: url)
        }
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: [.audio], updateFile: updateAudio))
#endif
        .onChange(of: editController.model.fileUrl, initial: true) {
            withAnimation { fileUrl = editController.model.fileUrl }
        }
    }

    private func updateAudio(url: URL) {
        editController.resetAudio(url: url)
    }
}

#Preview {
    AudioEditor(editController: .preview)
        .environment(AudioRoot.preview)
}

