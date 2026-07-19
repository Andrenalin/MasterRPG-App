// @copyright André Trettin

import CharacterRPG
import CoreRPG
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

public struct BattleRoundView: View {
    public init(model: BattleRoundModel, actions: BattleRoundActions) {
        self.model = model
        self.actions = actions
    }

    let model: BattleRoundModel
    let actions: BattleRoundActions

    @Environment(MapRootModel.self) private var root
    @Environment(ScenesManager.self) private var scenesManager
    @State private var presentation: BattleRoundPresentation?
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
                        showCharacter: showCharacterSheet
                    )
                } else {
                    BattleRoundEmptyState(isRunning: model.isRunning, start: actions.start)
                }
            }
            .navigationTitle(Text("Battle Round", bundle: .module))
            .battleInlineNavigationTitle()
        }
        .sheet(item: $presentation) { presentation in
            switch presentation {
            case .sheet(let sheet):
                BattleCharacterSheetPresentationView(presentation: sheet)
            case .selection:
                ManagedPresentationView {
                    root.viewController.characterSelection(
                        root: root,
                        selectionModel: selectedCharacter
                    )
                }
            }
        }
        .onChange(of: selectedCharacter.selection) { _, selection in
            guard let combatantId = pendingCharacterCombatantId,
                  let characterId = selection.first?.itemId else { return }
            actions.assignCharacter(combatantId, characterId)
            pendingCharacterCombatantId = nil
            selectedCharacter.resetSelection(itemId: nil, entryId: nil)
            if case .selection = presentation {
                presentation = nil
            }
        }
    }

    private func showCharacterSheet(_ combatant: BattleCombatant) {
        if let sheet = BattleCharacterSheetFactory(root: root).presentation(for: combatant) {
            presentation = .sheet(sheet)
            return
        }
        pendingCharacterCombatantId = combatant.id
        selectedCharacter.resetSelection(itemId: nil, entryId: nil)
#if os(macOS)
        root.characterRoot.itemSelectionModel = selectedCharacter
        scenesManager.openWindow(SceneId.sceneId(for: .value))
#else
        presentation = .selection(combatant.id)
#endif
    }
}

private enum BattleRoundPresentation: Identifiable {
    case sheet(BattleCharacterSheetPresentation)
    case selection(UUID)

    var id: UUID {
        switch self {
        case .sheet(let sheet): sheet.id
        case .selection(let combatantId): combatantId
        }
    }
}

private struct BattleCharacterSheetPresentationView: View {
    let presentation: BattleCharacterSheetPresentation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SheetRootView(
                root: presentation.root,
                rootModel: presentation.sheet,
                linkTypes: EmptyLinkTransferable.self
            )
            .navigationTitle(Text(verbatim: presentation.name))
            .battleInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
        }
    }
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

private struct BattleRoundList: View {
    private static let dragPayloadPrefix = "masterrpg-battle-entry:"

    let model: BattleRoundModel
    let actions: BattleRoundActions
    let showCharacter: @MainActor (BattleCombatant) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Turn Order", bundle: .module)
                        .font(.headline)

                    Spacer()

                    Label {
                        Text("Drag to reorder", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                ForEach(model.entries) { entry in
                    BattleRoundCard(
                        model: model,
                        entry: entry,
                        rank: rank(for: entry),
                        actions: actions,
                        showCharacter: showCharacter,
                        assignCharacter: actions.assignCharacter
                    )
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    #if !os(tvOS)
                    .draggable(dragPayload(for: entry))
                    .dropDestination(for: String.self) { payloads, _ in
                        return reorder(payloads, over: entry)
                    }
                    #endif
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(
                accessibilityReduceMotion ? nil : .snappy,
                value: model.entries.map(\.id)
            )
        }
    }

    private func rank(for entry: BattleRoundEntry) -> Int {
        (model.entries.firstIndex(where: { $0.id == entry.id }) ?? 0) + 1
    }

    private func dragPayload(for entry: BattleRoundEntry) -> String {
        Self.dragPayloadPrefix + entry.id.uuidString
    }

    private func reorder(_ payloads: [String], over target: BattleRoundEntry) -> Bool {
        guard let payload = payloads.first,
              payload.hasPrefix(Self.dragPayloadPrefix),
              let sourceId = UUID(
                  uuidString: String(payload.dropFirst(Self.dragPayloadPrefix.count))
              ),
              let sourceIndex = model.entries.firstIndex(where: { $0.id == sourceId }),
              let targetIndex = model.entries.firstIndex(where: { $0.id == target.id }) else {
            return false
        }
        guard sourceIndex != targetIndex else { return true }

        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        actions.moveEntries(IndexSet(integer: sourceIndex), destination)
        return true
    }
}

private struct BattleRoundCard: View {
    let model: BattleRoundModel
    let entry: BattleRoundEntry
    let rank: Int
    let actions: BattleRoundActions
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        if let attacker = model.attacker(for: entry) {
            let isActive = model.activeAttackerId == attacker.id
            let defenders = model.defenders(for: entry)

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
            .padding(10)
            .background(
                isActive ? Color.blue.opacity(0.14) : Color.gray.opacity(0.07),
                in: .rect(cornerRadius: 12)
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 12
                )
                .fill(isActive ? .blue : .clear)
                .frame(width: 4)
                .accessibilityHidden(true)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isActive ? Color.blue.opacity(0.65) : .clear,
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
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BattleRankBadge(rank: rank, isActive: isActive)
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
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                BattleRankBadge(rank: rank, isActive: isActive)
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
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void

    var body: some View {
        BattleParticipantColumn(
            combatant: attacker,
            rolls: model.rolls(for: attacker.id, in: entry),
            isAttacker: true,
            isActive: isActive,
            tint: isActive ? .blue : .gray,
            canReceiveRoll: !attacker.isPlayer && (isActive || model.isPreparingSurprise),
            isRollRecipient: model.masterRollRecipientCombatantId == attacker.id,
            showCharacter: showCharacter,
            assignCharacter: assignCharacter,
            selectRollRecipient: actions.selectRollRecipient,
            toggleDead: { actions.setDead(attacker.id, !attacker.isDead) }
        )
    }
}

private struct BattleRankBadge: View {
    let rank: Int
    let isActive: Bool

    var body: some View {
        Text(rank, format: .number)
            .font(.callout.bold().monospacedDigit())
            .foregroundStyle(isActive ? .white : .gray)
            .frame(minWidth: 28, minHeight: 28)
            .background(isActive ? Color.blue : Color.gray.opacity(0.14), in: .circle)
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
                if isActive {
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
    let showCharacter: @MainActor (BattleCombatant) -> Void
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
                            isActive: isActiveEntry,
                            tint: isActiveEntry ? .red : .gray,
                            canReceiveRoll: isActiveEntry && !defender.isPlayer,
                            isRollRecipient: model.masterRollRecipientCombatantId == defender.id,
                            showCharacter: showCharacter,
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
    let tint: Color
    let canReceiveRoll: Bool
    let isRollRecipient: Bool
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let assignCharacter: @MainActor (UUID, UUID) -> Void
    let selectRollRecipient: @MainActor (UUID) -> Void
    let toggleDead: @MainActor () -> Void

    @Environment(MapRootModel.self) private var root

    var body: some View {
        VStack(spacing: 4) {
            Button {
                showCharacter(combatant)
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
                    color: isActive ? tint.opacity(0.5) : .black.opacity(0.2),
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

            HStack(spacing: 6) {
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
                    .foregroundStyle(isRollRecipient ? tint : .secondary)
                    .help(Text("Assign the next master roll to this combatant", bundle: .module))
                    .accessibilityValue(
                        Text(isRollRecipient ? "Selected" : "Not selected", bundle: .module)
                    )
                }

                Button(
                    combatant.isDead ? "Mark Alive" : "Mark Dead",
                    systemImage: combatant.isDead ? "heart.fill" : "skull.fill",
                    action: toggleDead
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(combatant.isDead ? .green : .red)
                .help(
                    Text(
                        combatant.isDead ? "Mark Alive" : "Mark Dead",
                        bundle: .module
                    )
                )
            }

            BattleRollResults(results: rolls, tint: tint)

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
        if isRollRecipient || isActive { return tint }
        return .gray.opacity(0.45)
    }

    private var haloWidth: CGFloat {
        isRollRecipient || isActive ? 3 : 1
    }

    private var hasCharacter: Bool {
        combatant.gameCharacterId != nil || combatant.sourceCharacterId != nil
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

private struct BattleCharacterSheetPresentation: Identifiable {
    let id: UUID
    let name: String
    let root: ItemRootController
    let sheet: SheetRootModel
}

@MainActor
private struct BattleCharacterSheetFactory {
    let root: MapRootModel

    func presentation(for combatant: BattleCombatant) -> BattleCharacterSheetPresentation? {
        let characterRoot = root.characterRoot
        guard let baseRootManager = characterRoot.rootManager else { return nil }

        let itemId: UUID
        let sheetRootManager: RootManager
        if let gameCharacterId = combatant.gameCharacterId,
           let clone = characterRoot.valueGameControllable.battleCharacterCopy(for: gameCharacterId) {
            let items: [UUID: any ItemDataAccessable] = [clone.id: clone]
            itemId = clone.id
            sheetRootManager = baseRootManager.with(
                reviewSheetMemory: ReviewSheetMemory(items: [.value: items])
            )
        } else if let sourceCharacterId = combatant.sourceCharacterId {
            itemId = sourceCharacterId
            sheetRootManager = baseRootManager
        } else {
            return nil
        }

        let controller = characterRoot.rootController
        let sheet = SheetRootModel(
            rootManager: sheetRootManager,
            linkControllable: controller.linkControllable,
            sheetControllable: controller.sheetControllable,
            itemId: itemId,
            isEditor: false
        )
        return BattleCharacterSheetPresentation(
            id: combatant.id,
            name: combatant.name,
            root: controller,
            sheet: sheet
        )
    }
}

private extension View {
    @ViewBuilder
    func battleInitiativeTextFieldStyle() -> some View {
#if os(tvOS)
        self
#else
        textFieldStyle(.roundedBorder)
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
