// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root
    WeatherConditionEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}

struct WeatherConditionEditor: View {
    let model: WeatherModel

    @Environment(WeatherRootModel.self) private var root

    @State private var cloudEditModel: EditIdentifierModel<Cloud.Thickness> = EditIdentifierModel(value: .none)
    @State private var timeEditModel: EditIdentifierModel<Double> = EditIdentifierModel(value: 0)

    var body: some View {
        Section {
            WeatherTimeEditor(editModel: timeEditModel)
            WeatherCloudsEditor(model: cloudEditModel)
        } header: {
            WeatherSectionHeader(titleKey: "Weather", bundle: .module)
        }
        .onChange(of: model.id, initial: true) {
            syncCloudModel()
            syncTimeModel()
        }
        .onChange(of: model.cloudThickness) {
            syncCloudModel()
        }
        .onChange(of: model.time) {
            syncTimeModel()
        }
    }

    private func syncTimeModel() {
        let editController = root.editController
        timeEditModel.reset(valueId: model.id, value: model.time) { itemId, value in
            editController.reset(time: value, itemId: itemId, forceSave: true)
        }
    }

    private func syncCloudModel() {
        let editController = root.editController
        cloudEditModel.reset(valueId: model.id, value: model.cloudThickness) { itemId, value in
            editController.reset(cloudThickness: value, itemId: itemId, forceSave: true)
        }
    }
}

/// Extracted from `WeatherConditionEditor` computed properties: dedicated `View` structs so
/// dragging the time slider doesn't re-evaluate the clouds picker's body (and vice versa) —
/// computed properties share the parent's invalidation boundary, dedicated `View` structs
/// don't. See CODE_AUDIT_9 §8.1.
private struct WeatherTimeEditor: View {
    @Bindable var editModel: EditIdentifierModel<Double>

    var body: some View {
        LabeledContent {
#if os(tvOS)
            Text(formattedTime)
#else
            HStack {
                // Edits a draft, saved when the drag ends: the model itself is only written through
                // the edit controller. See CODE_AUDIT_26 §5.7.
                Slider(value: $editModel.value) { isEditing in
                    if !isEditing { editModel.save() }
                }
                    .accessibilityLabel(Text("Time", bundle: .module))
                    .accessibilityValue(Text(verbatim: formattedTime))
                Text(formattedTime)
            }
#endif
        } label: {
            Text("Time", bundle: .module)
        }
    }

    private var formattedTime: String {
        let start = Calendar.current.startOfDay(for: Date.now)
        let advanced = start.addingTimeInterval(editModel.value * 24 * 60 * 60)
        return advanced.formatted(date: .omitted, time: .shortened)
    }
}

private struct WeatherCloudsEditor: View {
    let model: EditIdentifierModel<Cloud.Thickness>

    var body: some View {
        ValuePickerEditor(model: model, allCategories: Cloud.Thickness.allCases, title: "Clouds", bundle: .module) { thickness in
            Text(thickness.localizedTitle)
        }
    }
}
