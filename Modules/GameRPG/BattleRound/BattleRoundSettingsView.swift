// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG
import SwiftUI

struct BattleRoundSettingsView: View {
    @Bindable var settings: BattleRoundSettingsModel
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    var body: some View {
                BattleRoundPatternSection(
                    title: String(localized: "Initiative Pattern", bundle: .module),
                    systemImage: "list.number",
                    kind: .initiative,
                    settings: settings,
                    controller: controller,
                    screenModel: screenModel
                )

                BattleRoundPatternSection(
                    title: String(localized: "Hit Points Pattern", bundle: .module),
                    systemImage: "heart.text.square",
                    kind: .hitPoints,
                    settings: settings,
                    controller: controller,
                    screenModel: screenModel
                )

                LabeledContent {
                    BattleInitiativeOrderMenu(
                        selection: $settings.initiativeOrder,
                        isDisabled: false
                    )
                    .onChange(of: settings.initiativeOrder) { _, newOrder in
                        controller.setInitiativeOrder(newOrder)
                    }
                } label: {
                    Label(
                        String(localized: "Initiative Order", bundle: .module),
                        systemImage: "arrow.up.arrow.down"
                    )
                }
                .padding(BattleRoundSpacing.standard)
    }
}

private struct BattleRoundPatternSection: View {
    let title: String
    let systemImage: String
    let kind: BattleValueKind
    let settings: BattleRoundSettingsModel
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)

        ForEach(settings.names(for: kind), id: \.self) { name in
            BattleRoundPatternRow(name: name, kind: kind, settings: settings)
        }

        BattleRoundPatternAddRow(
            kind: kind,
            settings: settings,
            controller: controller,
            screenModel: screenModel
        )
    }
}

/// Extracted from `BattleRoundPatternSection` into its own `View` struct
/// rather than a computed property, per the project's rule against
/// decomposing views that way. See CODE_AUDIT §8.1.
private struct BattleRoundPatternAddRow: View {
    let kind: BattleValueKind
    let settings: BattleRoundSettingsModel
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    @Environment(ScenesManager.self) private var scenesManager
    @State private var newName = ""

    var body: some View {
        HStack {
            TextField(String(localized: "Add Pattern", bundle: .module), text: $newName)
                .onSubmit(addTypedName)

            Button(
                String(localized: "Add Pattern", bundle: .module),
                systemImage: "plus.circle.fill",
                action: addTypedName
            )
            .labelStyle(.iconOnly)
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(
                String(localized: "Choose Value", bundle: .module),
                systemImage: "person.crop.circle.badge.checkmark"
            ) {
                screenModel.selectConfiguredValue(kind, controller: controller, scenesManager: scenesManager)
            }
            .labelStyle(.iconOnly)
        }
        .padding(BattleRoundSpacing.standard)
        .battleLinkCharacterDropDestination { values, _ in
            guard let value = values.first, value.entryId != nil else {
                return false
            }
            return screenModel.useDroppedConfiguredValue(value, kind: kind, controller: controller)
        }
    }

    private func addTypedName() {
        guard settings.addName(newName, for: kind) else { return }
        newName = ""
        screenModel.refreshConfiguredValues(controller: controller)
    }
}

private struct BattleRoundPatternRow: View {
    let name: String
    let kind: BattleValueKind
    let settings: BattleRoundSettingsModel

    var body: some View {
        HStack {
            Text(verbatim: name)
            Spacer()
            Button(
                String(localized: "Remove Pattern", bundle: .module),
                systemImage: "minus.circle.fill"
            ) {
                settings.removeName(name, for: kind)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .padding(BattleRoundSpacing.standard)
        .background(.fill.tertiary, in: .rect(cornerRadius: 8))
    }
}

#Preview("Battle settings", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let screenModel = BattleRoundScreenModel(model: controller.model, layout: .wide)
    let defaults = UserDefaults(suiteName: "BattleRoundSettingsPreview") ?? .standard
    let settings = BattleRoundSettingsModel(defaults: defaults)

    BattleRoundSettingsView(
        settings: settings,
        controller: controller,
        screenModel: screenModel
    )
}
