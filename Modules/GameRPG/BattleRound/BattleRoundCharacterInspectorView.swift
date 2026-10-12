// @copyright André Trettin

#if os(macOS)
import CharacterRPG
import CoreRPG
import MapRPG
import SwiftUI

/// The battle window's inspector: the Character list.
///
/// Without a pending "choose" action it is the plain browsing list — rows are
/// dragged onto a card's avatar, "Ini:" or "HP:". After "Choose a Character"
/// or "Choose the … value" it becomes a selecting list for that one pick: a
/// click assigns, the bar on top says what is being chosen, and "Show All
/// Characters" leaves the mode. Dragging still works in both.
struct BattleRoundCharacterInspectorView: View {
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    var body: some View {
        let prompt = BattleRoundSelectionPrompt(mode: screenModel.selectionMode)

        VStack(spacing: 0) {
            if let prompt {
                BattleRoundSelectionPromptBar(prompt: prompt, cancel: screenModel.cancelSelection)
            }

            // `.selectionInline` selects on click and, like `.inspector`,
            // adds neither a toolbar nor a search field to the window.
            controller.root.characterRoot.viewController.linkListView(
                type: prompt == nil ? .inspector : .selectionInline,
                itemSelectionModel: screenModel.activeSelectionModel
            )
        }
    }
}

/// What the inspector list is waiting for, in words. `nil` for the plain
/// browsing list.
struct BattleRoundSelectionPrompt: Equatable {
    let title: String
    /// Whom or what the pick is for: the combatant, or the settings pattern.
    let detail: String?
    let systemImage: String

    init?(mode: BattleRoundSelectionMode) {
        switch mode {
        case .browse:
            return nil
        case .character(let combatantName):
            title = String(localized: "Choose a Character", bundle: .module)
            detail = combatantName
            systemImage = "person.badge.plus"
        case let .value(kind, combatantName):
            title = kind.chooseTitle
            detail = combatantName
            systemImage = kind.chooseSystemImage
        case .pattern(let kind):
            title = String(localized: "Choose Value", bundle: .module)
            detail = switch kind {
            case .initiative: String(localized: "Initiative Pattern", bundle: .module)
            case .hitPoints: String(localized: "Hit Points Pattern", bundle: .module)
            }
            systemImage = kind.chooseSystemImage
        }
    }
}

/// Shows the prompt above the list, with the way back to all Characters.
private struct BattleRoundSelectionPromptBar: View {
    let prompt: BattleRoundSelectionPrompt
    let cancel: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BattleRoundSpacing.compact) {
            Label(prompt.title, systemImage: prompt.systemImage)
                .font(.headline)

            if let detail = prompt.detail {
                Text(verbatim: detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: cancel) {
                Text("Show All Characters", bundle: .module)
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BattleRoundSpacing.loose)
        .background(.fill.quaternary)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("Choosing hit points") {
    if let prompt = BattleRoundSelectionPrompt(mode: .value(.hitPoints, combatantName: "Bone Sentinel")) {
        BattleRoundSelectionPromptBar(prompt: prompt, cancel: {})
            .frame(width: 300)
    }
}
#endif
