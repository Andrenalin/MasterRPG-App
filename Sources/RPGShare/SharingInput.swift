// @copyright André Trettin

import CoreRPG
import SwiftUI

@Observable @MainActor
final class InputModel {
    var name: String = ""
    var text: String = ""
}

struct SharingInput: View {
    let model: InputModel
    
    private enum Field {
        case name
        case text
    }
    @FocusState private var focusedField: Field?

    /// Lets this view's own presentation animation finish before grabbing keyboard focus.
    /// See CODE_AUDIT §9.14.
    private static let autoFocusDelay: Duration = .seconds(0.5)

    var body: some View {
        @Bindable var model = model
        TextField(text: $model.name, axis: .vertical) {
            Text("Name", bundle: .main)
        }
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .name)
            .onSubmit {
                focusedField = .text
            }
            .hideKeyboardView(enabled: focusedField != nil, focusedField: $focusedField)
            .task {
                try? await Task.sleep(for: Self.autoFocusDelay)
                guard !Task.isCancelled else { return }
                focusedField = .name
            }

        TextField(text: $model.text, axis: .vertical) {
            Text("Text", bundle: .main)
        }
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .text)
            .onSubmit {
                focusedField = nil
            }
    }
}

#Preview("Adventure share input") {
    let model: InputModel = {
        let model = InputModel()
        model.name = "The Verdant Vault"
        model.text = "A moss-covered stair descends beneath the ruined observatory."
        return model
    }()

    SharingInput(model: model)
        .padding()
}
