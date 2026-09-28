// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Reusable 4-digit join-code entry field.
///
/// The same field backs two different bindings depending on where it's used:
/// - **Setup** binds it to a persisted code (`GameJoinCodeModel.masterCode`/
///   `.playerCode`) and passes `onRandomize` so the user can replace it.
/// - **Join** binds it to a transient `@State` value the player types in to
///   match a remote host's code, with no `onRandomize`.
struct GameJoinCodeField: View {
    let title: LocalizedStringKey
    @Binding var code: String
    var onRandomize: (() -> Void)?
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(spacing: 4) {
                GameJoinCodeOTPField(
                    code: $code,
                    accessibilityLabel: title,
                    submitLabel: submitLabel,
                    onSubmit: onSubmit
                )
            }

            if let onRandomize {
                Button(action: onRandomize) {
                    Label {
                        Text("New Code", bundle: .module)
                    } icon: {
                        Image(systemName: "shuffle")
                    }
                }
                .selectedRoundButton(
                    title: String(localized: "New Code", bundle: .module),
                    module: .game,
                    isSelected: false
                )
            }
        }
    }
}

#Preview("Editable") {
    @Previewable @State var code = "4821"
    GameJoinCodeField(title: "Game Master Code", code: $code) {
        code = GameJoinCodeModel.randomCode()
    }
    .padding()
}

#Preview("Entry") {
    @Previewable @State var code = ""
    GameJoinCodeField(title: "Enter Code", code: $code)
        .padding()
}
