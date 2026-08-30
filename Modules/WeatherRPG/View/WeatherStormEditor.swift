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

    var body: some View {
        Section {
            WeatherStormPrecipitationEditor(model: stormEditModel)
            WeatherStormRainIntensityEditor(model: model)
            WeatherStormRainAngleEditor(model: model)
            WeatherStormRainDirectionEditor(
                model: directionEditModel,
                icon: model.rainDirection ? "chevron.right" : "chevron.left"
            )
        } header: {
#if os(macOS)
            Divider()
                .padding(.top)
#endif
            Text("Storm", bundle: .module)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .onChange(of: model.id, initial: true) {
            syncStormModel()
            syncDirectionModel()
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
            editController.reset(stormType: value, itemId: itemId)
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
                editController.save(updated: item, message: String(localized: "toggle rain direction", bundle: .module).localizedString)
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
    @Bindable var model: WeatherModel

    var body: some View {
        LabeledContent {
#if os(tvOS)
            Text(model.rainIntensity, format: .number.precision(.fractionLength(0)))
#else
            Slider(value: $model.rainIntensity, in: 0 ... 1000)
                .accessibilityLabel(Text("Intensity", bundle: .module))
                .accessibilityValue(
                    Text(model.rainIntensity, format: .number.precision(.fractionLength(0)))
                )
#endif
        } label: {
            Text("Intensity", bundle: .module)
        }
    }
}

private struct WeatherStormRainAngleEditor: View {
    @Bindable var model: WeatherModel

    var body: some View {
        LabeledContent {
#if os(tvOS)
            Text(model.rainAngle, format: .number.precision(.fractionLength(0)))
#else
            Slider(value: $model.rainAngle, in: -90 ... 90)
                .accessibilityLabel(Text("Angle", bundle: .module))
                .accessibilityValue(
                    Text(
                        verbatim: "\(model.rainAngle.formatted(.number.precision(.fractionLength(0))))°"
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
