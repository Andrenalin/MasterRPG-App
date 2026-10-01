// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Shows `PersistenceIssueCenter`'s failed saves, failed file replacements and discarded
/// edits at the top of the main window. See CODE_AUDIT_19 §5.13.
struct PersistenceIssueBannerViewModifier: ViewModifier {
    let center: PersistenceIssueCenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top) {
                if center.hasIssue {
                    PersistenceIssueBanner(center: center)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .default, value: center.hasIssue)
            .onChange(of: center.hasIssue) { _, hasIssue in
                // VoiceOver is told when edits fail to save or are discarded; the banner alone
                // appears silently. See CODE_AUDIT_20 §8.3.
                guard hasIssue else { return }
                AccessibilityNotification.Announcement(
                    String(localized: PersistenceIssueBanner.headline(for: center))
                ).post()
            }
    }
}

struct PersistenceIssueBanner: View {
    let center: PersistenceIssueCenter

    /// What went wrong: a failed attach is not "changes could not be saved". Both cases read
    /// "saved" when edits were also lost or a save failed. See CODE_AUDIT_20 §8.2.
    static func headline(for center: PersistenceIssueCenter) -> LocalizedStringResource {
        if center.saveError == nil, center.discardedEditCount == 0, center.fileError != nil {
            return LocalizedStringResource("A file could not be attached", bundle: .module)
        }
        return LocalizedStringResource("Changes could not be saved", bundle: .module)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(Self.headline(for: center))
                    .font(.headline)
                if center.discardedEditCount > 0 {
                    Text("\(center.discardedEditCount) edits were discarded after repeated save failures.", bundle: .module)
                        .font(.caption)
                }
                if let saveError = center.saveError {
                    Text(verbatim: saveError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let fileError = center.fileError {
                    Text(verbatim: fileError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: center.dismiss) {
                Label {
                    Text("Dismiss", bundle: .module)
                } icon: {
                    Image(systemName: "xmark")
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .padding(.horizontal)
    }
}

#Preview {
    Text(verbatim: "Content")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PersistenceIssueBannerViewModifier(center: .shared))
        .task {
            PersistenceIssueCenter.shared.recordDiscardedEdits(3)
        }
}
