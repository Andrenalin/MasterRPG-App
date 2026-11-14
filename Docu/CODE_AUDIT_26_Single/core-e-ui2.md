# CoreRPG UI part 2 audit (EntryEditor, Views, ItemList, Menu, ItemDetail, Buttons, Fake, Simple, Extensions, Inspector, Theme, ViewModifiers, Editors, List, Rows, Animations, Layout, ItemViews, TabNavigation)

Files read in full: EntryEditor (10 files), Views (13), ItemList (9), Menu (28), ItemDetail (7), Buttons (14), Simple (8), Extensions (18), Inspector (8), Theme (5), ViewModifiers (10), Editors (6), List (2), Rows (3), Animations, Layout, ItemViews (2), TabNavigation; of the 22 Fake fixture files only the ones production code touches (export, game, import, folder list, search, view controllers, PreviewAssetFixture, TestWait, PreviewFixtureLoader) were read, the model fixtures were skimmed. About 13.3k LOC in Modules/CoreRPG. A script-assisted cross-repo reference scan was used for dead code. Overall health: good. The code uses the project idioms consistently (reduce-motion checks, `bundle: .module`, `@MainActor` models, `FormatStyle`, no GCD, no `ObservableObject`) and the 40 earlier audits have clearly been applied. The real issues are (1) production code that depends on preview fixtures (`Fake*`), (2) body-time work in the quick editor, (3) a few dead leftovers from the audit 25 deletions, and (4) CLAUDE.md style rules (image-only buttons, UIKit haptics, `AnyView`, hard-coded paddings).

### Production Table outcome editor is built from preview fixtures (Fake*) with a latent trap
- Category: Refactor
- Location: Modules/CoreRPG/Simple/SimpleSheetEditingSession.swift:79-88,93; Modules/CoreRPG/Fake/FakeExportController.swift:17-25,27-29; Modules/CoreRPG/Fake/FakeFolderListController.swift:63; Modules/CoreRPG/Fake/FakeSearchController.swift:27; Modules/CoreRPG/Controllable/RootManager.swift:142
- What: `SimpleSheetEditingSession` (used by TableRPG outcome editing, `TableGenerationController+OutcomeEditing.swift:29`) wires `FakeExportController.fake`, `FakeGameController.fake`, `FakeImportController.fake`, `FakeFolderListController.fake`, `FakeSearchController.fake`, `FakeViewController()` and `RootManager.preview(fake:)` into a real `ItemRootController`. The Fake files are compiled in every configuration (partly by design, so preview declarations compile in Release; `PreviewAssetFixture` and `TestWait` do gate their heavy parts with `#if DEBUG`), so about 980 LOC of fixtures ship in Release, and the rest cannot be gated while Simple depends on them.
- Why: (a) `FakeExportController.hubControllable` calls `preconditionFailure` when no hub was set; the session never sets one, so any code path that reads `rootExportController`/`rootImportController` (Modules/CoreRPG/Controllable/ExportControllable.swift:100-108, protocol defaults that forward to the hub) on this root traps in Release (whether the sheet UI reaches them is not verified). (b) The `static let fake` singletons (`FakeFolderListController.fake` with its `FolderListModel`/`ListDisplayModel`/`CacheItemListModel`, `FakeSearchController.fake` with `SearchModel.preview()`, `FakeItemController.fake`) are one shared mutable instance for every session and for previews, so state leaks between two open outcome editors. (c) Preview/test code is invisible to reviewers as production surface.
- Action: Introduce small production `Null*`/`Inert*` conformers (export, game, import, folder list, search, view) owned by Simple, give each session its own instances, and then wrap `Fake/` in `#if DEBUG` (tests build Debug). Make the export stub's hub access non-trapping.
- Severity: Medium
- Status: NEW

### Quick editor recomputes `initialText` and deep-copies the model on every parent body pass
- Category: Performance
- Location: Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:57,108-112,23-24
- What: `initialText` (`editController.editEntries(for:)` plus `parser.format` over all entries) is evaluated in `body` only to hand a `let initialText: String` to `QuickEntryEditorContentView`, which reads it once in `onAppear` (line 296). `init` also builds a `TextEditModel` and calls `model.copy()` (deep copy of the item) every time the parent re-creates the view, although `@State` keeps only the first value.
- Why: Every `showHelp`/`showResult`/`showInspector` toggle and every parent update re-formats the whole table text and copies the model; large tables (hundreds of entries) make toggling the result pane sluggish.
- Action: Pass a closure evaluated in `onAppear`, and create the copy and the `TextEditModel` lazily (for example in `.task`/`onAppear` or through a small `@State` holder).
- Severity: Medium
- Status: NEW

### Preview fixture injected in the production quick editor list
- Category: Dead code
- Location: Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:321 (helper at Modules/CoreRPG/Model/SearchModel.swift:113)
- What: `QuickEntryEditorEntryListView` applies `.environment(SearchModel.preview())` (a `#Preview` helper using `TagController.preview`, module `.photo`). A repo-wide grep (Modules, Sources, Tests) finds no `@Environment(SearchModel.self)` reader.
- Why: Dead injection that allocates a new SearchModel on every body evaluation and ties production UI to a preview fixture with the wrong module.
- Action: Remove the modifier.
- Severity: Low
- Status: NEW

### Add Item and Add Collection menu buttons lack the in-flight guard Add Folder got
- Category: Bug
- Location: Modules/CoreRPG/Menu/AddItemButton.swift:11-19; Modules/CoreRPG/Menu/AddCollectionButton.swift:11-19 (guarded version: Modules/CoreRPG/Menu/AddFolderButton.swift:11-18)
- What: `AddFolderButton` ignores a second press while `addNew` is in flight (`isCreating`, CODE_AUDIT_Folder §5.29). The two sibling buttons start a new `Task { await addNew }` per press.
- Why: Holding Cmd+N (key repeat) or double-pressing creates several items or collections before the first route lands; macOS menu shortcut repeat makes this easy to hit.
- Action: Share one guarded helper for the three buttons (the donation and tip-refresh tail is also copied three times, so extract it together).
- Severity: Low
- Status: NEW

### `move(itemId:entryIds:)` replaces the entry list with only the ids it is given
- Category: Bug
- Location: Modules/CoreRPG/ItemList/EntryDataEditable.swift:362-367 (callers Modules/CoreRPG/Sheet/SheetRootModel+ContextMenu.swift:25,49)
- What: `item.entries = entryIds.compactMap { id in item.entries.first { $0.id == id } }` rebuilds the array from the ids the sheet passes. Any entry of the item that is not in `entryIds` (hidden or group-hidden entries the sheet does not list, or ids that failed to resolve) is dropped silently on a reorder, and the result is saved.
- Why: Data loss path on reorder if the sheet's entry list is ever a subset of the item's entries (not confirmed for every module; sheets that filter by search call `updateFilteredEntries` after, which suggests the list is complete today). The O(n^2) `first` lookup is also repeated per id.
- Action: Keep entries missing from `entryIds` (append them in their old relative order) and build a dictionary for the lookup; add a test with a hidden entry.
- Severity: Medium
- Status: NEW

### Default group helpers return a random UUID as if they had worked
- Category: Bug
- Location: Modules/CoreRPG/ItemList/EntryDataEditable.swift:122-130; Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:33,46
- What: The protocol-extension defaults of `addNewGroup` and `convertToGroup` return `UUID()`; `convertToGroup` also returns `UUID()`/`groupId` on the guard failures. Callers (`SheetRootModel+Editor.swift:58,82`) then set the editor to that entry id.
- Why: A module that does not support groups, or a failed lookup, opens the editor on an id that does not exist instead of failing visibly.
- Action: Return `UUID?` (nil on failure) and let callers skip.
- Severity: Low
- Status: NEW

### `updateDefault` duplicate-link repair applies ranges of the original string to the edited string
- Category: Bug
- Location: Modules/CoreRPG/ItemList/EntryDataEditable.swift:337-353
- What: For each link whose id was seen before, `content.firstRange(of: oldLinkText)` finds the first occurrence in the unmodified `content` and `newContent.replaceSubrange(range, ...)` applies that range to `newContent`, which earlier iterations already changed.
- Why: With three or more links of the same id, the range always points at the first occurrence (which already holds a replaced link), so the second and third duplicates keep the shared id and one registered new link is orphaned. If a replacement ever differs in length, later ranges are also off. Unverified at runtime; it needs three identical-id links, which `linksRepair` numbering normally prevents.
- Action: Resolve the n-th occurrence per link (iterate occurrences in order, build the result in one pass like `replacing(ranges:)`), and add a test with three duplicates.
- Severity: Low
- Status: NEW

### `convertToGroup(existingItemId:)` does not take the item out of its folder
- Category: Bug
- Location: Modules/CoreRPG/ItemList/GroupableEntryEditing.swift:36-43 (compare 73-76)
- What: `moveIntoGroup` removes a folder child from its parent first ("A hidden group has no folder; the folder would keep listing it"); `convertToGroup` with an existing item sets `groupId` and hides it but never calls `removeItemFromParent`.
- Why: A linked item that sits in a folder becomes a group value and can still be referenced by the folder (inconsistent with `moveIntoGroup`, which was fixed for exactly this). Not verified in the UI.
- Action: Apply the same parent removal, or document why a hidden item may stay in its folder.
- Severity: Low
- Status: NEW

### Item detail root swaps the whole view subtree when `showsBottomOverlayBar` flips
- Category: SwiftUI
- Location: Modules/CoreRPG/ItemDetail/ItemDetailRootView.swift:157-178; flip source Modules/AudioRPG/View/DetailFolderListView.swift:29 (`showsBottomOverlayBar: !usesPhoneTabAccessory`)
- What: The body returns `content`, `content.safeAreaInset...overlay`, or `content` depending on a runtime flag, so each branch is a different view identity. Audio passes a flag that follows the size class.
- Why: Rotating an iPad or resizing a window across the compact threshold re-creates the entire detail subtree (editor state, scroll position, an open header editor) instead of animating the inset.
- Action: Keep one structure (always apply `safeAreaInset`/`overlay`, with a conditional inner content) so the identity is stable.
- Severity: Low
- Status: NEW

### CloudKit "Synced" badge never expires
- Category: Bug
- Location: Modules/CoreRPG/Views/CloudKitSyncStatusView.swift:37-48
- What: `.succeeded` shows the badge only while `Date().timeIntervalSince(lastSync) < 60`, evaluated in `body`.
- Why: Nothing re-renders the view after 60 s, so the badge stays until some other state changes, and a late re-render removes it without animation (the animation is keyed on `syncState` only).
- Action: Expire it from the model (reset state after a delay) or use `TimelineView`/`.task(id: lastSync)` with `Task.sleep(for:)`.
- Severity: Low
- Status: NEW

### Orphaned `OptionKeyDownModel` still installs a global key monitor on macOS
- Category: Dead code
- Location: Modules/CoreRPG/Extensions/PressedKeyDetection.swift:7-36; Modules/RolePlayGameKit/Model/AppModel.swift:38,139; Modules/RolePlayGameKit/View/AppEnvironmentSetUpViewModifier.swift:38
- What: The only reader (`OptionKeyPressedButton`) was deleted in CODE_AUDIT_25 §9.10. The model is still created by `AppModel`, injected into the environment, and on macOS registers an `NSEvent` local `flagsChanged` monitor for the app's lifetime. Grep finds no `@Environment(OptionKeyDownModel.self)` or `isPressedOptionKey` reader (only two snapshot tests inject an instance).
- Why: Dead event monitoring (runs on every modifier key change) plus an unused iOS stub.
- Action: Delete the type, the AppModel property, the environment injection and the two test lines.
- Severity: Low
- Status: NEW

### Dead leftovers inside the audited files
- Category: Dead code
- Location: Modules/CoreRPG/Rows/ColoredBackgroundRowModifier.swift (`rowColorBackground`, zero references); Modules/CoreRPG/Menu/LinkWindowCommandView.swift:8-14,33-41 (`isAlt` is never `true` anywhere, so `modifiers` and the `titleWindow` "New ..." branch are dead; the button always uses `[.command, .option, .shift]`); Modules/CoreRPG/ItemDetail/ItemDetailRootView.swift:229-249 (empty `// MARK:` sections left behind by extractions); Modules/CoreRPG/EntryEditor/EntryEditorContent.swift:23,25 (`theme`, `reduceTransparency` unused in `EntryEditorContent`); Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:36 (`scenesManager` unused in the parent); Modules/CoreRPG/ItemList/CacheItemListModel.swift:11-18 (`CacheType.entryName/.content/.thumbnail` have no users, only `.name`, `.description`, `.row`, `.image` are written); Modules/CoreRPG/Editors/AddTagsEditor.swift:7 (`theme` unused in `AddTagsEditor`); Modules/CoreRPG/Animations/MeshAnimationView.swift (whole file, 81 LOC, plus the `meshAnimationEnabled` environment key: no production reference in Modules or Sources, only the snapshot tests and a preview use it)
- What: Verified by grep over Modules, Sources and Tests.
- Why: Noise; each unused `@Environment` also invalidates the view when the value changes.
- Action: Delete.
- Severity: Low
- Status: NEW

### `CacheItemListModel` is never pruned for removed entries and keys are built with string interpolation
- Category: Performance
- Location: Modules/CoreRPG/ItemList/CacheItemListModel.swift:22-52; Modules/CoreRPG/Controllable/EditControllable.swift:911,1017 (only item ids are reset)
- What: Entries are cached under `"row-<entryId>"`; `reset(itemId:)` clears keys for the item id, never for its entries, so an entry removed or an item deleted leaves its `LinkHighlightTextModel` cached. Every lookup builds a `String` key, and `reset(search:)` walks every cached model on each filter keystroke (`LinkItemFilterFieldView.swift:32-36`).
- Why: Bounded by session length, but the cache grows with editing churn and each keystroke touches all models.
- Action: Key by a `struct { CacheType, UUID }`, drop entry ids when an entry is removed, and only reset visible models on search.
- Severity: Low
- Status: NEW

### Double localization lookup: `String(localized:).localizedString`
- Category: API
- Location: Modules/CoreRPG/Extensions/LocalizedStringKey+String.swift:11-15; 107 call sites repo-wide, for example Modules/CoreRPG/ItemList/EntryDataEditable.swift:152,192,206,226,300,359; Modules/CoreRPG/Menu/LinkWindowCommandView.swift:39
- What: `String(localized: "Add entry", bundle: .module)` already returns the translated text; the extra `.localizedString` looks the translated text up again as a key in the module bundle.
- Why: Harmless in most cases but wasted lookups, and a translated string that happens to equal another English key is translated twice. Interpolated keys ("Copy entry \(name)") are looked up again with the user's data as key.
- Action: Remove `.localizedString` after `String(localized:)` (107 sites), keep the extension only for raw keys.
- Severity: Low
- Status: NEW

### Menu title "<Module> Link" is not localized
- Category: API
- Location: Modules/CoreRPG/Menu/LinkWindowCommandView.swift:9,28
- What: `title = "\(networkModule.title) Link"` is a plain `String` passed to `Label(titleWindow, systemImage:)`, which uses the verbatim `StringProtocol` initializer, so "Link" never goes through the string catalog.
- Why: The macOS Window menu shows an English word in every language.
- Action: Use a localized format string with `bundle: .module`.
- Severity: Low
- Status: NEW

### Global `UINavigationController` delegate hijack
- Category: API
- Location: Modules/CoreRPG/Extensions/NavigationController+Back.swift:6-31
- What: A retroactive `UIGestureRecognizerDelegate` conformance on every `UINavigationController` replaces `interactivePopGestureRecognizer.delegate` in an overridden `viewDidLoad`, returns `true` from `shouldBeRequiredToFailBy` and `shouldRecognizeSimultaneouslyWith` whenever more than one controller is on the stack.
- Why: The hack (from a StackOverflow answer for early iOS 16) also applies to system-owned navigation controllers (QuickLook, pickers, share UI) and makes every other gesture wait for the pop gesture to fail on non-root screens. The target is now iOS 26 only, where the system interactive content pop gesture exists, and CLAUDE.md says to avoid UIKit.
- Action: Re-test on iOS 26 without it; if still needed, scope it to the app's own navigation controllers.
- Severity: Low
- Status: NEW

### `removeWhiteBackground` reads the bitmap channels in the wrong order
- Category: Bug
- Location: Modules/CoreRPG/Extensions/UIImage+clear.swift:15,33-36; used from Modules/CoreRPG/Extensions/Image+AKImage.swift:379 and Modules/CoreRPG/Controllable/ImageCacheControllable.swift:118
- What: The context uses `byteOrder32Little | premultipliedFirst`, which stores pixels as B,G,R,A bytes, but the loop treats offsets 0..3 as A,R,G,B.
- Why: The test effectively becomes "alpha > 254, R > 254, G > 254, B > 200": opaque near-white is still cleared, but cream or light-yellow paper (B 201..254) is cleared too, and pixels with alpha 201..254 are kept. The 1M-pixel loop also runs on the calling actor (`createQuickLookThumbnail` is `@MainActor`, the helper is a nonisolated async function that inherits it).
- Action: Read B,G,R,A, move the loop to a `@concurrent` function.
- Severity: Low
- Status: NEW

### Image-only buttons use `Image` + `accessibilityLabel` instead of a `Label`
- Category: SwiftUI
- Location: Modules/CoreRPG/EntryEditor/QuickEntryEditorView.swift:177-183,206-225; Modules/CoreRPG/EntryEditor/QuickEntryEditorView+QuickLink.swift:69-75; Modules/CoreRPG/Views/HideKeyboardFocusView.swift:31-43; Modules/CoreRPG/Menu/MenuWindowButtonView.swift:25-29; Modules/CoreRPG/ItemDetail/ItemDetailContentView.swift:108-119
- What: CLAUDE.md requires text next to an image in a button label.
- Why: Rule violation; VoiceOver is fine, but Voice Control names, `.help` and toolbar customization get no title.
- Action: `Label` with `.labelStyle(.iconOnly)`, as the entry header buttons already do.
- Severity: Low
- Status: NEW

### UIKit haptics instead of `sensoryFeedback`
- Category: API
- Location: Modules/CoreRPG/EntryEditor/EntryEditorHeaderView.swift:43-45,82-84,110-114
- What: `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator` behind `#if os(iOS)`, the success haptic scheduled with `delayedTask(.settleDelay)`.
- Why: CLAUDE.md says avoid UIKit; `sensoryFeedback(_:trigger:)` works on all platforms without a fire-and-forget task.
- Action: Trigger from `isSaving` and a drop counter.
- Severity: Low
- Status: NEW

### `AnyView` in protocol surface and sub-folder detail
- Category: SwiftUI
- Location: Modules/CoreRPG/ItemList/EntryDataEditable.swift:52,159; Modules/CoreRPG/ItemDetail/ItemDetailContentView.swift:106 (`.asAnyView()`)
- What: `additionalRowView` returns `AnyView`; the inline sub-folder destination is erased with `asAnyView()`.
- Why: CLAUDE.md says avoid `AnyView`; erased views defeat diffing for every entry row of the character sheet.
- Action: Return `some View` through an associated type or a `@ViewBuilder` on a generic container; accept as known debt if the existential protocol cannot change.
- Severity: Low
- Status: NEW

### Detail screens duplicate helpers and use magic layout numbers
- Category: Duplication
- Location: Modules/CoreRPG/ItemDetail/ItemDetailRootView.swift:185-192,197-201 vs Modules/CoreRPG/ItemDetail/ItemDetailContentView.swift:74-96 (`fileTypes`, `shouldShowContent`, `openEditingSheet` copied); Modules/CoreRPG/ItemDetail/ItemDetailHeaderView.swift:25 (`.padding(.top, -64)`); Modules/CoreRPG/ItemDetail/ItemEditorBackgroundView.swift:49 (fixed 96 pt inset)
- What: Two views carry the same three members; the header uses a negative magic padding and a fixed inset that does not scale with Dynamic Type.
- Why: Drift risk (the Root copy is what `handleModelIdChange` uses); layout breaks with larger text.
- Action: Pass the values down from Root, use `@ScaledMetric`.
- Severity: Low
- Status: NEW

### Chevron in inspector rows is hard-coded red
- Category: SwiftUI
- Location: Modules/CoreRPG/Inspector/InspectorRowView.swift:258
- What: `.foregroundStyle(.red)` on the folder chevron, while the rest of the file uses the theme.
- Why: Looks like a debug color left in, ignores the app theme and contrast settings.
- Action: Use the theme tint or `.secondary`.
- Severity: Low
- Status: NEW

### Inspector row opens details through `showDetails.toggle()`
- Category: Bug
- Location: Modules/CoreRPG/Inspector/InspectorRowView.swift:145; consumer Modules/CoreRPG/Inspector/LinkItemListView.swift:132-135
- What: The event is signalled by toggling a Bool; the `onChange` navigates on both transitions.
- Why: Works only as an event pulse. `showDetails` is also shared by every row, so two quick double taps push the detail twice.
- Action: Use an optional destination binding (`navigationDestination(item:)` or a counter) instead of a toggled Bool.
- Severity: Low
- Status: NEW

### Test gap: no coverage found for the Simple session and EntryDataEditable defaults
- Category: Test gap
- Location: Modules/CoreRPG/Simple/SimpleSheetController.swift:73-112; Modules/CoreRPG/ItemList/EntryDataEditable.swift:258-304,331-360
- What: `entriesMatchedByName`, the default `merge`, `updateDefault` and the Simple sheet reconcile are non-trivial logic. (Not re-verified against Tests/CoreRPGTests file names beyond a quick grep; check before acting.)
- Why: Reorder, merge and duplicate-link repair are data-integrity paths.
- Action: Add tests for hidden entries on reorder/merge and three same-id links.
- Severity: Low
- Status: NEW

### `TextIntEditor(value:)` and `ToggleEditor(value:)` build a new model, with a new id, on every parent body pass
- Category: SwiftUI
- Location: Modules/CoreRPG/Editors/TextDoubleEditor.swift:7-11; Modules/CoreRPG/Editors/TextIntEditor.swift:7 and 43-53; Modules/CoreRPG/Editors/ToggleEditor.swift:7; callers Modules/DiceRPG/Dice/RerollEditor.swift:128,162, Modules/DiceRPG/Dice/SpecialValueEditor.swift:127
- What: The `Binding` initializers create `EditIdentifierModel(value:)` in `init` (not in `@State`); that model gets `valueId = UUID()`. `TextIntEditor` resets its `text` in `.onChange(of: model.valueId, initial: true)`.
- Why: Every re-render of the parent produces a new `valueId`, so the field text is overwritten with the formatted value even while the user is typing (for example when the dice model changes for an unrelated reason). The other callers hold the model in `@State` and are not affected.
- Action: Keep the model in `@State` inside the editor (created once, binding re-attached), or give the binding variant a stable id (for example a fixed UUID).
- Severity: Low
- Status: NEW

### Slider drag saves on every tick
- Category: Performance
- Location: Modules/CoreRPG/Editors/TextDoubleEditor.swift:92-95; Modules/CoreRPG/Editors/TextIntEditor.swift:50-53; Modules/CoreRPG/Editors/ToggleEditor.swift:31-33
- What: `.onChange(of: model.value) { model.save() }` runs for every value change, including each slider step, and `save()` is the caller's persistence closure; focus loss and submit call it again.
- Why: Dragging a slider over a 0...20 range issues up to 20 saves (each a model edit and possibly a game broadcast), and values are saved twice on submit.
- Action: Save on `onEditingChanged(false)` for the slider and on submit/focus loss for the field; keep onChange only for the toggle.
- Severity: Low
- Status: NEW

### Tag editor accepts blank and whitespace-padded tags
- Category: Bug
- Location: Modules/CoreRPG/Editors/AddTagsEditor.swift:63-75,81-91
- What: The add button is enabled for any non-empty text and `addCurrentTag` uses `currentTag.localizedUppercase` without trimming.
- Why: A tag of one space is added (an empty-looking chip), and "DUNGEON" and "DUNGEON " are distinct duplicates. `.textContentType(.name)` (line 46) also offers contact-name autofill for tags.
- Action: Trim whitespace and newlines before the empty and duplicate checks, disable the button on a trimmed-empty string, drop the content type.
- Severity: Low
- Status: NEW

### Remove-badge buttons have no accessible "remove" semantics
- Category: SwiftUI
- Location: Modules/CoreRPG/ViewModifiers/RemoveItemViewModifier.swift:20-36; use Modules/CoreRPG/Editors/RemoveTagsEditor.swift:30
- What: The whole content (for example the tag text) becomes the button label and the red minus badge is `accessibilityHidden(true)`; no label, hint or role says what the button does.
- Why: VoiceOver announces "DUNGEON, button" and activating it deletes the tag. Accessibility guideline violation on a destructive action.
- Action: Add an accessibility label/hint such as "Remove <content>" (needs the caller's title) and `role: .destructive`.
- Severity: Medium
- Status: NEW

### Link drag and drop modifier: 11-way switch repeated four times and a mismatched default
- Category: Duplication
- Location: Modules/CoreRPG/ViewModifiers/LinkDragViewModifier.swift:37-50,66-79,93-106,189-202 and handlers 111-175,206-281 (282 LOC); default branches at lines 49, 78, 105, 201
- What: One `switch module` per modifier maps each module to its `Link*Data` type, and 22 handlers are identical. The drag side falls back to `LinkEntryData` for unknown modules, the drop side falls back to `LinkAdventureData`.
- Why: A module that reaches `default` (`.generator`, `.none`, for example `InspectorRowView` passes `.none` for entry-only selections) can be dragged as `LinkEntryData` but its drop zone only accepts Adventure links, so the pair does not match, and an Adventure link dropped on such a zone is accepted as if it were meant for it.
- Action: Table-drive the type mapping (a function returning the `Transferable` metatype/closure) and use one handler; make the drop default match the drag default (`LinkEntryData`) or disable the drop.
- Severity: Low
- Status: NEW

### `numericInput` filter edge cases
- Category: Bug
- Location: Modules/CoreRPG/ViewModifiers/NumericViewModifier.swift:17-32
- What: The allowed set contains "-" at any position and the decimal separator of the current locale only. Pasted text such as "1.5" in a comma locale loses the dot and becomes "15"; "1-2" is kept.
- Why: A wrong number is stored silently instead of being rejected; the later `Int(text)`/`FloatingPointFormatStyle` parse then fails for "1-2" and the value is ignored without feedback.
- Action: Validate with the same `FormatStyle` the submit handler uses and keep the previous text on a failed parse; allow "-" only as the first character.
- Severity: Low
- Status: NEW

### `FlowLayout` falls back to a 10 pt width and reports the full proposed width
- Category: SwiftUI
- Location: Modules/CoreRPG/Layout/FlowLayout.swift:14,48
- What: `sizeThatFits` uses `proposal.replacingUnspecifiedDimensions().width` (10 pt when the width is unspecified) and returns `width: maxWidth` instead of the widest line.
- Why: Under an ideal-size or `fixedSize` query (for example a tag list in a horizontal container) every item wraps onto its own line; the layout also grabs the whole proposed width, which centers or stretches the surrounding label. Today both users sit in a `Toggle` label with a definite width, so it does not show yet.
- Action: Treat an unspecified width as `.infinity`/the sum of widths and return the used width; add a cache for the per-subview sizes (computed twice per layout pass).
- Severity: Low
- Status: NEW

### Share button is implemented twice
- Category: Duplication
- Location: Modules/CoreRPG/List/ShareListItemModifier.swift:41-71 vs Modules/CoreRPG/Views/SendFeedbackButton.swift:57-117
- What: `ShareItemViewModifierButtonView` and `SendFeedbackButtonButtonView` share icon choice, `selectedRoundButton`, accessibility label and first/second action logic; they differ only by the sending animation.
- Why: Two places to change for any accessibility or icon fix (the `Perform follow-up action` label already exists twice).
- Action: Make the feedback animation an option of one button view.
- Severity: Low
- Status: NEW

### Test gap: Viewport geometry, theme contrast and numeric filter
- Category: Test gap
- Location: Modules/CoreRPG/Views/ViewportGeometry.swift (466 LOC pure functions used by Photo and Map), Modules/CoreRPG/Theme/ThemeColor.swift:41-69 (`ensuringContrast`), Modules/CoreRPG/ViewModifiers/NumericViewModifier.swift
- What: These are pure or near-pure logic with branchy edge handling. A name search in Tests/ was not exhaustive; check `Tests/CoreRPGTests` for existing coverage before adding.
- Why: A regression in zoom/pan clamping or in the contrast fix would only show in the UI.
- Action: Add golden-value tests (all four theme x contrast combinations keep the documented ratios; viewport resize/zoom anchors).
- Severity: Low
- Status: NEW

Not audited in this area:
- Fake model fixtures other than the ones named above (`FakeItemModel`, `FakeEntryModel`, `FakeEditController`, `FakeItemRootController`, `FakeLinkController`, `FakeLinkRegisterController`, `FakeSheetController`, `FakeImageCacheControllable`, `TestFixtures`, `ImportControllable+TestSupport`): skimmed only, they are preview/test doubles and no production use besides the Simple dependency was found.
- Theme/AppThemeCatalog.swift lines 60-150 (the individual theme palettes), checked only for structure.
- Runtime behaviour: nothing was built or run; the SwiftUI layout findings (item detail identity swap, FlowLayout fallback, SpecialCategoryContentView overlay stacking) are from reading the code.
- Sheet/, LGViews/, LGViewModifiers/, FileViews/ and the controllers (outside the assigned folders) were only opened to confirm call sites.
