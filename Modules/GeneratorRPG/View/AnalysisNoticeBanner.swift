// @copyright André Trettin

import SwiftUI

/// A hint shown above the analysis, e.g. that more input would improve the result. Unlike
/// `AnalysisErrorBanner` it is not an error and stays until the input changes.
struct AnalysisNoticeBanner: View {
    let message: LocalizedStringResource

    var body: some View {
        Label {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .padding()
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
    }
}

#Preview {
    // Not a literal, so the sample text is not extracted into this module's string catalog.
    let sample = "Add a photo description and tags to improve the character information"
    AnalysisNoticeBanner(message: LocalizedStringResource(String.LocalizationValue(sample)))
        .padding()
}
