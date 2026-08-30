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
            WeatherLightningFrequencyEditor(model: model, editModel: lightningFrequency)
            WeatherLightningMaxBoltsEditor(model: model, editModel: lightningMaxBolts)
            WeatherLightningForkEditor(model: model, editModel: lightningForkProbability)
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

/// Extracted from `WeatherThunderEditor` computed properties: dedicated `View` structs so
/// dragging one slider doesn't re-evaluate every sibling section's body — computed properties
/// share the parent's invalidation boundary, dedicated `View` structs don't. See CODE_AUDIT_9 §8.1.
private struct WeatherLightningFrequencyEditor: View {
    let model: WeatherModel
    @Bindable var editModel: EditIdentifierModel<Double>

    var body: some View {
        LabeledContent {
#if os(tvOS)
            Text(model.lightningFrequency, format: .number.precision(.fractionLength(0)))
#else
            Slider(value: $editModel.value, in: 0 ... 100)
                .accessibilityLabel(Text("Frequency", bundle: .module))
                .accessibilityValue(
                    Text(editModel.value, format: .number.precision(.fractionLength(0)))
                )
#endif
        } label: {
            Text("Frequency", bundle: .module)
        }
        .onSignificantChange(of: editModel.value) {
            editModel.save()
        }
    }
}

private struct WeatherLightningMaxBoltsEditor: View {
    let model: WeatherModel
    @Bindable var editModel: EditIdentifierModel<Double>

    var body: some View {
        LabeledContent {
#if os(tvOS)
            Text(model.lightningMaxBolts, format: .number.precision(.fractionLength(0)))
#else
            Slider(value: $editModel.value, in: 0 ... 10)
                .accessibilityLabel(Text("Max Bolts", bundle: .module))
                .accessibilityValue(
                    Text(editModel.value, format: .number.precision(.fractionLength(0)))
                )
#endif
        } label: {
            Text("Max Bolts", bundle: .module)
        }
        .onSignificantChange(of: editModel.value) {
            editModel.save()
        }
    }
}

private struct WeatherLightningForkEditor: View {
    let model: WeatherModel
    @Bindable var editModel: EditIdentifierModel<Double>

    var body: some View {
        LabeledContent {
#if os(tvOS)
            Text(model.lightningForkProbability, format: .number.precision(.fractionLength(0)))
#else
            Slider(value: $editModel.value, in: 0 ... 100)
                .accessibilityLabel(Text("Fork %", bundle: .module))
                .accessibilityValue(
                    Text(editModel.value / 100, format: .percent.precision(.fractionLength(0)))
                )
#endif
        } label: {
            Text("Fork %", bundle: .module)
        }
        .onSignificantChange(of: editModel.value) {
            editModel.save()
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
