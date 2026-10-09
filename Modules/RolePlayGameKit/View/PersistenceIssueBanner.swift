// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Shows `PersistenceIssueCenter`'s failed saves, failed file replacements and discarded
/// edits at the top of the main window. See CODE_AUDIT_19 §5.13.
struct PersistenceIssueBannerViewModifier: ViewModifier {
    let center: PersistenceIssueCenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the banner says, as far as VoiceOver is told: its headline, and what it counts.
    private struct AnnouncedIssue: Equatable {
        let headline: String
        let saveError: String?
        let fileError: String?
        let discardedEditCount: Int
    }

    private var announcedIssue: AnnouncedIssue? {
        guard center.hasIssue else { return nil }
        return AnnouncedIssue(
            headline: String(localized: PersistenceIssueBanner.headline(for: center)),
            saveError: center.saveError,
            fileError: center.fileError,
            discardedEditCount: center.discardedEditCount
        )
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top) {
                if center.hasIssue {
                    PersistenceIssueBanner(center: center)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? nil : .default, value: center.hasIssue)
            // VoiceOver is told when edits fail to save or are discarded; the banner alone appears
            // silently. Keyed on the headline, not on `hasIssue`: a second issue that arrives
            // while the banner is up changes what it says and was not announced.
            // See CODE_AUDIT_20 §8.3, CODE_AUDIT_21 §8.4.
            .onChange(of: announcedIssue) { _, issue in
                guard let issue else { return }
                AccessibilityNotification.Announcement(issue.headline).post()
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
        .background(.regularMaterial, in: .rect(cornerRadius: ResolvedAppTheme.panelCornerRadius))
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
