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

private extension WeatherStormEditor {
    @ViewBuilder var precipitationEditorView: some View {
        ValuePickerEditor(model: stormEditModel, allCategories: Storm.Contents.allCases, title: "Precipitation", bundle: .module) { stormType in
            Text(stormType.localizedTitle, bundle: .module)
        }
    }

    @ViewBuilder var rainIntensityEditorView: some View {
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

    @ViewBuilder var rainAngleEditorView: some View {
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
    }
}
