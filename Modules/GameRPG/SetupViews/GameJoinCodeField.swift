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

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title, bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("0000", text: $code)
#if os(iOS) || os(tvOS)
                    .keyboardType(.numberPad)
#endif
                    .font(.title2.monospacedDigit())
                    .multilineTextAlignment(.center)
#if !os(tvOS)
                    .textFieldStyle(.roundedBorder)
#endif
                    .frame(maxWidth: 100)
                    .onChange(of: code, initial: false) { _, newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(4))
                        if filtered != newValue {
                            code = filtered
                        }
                    }
            }

            if let onRandomize {
                Button("New Code", systemImage: "shuffle", action: onRandomize)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .help(Text("Generate a new random code", bundle: .module))
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
