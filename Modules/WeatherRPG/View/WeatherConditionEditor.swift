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

    var body: some View {
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
        .onChange(of: model.id, initial: true) {
            syncCloudModel()
        }
        .onChange(of: model.cloudThickness) {
            syncCloudModel()
        }
    }

    private func syncCloudModel() {
        let editController = root.editController
        cloudEditModel.reset(valueId: model.id, value: model.cloudThickness) { itemId, value in
            editController.reset(cloudThickness: value, itemId: itemId)
        }
    }
}

private extension WeatherConditionEditor {
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

    @ViewBuilder var cloudsEditorView: some View {
        ValuePickerEditor(model: cloudEditModel, allCategories: Cloud.Thickness.allCases, title: "Clouds", bundle: .module) { thickness in
            Text(thickness.localizedTitle, bundle: .module)
        }
    }

    var formattedTime: String {
        let start = Calendar.current.startOfDay(for: Date.now)
        let advanced = start.addingTimeInterval(model.time * 24 * 60 * 60)
        return advanced.formatted(date: .omitted, time: .shortened)
    }
}
