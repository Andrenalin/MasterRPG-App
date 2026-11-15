// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class EditIdentifierModel<Value: Equatable> {
    /// A binding-backed model reads and writes the binding itself, and an editor that is given one
    /// is created again on every pass of its parent. A fresh `valueId` each time told the editor
    /// the edited value had changed and reset what the user was typing, so the id is a constant.
    /// See CODE_AUDIT_26 §8.15.
    private static var bindingValueId: UUID {
        UUID(uuidString: "6D0B1F6E-0A5C-4C3B-9D55-2F4E7A1B8C90") ?? UUID()
    }

    public init(value: Binding<Value>) {
        self.valueId = Self.bindingValueId
        self._value = value.wrappedValue
        self.bindingValue = value
    }

    public init(valueId: UUID = UUID(), value: Value, save: ((UUID, Value) -> Void)? = nil) {
        self.valueId = valueId
        self._value = value
        self._save = save
    }

    private var bindingValue: Binding<Value>?
    private var _value: Value
    private var _save: ((UUID, Value) -> Void)?

    public private(set) var valueId: UUID
    public var value: Value {
        get {
            if let bindingValue {
                return bindingValue.wrappedValue
            } else {
                return _value
            }
        }
        set {
            if let bindingValue {
                bindingValue.wrappedValue <=> newValue
            } else {
                _value <=> newValue
            }
        }
    }

    public func reset(valueId: UUID, value: Value, saveHandler: ((UUID, Value) -> Void)?) {
        self.valueId = valueId
        self.value = value
        self._save = saveHandler
    }

    public func save() {
        _save?(valueId, value)
    }
}

public struct TextDoubleEditor: View {
    public init(model: EditIdentifierModel<Double>, title: LocalizedStringKey, icon: String, prompt: LocalizedStringKey, bundle: Bundle?, range: ClosedRange<Double>) {
        self.model = model
        self.title = title
        self.icon = icon
        self.prompt = prompt
        self.bundle = bundle
        self.range = range
    }

    let model: EditIdentifierModel<Double>
    let title: LocalizedStringKey
    let icon: String
    let prompt: LocalizedStringKey
    let bundle: Bundle?
    let range: ClosedRange<Double>

    @FocusState private var focusState: Bool
    @State private var text: String = ""
    /// A slider drag changes the value on every tick; it is saved once when the drag ends.
    /// See CODE_AUDIT_26 §7.45.
    @State private var isSliding = false

    public var body: some View {
        LabeledContent {
            TextDoubleEditorTextField(
                model: model,
                title: title,
                prompt: prompt,
                bundle: bundle,
                range: range,
                text: $text,
                focusState: $focusState
            )
        } label: {
            Label { Text(title, bundle: bundle) } icon: { Image(systemName: icon).imageScale(.large) }
        }
        .onChange(of: focusState, initial: false) {
            guard focusState == false else { return }
            model.save()
        }
        .onChange(of: model.valueId, initial: true) {
            text = Self.format(number: model.value)
        }
        .onChange(of: model.value) {
            text = Self.format(number: model.value)
            if !isSliding { model.save() }
        }

        LabeledContent {
            TextDoubleEditorSlider(model: model, title: title, bundle: bundle, range: range, isSliding: $isSliding)
        } label: {
#if os(macOS)
            Text(title, bundle: bundle)
#endif
        }
    }

    static func format(number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(1)))
    }
}

/// Extracted from a `TextDoubleEditor` computed property: a dedicated `View` struct so typing
/// in the text field doesn't re-evaluate the slider section's body (and vice versa) — computed
/// properties share the parent's invalidation boundary, dedicated `View` structs don't.
/// See CODE_AUDIT_9 §8.1.
private struct TextDoubleEditorTextField: View {
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
        .numericInput($text, includeDecimal: true)
        .labelsHidden()
        .submitLabel(.next)
        .focused(focusState)
        .onSubmit {
            // `wholeMatch(of:)` requires the entire string to match, unlike
            // `Double(_:format:)`'s prefix-matching parse — see Calculator.swift's
            // fix for the same issue.
            if let value = text.wholeMatch(of: FloatingPointFormatStyle<Double>(locale: Locale.current))?.output,
               let clamped = EditorValueClamp.clamped(value, to: range) {
                model.value <=> clamped
            }
            model.save()
        }
    }
}

private struct TextDoubleEditorSlider: View {
    @Bindable var model: EditIdentifierModel<Double>
    let title: LocalizedStringKey
    let bundle: Bundle?
    let range: ClosedRange<Double>
    @Binding var isSliding: Bool

    var body: some View {
#if !os(tvOS)
        Slider(
            value: $model.value,
            in: range,
            step: 1,
            label: { Text(title, bundle: bundle) },
            minimumValueLabel: { Text(Int(range.lowerBound), format: .number) },
            maximumValueLabel: { Text(Int(range.upperBound), format: .number) },
            onEditingChanged: { isEditing in
                isSliding = isEditing
                if !isEditing { model.save() }
            }
        )
        .labelsHidden()
#else
        EmptyView()
#endif
    }
}

#Preview {
    let title = LocalizedStringKey(String("Scale"))
    TextDoubleEditor(
        model: EditIdentifierModel(value: 2.5),
        title: title,
        icon: "slider.horizontal.3",
        prompt: title,
        bundle: nil,
        range: 0...5
    )
    .padding()
}
