// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Overlay control for adding a plain-text entry to a character sheet during play.
///
/// Mirrors the position and interaction of `sheetAIAssistant` (Ask AI) used by other
/// modules' game views, but performs no AI generation: the typed text is split into
/// a name/content pair and saved directly as a new `ValueEntryModel` via the
/// `EditController`. Bypasses `EntryDataEditable.add(entry:itemId:)`, so it must
/// reconcile the live game view's `SheetRootModel` itself afterward — per
/// `Docu/SHEETS.md`, a `SheetModel` tree never re-derives from domain changes on
/// its own — see `addForcingPersistence(entry:)`.
extension View {
    func characterAddEntryOverlay(root: CharacterRootModel, itemId: UUID) -> some View {
        safeAreaInset(edge: .bottom, alignment: .center, spacing: 12) {
            Color.clear
                .frame(height: 80)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            CharacterAddEntryOverlayContent(root: root, itemId: itemId)
                .padding(.horizontal)
                .padding(.bottom)
        }
    }
}

/// Keeps the glass node alive while its contents expand, matching
/// `SheetAIAssistantContent`'s rationale for the Ask AI control.
struct CharacterAddEntryOverlayContent: View {
    let root: CharacterRootModel
    let itemId: UUID

    var body: some View {
        GlassEffectContainerAll {
            CharacterAddEntryControl(root: root, itemId: itemId)
        }
    }
}

struct CharacterAddEntryControl: View {
    let root: CharacterRootModel
    let itemId: UUID

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFieldFocused: Bool

    @State private var isExpanded = false
    @State private var text = ""

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                toggle()
            } label: {
                Label {
                    Text(isExpanded ? "Hide Add Entry" : "Add Entry", bundle: .module)
                } icon: {
                    Image(systemName: "plus")
                        .imageScale(.large)
                        .padding(10)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            if isExpanded {
                TextField(
                    String(localized: "Name: content", bundle: .module),
                    text: $text
                )
                .textFieldStyle(.plain)
                .focused($isTextFieldFocused)
                .onSubmit(submit)
                .onKeyPress(.return) {
                    submit()
                    return .handled
                }
#if os(iOS)
                .submitLabel(.send)
#endif
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(theme.background(for: .value), in: .capsule)
                .overlay {
                    fieldBorderShape
                        .strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .foregroundStyle(theme.foregroundColor)
        .padding(.horizontal, isExpanded ? 12 : 0)
        .padding(.vertical, isExpanded ? 8 : 0)
        .animation(reduceMotion ? nil : .smooth, value: isExpanded)
#if os(visionOS)
        .background(.regularMaterial, in: .capsule)
#else
        .glassEffectAll(
            .regular.tint(theme.tint(for: .value)).interactive(),
            in: .capsule
        )
#endif
    }

    private var fieldBorderShape: some InsettableShape {
        .capsule
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .smooth) {
            isExpanded.toggle()
        }
        if isExpanded {
            Task {
                await Task.yield()
                isTextFieldFocused = true
            }
        } else {
            isTextFieldFocused = false
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let content = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""

        let entry = root.editController.create(name: name, content: content)
        addForcingPersistence(entry: entry)

        text = ""
        isTextFieldFocused = false
        withAnimation(reduceMotion ? nil : .smooth) {
            isExpanded = false
        }
    }

    /// `EntryDataEditable.add(entry:itemId:)` saves without `forceSave`, which
    /// `ItemControllable.replace` routes into game-session memory only while a
    /// game is running — it never reaches permanent storage. Entries added here
    /// are meant to outlive the session, so persist with `forceSave: true`,
    /// mirroring how `updateValue`'s `saveGameDataToPermanent` forces game edits
    /// back to the permanent item.
    private func addForcingPersistence(entry: ValueEntryModel) {
        guard let item = root.editController.editModel(for: itemId) else { return }
        item.entries.append(entry)
        root.editController.save(
            updated: item,
            message: String(localized: "Add entry", bundle: .module).localizedString,
            forceSave: true
        )
        // Reconcile the live game view's own SheetRootModel — this bypassed
        // EntryDataEditable.add(entry:itemId:), so nothing else does it.
        root.editController.editorModel.gameSheetRootModel?.updateFromRoot()
    }
}

#Preview("Character Add Entry") {
    @Previewable @Environment(\.appTheme) var theme
    let backgroundShape: some Shape = .rect
    backgroundShape.fill(theme.backgroundGradient)
        .overlay {
            CharacterAddEntryOverlayContent(root: .preview, itemId: UUID())
                .padding()
        }
}
