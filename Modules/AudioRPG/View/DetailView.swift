// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DetailView: View {
    let model: AudioDataModel
    
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Environment(AudioRootModel.self) private var root
    
    @State private var selection = GroupItemSelectionModel()
    @State private var isEditing = false
    
    var body: some View {
        ZStack(alignment: .top) {
            initialFileImporterView
            
            contentView
                .padding()
        }
        .animation(.bouncy, value: model.url)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.id) {
            withAnimation {
                selection.selectedItem = nil
                isEditing = false
            }
        }
        .onChange(of: model.fileUrl) { oldValue, newValue in
            guard oldValue == nil else { return }
            withAnimation { isEditing = true }
        }
#if !os(tvOS)
        .onDrop(of: [.fileURL], delegate: FileDropDelegate(for: FileController.fileTypes, updateFile: updateFile))
#endif
        .sheet(isPresented: $isEditing) {
            DetailEditorView(model: model) {
                withAnimation { isEditing = false }
            }
            .padding()
            .presentationContentInteraction(.resizes)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.url != nil {
                    FileImporterView(model: model, prominent: false)
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                if model.url != nil {
                    Button {
                        withAnimation { isEditing = true }
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .toolbarRole(.editor)
    }

    @ViewBuilder
    var initialFileImporterView: some View {
        ZStack {
            Color.clear

            FileImporterView(model: model, prominent: true)
        }
        .opacity(model.fileUrl == nil ? 1 : 0)
        .transition(.scale)
    }

    @ViewBuilder
    var contentView: some View {
        VStack(spacing: 0) {
            DetailOverlayView(itemId: model.id, model: model, nameKeyPath: \.name, categoryKeyPath: \.category, tagsKeyPath: \.tags, descriptionKeyPath: \.information)
            
        }
        .opacity(model.fileUrl != nil ? 1 : 0)
        .transition(.scale)
    }

    private func updateFile(url: URL) {
        root.editController.resetFile(url: url, in: model)
    }
    
    @ViewBuilder
    private var detailEditorView: some View {
        DetailEditorView(model: model) {
            withAnimation {  }
        }
        .id(model.id)
        .background {
            RoundedRectangle(cornerRadius: 24).fill(.thickMaterial)
        }
        .frame(minWidth: 320, alignment: .center)
        .padding(.horizontal, editorMargin)
        .transition(.scale)
    }
    
    private var editorMargin: CGFloat {
#if os(iOS)
        if horizontalSizeClass == .compact {
            0
        } else {
            40
        }
#else
        40
#endif
    }
}

#Preview(traits: .mockData) {
    @Previewable @Query var models: [AudioDataModel]
    @Previewable @Environment(\.modelContext) var modelContext
    
    DetailView(model: models[0])
        .environment(CacheItemListModel())
}
