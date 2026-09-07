// @copyright André Trettin

import CoreRPG
import PhotoRPG
import SwiftUI

struct DisplayConfigEditor: View {
    let model: MapModel
    
    @Environment(MapRootModel.self) private var root
    
    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var color = Color.black
    @State private var borderToggleEditModel: EditIdentifierModel<Bool> = EditIdentifierModel(value: false)
    @State private var tileImage: AKImage?
    
    var body: some View {
        Section {
#if !os(tvOS)
            CoverColorView(model: model, color: $color, saveAction: saveColor, resetAction: resetColor)

            TileCoordinatesView(model: model, tileImage: tileImage, clearTileCoordinatesAction: clearTileCoordinates)

            ActivateBorderView(model: model, borderToggleEditModel: borderToggleEditModel, updateToggleValueAction: updateToggleValue)

            DisplayConfigBorderEditor(model: model)
                .opacity(model.displayConfig.hasBorder ? 1 : 0)
                .frame(maxHeight: model.displayConfig.hasBorder ? .infinity : 1)
                .allowsHitTesting(model.displayConfig.hasBorder)
                .accessibilityHidden(!model.displayConfig.hasBorder)
#endif
        } header: {
            Text("Config", bundle: .module)
        }
        .animation(reduceMotion ? nil : .default, value: model.displayConfig.hasBorder)
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
    
    private func resetColor() {
        guard color != model.displayConfig.color else { return }
        color <=> model.displayConfig.color
    }
    
    private func saveColor() {
        root.editController.reset(coverColor: color, itemId: model.id)
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

    private func clearTileCoordinates() {
        root.editController.reset(tileCoordinates: [], itemId: model.id)
        tileImage = nil
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

#if !os(tvOS)
private struct CoverColorView: View {
    let model: MapModel
    @Binding var color: Color
    let saveAction: () -> Void
    let resetAction: () -> Void

    @Environment(MapRootModel.self) private var root

    var body: some View {
        LabeledContent {
            ColorPicker(selection: $color, supportsOpacity: false) {
                Text("Cover color", bundle: .module)
            }
            .labelsHidden()
            .moduleTint(root.configurable.module)
        } label: {
            Text("Cover color", bundle: .module)
        }
        .onChange(of: color) {
            saveAction()
        }
        .onChange(of: model.displayConfig.color) {
            resetAction()
        }
    }
}
#endif

private struct ActivateBorderView: View {
    let model: MapModel
    let borderToggleEditModel: EditIdentifierModel<Bool>
    let updateToggleValueAction: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ToggleEditor(model: borderToggleEditModel, title: "Activate Border", bundle: .module, icon: "rectangle")
            .onChange(of: model.displayConfig.hasBorder) {
                withAnimation(reduceMotion ? nil : .default) { updateToggleValueAction() }
            }
    }
}

private struct TileCoordinatesView: View {
    let model: MapModel
    let tileImage: AKImage?
    let clearTileCoordinatesAction: () -> Void

    @Environment(MapRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                if let tileImage {
                    Image(akImage: tileImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 120, maxHeight: 80)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel(Text("Cover tile", bundle: .module))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .overlay(alignment: .topTrailing) {
                            Button(role: .destructive) {
                                withAnimation(reduceMotion ? nil : .default) {
                                    clearTileCoordinatesAction()
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .imageScale(.large)
                                    .foregroundStyle(.white, .red, .red)
                            }
                            .accessibilityLabel(Text("Remove Tile", bundle: .module))
                            .frame(minWidth: 44, minHeight: 44)
                            .borderLessTVBottonStyle()
                            .padding(4)
                            .contentShape(.circle)
#if !os(visionOS)
                            .glassEffect(.regular.interactive())
#endif
                            .opacity(model.displayConfig.tileCoordinates.isEmpty ? 0.0 : 1.0)
                            .allowsHitTesting(!model.displayConfig.tileCoordinates.isEmpty)
                            .accessibilityHidden(model.displayConfig.tileCoordinates.isEmpty)
                        }
                }
                Spacer()

                Button {
#if os(visionOS) || os(macOS)
                    root.editController.editorModel.sheetEditorModel.itemId = model.id
                    scenesManager.openWindow(.mapTileEditor)
#else
                    navigator.navigate(to: MapEditorRoute.mapTileEditor(model.id))
#endif
                } label: {
                    Label {
                        Text("Edit cover tile", bundle: .module)
                    } icon: {
                        Image(systemName: "rectangle.dashed")
                    }
                }
                .buttonStyle(.borderless)
                .moduleTint(root.configurable.module)

            } label: {
                Text("Cover tile", bundle: .module)
            }
        }
    }
}

#Preview(traits: .mockData) { DisplayConfigEditor(model: .preview).environment(ScenesManager()) }
