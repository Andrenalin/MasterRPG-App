// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct BattleRoundSettingsView: View {
    @Bindable var settings: BattleRoundSettingsModel
    let actions: BattleRoundActions
    let selectEntry: @MainActor (BattleValueKind) -> Void
    let useDroppedEntry: @MainActor (LinkCharacterData, BattleValueKind) -> Void
    let refresh: @MainActor () -> Void

    var body: some View {
        GroupBoxTV {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent {
                    BattleInitiativeOrderMenu(
                        selection: $settings.initiativeOrder,
                        isDisabled: false
                    )
                    .onChange(of: settings.initiativeOrder) { _, newOrder in
                        actions.setInitiativeOrder(newOrder)
                    }
                } label: {
                    Label(
                        String(localized: "Initiative Order", bundle: .module),
                        systemImage: "arrow.up.arrow.down"
                    )
                }
                
                BattleValueNameRow(
                    title: String(localized: "Initiative Pattern", bundle: .module),
                    systemImage: "list.number",
                    text: $settings.initiativeName,
                    kind: .initiative,
                    selectEntry: selectEntry,
                    useDroppedEntry: useDroppedEntry,
                    refresh: refresh
                )
                
                BattleValueNameRow(
                    title: String(localized: "Hit Points Pattern", bundle: .module),
                    systemImage: "heart.text.square",
                    text: $settings.hitPointsName,
                    kind: .hitPoints,
                    selectEntry: selectEntry,
                    useDroppedEntry: useDroppedEntry,
                    refresh: refresh
                )
            }
            .labeledContentStyle(AlignedLabelStyle(labelWidth: 180))
            .padding()

        } label: {
            Text("Settings", bundle: .module)
        }
        .padding()
        .transition(.move(edge: .top).combined(with: .opacity))
    }

}

private struct BattleValueNameRow: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    let kind: BattleValueKind
    let selectEntry: @MainActor (BattleValueKind) -> Void
    let useDroppedEntry: @MainActor (LinkCharacterData, BattleValueKind) -> Void
    let refresh: @MainActor () -> Void

    var body: some View {
        LabeledContent {
            HStack {
                TextField(title, text: $text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(refresh)

                Button(
                    String(localized: "Choose Value", bundle: .module),
                    systemImage: "person.crop.circle.badge.checkmark"
                ) {
                    selectEntry(kind)
                }
                .labelStyle(.iconOnly)
            }
            .battleLinkCharacterDropDestination { values, _ in
                guard let value = values.first, value.entryId != nil else {
                    return false
                }
                useDroppedEntry(value, kind)
                return true
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct AlignedLabelStyle: LabeledContentStyle {
    let labelWidth: CGFloat
    
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline) {
            // Force the label to take up a rigid width, aligned to the leading edge
            configuration.label
                .frame(width: labelWidth, alignment: .leading)
            
            // Let the content fill the remaining space
            configuration.content
        }
    }
}

#Preview("Battle settings") {
    let model = BattleRoundPreviewData.model()
    let defaults = UserDefaults(suiteName: "BattleRoundSettingsPreview") ?? .standard
    let settings = BattleRoundSettingsModel(defaults: defaults)

    BattleRoundSettingsView(
        settings: settings,
        actions: .preview(model: model),
        selectEntry: { _ in },
        useDroppedEntry: { _, _ in },
        refresh: {}
    )
}
