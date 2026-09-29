// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Shows `PersistenceIssueCenter`'s failed saves, failed file replacements and discarded
/// edits at the top of the main window. See CODE_AUDIT_19 §5.13.
struct PersistenceIssueBannerViewModifier: ViewModifier {
    let center: PersistenceIssueCenter

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top) {
                if center.hasIssue {
                    PersistenceIssueBanner(center: center)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: center.hasIssue)
    }
}

struct PersistenceIssueBanner: View {
    let center: PersistenceIssueCenter

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text("Changes could not be saved", bundle: .module)
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
            Button("Dismiss", systemImage: "xmark", action: center.dismiss)
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
