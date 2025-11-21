// @copyright André Trettin

import SwiftUI

public struct ValuePickerEditor<Value: Hashable, Content: View>: View where Value: Identifiable {
    public init(editController: any EditControllable, model: Binding<Value>, allCategories: [Value], title: LocalizedStringKey = "Value", bundle: Bundle?, @ViewBuilder contentView: @escaping (Value) -> Content) {
        self.editController = editController
        self.model = model
        self.allCategories = allCategories
        self.title = title
        self.bundle = bundle
        self.contentView = contentView
    }

    let editController: any EditControllable
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
        Picker(selection: selection) {
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

    private var selection: Binding<Value> {
        Binding {
            model.wrappedValue
        } set: {
            if $0 != model.wrappedValue {
                model.wrappedValue = $0
                editController.save(with: String(localized: "Change value").localizedString)
            }
        }
    }
}

