// @copyright André Trettin

import SwiftUI

struct AdventureBlockListSectionHeader: View {
    let title: String
    let count: Int
    let systemImage: String
    let isWorking: Bool
    let selectedCount: Int?
    let isTaken: Bool
    let canTake: Bool
    let takeAction: () -> Void
    let restoreAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: systemImage)
            }
                .font(.headline)
            if isWorking {
                ProgressView().controlSize(.small)
            }
            Spacer(minLength: 0)
            if canTake {
                Button(
                    LocalizedStringResource("Take", bundle: .module),
                    systemImage: "checkmark.circle",
                    action: takeAction
                )
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if isTaken {
                Button(
                    LocalizedStringResource("Restore", bundle: .module),
                    systemImage: "arrow.uturn.backward",
                    action: restoreAction
                )
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            if count > 0 {
                Button(
                    LocalizedStringResource("Delete Answers", bundle: .module),
                    systemImage: "trash",
                    action: deleteAction
                )
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .tint(.red)
                    .frame(minWidth: 44, minHeight: 44)
                    .help(Text("Delete answers", bundle: .module))
            }
            Text(count, format: .number)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let selectedCount {
                Label {
                    Text(selectedCount, format: .number)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}

#Preview {
    AdventureBlockListSectionHeader(
        title: "Answers / Ideas",
        count: 4,
        systemImage: "sparkles",
        isWorking: false,
        selectedCount: 2,
        isTaken: false,
        canTake: true,
        takeAction: {},
        restoreAction: {},
        deleteAction: {}
    )
    .padding()
}
