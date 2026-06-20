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
    
    var body: some View {
        @Bindable var model = model
        TextField("Name", text: $model.name, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .name)
            .onSubmit {
                focusedField = .text
            }
            .hideKeyboardView(enabled: focusedField != nil, focusedField: $focusedField)
            .onAppear {
                Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    focusedField = .name
                }
            }

        TextField("Text", text: $model.text, axis: .vertical)
            .lineLimit(3...6)
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: .text)
            .onSubmit {
                focusedField = nil
            }
    }
}
