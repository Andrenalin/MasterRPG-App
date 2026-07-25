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
        Form {
            LabeledContent {
                BattleInitiativeOrderMenu(
                    selection: initiativeOrder,
                    isDisabled: false
                )
            } label: {
                Label("Initiative Order", systemImage: "arrow.up.arrow.down")
            }

            valueNameRow(
                title: String(localized: "Initiative Value", bundle: .module),
                systemImage: "list.number",
                text: $settings.initiativeName,
                kind: .initiative
            )

            valueNameRow(
                title: String(localized: "Hit Points Value", bundle: .module),
                systemImage: "heart.text.square",
                text: $settings.hitPointsName,
                kind: .hitPoints
            )
        }
        .formStyle(.grouped)
        .frame(maxHeight: 300)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var initiativeOrder: Binding<BattleInitiativeOrder> {
        Binding(
            get: { settings.initiativeOrder },
            set: { value in
                settings.initiativeOrder = value
                actions.setInitiativeOrder(value)
            }
        )
    }

    private func valueNameRow(
        title: String,
        systemImage: String,
        text: Binding<String>,
        kind: BattleValueKind
    ) -> some View {
        LabeledContent {
            HStack {
                TextField(title, text: text)
                    .onSubmit(refresh)

                Button("Choose Value", systemImage: "person.crop.circle.badge.checkmark") {
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
    .frame(width: 560)
    .padding()
}
