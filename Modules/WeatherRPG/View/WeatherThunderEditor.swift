// @copyright André Trettin

import CoreRPG
import SwiftUI

struct WeatherThunderEditor: View {
    let model: WeatherModel

    @Environment(WeatherRootModel.self) private var root

    @State private var lightningFrequency: EditIdentifierModel<Double> = EditIdentifierModel(value: 0.0)
    @State private var lightningMaxBolts: EditIdentifierModel<Double> = EditIdentifierModel(value: 0.0)
    @State private var lightningForkProbability: EditIdentifierModel<Double> = EditIdentifierModel(value: 0.0)

    var body: some View {
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
        .onChange(of: model.id, initial: true) {
            syncLightningModels()
        }
        .onChange(of: model.lightningFrequency) {
            syncFrequencyModel()
        }
        .onChange(of: model.lightningMaxBolts) {
            syncMaxBoltsModel()
        }
        .onChange(of: model.lightningForkProbability) {
            syncForkModel()
        }
    }

    private func syncLightningModels() {
        syncFrequencyModel()
        syncMaxBoltsModel()
        syncForkModel()
    }

    private func syncFrequencyModel() {
        let editController = root.editController
        lightningFrequency.reset(valueId: model.id, value: model.lightningFrequency) { itemId, value in
            editController.reset(lightningFrequency: value, itemId: itemId)
        }
    }

    private func syncMaxBoltsModel() {
        let editController = root.editController
        lightningMaxBolts.reset(valueId: model.id, value: model.lightningMaxBolts) { itemId, value in
            editController.reset(lightningMaxBolts: value, itemId: itemId)
        }
    }

    private func syncForkModel() {
        let editController = root.editController
        lightningForkProbability.reset(valueId: model.id, value: model.lightningForkProbability) { itemId, value in
            editController.reset(lightningForkProbability: value, itemId: itemId)
        }
    }
}

private extension WeatherThunderEditor {
    @ViewBuilder var lightningFrequencyEditorView: some View {
        LabeledContent {
#if os(tvOS)
            Text("\(model.lightningFrequency)")
#else
            Slider(value: $lightningFrequency.value, in: 0 ... 100)
#endif
        } label: {
            Text("Frequency", bundle: .module)
        }
        .onChange(of: lightningFrequency.value) { oldValue, newValue in
            if abs(oldValue - newValue) >= 1 {
                lightningFrequency.save()
            }
        }
    }

    @ViewBuilder var lightningMaxBoltsEditorView: some View {
        LabeledContent {
#if os(tvOS)
            Text("\(model.lightningMaxBolts)")
#else
            Slider(value: $lightningMaxBolts.value, in: 0 ... 10)
#endif
        } label: {
            Text("Max Bolts", bundle: .module)
        }
        .onChange(of: lightningMaxBolts.value) { oldValue, newValue in
            if abs(oldValue - newValue) >= 1 {
                lightningMaxBolts.save()
            }
        }
    }

    @ViewBuilder var lightningForkEditorView: some View {
        LabeledContent {
#if os(tvOS)
            Text("\(model.lightningForkProbability)")
#else
            Slider(value: $lightningForkProbability.value, in: 0 ... 100)
#endif
        } label: {
            Text("Fork %", bundle: .module)
        }
        .onChange(of: lightningForkProbability.value) { oldValue, newValue in
            if abs(oldValue - newValue) >= 1 {
                lightningForkProbability.save()
            }
        }
    }
}
