// @copyright André Trettin

import SwiftUI

struct SingleReviewReferenceRow: View {
    let reference: SingleReviewReference

    var body: some View {
        HStack {
            Image(systemName: reference.status.systemImage)
                .foregroundStyle(reference.status.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(reference.itemName)
                Text(reference.moduleName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            reference.status.label
                .font(.caption2)
                .foregroundStyle(reference.status.tint)
        }
        .padding(10)
        .background(reference.status.tint.opacity(0.08))
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

extension SingleReviewReference.Status {
    var systemImage: String {
        switch self {
        case .resolved: "checkmark.circle.fill"
        case .pendingImport: "arrow.down.circle.fill"
        case .missing: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .resolved: .green
        case .pendingImport: .orange
        case .missing: .red
        }
    }

    var label: Text {
        switch self {
        case .resolved: Text("Resolved", bundle: .module)
        case .pendingImport: Text("Pending Import", bundle: .module)
        case .missing: Text("Missing", bundle: .module)
        }
    }
}

#Preview {
    SingleReviewReferenceRow(reference: SingleItemImportModel.preview.references[0])
        .padding()
}
