// @copyright André Trettin

import SwiftUI

public struct TextDoubleEditor: View {
    public init(editController: any EditControllable, model: Binding<Double>, title: LocalizedStringKey, icon: String, prompt: LocalizedStringKey, bundle: Bundle?, range: ClosedRange<Double>) {
        self.editController = editController
        self.model = model
        self.title = title
        self.icon = icon
        self.prompt = prompt
        self.bundle = bundle
        self.range = range
    }

    let editController: any EditControllable
    let model: Binding<Double>
    let title: LocalizedStringKey
    let icon: String
    let prompt: LocalizedStringKey
    let bundle: Bundle?
    let range: ClosedRange<Double>

    @FocusState private var focusState: Bool

    public var body: some View {
        LabeledContent {
            textInputView
        } label: {
            Label { Text(title, bundle: bundle) } icon: { Image(systemName: icon).imageScale(.large) }
        }
        .onChange(of: focusState, initial: false) {
            guard focusState == false else { return }
            editController.save(with: String(localized: "Typing").localizedString)
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

private extension TextDoubleEditor{
    var textInputView: some View {
        TextField(text: text, prompt: Text(prompt, bundle: bundle)) {
            Text(title, bundle: bundle)
        }
#if os(iOS) || os(visionOS)
        .autocapitalization(.none)
        .keyboardType(.numbersAndPunctuation)
#endif
        .disableAutocorrection(true)
        .numericInput(text, includeDecimal: true)
        .labelsHidden()
        .submitLabel(.next)
        .focused($focusState)
        .onSubmit {
            editController.save(with: String(localized: "Typing").localizedString)
        }
    }

    var sliderView: some View {
#if !os(tvOS)
        Slider(value: model, in: range, step: 1, minimumValueLabel: Text("\(Int(range.lowerBound))"), maximumValueLabel: Text("\(Int(range.upperBound))")) {
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
    
    var text: Binding<String> {
        Binding {
            format(number: model.wrappedValue)
        } set: {
            if let number = Double($0), number != model.wrappedValue {
                model.wrappedValue = number
            }
        }
    }
}
