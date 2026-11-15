// @copyright André Trettin

import SwiftUI

/// The dismissible error line shown under the Apple Intelligence analysis and extraction views.
struct AnalysisErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)

            Text(verbatim: message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: dismiss) {
                Text("Dismiss", bundle: .module)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(.red.opacity(0.1), in: .rect(cornerRadius: 8))
    }
}
