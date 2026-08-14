// @copyright André Trettin

import CoreRPG
import SwiftUI

#Preview(traits: .mockData) {
    @Previewable @Environment(WeatherRootModel.self) var root
    WeatherThunderEditor(model: root.itemController.itemOrEmpty(for: root.itemController.itemDataModel.items[0]))
}

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
            Text(model.lightningFrequency, format: .number.precision(.fractionLength(0)))
#else
            Slider(value: $lightningFrequency.value, in: 0 ... 100)
                .accessibilityLabel(Text("Frequency", bundle: .module))
                .accessibilityValue(
                    Text(lightningFrequency.value, format: .number.precision(.fractionLength(0)))
                )
#endif
        } label: {
            Text("Frequency", bundle: .module)
        }
        .onSignificantChange(of: lightningFrequency.value) {
            lightningFrequency.save()
        }
    }

    @ViewBuilder var lightningMaxBoltsEditorView: some View {
        LabeledContent {
#if os(tvOS)
            Text(model.lightningMaxBolts, format: .number.precision(.fractionLength(0)))
#else
            Slider(value: $lightningMaxBolts.value, in: 0 ... 10)
                .accessibilityLabel(Text("Max Bolts", bundle: .module))
                .accessibilityValue(
                    Text(lightningMaxBolts.value, format: .number.precision(.fractionLength(0)))
                )
#endif
        } label: {
            Text("Max Bolts", bundle: .module)
        }
        .onSignificantChange(of: lightningMaxBolts.value) {
            lightningMaxBolts.save()
        }
    }

    @ViewBuilder var lightningForkEditorView: some View {
        LabeledContent {
#if os(tvOS)
            Text(model.lightningForkProbability, format: .number.precision(.fractionLength(0)))
#else
            Slider(value: $lightningForkProbability.value, in: 0 ... 100)
                .accessibilityLabel(Text("Fork %", bundle: .module))
                .accessibilityValue(
                    Text(lightningForkProbability.value / 100, format: .percent.precision(.fractionLength(0)))
                )
#endif
        } label: {
            Text("Fork %", bundle: .module)
        }
        .onSignificantChange(of: lightningForkProbability.value) {
            lightningForkProbability.save()
        }
    }
}

private struct SignificantChangeModifier: ViewModifier {
    let value: Double
    var threshold: Double = 1
    let onSignificantChange: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: value) { oldValue, newValue in
            guard abs(oldValue - newValue) >= threshold else { return }
            onSignificantChange()
        }
    }
}

private extension View {
    /// Runs `action` when `value` changes by at least `threshold`, collapsing the
    /// repeated "debounce tiny slider jitter, then save" pattern used by this editor's sliders.
    func onSignificantChange(of value: Double, threshold: Double = 1, perform action: @escaping () -> Void) -> some View {
        modifier(SignificantChangeModifier(value: value, threshold: threshold, onSignificantChange: action))
    }
}
