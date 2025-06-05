// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public class ToggleModel {
    public init(state: Bool = false) {
        self.state = state
    }

    public var state: Bool
}

public struct ToggleModelEditor: View {
    public init(editController: any EditControllable, model: ToggleModel, title: LocalizedStringKey = "Hidden", bundle: Bundle?, icon: String = "eye.slash") {
        self.editController = editController
        self.model = model
        self.title = title
        self.bundle = bundle
        self.icon = icon
    }

    let editController: any EditControllable
    let model: ToggleModel
    let title: LocalizedStringKey
    let bundle: Bundle?
    let icon: String

    public var body: some View {
        @Bindable var model = model
        LabeledContent {
            Toggle(isOn: $model.state) {
                Text(title, bundle: bundle)
            }
            .tint(Color.accentColor)
        } label: {
            Image(systemName: icon)
        }
    }
}
