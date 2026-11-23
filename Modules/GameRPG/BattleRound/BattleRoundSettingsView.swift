// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG
import SwiftUI

/// The battle settings panel: the name patterns Initiative and Hit Points are
/// detected by, and the initiative order. One container, so the panel is laid
/// out, backed and animated as a whole.
struct BattleRoundSettingsView: View {
    let settings: BattleRoundSettingsModel
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: BattleRoundSpacing.loose) {
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
                // The settings own the order; the controller is the one
                // writer, and it re-sorts the turn list with the change.
                BattleInitiativeOrderMenu(
                    selection: Binding(
                        get: { settings.initiativeOrder },
                        set: { controller.setInitiativeOrder($0) }
                    )
                )
            } label: {
                Label(
                    String(localized: "Initiative Order", bundle: .module),
                    systemImage: "arrow.up.arrow.down"
                )
            }

            // A display choice only: no pin changes, so a pin that is revealed
            // later shows up in the list and one that is hidden later leaves it.
            Toggle(isOn: $settings.hidesHiddenAttackers) {
                Label(
                    String(localized: "Hide Hidden Attackers", bundle: .module),
                    systemImage: "eye.slash"
                )
            }
        }
        .padding(BattleRoundSpacing.loose)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: BattleRoundSpacing.cardCornerRadius))
        .padding(.horizontal, BattleRoundSpacing.standard)
        .padding(.top, BattleRoundSpacing.standard)
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
        VStack(alignment: .leading, spacing: BattleRoundSpacing.standard) {
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
}

private struct BattleRoundPatternAddRow: View {
    let kind: BattleValueKind
    let settings: BattleRoundSettingsModel
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

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
                screenModel.selectConfiguredValue(kind)
            }
            .labelStyle(.iconOnly)
        }
        .battleLinkCharacterDropDestination { values, _ in
            guard let value = values.first else { return false }
            return screenModel.useDroppedConfiguredValue(value, kind: kind, controller: controller)
        }
    }

    private func addTypedName() {
        guard settings.addName(newName, for: kind) else { return }
        newName = ""
        controller.refreshConfiguredValues()
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
        .background(.fill.tertiary, in: .rect(cornerRadius: BattleRoundSpacing.rowCornerRadius))
    }
}

#Preview("Battle settings", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let screenModel = BattleRoundScreenModel(model: controller.model)
    let defaults = UserDefaults(suiteName: "BattleRoundSettingsPreview") ?? .standard
    let settings = BattleRoundSettingsModel(defaults: defaults)

    BattleRoundSettingsView(
        settings: settings,
        controller: controller,
        screenModel: screenModel
    )
}
