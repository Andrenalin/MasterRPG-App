// @copyright André Trettin

import SwiftUI

public struct ValuePickerEditor<Value: Hashable, Content: View>: View where Value: Identifiable {
    public init(model: Binding<Value>, allCategories: [Value], title: LocalizedStringKey = "Value", bundle: Bundle?, @ViewBuilder contentView: @escaping (Value) -> Content) {
        self.model = model
        self.allCategories = allCategories
        self.title = title
        self.bundle = bundle
        self.contentView = contentView
    }

    let model: Binding<Value>
    let allCategories: [Value]
    let title: LocalizedStringKey
    let bundle: Bundle?
    let contentView: (Value) -> Content

    public var body: some View {
        LabeledContent {
            pickerView
        } label: {
            Text(title, bundle: bundle)
        }
    }

    private var pickerView: some View {
        Picker(selection: model) {
            ForEach(allCategories) { value in
                contentView(value)
                    .tag(value)
            }
        } label: {
            Text(title, bundle: bundle)
        }
        .labelsHidden()
        .pickerStyle(.automatic)
        .tint(Color.accentColor)
    }
}

