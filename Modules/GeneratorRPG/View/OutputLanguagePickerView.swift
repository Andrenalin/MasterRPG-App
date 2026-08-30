// @copyright André Trettin

import SwiftUI

/// Language picker for on-device AI analysis flows.
///
/// Extracted from `PdfSummaryAnalysisView`, `TableSummaryAnalysisView`, and
/// `BatchTextSummaryExtractionView`, which each held a byte-for-byte identical private
/// `languagePicker` computed property — a plain `HStack` with `.labelsHidden()` and no
/// compensating accessibility label, so VoiceOver announced only the selected language, not
/// what it controls. `LabeledContent` ties the label and picker together the way
/// `ValuePickerEditor` already does elsewhere in the codebase. See CODE_AUDIT_9 §8.1/§8.3.
struct OutputLanguagePickerView: View {
    @Binding var selectedLanguage: OutputLanguage

    var body: some View {
        LabeledContent {
            Picker(selection: $selectedLanguage) {
                ForEach(OutputLanguage.supported) { language in
                    Text(verbatim: language.displayName).tag(language)
                }
            } label: {
                Text("Output Language", bundle: .module)
            }
            .labelsHidden()
        } label: {
            Text("Output Language", bundle: .module)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
