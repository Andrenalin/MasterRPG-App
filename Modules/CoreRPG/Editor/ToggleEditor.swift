// @copyright André Trettin

import SwiftUI

public struct ToggleEditor: View {
    public init(editController: any EditControllable, model: Binding<Bool>, canToggle: Bool = true, title: LocalizedStringKey = "Hidden", bundle: Bundle?, icon: String = "eye.slash") {
        self.editController = editController
        self.model = model
        self.canToggle = canToggle
        self.title = title
        self.bundle = bundle
        self.icon = icon
    }

    let editController: any EditControllable
    let model: Binding<Bool>
    let canToggle: Bool
    let title: LocalizedStringKey
    let bundle: Bundle?
    let icon: String

    public var body: some View {
        let _ = Self._printChanges()
        
        toggleEditorView
            .disabled(!canToggle)
    }
}

private extension ToggleEditor {
    var toggleEditorView: some View {
        LabeledContent {
            Toggle(isOn: model) {
                Text(title, bundle: bundle)
            }
            .tint(Color.accentColor)
        } label: {
            Image(systemName: icon)
        }
    }

    var calculatedBinding: Binding<Bool> {
        Binding {
            model.wrappedValue
        } set: {
            if $0 != model.wrappedValue {
                model.wrappedValue = $0
            }
        }
    }
}
