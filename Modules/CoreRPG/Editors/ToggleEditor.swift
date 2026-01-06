// @copyright André Trettin

import SwiftUI

public struct ToggleEditor: View {
    public init(value: Binding<Bool>, canToggle: Bool = true, title: LocalizedStringKey = "Hidden", bundle: Bundle?, icon: String = "eye.slash") {
        self.model = EditIdentifierModel(value: value)
        self.canToggle = canToggle
        self.title = title
        self.bundle = bundle
        self.icon = icon
    }

    public init(model: EditIdentifierModel<Bool>, canToggle: Bool = true, title: LocalizedStringKey = "Hidden", bundle: Bundle?, icon: String = "eye.slash") {
        self.model = model
        self.canToggle = canToggle
        self.title = title
        self.bundle = bundle
        self.icon = icon
    }

    let model: EditIdentifierModel<Bool>
    let canToggle: Bool
    let title: LocalizedStringKey
    let bundle: Bundle?
    let icon: String

    public var body: some View {
        let _ = Self._printChanges()
        toggleEditorView
            .disabled(!canToggle)
            .onChange(of: model.value) {
                model.save()
            }
    }
}

private extension ToggleEditor {
    @ViewBuilder var toggleEditorView: some View {
        @Bindable var model = model
        LabeledContent {
            Toggle(isOn: $model.value) {
                Text(title, bundle: bundle)
            }
            .tint(Color.accentColor)
        } label: {
            Image(systemName: icon)
        }
    }
}
