// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct DisplayConfigEditor: View {
    let model: MapModel
    
    @Environment(MapRootModel.self) private var root
    
    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager

    @State private var color = Color.black
    @State private var borderToggleEditModel: EditIdentifierModel<Bool> = EditIdentifierModel(value: false)
    @State private var showTileEditor = false
    @State private var tileImage: AKImage?
    
    var body: some View {
        Section {
#if !os(tvOS)
            coverColorView
            
            tileCoordinatesView
            
            activateBorderView
            
            DisplayConfigBorderEditor(model: model)
                .opacity(model.displayConfig.hasBorder ? 1 : 0)
                .frame(maxHeight: model.displayConfig.hasBorder ? .infinity : 1)
#endif
        } header: {
            Text("Config", bundle: .module)
        }
        .animation(.default, value: model.displayConfig.hasBorder)
        .onChange(of: model.id, initial: true) {
#if !os(tvOS)
            resetColor()
            updateToggleValue()
            loadTileImage()
#endif
        }
        .onChange(of: model.displayConfig.tileCoordinates) {
            loadTileImage()
        }
    }
    
#if !os(tvOS)
    @ViewBuilder private var coverColorView: some View {
        LabeledContent {
            ColorPicker(selection: $color, supportsOpacity: false) {
                Text("Cover color", bundle: .module)
            }
            .labelsHidden()
            .tint(root.configurable.module.tint)
        } label: {
            Text("Cover color", bundle: .module)
        }
        .onChange(of: color) {
            saveColor()
        }
        .onChange(of: model.displayConfig.color) {
            resetColor()
        }
    }    
#endif

    private func resetColor() {
        guard color != model.displayConfig.color else { return }
        color <=> model.displayConfig.color
    }

    private func saveColor() {
        root.editController.reset(coverColor: color, itemId: model.id)
    }

    @ViewBuilder private var activateBorderView: some View {
        ToggleEditor(model: borderToggleEditModel, title: "Activate Border", bundle: .module, icon: "rectangle")
            .onChange(of: model.displayConfig.hasBorder) {
                withAnimation { updateToggleValue() }
            }
    }
    
    private func updateToggleValue() {
        let toggleValue = model.displayConfig.hasBorder
        if model.id != borderToggleEditModel.valueId || toggleValue != borderToggleEditModel.value {
            let editController = root.editController
            borderToggleEditModel.reset(valueId: model.id, value: toggleValue) { itemId, value in
                editController.reset(hasBorder: value, itemId: itemId)
            }
        }
    }
    
    // MARK: - Tile Coordinates
    
    @ViewBuilder private var tileCoordinatesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tile Cover", bundle: .module)
                Spacer()
                Button {
#if os(visionOS) || os(macOS)
            root.editController.sheetEditorModel.itemId = model.id
            scenesManager.openWindow(.mapEditor)
#else
            navigator.navigate(to: MapEditorRoute.mapEditor(model.id))
#endif
                } label: {
                    Label("Edit Tile", systemImage: "rectangle.dashed")
                }
                .buttonStyle(.borderless)
                .tint(root.configurable.module.tint)
                
                if !model.displayConfig.tileCoordinates.isEmpty {
                    Button(role: .destructive) {
                        clearTileCoordinates()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            if let tileImage {
                Image(akImage: tileImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 120, maxHeight: 80)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            } else if !model.displayConfig.tileCoordinates.isEmpty {
                Text("Tile configured", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
        
    private func clearTileCoordinates() {
        root.editController.reset(tileCoordinates: [], itemId: model.id)
        tileImage = nil
    }
    
    private func saveTileCoordinates(_ coordinates: [CGPoint]) {
        root.editController.reset(tileCoordinates: coordinates, itemId: model.id)
    }
    
    private func loadTileImage() {
        guard !model.displayConfig.tileCoordinates.isEmpty,
              model.displayConfig.tileCoordinates.count == 4,
              let photoId = model.photoId else {
            tileImage = nil
            return
        }
        
        Task {
            if let (fullImage, _) = await root.photoRoot.fetchPhotoImage(for: photoId, useGame: true) {
                let coords = model.displayConfig.tileCoordinates
                let minX = coords.map { $0.x }.min() ?? 0
                let maxX = coords.map { $0.x }.max() ?? 0
                let minY = coords.map { $0.y }.min() ?? 0
                let maxY = coords.map { $0.y }.max() ?? 0
                
                let tileRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                
                #if os(macOS)
                if let cgImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                   let croppedCGImage = cgImage.cropping(to: tileRect) {
                    tileImage = NSImage(cgImage: croppedCGImage, size: tileRect.size)
                }
                #else
                if let cgImage = fullImage.cgImage?.cropping(to: tileRect) {
                    tileImage = UIImage(cgImage: cgImage)
                }
                #endif
            }
        }
    }
}
