// @copyright André Trettin

import SwiftUI

public struct TextIntEditor: View {
    public init(value: Binding<Double>, title: LocalizedStringKey, icon: String, prompt: LocalizedStringKey, bundle: Bundle?, range: ClosedRange<Int>) {
        self.model = EditIdentifierModel(value: value)
        self.title = title
        self.icon = icon
        self.prompt = prompt
        self.bundle = bundle
        let uppperBound = range.upperBound <= range.lowerBound ? range.lowerBound + 1 : range.upperBound
        self.range = ClosedRange(uncheckedBounds: (Double(range.lowerBound), Double(uppperBound)))
    }

    public init(model: EditIdentifierModel<Double>, title: LocalizedStringKey, icon: String, prompt: LocalizedStringKey, bundle: Bundle?, range: ClosedRange<Int>) {
        self.model = model
        self.title = title
        self.icon = icon
        self.prompt = prompt
        self.bundle = bundle
        let uppperBound = range.upperBound <= range.lowerBound ? range.lowerBound + 1 : range.upperBound
        self.range = ClosedRange(uncheckedBounds: (Double(range.lowerBound), Double(uppperBound)))
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
            textInputView
                .frame(maxWidth: 64, alignment: .leading)
            
            sliderView
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

private extension TextIntEditor{
    var textInputView: some View {
        TextField(text: $text, prompt: Text(prompt, bundle: bundle)) {
            Text(title, bundle: bundle)
        }
#if os(iOS) || os(visionOS)
            .autocapitalization(.none)
            .keyboardType(.numbersAndPunctuation)
#endif
            .disableAutocorrection(true)
            .numericInput($text, includeDecimal: false)
            .labelsHidden()
            .submitLabel(.next)
            .focused($focusState)
            .onSubmit {
                if let value = Int(text) {
                    model.value <=> Double(value)
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
}
