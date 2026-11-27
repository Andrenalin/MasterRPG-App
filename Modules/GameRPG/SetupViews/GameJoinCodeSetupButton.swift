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
    // Scaled with Dynamic Type instead of fixed points. See CODE_AUDIT_29 §8.7.
    @ScaledMetric private var padding14: CGFloat = 14
    @ScaledMetric private var padding8: CGFloat = 8
    @ScaledMetric private var spacing6: CGFloat = 6
    let title: LocalizedStringKey
    @Binding var code: String

    @State private var isPresented = false
    @State private var draftCode = ""

    var body: some View {
        Button {
            draftCode = code
            isPresented = true
        } label: {
            HStack(spacing: spacing6) {
                Image(systemName: "wifi")
                Text(code)
                    .fontDesign(.monospaced)
                    .speechSpellsOutCharacters()
            }
#if !os(visionOS)
            .padding(.horizontal, padding14)
            .padding(.vertical, padding8)
#endif
        }
#if os(visionOS)
        // The system style keeps the standard control height next to the
        // neighbouring buttons; a plain, hand-outlined capsule collapsed.
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
#else
        .buttonStyle(.plain)
        .overlay {
            Capsule().stroke(Color.secondary.opacity(0.35), lineWidth: 1)
        }
        .contentShape(.capsule)
#endif
        .accessibilityLabel(Text(title, bundle: .module))
        .accessibilityValue(Text(code).speechSpellsOutCharacters())
#if os(tvOS)
        .sheet(isPresented: $isPresented, onDismiss: commitDraftIfValid) {
            GameJoinCodeSetupButtonPresentedContentView(title: title, draftCode: $draftCode, isPresented: $isPresented, onRandomize: randomizeDraft)
        }
#else
        .popover(isPresented: $isPresented) {
            GameJoinCodeSetupButtonPresentedContentView(title: title, draftCode: $draftCode, isPresented: $isPresented, onRandomize: randomizeDraft)
        }
        // `.popover` has no `onDismiss` callback (unlike `.sheet`), so the
        // draft is committed by watching presentation itself end instead.
        .onChange(of: isPresented) { _, isPresented in
            guard !isPresented else { return }
            commitDraftIfValid()
        }
#endif
    }

    private func randomizeDraft() {
        draftCode = GameJoinCodeModel.randomCode()
    }

    private func commitDraftIfValid() {
        guard GameJoinCodeModel.isValidCode(draftCode) else { return }
        code = draftCode
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.3)

private struct GameJoinCodeSetupButtonPresentedContentView: View {
    // Scaled with Dynamic Type instead of fixed points. See CODE_AUDIT_29 §8.7.
    @ScaledMetric private var spacing16: CGFloat = 16
    let title: LocalizedStringKey
    @Binding var draftCode: String
    @Binding var isPresented: Bool
    let onRandomize: () -> Void

    var body: some View {
        VStack(spacing: spacing16) {
            Text(title, bundle: .module)
                .font(.headline)
            GameJoinCodeField(title: title, code: $draftCode, onRandomize: onRandomize) {
                isPresented = false
            }
        }
        .padding()
        .frame(minWidth: 220)
    }
}

#Preview {
    @Previewable @State var code = "4821"
    GameJoinCodeSetupButton(title: "Game Master Code", code: $code)
        .padding()
}
