// @copyright André Trettin

import SwiftUI

public struct ToggleEditor: View {
    public init(model: Binding<Bool>, canToggle: Bool = true, title: LocalizedStringKey = "Hidden", bundle: Bundle?, icon: String = "eye.slash") {
        self.model = model
        self.canToggle = canToggle
        self.title = title
        self.bundle = bundle
        self.icon = icon
    }

    let model: Binding<Bool>
    let canToggle: Bool
    let title: LocalizedStringKey
    let bundle: Bundle?
    let icon: String

    public var body: some View {
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
