// @copyright André Trettin

import CoreRPG
import SwiftUI

struct WeatherEditor: View {
    let model: WeatherModel

    @Environment(WeatherRootModel.self) private var root
        
    @State private var cloudEditModel: EditIdentifierModel<Cloud.Thickness> = EditIdentifierModel(value: .none)
    @State private var stormEditModel: EditIdentifierModel<Storm.Contents> = EditIdentifierModel(value: .none)
    @State private var directionEditModel: EditIdentifierModel<Bool> = EditIdentifierModel(value: false)
    
    var body: some View {
        Section {
            root.viewController.photoSelection(root: root, selectionModel: root.editController.weatherEditModel.selectionPhoto)
                .onChange(of: root.editController.weatherEditModel.selectionPhoto.selection) {
                    withAnimation { root.editController.add(photoId: root.editController.weatherEditModel.selectionPhoto.itemId, itemId: model.id) }
                }
                .onChange(of: model.photoId, initial: true) {
                    withAnimation { root.editController.weatherEditModel.selectionPhoto.resetSelection(itemId: model.photoId, entryId: nil) }
                }
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Photo", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onChange(of: model.id, initial: true) {
            let editController = root.editController
            cloudEditModel.reset(valueId: model.id, value: model.cloudThickness) { itemId, value in
                editController.reset(cloudThickness: value, itemId: itemId)
            }
            stormEditModel.reset(valueId: model.id, value: model.stormType) { itemId, value in
                editController.reset(stormType: value, itemId: itemId)
            }
        }
        Section {
            timeEditorView
            
            cloudsEditorView
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Weather", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        
        Section {
            precipitationEditorView
            rainIntensityEditorView
            rainAngleEditorView
            rainDirectionEditorView
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Storm", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        
        Section {
            lightningFrequencyEditorView
            lightningMaxBoltsEditorView
            lightningForkEditorView
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Thunder", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private extension WeatherEditor {
    @ViewBuilder var timeEditorView: some View {
        @Bindable var model = model

        LabeledContent {
#if os(tvOS)
            Text(formattedTime)
#else
            HStack {
                Slider(value: $model.time)
                Text(formattedTime)
            }
#endif
        } label: {
            Text("Time", bundle: .module)
        }
    }

    @ViewBuilder
    var timeDisplayView: some View {
        LabeledContent {
            Text(formattedTime)
        } label: {
            Text("Time", bundle: .module)
        }
    }

    @ViewBuilder var cloudsEditorView: some View {
        ValuePickerEditor(model: cloudEditModel, allCategories: Cloud.Thickness.allCases, title: "Clouds", bundle: .module) { thickness in
            Text(thickness.localizedTitle, bundle: .module)
        }
    }

    @ViewBuilder var precipitationEditorView: some View {
        ValuePickerEditor(model: stormEditModel, allCategories: Storm.Contents.allCases, title: "Precipitation", bundle: .module) { stormType in
            Text(stormType.localizedTitle, bundle: .module)
        }
    }

    @ViewBuilder
    var rainIntensityEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
#if os(tvOS)
            Text("\(model.rainIntensity)")
#else
            Slider(value: $model.rainIntensity, in: 0 ... 1000)
#endif
        } label: {
            Text("Intensity", bundle: .module)
        }
    }

    @ViewBuilder
    var rainAngleEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
#if os(tvOS)
            Text("\(model.rainAngle)")
#else
            Slider(value: $model.rainAngle, in: -90 ... 90)
#endif
        } label: {
            Text("Angle", bundle: .module)
        }
    }

    @ViewBuilder var rainDirectionEditorView: some View {
        ToggleEditor(model: directionEditModel, title: "Direction", bundle: .module, icon: model.rainDirection ? "chevron.right" : "chevron.left")
            .onChange(of: model, initial: true) {
                updateToggleValue()
            }
            .onChange(of: model.rainDirection) {
                updateToggleValue()
            }
    }
    
    func updateToggleValue() {
        let toggleValue = model.rainDirection
        guard model.id != directionEditModel.valueId || toggleValue != directionEditModel.value else { return }
        let editController = root.editController
        directionEditModel.reset(valueId: model.id, value: toggleValue) { itemId, value in
            guard let item = editController.editModel(for: itemId) else { return }
            if value != item.rainDirection {
                item.rainDirection = value
                editController.save(updated: item, message: String(localized: "toggle rain direction", bundle: .module).localizedString)
            }
        }
    }

    @ViewBuilder
    var lightningFrequencyEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
#if os(tvOS)
            Text("\(model.lightningFrequency)")
#else
            Slider(value: $model.lightningFrequency, in: 0 ... 100)
#endif
        } label: {
            Text("Frequency", bundle: .module)
        }
    }

    @ViewBuilder
    var lightningMaxBoltsEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
#if os(tvOS)
            Text("\(model.lightningMaxBolts)")
#else
            Slider(value: $model.lightningMaxBolts, in: 0 ... 10)
#endif
        } label: {
            Text("Max Bolts", bundle: .module)
        }
    }

    @ViewBuilder
    var lightningForkEditorView: some View {
        @Bindable var model = model
        
        LabeledContent {
#if os(tvOS)
            Text("\(model.lightningForkProbability)")
#else
            Slider(value: $model.lightningForkProbability, in: 0 ... 100)
#endif
        } label: {
            Text("Fork %", bundle: .module)
        }
    }

    private var formattedTime: String {
        let start = Calendar.current.startOfDay(for: Date.now)
        let advanced = start.addingTimeInterval(model.time * 24 * 60 * 60)
        return advanced.formatted(date: .omitted, time: .shortened)
    }
}

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root

    WeatherEditor(model: root.itemController.itemOrEmpty(for: MockData.previewId))
}
