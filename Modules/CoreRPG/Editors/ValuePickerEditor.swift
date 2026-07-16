// @copyright André Trettin

import SwiftUI

public struct ValuePickerEditor<Value: Hashable, Content: View>: View where Value: Identifiable {
    public init(model: EditIdentifierModel<Value>, allCategories: [Value], title: LocalizedStringKey = "Value", bundle: Bundle?, @ViewBuilder contentView: @escaping (Value) -> Content) {
        self.model = model
        self.allCategories = allCategories
        self.title = title
        self.bundle = bundle
        self.contentView = contentView
        self._selection = State(wrappedValue: model.value)
    }

    let model: EditIdentifierModel<Value>
    let allCategories: [Value]
    let title: LocalizedStringKey
    let bundle: Bundle?
    let contentView: (Value) -> Content

    @State private var selection: Value
    
    public var body: some View {
        LabeledContent {
            pickerView
        } label: {
            Text(title, bundle: bundle)
        }
        .onChange(of: model.value) {
            selection <=> model.value
        }
        .onChange(of: selection) {
            model.value <=> selection
            model.save()
        }
    }

    private var pickerView: some View {
        Picker(selection: $selection) {
            ForEach(allCategories) { value in
                contentView(value)
                    .tag(value)
            }
        } label: {
            Text(title, bundle: bundle)
        }
        .labelsHidden()
        .pickerStyle(.automatic)
    }
}

enum ValuePickerPreviewOption: String, CaseIterable, Identifiable {
    case novice, veteran, legendary

    var id: Self { self }
}

#Preview {
    let title = LocalizedStringKey(String("Rank"))
    ValuePickerEditor(
        model: EditIdentifierModel(value: ValuePickerPreviewOption.veteran),
        allCategories: ValuePickerPreviewOption.allCases,
        title: title,
        bundle: nil
    ) { option in
        Text(option.rawValue.capitalized)
    }
    .padding()
}
