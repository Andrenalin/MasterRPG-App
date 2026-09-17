// @copyright André Trettin

#if !os(tvOS)
import SwiftUI

/// Shared with `ContentExtractionView`, `SummaryAnalysisView`, and `PdfContentView` — a
/// single place for the PDF loading/unavailable presentation so wording and accessibility
/// text can't drift out of sync between them again. See CODE_AUDIT_Pdf §9.2/§8.2.
struct PdfLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading PDF...", bundle: .module)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Loading PDF document", bundle: .module))
    }
}

struct PdfUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("PDF Not Available", bundle: .module)
            } icon: {
                Image(systemName: "doc.questionmark")
            }
        } description: {
            Text("The PDF file could not be loaded.", bundle: .module)
        }
        .accessibilityLabel(Text("PDF unavailable", bundle: .module))
        .accessibilityHint(Text("The PDF file could not be loaded", bundle: .module))
    }
}

#Preview {
    PdfLoadingView()
}

#Preview {
    PdfUnavailableView()
}
#endif
