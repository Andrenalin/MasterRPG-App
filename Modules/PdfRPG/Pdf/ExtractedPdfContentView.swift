// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import GeneratorRPG
import SwiftUI

/// View displaying analyzed PDF summary with selectable properties
public struct ExtractedPdfContentView: View {

    let content: PdfSummaryAnalysis
    @Binding var selectedProperties: PdfPropertySelection

    public init(content: PdfSummaryAnalysis, selectedProperties: Binding<PdfPropertySelection>) {
        self.content = content
        self._selectedProperties = selectedProperties
    }

    public var body: some View {
        Form {
            Section {
                Text("Select which extracted values you would like to apply on the PDF item.", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $selectedProperties.applyTitle) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(content.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                }
            } header: {
                Text("Title", bundle: .module)
            }

            Section{
                Toggle(isOn: $selectedProperties.applyDescription) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(content.summary)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    }
                }
            } header: {
                Text("Description", bundle: .module)
            }

            if !content.tags.isEmpty {
                Section {
                    Toggle(isOn: $selectedProperties.applyTags) {
                        VStack(alignment: .leading, spacing: 8) {
                            FlowLayout(spacing: 8) {
                                ForEach(content.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.2))
                                        .clipShape(.capsule)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Tags", bundle: .module)
                }
            }

            if !content.sections.isEmpty {
                Section {
                    Toggle(isOn: $selectedProperties.applySections) {
                        Text("Create \(content.sections.count) bookmark(s) from sections", bundle: .module)
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
                                        Text("Page \(pageNumber)", bundle: .module)
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
                } header: {
                    Text("Bookmarks from Sections", bundle: .module)
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

#Preview("Extracted Content") {
    @Previewable @State var selection = PdfPropertySelection()

    ExtractedPdfContentView(
        content: PdfSummaryAnalysis(
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
