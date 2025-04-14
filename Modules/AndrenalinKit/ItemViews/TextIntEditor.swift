// @copyright André Trettin

import SwiftUI

public struct TextIntEditor: View {
    public init(editController: any EditControllable, model: Binding<Int>, title: LocalizedStringKey, icon: String, prompt: LocalizedStringKey, bundle: Bundle?, range: ClosedRange<Int>) {
        self.editController = editController
        self.model = model
        self.title = title
        self.icon = icon
        self.prompt = prompt
        self.bundle = bundle
        let uppperBound = range.upperBound <= range.lowerBound ? range.lowerBound + 1 : range.upperBound
        self.range = ClosedRange(uncheckedBounds: (Double(range.lowerBound), Double(uppperBound)))
    }
    
    let editController: any EditControllable
    let model: Binding<Int>
    let title: LocalizedStringKey
    let icon: String
    let prompt: LocalizedStringKey
    let bundle: Bundle?
    let range: ClosedRange<Double>
    
    @FocusState private var focusState: Bool
    
    public var body: some View {
        HStack {
            textInputView
                .frame(maxWidth: 64, alignment: .leading)
            
            sliderView
        }
        .onChange(of: focusState, initial: false) {
            guard focusState == false else { return }
            editController.save(with: String(localized: "Typing").localizedString)
        }
    }
}

private extension TextIntEditor{
    var textInputView: some View {
        
        TextField(text: text, prompt: Text(prompt, bundle: bundle)) {
            Text(title, bundle: bundle)
        }
#if os(iOS) || os(visionOS)
            .autocapitalization(.none)
            .keyboardType(.numbersAndPunctuation)
#endif
            .disableAutocorrection(true)
            .numericInput(text, includeDecimal: false)
            .labelsHidden()
            .submitLabel(.next)
            .focused($focusState)
            .onSubmit {
                editController.save(with: String(localized: "Typing").localizedString)
            }
    }
    
    var text: Binding<String> {
        Binding {
            "\(model.wrappedValue)"
        } set: {
            if let number = Int($0), number != model.wrappedValue {
                model.wrappedValue = number
            }
        }
    }
    
    var sliderView: some View {
#if !os(tvOS)
        Slider(value: sliderBinding, in: range, step: 1, minimumValueLabel: Text("\(Int(range.lowerBound))"), maximumValueLabel: Text("\(Int(range.upperBound))")) {
            Text(title, bundle: bundle)
        }
        .labelsHidden()
#else
        EmptyView()
#endif
    }
    
    var sliderBinding: Binding<Double> {
        Binding {
            Double(model.wrappedValue)
        } set: {
            let number = Int($0)
            if number != model.wrappedValue {
                model.wrappedValue = number
            }
        }
    }
}
