// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Observation
import PhotoRPG
import SwiftUI

/// Stable, window-level actions keep networking and persistence out of the
/// individual combatant rows. Row views only edit their local text field and
/// commit one domain action when editing ends.
public struct BattleRoundActions {
    public init(
        start: @escaping @MainActor () -> Void,
        end: @escaping @MainActor () -> Void,
        nextAttacker: @escaping @MainActor () -> Void,
        nextRound: @escaping @MainActor () -> Void,
        setInitiative: @escaping @MainActor (UUID, Int?) -> Void,
        adjustInitiative: @escaping @MainActor (UUID, Int) -> Void,
        setInitiativeOrder: @escaping @MainActor (BattleInitiativeOrder) -> Void,
        moveEntries: @escaping @MainActor (IndexSet, Int) -> Void,
        activateAttacker: @escaping @MainActor (UUID) -> Void,
        selectRollRecipient: @escaping @MainActor (UUID) -> Void,
        setDead: @escaping @MainActor (UUID, Bool) -> Void,
        assignCharacter: @escaping @MainActor (UUID, UUID) -> Void
    ) {
        self.start = start
        self.end = end
        self.nextAttacker = nextAttacker
        self.nextRound = nextRound
        self.setInitiative = setInitiative
        self.adjustInitiative = adjustInitiative
        self.setInitiativeOrder = setInitiativeOrder
        self.moveEntries = moveEntries
        self.activateAttacker = activateAttacker
        self.selectRollRecipient = selectRollRecipient
        self.setDead = setDead
        self.assignCharacter = assignCharacter
    }

    let start: @MainActor () -> Void
    let end: @MainActor () -> Void
    let nextAttacker: @MainActor () -> Void
    let nextRound: @MainActor () -> Void
    let setInitiative: @MainActor (UUID, Int?) -> Void
    let adjustInitiative: @MainActor (UUID, Int) -> Void
    let setInitiativeOrder: @MainActor (BattleInitiativeOrder) -> Void
    let moveEntries: @MainActor (IndexSet, Int) -> Void
    let activateAttacker: @MainActor (UUID) -> Void
    let selectRollRecipient: @MainActor (UUID) -> Void
    let setDead: @MainActor (UUID, Bool) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void
}

/// A resolved Character sheet which can be embedded beside the battle list.
///
/// The presentation deliberately exposes CoreRPG sheet primitives instead of
/// a GameRPG root. This keeps MapRPG usable by itself while allowing a game
/// container to supply richer inline sheet content without type erasure.
public struct BattleRoundCharacterDetailPresentation: Identifiable {
    public struct ID: Hashable, Sendable {
        public let entryId: UUID
        public let combatantId: UUID

        public init(entryId: UUID, combatantId: UUID) {
            self.entryId = entryId
            self.combatantId = combatantId
        }
    }

    public let entryId: UUID
    public let combatantId: UUID
    public let characterId: UUID
    public let name: String
    public let root: ItemRootController
    public let sheetRootModel: SheetRootModel

    public var id: ID { ID(entryId: entryId, combatantId: combatantId) }
}

/// The default inline Character sheet used by existing BattleRoundView
/// call-sites. A custom detail builder can replace it without changing the
/// battle list or introducing AnyView into its rows.
public struct BattleRoundInlineCharacterSheet: View {
    public init(presentation: BattleRoundCharacterDetailPresentation) {
        self.presentation = presentation
    }

    let presentation: BattleRoundCharacterDetailPresentation

    public var body: some View {
        SheetRootView(
            root: presentation.root,
            rootModel: presentation.sheetRootModel,
            linkTypes: EmptyLinkTransferable.self
        )
    }
}

public struct BattleRoundView<CharacterDetail: View>: View {
    public init(
        model: BattleRoundModel,
        actions: BattleRoundActions,
        @ViewBuilder characterDetail: @escaping (BattleRoundCharacterDetailPresentation) -> CharacterDetail
    ) {
        self.model = model
        self.actions = actions
        self.characterDetail = characterDetail
    }

    let model: BattleRoundModel
    let actions: BattleRoundActions
    let characterDetail: (BattleRoundCharacterDetailPresentation) -> CharacterDetail

    @Environment(MapRootModel.self) private var root
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var inlineSelection = BattleRoundInlineCharacterSelection()
    @State private var characterSelectionPresentation: BattleRoundCharacterSelectionPresentation?
    @State private var pendingCharacterCombatantId: UUID?
    @State private var selectedCharacter = ItemSelectionModel(
        isSingleSelection: true,
        allowCollections: false
    )

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BattleRoundHeader(model: model, actions: actions)

                if model.isRunning, !model.entries.isEmpty {
                    BattleRoundList(
                        model: model,
                        actions: actions,
                        inlineCharacter: inlineSelection.presentation,
                        showCharacter: showCharacter,
                        characterDetail: inlineSelection.presentation.map(characterDetail)
                    )
                } else {
                    BattleRoundEmptyState(isRunning: model.isRunning, start: actions.start)
                }
            }
            .navigationTitle(Text("Battle Round", bundle: .module))
            .battleInlineNavigationTitle()
        }
        .sheet(item: $characterSelectionPresentation) { _ in
            ManagedPresentationView {
                root.viewController.characterSelection(
                    root: root,
                    selectionModel: selectedCharacter
                )
            }
        }
        .onChange(of: selectedCharacter.selection) { _, selection in
            guard let combatantId = pendingCharacterCombatantId,
                  let characterId = selection.first?.itemId else { return }
            actions.assignCharacter(combatantId, characterId)
            pendingCharacterCombatantId = nil
            selectedCharacter.resetSelection(itemId: nil, entryId: nil)
            characterSelectionPresentation = nil
        }
        .onChange(of: model.combatants) { _, combatants in
            inlineSelection.retainSelection(in: combatants, entries: model.entries)
        }
        .onChange(of: model.entries) { _, entries in
            inlineSelection.retainSelection(in: model.combatants, entries: entries)
        }
        .onChange(of: model.isRunning) { _, isRunning in
            guard !isRunning else { return }
            inlineSelection.clear()
        }
    }

    private func showCharacter(entry: BattleRoundEntry, combatant: BattleCombatant) {
        if inlineSelection.presentation?.entryId == entry.id,
           inlineSelection.presentation?.combatantId == combatant.id {
            withAnimation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2)) {
                inlineSelection.clear()
            }
            return
        }

        if let presentation = BattleRoundCharacterDetailResolver(root: root).presentation(
            entryId: entry.id,
            for: combatant
        ) {
            withAnimation(accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2)) {
                inlineSelection.toggle(presentation)
            }
            return
        }

        inlineSelection.clear()
        pendingCharacterCombatantId = combatant.id
        selectedCharacter.resetSelection(itemId: nil, entryId: nil)
#if os(macOS)
        root.characterRoot.itemSelectionModel = selectedCharacter
        scenesManager.openWindow(SceneId.sceneId(for: .value))
#else
        characterSelectionPresentation = BattleRoundCharacterSelectionPresentation(
            combatantId: combatant.id
        )
#endif
    }
}

public extension BattleRoundView where CharacterDetail == BattleRoundInlineCharacterSheet {
    init(model: BattleRoundModel, actions: BattleRoundActions) {
        self.init(model: model, actions: actions) { presentation in
            BattleRoundInlineCharacterSheet(presentation: presentation)
        }
    }
}

@MainActor @Observable
final class BattleRoundInlineCharacterSelection {
    private(set) var presentation: BattleRoundCharacterDetailPresentation?

    func toggle(_ newPresentation: BattleRoundCharacterDetailPresentation) {
        if presentation?.entryId == newPresentation.entryId,
           presentation?.combatantId == newPresentation.combatantId {
            presentation = nil
        } else {
            presentation = newPresentation
        }
    }

    func clear() {
        presentation = nil
    }

    func retainSelection(
        in combatants: [BattleCombatant],
        entries: [BattleRoundEntry]
    ) {
        guard let presentation else { return }
        guard combatants.contains(where: { $0.id == presentation.combatantId }),
              let entry = entries.first(where: { $0.id == presentation.entryId }),
              entry.attackerId == presentation.combatantId
                || entry.defenderIds.contains(presentation.combatantId) else {
            self.presentation = nil
            return
        }
    }
}

private struct BattleRoundCharacterSelectionPresentation: Identifiable {
    let combatantId: UUID
    var id: UUID { combatantId }
}

private struct BattleRoundHeader: View {
    let model: BattleRoundModel
    let actions: BattleRoundActions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                BattleRoundHeading(model: model)
                Spacer(minLength: 8)
                BattleInitiativeOrderMenu(
                    selection: initiativeOrderBinding,
                    isDisabled: model.isRunning && model.entries.isEmpty
                )
                BattleRoundHeaderActions(model: model, actions: actions)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    BattleRoundHeading(model: model)
                    Spacer(minLength: 4)
                    BattleInitiativeOrderMenu(
                        selection: initiativeOrderBinding,
                        isDisabled: model.isRunning && model.entries.isEmpty
                    )
                }
                BattleRoundHeaderActions(model: model, actions: actions)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
#if os(tvOS)
        .background(Color.black.opacity(0.35))
#else
        .background(.bar)
#endif
    }

    private var initiativeOrderBinding: Binding<BattleInitiativeOrder> {
        Binding(
            get: { model.initiativeOrder },
            set: actions.setInitiativeOrder
        )
    }
}

private struct BattleRoundHeading: View {
    let model: BattleRoundModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.isRunning {
                BattleRoundHeaderTitle(round: model.roundCounter)
                    .font(.title2.bold())
                    .monospacedDigit()

                if let entry = model.activeEntry,
                   let attacker = model.attacker(for: entry) {
                    Text(attacker.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Initiative", bundle: .module)
                    .font(.title2.bold())
            }
        }
    }
}

private struct BattleInitiativeOrderMenu: View {
    @Binding var selection: BattleInitiativeOrder
    let isDisabled: Bool

    var body: some View {
        Picker("Initiative Order", selection: $selection) {
            Label {
                Text("Descending", bundle: .module)
            } icon: {
                Image(systemName: "arrow.down")
            }
            .tag(BattleInitiativeOrder.descending)

            Label {
                Text("Ascending", bundle: .module)
            } icon: {
                Image(systemName: "arrow.up")
            }
            .tag(BattleInitiativeOrder.ascending)
        }
        .pickerStyle(.menu)
        .disabled(isDisabled)
    }
}

private struct BattleRoundHeaderActions: View {
    let model: BattleRoundModel
    let actions: BattleRoundActions

    var body: some View {
        HStack(spacing: 8) {
            if model.isRunning {
                Button("Next Turn", systemImage: "person.line.dotted.person.fill", action: actions.nextAttacker)
                    .buttonStyle(.bordered)

                Button("Next Round", systemImage: "chevron.right.2", action: actions.nextRound)
                    .buttonStyle(.borderedProminent)

                Menu {
                    Button("End Battle", systemImage: "stop.fill", role: .destructive, action: actions.end)
                } label: {
                    Label("More Battle Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
            } else {
                Button("Start Battle", systemImage: "play.fill", action: actions.start)
                    .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.small)
    }
}

private struct BattleRoundHeaderTitle: View {
    let round: Int

    var body: some View {
        if round == 0 {
            Text("Surprise", bundle: .module)
        } else {
            Text("Round \(round)", bundle: .module)
        }
    }
}

private struct BattleRoundEmptyState: View {
    let isRunning: Bool
    let start: @MainActor () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(isRunning ? "No Combatants" : "No Battle Running", bundle: .module)
            } icon: {
                Image(systemName: "shield.lefthalf.filled")
            }
        } description: {
            Text(
                isRunning
                    ? "The selected map has no player or active-room combatants."
                    : "Start a battle with player pins and the monsters in the selected room.",
                bundle: .module
            )
        } actions: {
            if !isRunning {
                Button("Start Battle", systemImage: "play.fill", action: start)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BattleRoundList<CharacterDetail: View>: View {
    let model: BattleRoundModel
    let actions: BattleRoundActions
    let inlineCharacter: BattleRoundCharacterDetailPresentation?
    let showCharacter: @MainActor (BattleRoundEntry, BattleCombatant) -> Void
    let characterDetail: CharacterDetail?

    var body: some View {
        List {
            Section {
                ForEach(model.entries) { entry in
                    BattleRoundCard(
                        model: model,
                        entry: entry,
                        rank: rank(for: entry),
                        actions: actions,
                        inlineCharacter: inlineCharacter,
                        showCharacter: showCharacter,
                        assignCharacter: actions.assignCharacter,
                        characterDetail: characterDetail
                    )
                    .listRowBackground(Color.clear)
                    .battleHiddenRowSeparator()
                    .listRowInsets(
                        EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
                    )
                }
                .onMove(perform: actions.moveEntries)
            } header: {
                HStack {
                    Text("Turn Order", bundle: .module)
                    Spacer()
                    Text("Drag to reorder", bundle: .module)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .battleInitiativeListStyle()
        .battleAlwaysEditableList()
    }

    private func rank(for entry: BattleRoundEntry) -> Int {
        (model.entries.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1
    }
}

private struct BattleRoundCard<CharacterDetail: View>: View {
    let model: BattleRoundModel
    let entry: BattleRoundEntry
    let rank: Int
    let actions: BattleRoundActions
    let inlineCharacter: BattleRoundCharacterDetailPresentation?
    let showCharacter: @MainActor (BattleRoundEntry, BattleCombatant) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void
    let characterDetail: CharacterDetail?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        if let attacker = model.attacker(for: entry) {
            let isActive = model.activeAttackerId == attacker.id
            let defenders = model.defenders(for: entry)

            VStack(spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    BattleRoundWideCardLayout(
                        model: model,
                        entry: entry,
                        attacker: attacker,
                        defenders: defenders,
                        rank: rank,
                        isActive: isActive,
                        actions: actions,
                        showCharacter: showCharacter,
                        assignCharacter: assignCharacter
                    )

                    BattleRoundCompactCardLayout(
                        model: model,
                        entry: entry,
                        attacker: attacker,
                        defenders: defenders,
                        rank: rank,
                        isActive: isActive,
                        actions: actions,
                        showCharacter: showCharacter,
                        assignCharacter: assignCharacter
                    )
                }

                if let inlineCharacter,
                   inlineCharacter.entryId == entry.id,
                   let characterDetail {
                    Divider()
                        .padding(.vertical, 10)

                    characterDetail
                        .id(inlineCharacter.id)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(10)
            .background(
                isActive ? attacker.color.opacity(0.14) : Color.secondary.opacity(0.07),
                in: .rect(cornerRadius: 12)
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 12
                )
                .fill(isActive ? attacker.color : .clear)
                .frame(width: 4)
                .accessibilityHidden(true)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isActive ? attacker.color.opacity(0.65) : .clear,
                        lineWidth: 1
                    )
                    .accessibilityHidden(true)
            }
            .opacity(attacker.isDead ? 0.58 : 1)
            .animation(
                accessibilityReduceMotion ? nil : .easeInOut(duration: 0.2),
                value: isActive
            )
            .accessibilityElement(children: .contain)
        }
    }
}

private struct BattleRoundWideCardLayout: View {
    let model: BattleRoundModel
    let entry: BattleRoundEntry
    let attacker: BattleCombatant
    let defenders: [BattleCombatant]
    let rank: Int
    let isActive: Bool
    let actions: BattleRoundActions
    let showCharacter: @MainActor (BattleRoundEntry, BattleCombatant) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BattleRankBadge(rank: rank, color: attacker.color, isActive: isActive)
            BattleAttackerPhoto(
                model: model,
                entry: entry,
                attacker: attacker,
                isActive: isActive,
                actions: actions,
                showCharacter: showCharacter,
                assignCharacter: assignCharacter
            )
            BattleAttackerDetails(combatant: attacker, isActive: isActive, actions: actions)
            Spacer(minLength: 8)
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .padding(.top, 20)
                .accessibilityHidden(true)
            BattleDefenderStrip(
                model: model,
                entry: entry,
                defenders: defenders,
                isActiveEntry: isActive,
                actions: actions,
                showCharacter: showCharacter,
                assignCharacter: assignCharacter
            )
        }
    }
}

private struct BattleRoundCompactCardLayout: View {
    let model: BattleRoundModel
    let entry: BattleRoundEntry
    let attacker: BattleCombatant
    let defenders: [BattleCombatant]
    let rank: Int
    let isActive: Bool
    let actions: BattleRoundActions
    let showCharacter: @MainActor (BattleRoundEntry, BattleCombatant) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                BattleRankBadge(rank: rank, color: attacker.color, isActive: isActive)
                BattleAttackerPhoto(
                    model: model,
                    entry: entry,
                    attacker: attacker,
                    isActive: isActive,
                    actions: actions,
                    showCharacter: showCharacter,
                    assignCharacter: assignCharacter
                )
                BattleAttackerDetails(combatant: attacker, isActive: isActive, actions: actions)
                Spacer(minLength: 0)
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
                    .accessibilityHidden(true)
                BattleDefenderStrip(
                    model: model,
                    entry: entry,
                    defenders: defenders,
                    isActiveEntry: isActive,
                    actions: actions,
                    showCharacter: showCharacter,
                    assignCharacter: assignCharacter
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

private struct BattleAttackerPhoto: View {
    let model: BattleRoundModel
    let entry: BattleRoundEntry
    let attacker: BattleCombatant
    let isActive: Bool
    let actions: BattleRoundActions
    let showCharacter: @MainActor (BattleRoundEntry, BattleCombatant) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void

    var body: some View {
        BattleParticipantColumn(
            combatant: attacker,
            rolls: model.rolls(for: attacker.id, in: entry),
            isAttacker: true,
            isActive: isActive,
            canReceiveRoll: isActive,
            isRollRecipient: model.rollRecipientCombatantId == attacker.id,
            showCharacter: { showCharacter(entry, attacker) },
            assignCharacter: assignCharacter,
            selectRollRecipient: actions.selectRollRecipient,
            toggleDead: { actions.setDead(attacker.id, !attacker.isDead) }
        )
    }
}

private struct BattleRankBadge: View {
    let rank: Int
    let color: Color
    let isActive: Bool

    var body: some View {
        Text(rank, format: .number)
            .font(.callout.bold().monospacedDigit())
            .foregroundStyle(isActive ? .white : color)
            .frame(minWidth: 28, minHeight: 28)
            .background(isActive ? color : color.opacity(0.14), in: .circle)
            .padding(.top, 8)
            .accessibilityLabel(Text("Initiative position \(rank)", bundle: .module))
    }
}

private struct BattleAttackerDetails: View {
    let combatant: BattleCombatant
    let isActive: Bool
    let actions: BattleRoundActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(combatant.name)
                    .font(.headline)
                    .lineLimit(1)

                if combatant.isPlayer {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Player", bundle: .module))
                }
                if combatant.isDead {
                    Image(systemName: "skull.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel(Text("Dead", bundle: .module))
                }
                if combatant.isHighlighted {
                    Image(systemName: "scope")
                        .foregroundStyle(.blue)
                        .accessibilityLabel(Text("Highlighted", bundle: .module))
                }
            }

            BattleInitiativeEditor(
                combatantId: combatant.id,
                value: combatant.initiative,
                setValue: actions.setInitiative,
                adjust: actions.adjustInitiative
            )

            Button(
                isActive ? "Active Attacker" : "Make Active",
                systemImage: isActive ? "scope" : "scope",
                action: { actions.activateAttacker(combatant.id) }
            )
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(isActive || combatant.isDead)
        }
        .frame(minWidth: 128, alignment: .leading)
        .padding(.top, 4)
    }
}

private struct BattleInitiativeEditor: View {
    let combatantId: UUID
    let value: Int?
    let setValue: @MainActor (UUID, Int?) -> Void
    let adjust: @MainActor (UUID, Int) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Button("Decrease Initiative", systemImage: "minus") {
                commit()
                adjust(combatantId, -1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            TextField("Initiative", text: $text)
                .battleInitiativeTextFieldStyle()
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 64)
                .focused($isFocused)
                .battleNumberKeyboard()
                .onSubmit(commit)

            Button("Increase Initiative", systemImage: "plus") {
                commit()
                adjust(combatantId, 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .onChange(of: value, initial: true) { _, newValue in
            guard !isFocused else { return }
            text = newValue.map(String.init) ?? ""
        }
        .onChange(of: isFocused) { oldValue, newValue in
            guard oldValue && !newValue else { return }
            commit()
        }
        .accessibilityElement(children: .contain)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = trimmed.isEmpty ? nil : Int(trimmed)
        guard parsed != value else { return }
        setValue(combatantId, parsed)
    }
}

private struct BattleDefenderStrip: View {
    let model: BattleRoundModel
    let entry: BattleRoundEntry
    let defenders: [BattleCombatant]
    let isActiveEntry: Bool
    let actions: BattleRoundActions
    let showCharacter: @MainActor (BattleRoundEntry, BattleCombatant) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void

    var body: some View {
        if defenders.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "person.badge.plus")
                    .foregroundStyle(.tertiary)
                Text("Highlight defenders on the map", bundle: .module)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(minWidth: 100, minHeight: 74)
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(defenders) { defender in
                        BattleParticipantColumn(
                            combatant: defender,
                            rolls: model.rolls(for: defender.id, in: entry),
                            isAttacker: false,
                            isActive: false,
                            canReceiveRoll: isActiveEntry,
                            isRollRecipient: model.rollRecipientCombatantId == defender.id,
                            showCharacter: { showCharacter(entry, defender) },
                            assignCharacter: assignCharacter,
                            selectRollRecipient: actions.selectRollRecipient,
                            toggleDead: { actions.setDead(defender.id, !defender.isDead) }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: 280, alignment: .trailing)
        }
    }
}

private struct BattleParticipantColumn: View {
    let combatant: BattleCombatant
    let rolls: [BattleRollResult]
    let isAttacker: Bool
    let isActive: Bool
    let canReceiveRoll: Bool
    let isRollRecipient: Bool
    let showCharacter: @MainActor () -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void
    let selectRollRecipient: @MainActor (UUID) -> Void
    let toggleDead: @MainActor () -> Void

    @Environment(MapRootModel.self) private var root

    var body: some View {
        VStack(spacing: 4) {
            Button {
                showCharacter()
            } label: {
                ZStack {
                    root.photoRoot.viewController.mapImage(
                        root: root.photoRoot,
                        for: combatant.photoId,
                        size: CGSize(width: 48, height: 48),
                        color: combatant.color
                    )
                    .frame(width: 48, height: 48)
                    .clipShape(.circle)

                    if combatant.isDead {
                        Circle()
                            .fill(.black.opacity(0.54))
                        Image(systemName: "xmark")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                    } else if !hasCharacter {
                        Image(systemName: "person.badge.plus")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, combatant.color)
                            .padding(3)
                            .background(.black.opacity(0.55), in: .circle)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(haloColor, lineWidth: haloWidth)
                }
                .shadow(
                    color: isActive ? combatant.color.opacity(0.5) : .black.opacity(0.2),
                    radius: isActive ? 6 : 2,
                    y: 2
                )
            }
            .buttonStyle(.plain)
            .help(
                Text(
                    hasCharacter ? "Open character sheet" : "Choose a Character",
                    bundle: .module
                )
            )
            .accessibilityLabel(
                hasCharacter
                    ? Text("Open character sheet for \(combatant.name)", bundle: .module)
                    : Text("Choose a Character for \(combatant.name)", bundle: .module)
            )
            .contextMenu {
                Button(
                    combatant.isDead ? "Mark Alive" : "Mark Dead",
                    systemImage: combatant.isDead ? "heart.fill" : "skull.fill",
                    action: toggleDead
                )
            }
#if os(iOS) || os(macOS) || os(visionOS)
            .dropDestination(for: LinkCharacterData.self) { characters, _ in
                guard let character = characters.first else { return }
                assignCharacter(combatant.id, character.itemId)
            }
#endif

            if canReceiveRoll {
                Button {
                    selectRollRecipient(combatant.id)
                } label: {
                    Label {
                        Text("Roll Target", bundle: .module)
                    } icon: {
                        Image(systemName: isRollRecipient ? "dice.fill" : "dice")
                    }
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isRollRecipient ? combatant.color : .secondary)
                .help(Text("Assign the next master roll to this combatant", bundle: .module))
                .accessibilityValue(
                    Text(isRollRecipient ? "Selected" : "Not selected", bundle: .module)
                )
            }

            BattleRollResults(results: rolls, tint: combatant.color)

            if !isAttacker {
                Text(combatant.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
            }
        }
        .opacity(combatant.isDead ? 0.62 : 1)
    }

    private var haloColor: Color {
        if isRollRecipient { return combatant.color }
        if combatant.isHighlighted { return .blue }
        if isActive { return combatant.color }
        return .secondary.opacity(0.45)
    }

    private var haloWidth: CGFloat {
        isRollRecipient || combatant.isHighlighted || isActive ? 3 : 1
    }

    private var hasCharacter: Bool {
        BattleRoundCharacterDetailResolver(root: root).canPresent(combatant)
    }
}

private struct BattleRollResults: View {
    let results: [BattleRollResult]
    let tint: Color

    var body: some View {
        if !results.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 3) {
                    ForEach(results) { result in
                        Text(result.total, format: .number)
                            .font(.caption2.bold().monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.18), in: .capsule)
                            .help(result.expression.map(Text.init(verbatim:)) ?? Text("Dice result", bundle: .module))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: 76)
            .accessibilityLabel(Text("Dice results", bundle: .module))
        }
    }
}

@MainActor
struct BattleRoundCharacterDetailResolver {
    let root: MapRootModel

    func canPresent(_ combatant: BattleCombatant) -> Bool {
        resolvedCharacter(for: combatant) != nil
    }

    func presentation(
        entryId: UUID,
        for combatant: BattleCombatant
    ) -> BattleRoundCharacterDetailPresentation? {
        let characterRoot = root.characterRoot
        guard let baseRootManager = characterRoot.rootManager else { return nil }
        guard let resolvedCharacter = resolvedCharacter(for: combatant) else { return nil }

        let sheetRootManager: RootManager
        switch resolvedCharacter {
        case .runtime(_, let clone):
            let items: [UUID: any ItemDataAccessable] = [clone.id: clone]
            sheetRootManager = baseRootManager.with(
                reviewSheetMemory: ReviewSheetMemory(items: [.value: items])
            )
        case .source:
            sheetRootManager = baseRootManager
        }

        let controller = characterRoot.rootController
        let sheet = SheetRootModel(
            rootManager: sheetRootManager,
            linkControllable: controller.linkControllable,
            sheetControllable: controller.sheetControllable,
            itemId: resolvedCharacter.id,
            isEditor: false
        )
        return BattleRoundCharacterDetailPresentation(
            entryId: entryId,
            combatantId: combatant.id,
            characterId: resolvedCharacter.id,
            name: combatant.name,
            root: controller,
            sheetRootModel: sheet
        )
    }

    private func resolvedCharacter(for combatant: BattleCombatant) -> ResolvedCharacter? {
        let characterRoot = root.characterRoot
        if let gameCharacterId = combatant.gameCharacterId,
           let clone = characterRoot.valueGameControllable.battleCharacterCopy(
               for: gameCharacterId
           ) {
            return .runtime(gameCharacterId, clone)
        }
        if let sourceCharacterId = combatant.sourceCharacterId,
           characterRoot.itemControllable.itemSync(for: sourceCharacterId) != nil {
            return .source(sourceCharacterId)
        }
        return nil
    }

    private enum ResolvedCharacter {
        case runtime(UUID, ValueModel)
        case source(UUID)

        var id: UUID {
            switch self {
            case .runtime(let id, _): id
            case .source(let id): id
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func battleInitiativeListStyle() -> some View {
#if os(iOS) || os(visionOS)
        listStyle(.insetGrouped)
#elseif os(tvOS)
        listStyle(.plain)
#else
        listStyle(.inset)
#endif
    }

    @ViewBuilder
    func battleHiddenRowSeparator() -> some View {
#if os(tvOS)
        self
#else
        listRowSeparator(.hidden)
#endif
    }

    @ViewBuilder
    func battleInitiativeTextFieldStyle() -> some View {
#if os(tvOS)
        self
#else
        textFieldStyle(.roundedBorder)
#endif
    }

    @ViewBuilder
    func battleAlwaysEditableList() -> some View {
#if os(iOS) || os(visionOS)
        environment(\.editMode, .constant(.active))
#else
        self
#endif
    }

    @ViewBuilder
    func battleInlineNavigationTitle() -> some View {
#if os(iOS) || os(visionOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }

    @ViewBuilder
    func battleNumberKeyboard() -> some View {
#if os(iOS)
        keyboardType(.numberPad)
#else
        self
#endif
    }
}

#Preview("Battle Round Cards") {
    let root = MapRootModel.preview
    let model = BattleRoundModel.previewCards
    BattleRoundView(model: model, actions: .preview(model: model))
        .environment(root)
        .environment(ScenesManager())
}

@MainActor
private extension BattleRoundModel {
    static var previewCards: BattleRoundModel {
        let model = BattleRoundModel()
        let pins = MapPinModel.previewPins
        let players = pins.prefix(2).map {
            BattleCombatant(pin: $0, sourceCharacterId: nil, gameCharacterId: nil, isPlayer: true)
        }
        let monsters = pins.dropFirst(2).map {
            BattleCombatant(pin: $0, sourceCharacterId: nil, gameCharacterId: nil, isPlayer: false)
        }
        model.begin(
            mapId: MapModel.previewId,
            players: players,
            roomCombatants: monsters,
            initiativeOrder: .descending
        )
        for (index, combatant) in model.combatants.enumerated() {
            _ = model.setInitiative(18 - (index * 3), for: combatant.id)
        }
        if let first = model.entries.first {
            _ = model.activateAttacker(first.attackerId)
            _ = model.addRoll(combatantId: first.attackerId, total: 17, expression: "1d20 + 4")
            _ = model.addRoll(combatantId: first.attackerId, total: 9, expression: "1d12 + 2")
        }
        return model
    }
}

@MainActor
private extension BattleRoundActions {
    static func preview(model: BattleRoundModel) -> BattleRoundActions {
        BattleRoundActions(
            start: {},
            end: { model.end() },
            nextAttacker: { _ = model.nextAttacker() },
            nextRound: { _ = model.nextRound() },
            setInitiative: { id, value in _ = model.setInitiative(value, for: id) },
            adjustInitiative: { id, amount in _ = model.adjustInitiative(by: amount, for: id) },
            setInitiativeOrder: { order in _ = model.setInitiativeOrder(order) },
            moveEntries: model.moveEntries,
            activateAttacker: { _ = model.activateAttacker($0) },
            selectRollRecipient: { model.selectRollRecipient($0) },
            setDead: { _, _ in },
            assignCharacter: { _, _ in }
        )
    }
}
