// @copyright André Trettin

import SwiftUI

/// Hosts "Generate" of the photo lists in the editor, like `ItemGenerationPresentationModifier`
/// hosts "Generate" of the table lists: it provides the action and presents its outcome. What it
/// makes is saved, then an alert asks whether to go to it. The alert and the Character picker of
/// "Clone Character" live here, not in the context menu, which is gone when they are needed.
///
/// During a game the action of the game is left alone (temporary map, see `GameRoot`).
struct GenerateFromPhotoPresentationModifier: ViewModifier {
    /// Saving items is editing, which tvOS does not have. See `ItemGenerationPresentationModifier`.
    private static var isSupported: Bool {
#if os(tvOS)
        false
#else
        true
#endif
    }

    let root: any ItemRootControllable

    @Environment(\.mapActions) private var mapActions
    @Environment(\.valueActions) private var valueActions
    @Environment(\.routeActions) private var routeActions

    @State private var generated: GeneratedItem?
    @State private var isGenerating = false
    /// The photo a clone is waiting for, while the user chooses the Character to clone.
    @State private var clonePhotoId: UUID?
    @State private var cloneSelection = ItemSelectionModel(isSingleSelection: true, allowCollections: false)

    struct GeneratedItem: Equatable {
        let kind: PhotoGenerationKind
        let id: UUID
        let name: String

        var module: NetworkModules {
            kind == .map ? .map : .value
        }
    }

    /// The Character module's root, to choose a Character from. Roots without a root manager
    /// (previews, extensions) can make maps only.
    private var characterRoot: ItemRootController? {
        root.rootManager?.characterRoot.rootController
    }

    func body(content: Content) -> some View {
        let providesAction = root.configurable.module == .photo && !root.itemControllable.itemDataModel.isGameMode
        content
            .transformEnvironment(\.generateFromPhotoAction) { action in
                guard providesAction else { return }
                action = GenerateFromPhotoAction(
                    id: .module(root.configurable.module),
                    kinds: Self.isSupported ? kinds : [],
                    generate: generate(_:photoId:)
                )
            }
            .alert(
                Text(titleKey, bundle: .module),
                isPresented: isPresented,
                presenting: generated
            ) { generated in
                Button(role: .cancel) {} label: {
                    Text("Cancel", bundle: .module)
                }
                Button {
                    routeActions.routePage(generated.module, generated.id, nil)
                } label: {
                    if generated.kind == .map {
                        Text("Go to Map", bundle: .module)
                    } else {
                        Text("Go to Character", bundle: .module)
                    }
                }
            } message: { generated in
                switch generated.kind {
                case .map:
                    Text("The map \(generated.name) was created from the photo. Go to the map?", bundle: .module)
                case .character:
                    Text("The character \(generated.name) was created from the photo. Go to the character?", bundle: .module)
                case .characterClone:
                    Text("The character \(generated.name) was cloned and now uses the photo. Go to the character?", bundle: .module)
                }
            }
#if !os(tvOS)
            .sizedSheet(isPresented: isChoosingClone, idealSize: .pickerSheet) {
                if let characterRoot {
                    CloneCharacterPickerView(characterRoot: characterRoot, selection: cloneSelection)
                }
            }
            .onChange(of: cloneSelection.itemId) {
                guard let characterId = cloneSelection.itemId, let photoId = clonePhotoId else { return }
                clonePhotoId = nil
                cloneSelection.resetSelection(itemId: nil, entryId: nil)
                clone(characterId: characterId, photoId: photoId)
            }
#endif
    }

    private var kinds: Set<PhotoGenerationKind> {
        characterRoot == nil ? [.map] : Set(PhotoGenerationKind.allCases)
    }

    private var titleKey: LocalizedStringKey {
        switch generated?.kind {
        case .character: "Character Created"
        case .characterClone: "Character Cloned"
        case .map, nil: "Map Created"
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { generated != nil },
            set: { if !$0 { generated = nil } }
        )
    }

    private var isChoosingClone: Binding<Bool> {
        Binding(
            get: { clonePhotoId != nil },
            set: { if !$0 { clonePhotoId = nil } }
        )
    }

    @MainActor
    private func generate(_ kind: PhotoGenerationKind, photoId: UUID) {
        guard !isGenerating else { return }
        let name = root.itemControllable.nameSync(itemId: photoId)
        switch kind {
        case .map:
            run(kind: .map, name: name) { await mapActions.quickMap(name, photoId) }
        case .character:
            run(kind: .character, name: name) { await valueActions.quickCharacter(name, photoId) }
        case .characterClone:
            // The Character is chosen first; `clone(characterId:photoId:)` does the work.
            cloneSelection.resetSelection(itemId: nil, entryId: nil)
            clonePhotoId = photoId
        }
    }

    @MainActor
    private func clone(characterId: UUID, photoId: UUID) {
        guard !isGenerating else { return }
        run(kind: .characterClone, name: nil) { await valueActions.cloneCharacter(characterId, photoId) }
    }

    /// Runs one generation at a time; a second press while it is in flight is ignored. `name` is
    /// the new item's name when it is known up front, else it is read from the new item.
    @MainActor
    private func run(kind: PhotoGenerationKind, name: String?, make: @escaping @MainActor () async -> UUID?) {
        isGenerating = true
        Task {
            defer { isGenerating = false }
            guard let id = await make() else { return }
            let resolvedName = name ?? characterRoot?.itemControllable.nameSync(itemId: id) ?? ""
            generated = GeneratedItem(kind: kind, id: id, name: resolvedName)
        }
    }
}

#if !os(tvOS)
/// The Character list the clone is chosen from, like the Table list of the Quick Link.
private struct CloneCharacterPickerView: View {
    let characterRoot: ItemRootController
    let selection: ItemSelectionModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ManagedNavigationStack(name: "CloneCharacterPicker") {
            characterRoot.viewControllable.linkListView(rootController: characterRoot, type: .selection, itemSelectionModel: selection)
                .navigationTitle(Text("Clone Character", bundle: .module))
                .navigationBarTitleDisplayModeAll(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .accessibilityLabel(Text("Cancel", bundle: .module))
                    }
                }
        }
    }
}
#endif

extension View {
    func generateFromPhotoPresentation(root: any ItemRootControllable) -> some View {
        modifier(GenerateFromPhotoPresentationModifier(root: root))
    }
}
