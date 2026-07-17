// @copyright André Trettin

import SwiftUI

/// A read-only representation of controller-generated inline content.
///
/// Normal module row viewers read from their live module controller. Import review rows
/// instead use this SheetModel-only representation so an Existing/New/Merge card never
/// renders data from a different live version. The generated inline type, name, and
/// description still come from the version-specific `SheetControllable` snapshot.
struct SheetEntryReviewInlineSnapshotView: View {
    let sheetModel: SheetModel

    var body: some View {
        VStack(alignment: .leading) {
            Label(displayName, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !sheetModel.description.isEmpty {
                Text(sheetModel.description.withoutLink())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var displayName: String {
        if !sheetModel.name.isEmpty {
            return sheetModel.name.withoutLink()
        }
        return sheetModel.source.typeId.title
    }

    private var systemImage: String {
        switch sheetModel.sheetType {
        case .item: "doc.text"
        case .group: "folder"
        case .audio: "waveform"
        case .dice: "dice"
        case .pdf: "doc.richtext"
        case .photo: "photo"
        case .space: "cube"
        case .weather: "cloud.sun"
        }
    }
}

#Preview("Entry Review Inline Snapshot") {
    let fixture = SheetEntryReviewPreviewFixture()
    SheetEntryReviewInlineSnapshotView(sheetModel: fixture.inlineSheetModel)
        .padding()
}
