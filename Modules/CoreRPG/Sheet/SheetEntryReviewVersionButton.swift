// @copyright André Trettin

import SwiftUI

struct SheetEntryReviewVersionButton: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let version: SheetReviewVersion
    let isSelected: Bool
    let selectAction: () -> Void

    var body: some View {
        Button(action: selectVersion) {
            VStack(alignment: .leading) {
                HStack {
                    Label(version.decision.title, systemImage: version.decision.systemImage)
                        .bold()
                        .foregroundStyle(version.decision.tint)

                    Spacer()

                    if isSelected {
                        Label {
                            Text("Selected", bundle: .module)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(version.decision.tint)
                    }
                }

                if version.isAvailable, let sheetModel = version.sheetModel {
                    SheetEntryReviewSnapshotView(sheetModel: sheetModel)
                } else {
                    Label {
                        Text("Not present or shown in this version — select to use this version", bundle: .module)
                    } icon: {
                        Image(systemName: "minus.circle")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                version.decision.tint.opacity(isSelected ? 0.16 : 0.06),
                in: .rect(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? version.decision.tint : version.decision.tint.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(version.decision.title) entry version", bundle: .module))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityValue: Text {
        if !version.isAvailable {
            Text("Not present or shown; selectable", bundle: .module)
        } else if isSelected {
            Text("Selected", bundle: .module)
        } else {
            Text("Not selected", bundle: .module)
        }
    }

    private func selectVersion() {
        withAnimation(accessibilityReduceMotion ? nil : .smooth) {
            selectAction()
        }
    }
}

#Preview("Entry Review Version") {
    let fixture = SheetEntryReviewPreviewFixture()
    SheetEntryReviewVersionButton(
        version: fixture.version,
        isSelected: true,
        selectAction: {}
    )
    .padding()
}
