// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root
    WeatherStormEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}

struct WeatherStormEditor: View {
    let model: WeatherModel

    @Environment(WeatherRootModel.self) private var root

    @State private var stormEditModel: EditIdentifierModel<Storm.Contents> = EditIdentifierModel(value: .none)
    @State private var directionEditModel: EditIdentifierModel<Bool> = EditIdentifierModel(value: false)
    @State private var intensityEditModel: EditIdentifierModel<Double> = EditIdentifierModel(value: 0)
    @State private var angleEditModel: EditIdentifierModel<Double> = EditIdentifierModel(value: 0)

    var body: some View {
        Section {
            WeatherStormPrecipitationEditor(model: stormEditModel)
            WeatherStormRainIntensityEditor(editModel: intensityEditModel)
            WeatherStormRainAngleEditor(editModel: angleEditModel)
            WeatherStormRainDirectionEditor(
                model: directionEditModel,
                icon: model.rainDirection ? "chevron.right" : "chevron.left"
            )
        } header: {
            WeatherSectionHeader(titleKey: "Storm", bundle: .module)
        }
        .onChange(of: model.id, initial: true) {
            syncStormModel()
            syncDirectionModel()
            syncIntensityModel()
            syncAngleModel()
        }
        .onChange(of: model.rainIntensity) {
            syncIntensityModel()
        }
        .onChange(of: model.rainAngle) {
            syncAngleModel()
        }
        .onChange(of: model.stormType) {
            syncStormModel()
        }
        .onChange(of: model.rainDirection) {
            syncDirectionModel()
        }
    }

    private func syncStormModel() {
        let editController = root.editController
        stormEditModel.reset(valueId: model.id, value: model.stormType) { itemId, value in
            editController.reset(stormType: value, itemId: itemId, forceSave: true)
        }
    }

    private func syncIntensityModel() {
        let editController = root.editController
        intensityEditModel.reset(valueId: model.id, value: model.rainIntensity) { itemId, value in
            editController.reset(rainIntensity: value, itemId: itemId, forceSave: true)
        }
    }

    private func syncAngleModel() {
        let editController = root.editController
        angleEditModel.reset(valueId: model.id, value: model.rainAngle) { itemId, value in
            editController.reset(rainAngle: value, itemId: itemId, forceSave: true)
        }
    }

    private func syncDirectionModel() {
        let toggleValue = model.rainDirection
        guard model.id != directionEditModel.valueId || toggleValue != directionEditModel.value else { return }
        let editController = root.editController
        directionEditModel.reset(valueId: model.id, value: toggleValue) { itemId, value in
            guard let item = editController.editModel(for: itemId) else { return }
            if value != item.rainDirection {
                item.rainDirection = value
                // The weather editor persists also during a game.
                editController.save(updated: item, message: String(localized: "toggle rain direction", bundle: .module), forceSave: true)
            }
        }
    }
}

/// Extracted from `WeatherStormEditor` computed properties: dedicated `View` structs so
/// dragging one slider doesn't re-evaluate every sibling section's body — computed properties
/// share the parent's invalidation boundary, dedicated `View` structs don't. See CODE_AUDIT_9 §8.1.
private struct WeatherStormPrecipitationEditor: View {
    let model: EditIdentifierModel<Storm.Contents>

    var body: some View {
        ValuePickerEditor(model: model, allCategories: Storm.Contents.allCases, title: "Precipitation", bundle: .module) { stormType in
            Text(stormType.localizedTitle)
        }
    }
}

private struct WeatherStormRainIntensityEditor: View {
    @Bindable var editModel: EditIdentifierModel<Double>

    var body: some View {
        LabeledContent {
#if os(tvOS)
            Text(editModel.value, format: .number.precision(.fractionLength(0)))
#else
            Slider(value: $editModel.value, in: 0 ... 1000) { isEditing in
                if !isEditing { editModel.save() }
            }
                .accessibilityLabel(Text("Intensity", bundle: .module))
                .accessibilityValue(
                    Text(editModel.value, format: .number.precision(.fractionLength(0)))
                )
#endif
        } label: {
            Text("Intensity", bundle: .module)
        }
    }
}

private struct WeatherStormRainAngleEditor: View {
    @Bindable var editModel: EditIdentifierModel<Double>

    var body: some View {
        LabeledContent {
#if os(tvOS)
            Text(editModel.value, format: .number.precision(.fractionLength(0)))
#else
            Slider(value: $editModel.value, in: -90 ... 90) { isEditing in
                if !isEditing { editModel.save() }
            }
                .accessibilityLabel(Text("Angle", bundle: .module))
                .accessibilityValue(
                    Text(
                        verbatim: "\(editModel.value.formatted(.number.precision(.fractionLength(0))))°"
                    )
                )
#endif
        } label: {
            Text("Angle", bundle: .module)
        }
    }
}

private struct WeatherStormRainDirectionEditor: View {
    let model: EditIdentifierModel<Bool>
    let icon: String

    var body: some View {
        ToggleEditor(model: model, title: "Direction", bundle: .module, icon: icon)
    }
}
