// @copyright André Trettin

#if !os(tvOS)

import SwiftUI
import GeneratorRPG
import PDFKit

/// View for extracting and displaying PDF content metadata
public struct PdfContentExtractionView: View {

    @State private var controller = PdfContentExtractorController()
    let pdfDocument: PDFDocument
    let onContentExtracted: (PdfExtractedContent) -> Void

    public init(pdfDocument: PDFDocument, onContentExtracted: @escaping (PdfExtractedContent) -> Void) {
        self.pdfDocument = pdfDocument
        self.onContentExtracted = onContentExtracted
    }

    public var body: some View {
        VStack(spacing: 20) {
            if !controller.isModelAvailable {
                unavailableView
            } else if controller.isExtracting {
                extractingView
            } else {
                extractButton
            }

            if let error = controller.lastError {
                errorView(error)
            }
        }
        .padding()
        .onAppear {
            controller.checkModelAvailability()
        }
    }

    // MARK: - Subviews

    private var extractButton: some View {
        Button {
            Task {
                if let content = await controller.extractWithProgress(from: pdfDocument) {
                    onContentExtracted(content)
                }
            }
        } label: {
            Label("Extract PDF Information", systemImage: "wand.and.stars")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var extractingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Analyzing PDF with Apple Intelligence...")
                .font(.headline)

            if let progress = controller.extractionProgress {
                VStack(alignment: .leading, spacing: 8) {
                    if let title = progress.title {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Title: \(title)")
                                .font(.subheadline)
                        }
                    }

                    if progress.summary != nil {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Summary extracted")
                                .font(.subheadline)
                        }
                    }

                    if let tags = progress.tags, !tags.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Found \(tags.count) tags")
                                .font(.subheadline)
                        }
                    }

                    if let sections = progress.sections, !sections.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Identified \(sections.count) sections")
                                .font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Apple Intelligence Required")
                .font(.headline)

            Text("PDF content extraction requires Apple Intelligence, which is not available on this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func errorView(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Dismiss") {
                controller.clearError()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// View displaying extracted PDF content with selectable properties
public struct ExtractedPdfContentView: View {

    let content: PdfExtractedContent
    @Binding var selectedProperties: PdfPropertySelection

    public init(content: PdfExtractedContent, selectedProperties: Binding<PdfPropertySelection>) {
        self.content = content
        self._selectedProperties = selectedProperties
    }

    public var body: some View {
        Form {
            Section {
                Text("Select which properties to apply to your PDF:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Title") {
                Toggle(isOn: $selectedProperties.applyTitle) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(content.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }
            }

            Section("Description") {
                Toggle(isOn: $selectedProperties.applyDescription) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(content.summary)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    }
                }
            }

            if !content.tags.isEmpty {
                Section("Tags") {
                    Toggle(isOn: $selectedProperties.applyTags) {
                        VStack(alignment: .leading, spacing: 8) {
                            FlowLayout(spacing: 8) {
                                ForEach(content.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }

            if !content.sections.isEmpty {
                Section("Bookmarks from Sections") {
                    Toggle(isOn: $selectedProperties.applySections) {
                        Text("Create \(content.sections.count) bookmark(s) from sections")
                            .font(.headline)
                    }

                    if selectedProperties.applySections {
                        ForEach(content.sections.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(content.sections[index].heading)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Spacer()
                                    if let pageNumber = content.sections[index].pageNumber {
                                        Text("Page \(pageNumber)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(content.sections[index].summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                            .padding(.leading, 20)
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

/// Selection state for which properties to apply
public struct PdfPropertySelection {
    public var applyTitle: Bool = true
    public var applyDescription: Bool = true
    public var applyTags: Bool = true
    public var applySections: Bool = true

    public init(
        applyTitle: Bool = true,
        applyDescription: Bool = true,
        applyTags: Bool = true,
        applySections: Bool = true
    ) {
        self.applyTitle = applyTitle
        self.applyDescription = applyDescription
        self.applyTags = applyTags
        self.applySections = applySections
    }

    public var hasAnySelected: Bool {
        applyTitle || applyDescription || applyTags || applySections
    }
}

/// Simple flow layout for tags
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var frames: [CGRect] = []
        var size: CGSize = .zero

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

#Preview("Extraction View") {
    if let url = Bundle.main.url(forResource: "sample", withExtension: "pdf"),
       let pdfDocument = PDFDocument(url: url) {
        PdfContentExtractionView(pdfDocument: pdfDocument) { content in
            print("Extracted: \(content.title)")
        }
    } else {
        Text("No sample PDF available")
    }
}

#Preview("Extracted Content") {
    @Previewable @State var selection = PdfPropertySelection()

    ExtractedPdfContentView(
        content: PdfExtractedContent(
            title: "Dungeons & Dragons Player's Handbook",
            summary: "The core rulebook for players, containing character creation rules, races, classes, equipment, spells, and gameplay mechanics for D&D 5th Edition.",
            tags: ["D&D 5e", "Fantasy", "Rulebook", "Core Rules", "Character Creation"],
            sections: [
                PdfSection(heading: "Chapter 1: Step-by-Step Characters", summary: "Guide to creating your character", pageNumber: 11),
                PdfSection(heading: "Chapter 2: Races", summary: "Available player races and their traits", pageNumber: 17),
                PdfSection(heading: "Chapter 3: Classes", summary: "Character classes and their abilities", pageNumber: 45)
            ]
        ),
        selectedProperties: $selection
    )
}

#endif
