// @copyright André Trettin

import SwiftUI

public struct ItemHeaderEditorView: View {
    public init(
        editControllable: any EditControllable,
        model: any ItemDataAccessible,
        module: NetworkModules,
        dismiss: @escaping () -> Void
    ) {
        self.editControllable = editControllable
        self.model = model
        self.module = module
        self.dismissAction = dismiss

        // Initialize @State properties with model values
        self._attributedName = State(initialValue: AttributedString(model.name))
        self._attributedInformation = State(initialValue: AttributedString(model.description))
        self._category = State(initialValue: model.category)
        self._tags = State(initialValue: model.tags)
    }

    let editControllable: any EditControllable
    let model: any ItemDataAccessible
    let module: NetworkModules
    let dismissAction: () -> Void

    enum FocusField {
        case name
        case information
    }
    @FocusState private var currentFocus: FocusField?

    @State private var attributedName: AttributedString
    @State private var attributedInformation: AttributedString
    @State private var category: ItemListCategory
    @State private var tags: [String]
    /// Triggers the save haptic (`sensoryFeedback` fires when its trigger changes).
    @State private var saveCount = 0
    /// A second tap (or Return) during the settle delay before the dismissal would save again. See CODE_AUDIT_28 §8.4.
    @State private var hasSaved = false

    private var isNameValid: Bool {
        !String(attributedName.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        GlassEffectContainerAll {
            ItemHeaderEditorCard(
                module: module,
                dismissAction: dismissAction,
                saveAction: saveChanges,
                isSaveEnabled: isNameValid,
                attributedName: $attributedName,
                attributedInformation: $attributedInformation,
                tags: $tags,
                tagController: editControllable.tagController,
                tagModule: editControllable.itemControllable.config.module,
                currentFocus: $currentFocus
            )
        }
        .frame(maxWidth: 800)
        .padding()
        .modifier(ItemHeaderEditorPlacement(dismissAction: dismissAction))
        .preference(key: EditorOverlayPresentedPreferenceKey.self, value: true)
        .sensoryFeedback(.success, trigger: saveCount)
        .task {
#if !os(tvOS)
            try? await Task.sleep(for: EditorFocus.autoFocusDelay)
            // A cancelled sleep (the editor went away) must not move focus.
            guard !Task.isCancelled else { return }
            currentFocus = .name
#endif
        }
#if os(macOS)
        .onKeyPress(.escape) {
            dismissAction()
            return .handled
        }
#endif
    }

    private func saveChanges() {
        guard !hasSaved else { return }
        hasSaved = true
        let trimmedName = String(attributedName.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        editControllable.update(
            id: model.id,
            name: trimmedName,
            description: String(attributedInformation.characters),
            category: category,
            tags: tags,
            // The standalone item editor always persists, even while a game is
            // running — unlike in-game quick-edit surfaces, which stay memory-only.
            forceSave: true
        )

        saveCount += 1

        // The haptic is driven by a view update, so the editor must still be on screen for it:
        // dismiss one short beat later instead of in the same update.
        delayedTask(.settleDelay) {
            dismissAction()
        }
    }
}

/// Tells the screen behind an editor overlay (`ItemHeaderEditorView`, `EntryEditorView`) that the
/// editor covers it, so floating controls such as the Ask AI button can step aside.
public struct EditorOverlayPresentedPreferenceKey: PreferenceKey {
    public static let defaultValue = false

    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private extension View {
    @ViewBuilder
    func itemHeaderEditorGlass(tint: Color) -> some View {
#if os(visionOS)
        self
#else
        glassEffectAll(
            .regular.tint(tint.opacity(0.18)),
            in: .rect(cornerRadius: 28, style: .continuous)
        )
#endif
    }
}

// MARK: - Placement

/// Centers the card over a dimmed backdrop that dismisses the editor.
///
/// On iPhone and iPad the software keyboard can leave less room than the card needs. A centered
/// card then grows out of both ends of that room and covers the navigation bar buttons, so there
/// the card scrolls instead.
private struct ItemHeaderEditorPlacement: ViewModifier {
    let dismissAction: () -> Void

#if os(iOS)
    @State private var visibleHeight: CGFloat = 0
#endif

    func body(content: Content) -> some View {
#if os(iOS)
        ScrollView {
            ItemHeaderEditorViewportLayout(visibleHeight: visibleHeight) {
                content
            }
            .background {
                // A scroll view takes the taps on its empty area, so the dismiss button
                // has to be part of the scroll content.
                ItemHeaderEditorDismissButton(dismissAction: dismissAction) {
                    Color.clear
                        .contentShape(.rect)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .mask {
            // Scroll content would otherwise pass under the navigation bar buttons.
            Rectangle()
                .ignoresSafeArea(edges: [.horizontal, .bottom])
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newValue in
            visibleHeight = newValue
        }
        .background {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
        }
#else
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background {
                ItemHeaderEditorDismissButton(dismissAction: dismissAction) {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                }
            }
#endif
    }
}

#if os(iOS)
/// Offers the scroll view's visible height to the card, which a scroll view itself never does:
/// the description gets shorter before the card has to scroll, and a card with room to spare is
/// centered.
private struct ItemHeaderEditorViewportLayout: Layout {
    let visibleHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let cardSize = subviews.first?.sizeThatFits(cardProposal(width: proposal.width)) ?? .zero
        return CGSize(
            width: proposal.width ?? cardSize.width,
            height: max(cardSize.height, visibleHeight)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: cardProposal(width: bounds.width)
        )
    }

    private func cardProposal(width: CGFloat?) -> ProposedViewSize {
        ProposedViewSize(width: width, height: visibleHeight)
    }
}
#endif

private struct ItemHeaderEditorDismissButton<Backdrop: View>: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let dismissAction: () -> Void
    @ViewBuilder let backdrop: Backdrop

    var body: some View {
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                dismissAction()
            }
        } label: {
            backdrop
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}

// MARK: - Extracted subviews (CODE_AUDIT §8.2)
//
// Each gives SwiftUI its own diffing boundary, instead of the previous computed `some View`
// properties on `ItemHeaderEditorView` itself.

private struct ItemHeaderEditorCard: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency

    let module: NetworkModules
    let dismissAction: () -> Void
    let saveAction: () -> Void
    let isSaveEnabled: Bool

    @Binding var attributedName: AttributedString
    @Binding var attributedInformation: AttributedString
    @Binding var tags: [String]
    let tagController: TagController
    /// The module the tag counts are kept under (`TagController` keys by the item controller's module).
    let tagModule: NetworkModules
    var currentFocus: FocusState<ItemHeaderEditorView.FocusField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ItemHeaderEditorHeaderRow(dismissAction: dismissAction, saveAction: saveAction, isSaveEnabled: isSaveEnabled)
            ItemHeaderEditorNameSection(attributedName: $attributedName, currentFocus: currentFocus)
            ItemHeaderEditorDescriptionSection(attributedInformation: $attributedInformation, currentFocus: currentFocus)
            ItemHeaderEditorTagsSection(tags: $tags, tagController: tagController, module: tagModule)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.panelColor.opacity(accessibilityReduceTransparency ? 1 : 0.58))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(theme.tint(for: module).opacity(0.45), lineWidth: 1)
        }
        .itemHeaderEditorGlass(tint: theme.background(for: module))
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        .containerShape(.rect(cornerRadius: 28, style: .continuous))
    }
}

private struct ItemHeaderEditorHeaderRow: View {
    let dismissAction: () -> Void
    let saveAction: () -> Void
    let isSaveEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            GlassButton(action: dismissAction) {
                Label {
                    Text("Cancel", bundle: .module)
                } icon: {
                    Image(systemName: "xmark")
                }
                .labelStyle(.iconOnly)
            }
            .buttonSizing(.fitted)
            .buttonBorderShape(.circle)
            .controlSize(.large)
#if os(macOS)
            .keyboardShortcut(.cancelAction)
#endif

            Spacer(minLength: 0)

            GlassButton(isProminent: true, action: saveAction) {
                Label {
                    Text("Save", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark")
                }
                .labelStyle(.iconOnly)
            }
            .buttonSizing(.fitted)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .disabled(!isSaveEnabled)
        }
    }
}

private struct ItemHeaderEditorNameSection: View {
    @Binding var attributedName: AttributedString
    var currentFocus: FocusState<ItemHeaderEditorView.FocusField?>.Binding

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                AttributedTextEditorSurface(
                    text: $attributedName,
                    links: [],
                    minHeight: 44,
                    maxHeight: 44,
                    isFocused: currentFocus.wrappedValue == .name,
                    layout: .singleLine
                )
                .focused(currentFocus, equals: .name)
                .onSubmit {
                    currentFocus.wrappedValue = .information
                }
                .overlay(alignment: .leading) {
                    if attributedName.characters.isEmpty {
                        Text("Enter a name", bundle: .module)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .allowsHitTesting(false)
                    }
                }

                if !attributedName.characters.isEmpty {
                    Button {
                        attributedName = AttributedString("")
                    } label: {
                        Label {
                            Text("Clear name", bundle: .module)
                        } icon: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .snappy(duration: 0.2),
            value: attributedName.characters.isEmpty
        )
    }
}

private struct ItemHeaderEditorDescriptionSection: View {
    @Binding var attributedInformation: AttributedString
    var currentFocus: FocusState<ItemHeaderEditorView.FocusField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Description", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

#if os(tvOS)
            TextField(
                text: Binding(
                    get: { String(attributedInformation.characters) },
                    set: { attributedInformation = AttributedString($0) }
                ),
                prompt: Text("Insert a description", bundle: .module),
                axis: .vertical
            ) {
                Text("Description", bundle: .module)
            }
            .lineLimit(5...10)
            .frame(minHeight: 120, maxHeight: 200)
            .border(Color.accentColor.secondary)
            .padding(.bottom, 6)
            .focused(currentFocus, equals: .information)
#else
            AttributedTextEditorSurface(
                text: $attributedInformation,
                links: [],
                minHeight: 120,
                maxHeight: 200,
                isFocused: currentFocus.wrappedValue == .information
            )
            .focused(currentFocus, equals: .information)
#endif
        }
    }
}

private struct ItemHeaderEditorTagsSection: View {
    @Binding var tags: [String]
    let tagController: TagController
    let module: NetworkModules

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)

            RemoveTagsEditor(tags: $tags)

            AddTagsEditor(tags: $tags, tagController: tagController, module: module)
        }
    }
}

#Preview("Item Header Editor") {
    ItemHeaderEditorView(
        editControllable: FakeEditController.fake,
        model: FakeItemModel(
            id: .fixture1,
            name: "Ancient Map",
            category: .album,
            description: "A weathered map showing the road to the lost keep.",
            tags: ["Map", "Quest"]
        ),
        module: .space,
        dismiss: {}
    )
    .moduleTint(.space)
    .environment(AppSettingsModel.previewFixture())
}
