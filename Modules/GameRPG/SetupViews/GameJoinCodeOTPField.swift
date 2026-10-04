// @copyright André Trettin

import CoreRPG
import SwiftUI

/// 4-digit "OTP style" code entry: one bordered box per digit, with the box
/// about to receive the next keystroke shown with an accented "active"
/// border. A single hidden `TextField` underneath captures all keyboard
/// input (and drives autofill/paste), so the boxes above are purely a
/// decorative, accessibility-hidden reflection of `code` — the `TextField`
/// itself carries the real accessibility label/value.
struct GameJoinCodeOTPField: View {
    @Binding var code: String
    let accessibilityLabel: LocalizedStringKey
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool
    /// The digit boxes grow with Dynamic Type so a large digit never clips. See CODE_AUDIT_Join §8.5.
    @ScaledMetric(relativeTo: .title2) private var boxWidth = 40
    @ScaledMetric(relativeTo: .title2) private var boxHeight = 48

    private static let digitCount = GameJoinCodeModel.codeLength

    var body: some View {
        ZStack {
            // No visible label (and no empty catalog key): `accessibilityLabel` below names it.
            TextField(text: $code) {
                Text(verbatim: "")
            }
#if os(iOS) || os(tvOS)
                .keyboardType(.numberPad)
#endif
                .autocorrectionDisabled()
#if os(iOS) || os(visionOS)
                .textContentType(.oneTimeCode)
#endif
                .focused($isFocused)
#if os(macOS)
                // AppKit draws the focus ring in the window's focus layer, so the
                // near-zero opacity doesn't hide it and it would outline all boxes.
                // The accented active digit box is the focus indicator instead.
                .textFieldStyle(.plain)
                .focusEffectDisabled()
#endif
                .opacity(0.02)
                .submitLabel(submitLabel)
                .accessibilityLabel(Text(accessibilityLabel, bundle: .module))
                .accessibilityValue(Text(code).speechSpellsOutCharacters())
                .onChange(of: code, initial: false) { _, newValue in
                    // ASCII digits only: other Unicode digits would derive a different key than
                    // the host's code. See CODE_AUDIT_Join §5.7.
                    let filtered = GameJoinCodeModel.sanitized(newValue)
                    if filtered != newValue {
                        code = filtered
                    }
                }
                .onSubmit {
                    onSubmit?()
                }

            HStack(spacing: 8) {
                ForEach(0..<Self.digitCount, id: \.self) { index in
                    digitBox(at: index)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onAppear {
            isFocused = true
        }
    }

    /// The box that will receive the next typed digit — the last box once
    /// the code is full, so exactly one box stays highlighted while focused.
    private var activeIndex: Int {
        min(code.count, Self.digitCount - 1)
    }

    private func character(at index: Int) -> String {
        let characters = Array(code)
        return index < characters.count ? String(characters[index]) : ""
    }

    @ViewBuilder
    private func digitBox(at index: Int) -> some View {
        let isCurrent = isFocused && index == activeIndex
        Text(character(at: index))
            .font(.title2)
            .fontDesign(.monospaced)
            .frame(width: boxWidth, height: boxHeight)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCurrent ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isCurrent ? 2 : 1)
            }
    }
}

#Preview("Empty") {
    @Previewable @State var code = ""
    GameJoinCodeOTPField(code: $code, accessibilityLabel: "Enter Code")
        .padding()
}

#Preview("Partial") {
    @Previewable @State var code = "48"
    GameJoinCodeOTPField(code: $code, accessibilityLabel: "Enter Code")
        .padding()
}

#Preview("Full") {
    @Previewable @State var code = "4821"
    GameJoinCodeOTPField(code: $code, accessibilityLabel: "Enter Code")
        .padding()
}
