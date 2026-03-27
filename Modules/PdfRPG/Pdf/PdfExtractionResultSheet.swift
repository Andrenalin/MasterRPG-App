// @copyright André Trettin

#if !os(tvOS)
import SwiftUI
import GeneratorRPG

/// Sheet view displaying extracted PDF content with apply/overwrite options
struct PdfExtractionResultSheet: View {
    let content: PdfExtractedContent
    @Binding var propertySelection: PdfPropertySelection
    let onDismiss: () -> Void
    let onApply: (PdfExtractedContent, PdfPropertySelection, Bool) -> Void

    init(
        content: PdfExtractedContent,
        propertySelection: Binding<PdfPropertySelection>,
        onDismiss: @escaping () -> Void,
        onApply: @escaping (PdfExtractedContent, PdfPropertySelection, Bool) -> Void
    ) {
        self.content = content
        self._propertySelection = propertySelection
        self.onDismiss = onDismiss
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            ExtractedPdfContentView(
                content: content,
                selectedProperties: $propertySelection
            )
            .navigationTitle("Apply Extracted Information")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        onDismiss()
                    } label: {
                        Text("Cancel", bundle: .module)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onApply(content, propertySelection, false)
                        onDismiss()
                    } label: {
                        Label {
                            Text("Apply", bundle: .module)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    }
                    .disabled(!propertySelection.hasAnySelected)

                    Button {
                        onApply(content, propertySelection, true)
                        onDismiss()
                    } label: {
                        Label {
                            Text("Overwrite", bundle: .module)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
                    .disabled(!propertySelection.hasAnySelected)
                }
            }
        }
        .onAppear {
            // Reset selection when showing new content
            propertySelection = PdfPropertySelection()
        }
    }
}

#endif
