// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Compact, capsule-shaped trigger for [[GameJoinCodeField]] on the setup
/// screens: shows the current code, and tapping it opens the full editable
/// [[GameJoinCodeOTPField]]. Presented via a plain `.popover`, so it floats
/// next to the button on Mac/iPad/visionOS but — with no
/// `.presentationCompactAdaptation` override — SwiftUI automatically adapts
/// it to a bottom sheet on a compact-width iPhone.
///
/// Editing happens on a local draft, not on `code` directly — every
/// keystroke (and the shuffle button) only ever changes `draftCode`, so a
/// half-typed code never becomes the live one. `code` is only overwritten
/// once, when the popover/sheet closes, and only if the draft is a valid
/// 4-digit code; closing with an incomplete draft leaves `code` untouched.
struct GameJoinCodeSetupButton: View {
    let title: LocalizedStringKey
    @Binding var code: String

    @State private var isPresented = false
    @State private var draftCode = ""

    var body: some View {
        Button {
            draftCode = code
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                Text(code)
                    .fontDesign(.monospaced)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .overlay {
            Capsule().stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        }
        .contentShape(.capsule)
        .accessibilityLabel(Text(title, bundle: .module))
        .accessibilityValue(Text(code))
#if os(tvOS)
        .sheet(isPresented: $isPresented, onDismiss: commitDraftIfValid) {
            presentedContent
        }
#else
        .popover(isPresented: $isPresented) {
            presentedContent
        }
        // `.popover` has no `onDismiss` callback (unlike `.sheet`), so the
        // draft is committed by watching presentation itself end instead.
        .onChange(of: isPresented) { _, isPresented in
            guard !isPresented else { return }
            commitDraftIfValid()
        }
#endif
    }

    private var presentedContent: some View {
        VStack(spacing: 16) {
            Text(title, bundle: .module)
                .font(.headline)
            GameJoinCodeField(title: title, code: $draftCode, onRandomize: randomizeDraft) {
                isPresented = false
            }
        }
        .padding()
        .frame(minWidth: 220)
    }

    private func randomizeDraft() {
        draftCode = GameJoinCodeModel.randomCode()
    }

    private func commitDraftIfValid() {
        guard GameJoinCodeModel.isValidCode(draftCode) else { return }
        code = draftCode
    }
}

#Preview {
    @Previewable @State var code = "4821"
    GameJoinCodeSetupButton(title: "Game Master Code", code: $code)
        .padding()
}
