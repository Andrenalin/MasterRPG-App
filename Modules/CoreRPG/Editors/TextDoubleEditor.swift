// @copyright André Trettin

import SwiftUI

@Observable
public final class EditIdentifierModel<Value: Equatable> {
    public init(value: Binding<Value>) {
        self.valueId = UUID()
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
        //save()
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
    
    public var body: some View {
        LabeledContent {
            textInputView
        } label: {
            Label { Text(title, bundle: bundle) } icon: { Image(systemName: icon).imageScale(.large) }
        }
        .onChange(of: focusState, initial: false) {
            guard focusState == false else { return }
            model.save()
        }
        .onChange(of: model.valueId, initial: true) {
            text = format(number: model.value)
        }
        .onChange(of: model.value) {
            text = format(number: model.value)
            model.save()
        }
        
        LabeledContent {
            sliderView
        } label: {
#if os(macOS)
            Text(title, bundle: bundle)
#endif
        }
    }
}

private extension TextDoubleEditor {
    var textInputView: some View {
        TextField(text: $text, prompt: Text(prompt, bundle: bundle)) {
            Text(title, bundle: bundle)
        }
#if os(iOS) || os(visionOS)
        .autocapitalization(.none)
        .keyboardType(.numbersAndPunctuation)
#endif
        .disableAutocorrection(true)
        .numericInput($text, includeDecimal: true)
        .labelsHidden()
        .submitLabel(.next)
        .focused($focusState)
        .onSubmit {
            let formatter = NumberFormatter()
            formatter.locale = Locale.current
            if let value = formatter.number(from: text)?.doubleValue {
                model.value <=> value
            }
            model.save()
        }
    }

    @ViewBuilder var sliderView: some View {
        @Bindable var model = model
#if !os(tvOS)
        Slider(value: $model.value, in: range, step: 1, minimumValueLabel: Text("\(Int(range.lowerBound))"), maximumValueLabel: Text("\(Int(range.upperBound))")) {
            Text(title, bundle: bundle)
        }
        .labelsHidden()
#else
        EmptyView()
#endif
    }

    func format(number: Double) -> String {
        number.formatted(.number.precision(.fractionLength(1)))
    }
}
