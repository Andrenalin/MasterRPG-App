// @copyright André Trettin

import SwiftUI

public struct TextDoubleEditor: View {
    public init(model: Binding<Double>, title: LocalizedStringKey, icon: String, prompt: LocalizedStringKey, bundle: Bundle?, range: ClosedRange<Double>) {
        self.model = model
        self.title = title
        self.icon = icon
        self.prompt = prompt
        self.bundle = bundle
        self.range = range
    }

    let model: Binding<Double>
    let title: LocalizedStringKey
    let icon: String
    let prompt: LocalizedStringKey
    let bundle: Bundle?
    let range: ClosedRange<Double>

    public var body: some View {
        LabeledContent {
            textInputView
        } label: {
            Label {
                Text(title, bundle: bundle)
            } icon: {
                Image(systemName: icon).imageScale(.large)
            }
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

    var text: Binding<String> {
        Binding {
            "\(model.wrappedValue)"
        } set: {
            if let number = Double($0), number != model.wrappedValue {
                model.wrappedValue = number
            }
        }
    }
}
