// @copyright André Trettin

import SwiftUI

public struct TextIntEditor: View {
    public init(value: Binding<Double>, title: LocalizedStringKey, icon: String, prompt: LocalizedStringKey, bundle: Bundle?, range: ClosedRange<Int>) {
        self.model = EditIdentifierModel(value: value)
        self.title = title
        self.icon = icon
        self.prompt = prompt
        self.bundle = bundle
        let upperBound = range.upperBound <= range.lowerBound ? range.lowerBound + 1 : range.upperBound
        self.range = ClosedRange(uncheckedBounds: (Double(range.lowerBound), Double(upperBound)))
    }

    public init(model: EditIdentifierModel<Double>, title: LocalizedStringKey, icon: String, prompt: LocalizedStringKey, bundle: Bundle?, range: ClosedRange<Int>) {
        self.model = model
        self.title = title
        self.icon = icon
        self.prompt = prompt
        self.bundle = bundle
        let upperBound = range.upperBound <= range.lowerBound ? range.lowerBound + 1 : range.upperBound
        self.range = ClosedRange(uncheckedBounds: (Double(range.lowerBound), Double(upperBound)))
    }

    let model: EditIdentifierModel<Double>
    let title: LocalizedStringKey
    let icon: String
    let prompt: LocalizedStringKey
    let bundle: Bundle?
    let range: ClosedRange<Double>

    @FocusState private var focusState: Bool
    @State private var text: String = ""

    public var body: some View {
        HStack {
            TextIntEditorTextField(model: model, title: title, prompt: prompt, bundle: bundle, range: range, text: $text, focusState: $focusState)
                .frame(maxWidth: 64, alignment: .leading)

            TextIntEditorSlider(model: model, title: title, bundle: bundle, range: range)
        }
        .onChange(of: focusState, initial: false) {
            guard focusState == false else { return }
            model.save()
        }
        .onChange(of: model.valueId, initial: true) {
            text = model.value.formatted(.number.precision(.fractionLength(0)))
        }
        .onChange(of: model.value) {
            text = model.value.formatted(.number.precision(.fractionLength(0)))
            model.save()
        }
    }
}

/// Extracted from a `TextIntEditor` computed property: a dedicated `View` struct so typing in
/// the text field doesn't re-evaluate the slider section's body (and vice versa) — computed
/// properties share the parent's invalidation boundary, dedicated `View` structs don't.
/// See CODE_AUDIT_9 §8.1.
private struct TextIntEditorTextField: View {
    let model: EditIdentifierModel<Double>
    let title: LocalizedStringKey
    let prompt: LocalizedStringKey
    let bundle: Bundle?
    let range: ClosedRange<Double>
    @Binding var text: String
    var focusState: FocusState<Bool>.Binding

    var body: some View {
        TextField(text: $text, prompt: Text(prompt, bundle: bundle)) {
            Text(title, bundle: bundle)
        }
#if os(iOS) || os(visionOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.numbersAndPunctuation)
#endif
            .autocorrectionDisabled()
            .numericInput($text, includeDecimal: false)
            .labelsHidden()
            .submitLabel(.next)
            .focused(focusState)
            .onSubmit {
                // A typed value stays inside the editor's range, like the slider. See CODE_AUDIT_26 §5.111.
                if let value = Int(text) {
                    model.value <=> min(max(Double(value), range.lowerBound), range.upperBound)
                }
                model.save()
            }
    }
}

private struct TextIntEditorSlider: View {
    @Bindable var model: EditIdentifierModel<Double>
    let title: LocalizedStringKey
    let bundle: Bundle?
    let range: ClosedRange<Double>

    var body: some View {
#if !os(tvOS)
        Slider(
            value: $model.value,
            in: range,
            step: 1,
            minimumValueLabel: Text(Int(range.lowerBound), format: .number),
            maximumValueLabel: Text(Int(range.upperBound), format: .number)
        ) {
            Text(title, bundle: bundle)
        }
        .labelsHidden()
#else
        EmptyView()
#endif
    }
}

#Preview {
    let title = LocalizedStringKey(String("Count"))
    TextIntEditor(
        model: EditIdentifierModel(value: 12.0),
        title: title,
        icon: "number",
        prompt: title,
        bundle: nil,
        range: 0...20
    )
    .padding()
}
