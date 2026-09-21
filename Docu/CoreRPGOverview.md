# CoreRPG LLM Documentation

Generated on 2026-07-07 from a six-subagent read-only scan plus a local `rg --files Modules/CoreRPG` inventory. The scan covered 411 pre-existing files; this document is the 412th CoreRPG file.

CoreRPG is the shared foundation module for MasterRPG. It supplies cross-module domain contracts, item/controller protocols, persistence helpers, navigation, reusable SwiftUI UI, file handling, link parsing/rendering, resources, test fakes, and support utilities. Treat it as infrastructure for the feature modules, not as a single user-facing feature.

## LLM Use

- Start with `ItemRootController`, `RootManager`, `ItemDataModel`, `ItemControllable`, `EditControllable`, `FolderListControllable`, `SearchControllable`, `LinkControllable`, and `Navigator` when reasoning about behavior.
- Preserve the MVC shape: domain models and root/controller state live in `@Observable` models and controller protocols; SwiftUI views call controllers instead of mutating storage directly.
- Assume item/domain state is MainActor-owned. Pass UUIDs, value snapshots, or copies across actor boundaries instead of live observable domain objects.
- Use existing generic protocols and default protocol-extension behavior before adding new controller surface area.
- Keep localization in CoreRPG resources with `bundle: .module`.
- Use `ItemRowModel(itemId:entryId:typeId:)` for cross-module identity. Folder membership may use entry IDs distinct from item IDs.
- Use `FileUrlDataController` and `FileManager+Coordination` for file movement, security-scoped access, bookmarks, and iCloud/group storage. Do not bypass them.
- Use `LinkReplaceController` for markdown link parsing/repair, `LinkRegisterController` for reference indexing, and `LinkHighlightTextView` for interactive display.
- Use `ManagedNavigationStack`, `Navigator`, `KnownRoutes`, `InternalRoute`, and module route receivers for deep linking and presentation; avoid raw navigation for routed module screens.

## Subagent Coverage

- Subagent 1: `Model`, `Persistence`, `Stores`, `CRDT`, `PropertyWrappers`, `Files`, `Cache`, shared Core Data model.
- Subagent 2: `Controllable`, `ItemList`, `Fake`.
- Subagent 3: `Navigator`, `Routes`, `ScenesManager`, `App`, `AppModels`, `TabNavigation`, `Platform`, `Settings`, `Menu`.
- Subagent 4: UI folders including `LGViews`, `LGViewModifiers`, `Views`, `ViewModifiers`, `Buttons`, `ItemViews`, `Rows`, `ItemDetail`, `Layout`, `CustomBars`, `FileViews`, `Editors`, `EntryEditor`, `Inspector`, `Sheet`.
- Subagent 5: `Links`, `LinkRenderer`, `Text`, `Parser`, `List`, `Accessibility`, `Animations`, `Shaders`.
- Subagent 6: support utilities, extensions, debug, resources, leftovers, and surprising files.

## Architecture Snapshot

### Module Composition

`RootManager` stores one `ItemRootControllable` per RPG module and resolves roots by `NetworkModules`. A module factory builds an `ItemRootController`, which composes the module configuration, navigation model, selection/removal models, and concrete controllers for item/edit/export/game/import/link/folder/search/sheet/view/cache behavior.

`ItemDataModel` is the shared in-memory store for ordered item IDs and item references. It also has a separate `gameItemData` overlay so game mode can mutate/share temporary state without always writing to persistent storage. Use `noGame: true` when persistent state is explicitly required.

### Item And Edit Flow

UI calls controller APIs. Typical edit flow is:

1. SwiftUI view calls `EditControllable` or `FolderListControllable`.
2. Controller obtains an editable copy/model.
3. `save(updated:)` paths update undo, tags, links, and cached text.
4. `ItemControllable.replace` updates in-memory state and queues persistence.
5. `ItemControllable.save` flushes pending persistence and invalidates app-intent content.

Most controller files are protocol mixins. Concrete modules should override narrow hooks instead of copying shared behavior.

### Search And Lists

`SearchRootControllable` and `SearchControllable` build `SearchResult` trees. `FolderListControllable` owns the debounced/coalesced search task, resets filters, flattens search results into `FolderListItemModel`, and preserves open/selection state.

`results(text:focusId:)` is for loading children/entries. `scopedResults(text:focusId:)` may return the focused item as the view root. Keep this distinction: mixing them can produce recursive or blank detail lists.

### Persistence And Sync

CoreRPG has shared Core Data infrastructure, but the runtime schema is merged from all module bundles. Do not treat `Resources/Model.xcdatamodeld` as the complete app schema.

`CoreDataPersistenceController` creates the local app-group store. `CloudKitCoreDataPersistenceController` creates the CloudKit private store. `CoreDataController<Model, DataType>` maps domain models to `NSManagedObject` types, supports fetches, snapshot fetches, queued replaces, batch operations, and duplicate UUID repair. Keep managed-object work inside `context.perform`.

Prefer snapshot APIs such as `fetchSnapshots` and snapshot replace when domain models are `@MainActor`.

### Files And Cache

`FileUrl` is the stable file reference. Its `data` property is transient transport/fallback data, while `contentHash` is durable byte identity. `FileUrlDataController` coordinates import, load, move, delete, duplicate, and download operations. `FileBookmarkController`, `LocationFileManager`, and `FileManager+Coordination` handle bookmarks and coordinated access.

Image/object caches live in `Cache` and are reached through cache controllers/protocols rather than direct view storage.

### Links And Text

Stored text uses markdown-style RPG links such as `[Name](RPG://MODULE/0/ITEM_UUID[/ENTRY_UUID][/COMMAND])`. `ReferenceScanner` and `RegularExpressionParser` extract links. `LinkReplaceController` normalizes and repairs links. `LinkRegisterController` persists source/destination references in Core Data and keeps an in-memory dictionary keyed by destination item UUID. `LinkHighlightTextModel/View/Renderer` turns text into interactive display with custom text attributes and transparent overlay buttons.

See [Link System](LINKS.md) for the complete URL grammar, occurrence identity,
editor round trip, structural references, persistence, actions, sheet toggling,
deep links, tests, and current review findings.

### Navigation And Scenes

`Navigator` is a custom `@Observable` navigation tree layered over SwiftUI navigation. It owns navigation paths, sheets, covers, checkpoints, route sending, and child navigator relationships. App-level navigation flows through `KnownRoutes`, `RouteActions`, `SceneId`, `ScenesManager`, and module-specific route receivers. Use `ManagedNavigationStack` when a screen participates in deep links, restoration, checkpoints, or global dismiss.

### UI Composition

Module roots enter through `ItemRootView`, which injects the root controller into the environment, applies module tint, and binds the `Navigator` back into the module navigation model. `ListRootView` renders reusable searchable/selectable module lists. `ItemDetailRootView` composes hideable headers, file importers, foreground/background editors, child lists, entry editor overlays, and edit sheets.

Inspectors, sheets, file import/export panels, quick editors, and rows reuse the same controller graph. Preserve that pattern instead of embedding business logic directly in views.

## Category Order

1. Model contracts and item/list state: `Model`, `ItemList`.
2. Controller architecture: `Controllable`, `Fake`.
3. Persistence, file storage, cache, sync primitives: `Persistence`, `Files`, `Cache`, `CRDT`, `Stores`, `PropertyWrappers`, shared Core Data resources.
4. Navigation, app state, windows, platform wrappers: `Navigator`, `Routes`, `ScenesManager`, `App`, `AppModels`, `TabNavigation`, `Platform`, `Settings`, `Menu`.
5. Reusable SwiftUI UI: `LGViews`, `LGViewModifiers`, `Views`, `ViewModifiers`, `Buttons`, `ItemViews`, `Rows`, `ItemDetail`, `Layout`, `CustomBars`, `Editors`, `EntryEditor`, `Inspector`, `Sheet`, `FileViews`.
6. Links, text, parsing, lists, accessibility, animation: `Links`, `LinkRenderer`, `Text`, `Parser`, `List`, `Accessibility`, `Animations`, `Shaders`.
7. Shared support utilities and resources: `Extensions`, `Debug`, `Resources`.

## Known Sharp Edges

- Some `@Observable` classes are not explicitly `@MainActor`; repo guidance says observable classes should be MainActor-isolated unless default actor isolation covers them.
- Existing code has older APIs in places: Combine debouncing, `DispatchQueue`, `DateFormatter`/`NumberFormatter`, `Task.sleep(nanoseconds:)`, `onTapGesture`, `showsIndicators: false`, and a few force unwraps. Follow repo guidance for new work even when older examples exist.
- `LinkRegisterController.linksFrom(source:)` and `resetUsedLink(for:)` deserve review before relying on outgoing-link semantics.
- The CloudKit container string in code should be checked against current entitlements before changing persistence behavior.

## Complete File Catalog

### Documentation

- `LLM_DOCUMENTATION.md`

### Accessibility


### Animations

- `Animations/MeshAnimationView.swift`

### App

- `App/AppExitNotificationsViewModifier.swift`
- `App/AppGroup.swift`
- `App/AppIntentContentInvalidator.swift`
- `App/AppTabBarViewModifier.swift`
- `App/Bundle+Module.swift`
- `App/ExportedRPGData.swift`
- `App/PlatformModifiers.swift`
- `App/RouterActions.swift`
- `App/URL+ItemId.swift`
- `App/UndoManaged.swift`
- `App/UserActivity.swift`
- `App/WindowPlacementPosition.swift`

### App Models

- `AppModels/AppGameStateModel.swift`
- `AppModels/AppSettingsModel.swift`
- `AppModels/AppWindowSizeModel.swift`

### Buttons

- `Buttons/BorderLessTVButtonStyleViewModifier.swift`
- `Buttons/ControlSharingView.swift`
- `Buttons/FeatureConfig.swift`
- `Buttons/GlassButton.swift`
- `Buttons/ImageOverlayButton.swift`
- `Buttons/InlineEditorView.swift`
- `Buttons/OverlayButtonStyle.swift`
- `Buttons/QuickEditorButtonView.swift`
- `Buttons/QuickEditorDoubleView.swift`
- `Buttons/QuickEditorIntView.swift`
- `Buttons/SelectedBorderedButton.swift`

### CRDT

- `CRDT/ApproxSizeable.swift`
- `CRDT/CRDT.swift`
- `CRDT/CRDTDataUpdate.swift`
- `CRDT/DecoderPool.swift`
- `CRDT/DeltaCRDT.swift`
- `CRDT/LWWRegister.swift`
- `CRDT/Replicable.swift`
- `CRDT/UnequalAssignment.swift`
- `CRDT/WallclockTimestamp.swift`

### Cache

- `Cache/ImageCacheController.swift`
- `Cache/ObjectCache.swift`
- `Cache/ResourceCache.swift`

### Controllable

- `Controllable/ContextMenuMultiController.swift`
- `Controllable/ConvertController.swift`
- `Controllable/CoreDataSnapshotPersistable.swift`
- `Controllable/DataPersistenceControllable.swift`
- `Controllable/EditControllable.swift`
- `Controllable/EditControllerAddType.swift`
- `Controllable/ExportControllable.swift`
- `Controllable/ExportModel.swift`
- `Controllable/FileControllable.swift`
- `Controllable/FolderListControllable.swift`
- `Controllable/GameControllable.swift`
- `Controllable/ImageCacheControllable.swift`
- `Controllable/ImportControllable.swift`
- `Controllable/ItemControllable.swift`
- `Controllable/ItemDiffComparable.swift`
- `Controllable/ItemRootControllable.swift`
- `Controllable/LinkControllable.swift`
- `Controllable/ModuleConfigurable.swift`
- `Controllable/RootControllable.swift`
- `Controllable/RootManager.swift`
- `Controllable/SearchControllable.swift`
- `Controllable/SearchListController.swift`
- `Controllable/SearchRootControllable.swift`
- `Controllable/SheetControllable.swift`
- `Controllable/SyncDataControllable.swift`
- `Controllable/TagController.swift`
- `Controllable/ViewControllable.swift`
- `Controllable/ViewControllableViews.swift`

### Custom Bars


### Debug

- `Debug/DumpEnvironment.swift`
- `Debug/Logging.swift`
- `Debug/RainbowDebug.swift`

### Editors

- `Editors/QuickLinkEditor.swift`
- `Editors/RemoveTagsEditor.swift`
- `Editors/TextDoubleEditor.swift`
- `Editors/TextIntEditor.swift`
- `Editors/ToggleEditor.swift`
- `Editors/ValuePickerEditor.swift`

### Entry Editor

- `EntryEditor/EntryContentEditor.swift`
- `EntryEditor/EntryEditorContent.swift`
- `EntryEditor/EntryEditorHeaderView.swift`
- `EntryEditor/EntryEditorView.swift`
- `EntryEditor/EntryNameEditor.swift`
- `EntryEditor/QuickEntryEditorView.swift`
- `EntryEditor/TextEditModel.swift`
- `EntryEditor/TextEditorLinkView.swift`

### Extensions

- `Extensions/AnchorPreference.swift`
- `Extensions/BottomSafety.swift`
- `Extensions/Bundle+decode.swift`
- `Extensions/CGPoint+Operators.swift`
- `Extensions/CGSize+Operators.swift`
- `Extensions/Collection+Index.swift`
- `Extensions/Color+AKColor.swift`
- `Extensions/Image+AKImage.swift`
- `Extensions/LocalizedStringKey+String.swift`
- `Extensions/NavigationController+Back.swift`
- `Extensions/PlatformHelpers.swift`
- `Extensions/PressedKeyDetection.swift`
- `Extensions/RandomColor.swift`
- `Extensions/Scene+DefaultSize.swift`
- `Extensions/String+Highlight.swift`
- `Extensions/String+MarkDown.swift`
- `Extensions/TaggedPrefernceKey.swift`
- `Extensions/UIImage+clear.swift`

### Fake

- `Fake/FakeEditController.swift`
- `Fake/FakeEntryModel.swift`
- `Fake/FakeExportController.swift`
- `Fake/FakeFileFileAccessible.swift`
- `Fake/FakeFolderListController.swift`
- `Fake/FakeGameController.swift`
- `Fake/FakeImageCacheControllable.swift`
- `Fake/FakeImportController.swift`
- `Fake/FakeItemController.swift`
- `Fake/FakeItemModel.swift`
- `Fake/FakeItemRootController.swift`
- `Fake/FakeLinkController.swift`
- `Fake/FakeLinkRegisterController.swift`
- `Fake/FakeModuleConfiguration.swift`
- `Fake/FakeRootController.swift`
- `Fake/FakeSearchController.swift`
- `Fake/FakeSheetController.swift`
- `Fake/FakeViewController.swift`
- `Fake/TestFixtures.swift`

### File Views

- `FileViews/ExportProgressPanelView.swift`
- `FileViews/FileBrowserPickerView.swift`
- `FileViews/ImportProgressPanelView.swift`
- `FileViews/ImportReviewItemListView.swift`
- `FileViews/ImportReviewModels.swift`
- `FileViews/ImportReviewModuleListView.swift`
- `FileViews/ImportReviewPreviewData.swift`
- `FileViews/ImportReviewSplitView.swift`
- `FileViews/SettingsView.swift`
- `FileViews/SingleReviewDecisionViews.swift`
- `FileViews/SingleReviewEntryRows.swift`
- `FileViews/SingleReviewFilePropertyRow.swift`
- `FileViews/SingleReviewModels.swift`
- `FileViews/SingleReviewPreviewData.swift`
- `FileViews/SingleReviewPropertyRows.swift`
- `FileViews/SingleReviewReferenceViews.swift`
- `FileViews/SingleReviewValueViews.swift`
- `FileViews/SingleReviewView.swift`
- `FileViews/StorageOptionEditor.swift`

### Files

- `Files/CloudDocumentController.swift`
- `Files/FileBookmarkController.swift`
- `Files/FileDataController.swift`
- `Files/FileDropDelegate.swift`
- `Files/FileLocation.swift`
- `Files/FileManager+Coordination.swift`
- `Files/FileUrl.swift`
- `Files/FileUrlDataController.swift`
- `Files/FileUrlViewModel.swift`
- `Files/LocationFileManager.swift`

### Inspector

- `Inspector/LinkEntryRowView.swift`
- `Inspector/LinkItemFilterFieldView.swift`
- `Inspector/LinkItemListView.swift`
- `Inspector/LinkItemPickerView.swift`
- `Inspector/LinkItemRootView.swift`
- `Inspector/ModuleInspectorView.swift`

### Item Detail

- `ItemDetail/ItemDetailRootView.swift`

### Item List

- `ItemList/CacheItemListModel.swift`
- `ItemList/EntryDataAccessable.swift`
- `ItemList/EntryDataEditable.swift`
- `ItemList/ItemDataAccessable.swift`
- `ItemList/ItemDataModel.swift`
- `ItemList/ItemEditorModel.swift`
- `ItemList/ItemListActions.swift`
- `ItemList/ItemListCategory.swift`
- `ItemList/ItemRowTreeModel.swift`
- `ItemList/ScreenSizeModel.swift`

### Item Views

- `ItemViews/CategoryItemRow.swift`
- `ItemViews/ModalCloseButton.swift`
- `ItemViews/TagItemRow.swift`

### LG View Modifiers

- `LGViewModifiers/DetailInspectorViewModifier.swift`
- `LGViewModifiers/ItemRootRouteViewModifier.swift`
- `LGViewModifiers/ListModelUpdatesViewModifier.swift`
- `LGViewModifiers/SearchItemListViewModifier.swift`
- `LGViewModifiers/SyncListDisplayViewModifier.swift`
- `LGViewModifiers/ToolbarItemListViewModifier.swift`

### LG Views

- `LGViews/CachePhotoView.swift`
- `LGViews/DescriptionItemNewRow.swift`
- `LGViews/EditorLinkView.swift`
- `LGViews/EffectedLinkActionPanelView.swift`
- `LGViews/EntryEditRow.swift`
- `LGViews/FileImporterView.swift`
- `LGViews/GameShareView.swift`
- `LGViews/GridLabelView.swift`
- `LGViews/GroupEditorView.swift`
- `LGViews/GroupedPhotoView.swift`
- `LGViews/HeaderContentScrollView.swift`
- `LGViews/HeaderFooterContentScrollView.swift`
- `LGViews/ItemDetailOverlayView.swift`
- `LGViews/ItemHeaderEditorView.swift`
- `LGViews/ItemRootView.swift`
- `LGViews/ItemRowView.swift`
- `LGViews/ItemStateRestorationView.swift`
- `LGViews/ListRootContextMenu.swift`
- `LGViews/ListRootView.swift`
- `LGViews/MenuSelectionButtonView.swift`
- `LGViews/NameItemNewRow.swift`
- `LGViews/SplitContentUnavailableView.swift`
- `LGViews/ThumbnailRowPhotoView.swift`

### Layout

- `Layout/FlowLayout.swift`

### Link Renderer

- `LinkRenderer/AttributedString+Link.swift`
- `LinkRenderer/LinkButtonStyle.swift`
- `LinkRenderer/LinkHighLightLocations.swift`
- `LinkRenderer/LinkHighlightTextModel.swift`
- `LinkRenderer/LinkHighlightTextRenderer.swift`
- `LinkRenderer/LinkHighlightTextView.swift`
- `LinkRenderer/String+Link.swift`
- `LinkRenderer/TextLayout+Extensions.swift`

### Links

- `Links/DragOverlayViewModifier.swift`
- `Links/LinkDetailModel.swift`
- `Links/LinkRegisterController.swift`
- `Links/LinkRegisterListModel.swift`
- `Links/LinkReplaceController.swift`
- `Links/QuickLinkConfig.swift`
- `Links/ReferenceLinks.swift`
- `Links/ReferenceScanner.swift`

### List

- `List/CustomListShapes.swift`
- `List/DetailSectionRow.swift`
- `List/ExpandableBaseView.swift`
- `List/RowTintModifier.swift`
- `List/SelectItemModifier.swift`
- `List/ShareListItemModifier.swift`

### Menu

- `Menu/AppCommands.swift`
- `Menu/LinkWindowCommandView.swift`
- `Menu/MenuDisplayModeToggle.swift`
- `Menu/MenuUndoRedoButton.swift`
- `Menu/MenuWindowButtonView.swift`
- `Menu/ModuleCommands.swift`
- `Menu/SelectedModuleKey.swift`
- `Menu/WindowKeyViewModifier.swift`

### Model

- `Model/ChildEntryModel.swift`
- `Model/CodableColor.swift`
- `Model/EditorLinkModel.swift`
- `Model/FolderListModel.swift`
- `Model/FolderRepresentable.swift`
- `Model/GameModel.swift`
- `Model/GameModus.swift`
- `Model/GeneratorRootModelTV.swift`
- `Model/GroupItemSelectionModel.swift`
- `Model/ItemDataExportModel.swift`
- `Model/ItemListable.swift`
- `Model/ItemSelection.swift`
- `Model/ItemSelectionModel.swift`
- `Model/JSONString.swift`
- `Model/LinkData.swift`
- `Model/LinkDataModel.swift`
- `Model/LinkDataTransferable.swift`
- `Model/ListDisplayModel.swift`
- `Model/MapActions.swift`
- `Model/NetworkCodableDataType.swift`
- `Model/NetworkModules.swift`
- `Model/Observable+Stream.swift`
- `Model/OpenFileWindowModel.swift`
- `Model/RPGMessageActionType.swift`
- `Model/RemoveEntryListModel.swift`
- `Model/ResultCategory.swift`
- `Model/SearchModel.swift`
- `Model/SearchResult.swift`
- `Model/ShareValueResult.swift`
- `Model/TagFilterList.swift`
- `Model/ValidateRepairModel.swift`
- `Model/ValueActions.swift`
- `Model/WindowItemSelection.swift`

### Navigator

- `Navigator/Core/AnyNavigationDestination.swift`
- `Navigator/Core/NavigationAction.swift`
- `Navigator/Core/NavigationConfiguration.swift`
- `Navigator/Core/NavigationDestination.swift`
- `Navigator/Core/NavigationDismiss.swift`
- `Navigator/Core/NavigationEventLogging.swift`
- `Navigator/Core/NavigationFind.swift`
- `Navigator/Core/NavigationLocked.swift`
- `Navigator/Core/NavigationMethod.swift`
- `Navigator/Core/NavigationModifiers.swift`
- `Navigator/Core/NavigationOperations.swift`
- `Navigator/Core/NavigationPresentation.swift`
- `Navigator/Core/NavigationProvidedDestination.swift`
- `Navigator/Core/NavigationRoutes.swift`
- `Navigator/Core/NavigationSceneStorage.swift`
- `Navigator/Core/NavigationSend.swift`
- `Navigator/Core/Navigator.swift`
- `Navigator/Extensions/LazyState.swift`
- `Navigator/Extensions/NavigationLink+Navigator.swift`
- `Navigator/Protocols/AsyncCallback.swift`
- `Navigator/Protocols/Binding+Extension.swift`
- `Navigator/Protocols/Callback.swift`
- `Navigator/Protocols/NavigationURLHandler.swift`
- `Navigator/Protocols/NavigationViewProviding.swift`
- `Navigator/Protocols/NavigationViewRouting.swift`
- `Navigator/Views/ManagedNavigationStack.swift`
- `Navigator/Views/ManagedPresentationView.swift`
- `Navigator/Views/NavigationProvidedView.swift`

### Parser

- `Parser/RegularExpressionParser.swift`

### Persistence

- `Persistence/CloudKitAccountController.swift`
- `Persistence/CloudKitCoreDataPersistenceController.swift`
- `Persistence/CloudKitSyncStatusView.swift`
- `Persistence/CoreDataChangeObserver.swift`
- `Persistence/CoreDataController.swift`
- `Persistence/CoreDataPersistenceController.swift`
- `Persistence/FilePersistenceController.swift`
- `Persistence/PersistentHistoryTrackerManager.swift`
- `Persistence/RpgSpotlightIndexerDelegate.swift`

### Platform

- `Platform/Color+Background.swift`
- `Platform/GlasseffectAll.swift`
- `Platform/NavigationStackWrapper.swift`
- `Platform/TextFieldAll.swift`
- `Platform/ToolbarSecondaryPlacement.swift`

### Property Wrappers

- `PropertyWrappers/IgnoreEquatableHashable.swift`

### Resources

- `Resources/Assets.xcassets/Colors/AdventureBackground.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/AdventureTint.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/AudioBackground.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/AudioTint.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/CharacterBackground.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/CharacterTint.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/Contents.json`
- `Resources/Assets.xcassets/Colors/DiceBackground.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/DiceTint.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/MapBackground.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/MapTint.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/PdfBackground.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/PdfTint.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/PhotoBackground.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/PhotoTint.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/SpaceBackground.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/SpaceTint.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/TableBackground.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/TableTint.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/WeatherBackground.colorset/Contents.json`
- `Resources/Assets.xcassets/Colors/WeatherTint.colorset/Contents.json`
- `Resources/Assets.xcassets/Contents.json`
- `Resources/Localizable.xcstrings`
- `Resources/Model.xcdatamodeld/Model.xcdatamodel/contents`

### Routes

- `Routes/AppInitialRouteType.swift`
- `Routes/AppModeRouteType.swift`
- `Routes/AppNavigationModel.swift`
- `Routes/InternalRoute.swift`
- `Routes/KnownRoutes.swift`
- `Routes/ModuleNavigationModel.swift`

### Rows

- `Rows/ColoredBackgroundRowModifier.swift`
- `Rows/ColoredEditRowModifier.swift`
- `Rows/ColoredTagRowModifier.swift`

### Scenes Manager

- `ScenesManager/Modifiers/ImmersiveSpaceTrackerModifier.swift`
- `ScenesManager/Modifiers/SceneTrackerModifier.swift`
- `ScenesManager/ModuleRouting.swift`
- `ScenesManager/SceneId+Windows.swift`
- `ScenesManager/SceneId.swift`
- `ScenesManager/ScenesManager.swift`

### Settings

- `Settings/ColorSchemeSettingView.swift`

### Shaders


### Sheet

- `Sheet/SheetBorderViewModifier.swift`
- `Sheet/SheetContextMenuView.swift`
- `Sheet/SheetEditorModel.swift`
- `Sheet/SheetEntryAddGroupButton.swift`
- `Sheet/SheetEntryButtons.swift`
- `Sheet/SheetEntryView.swift`
- `Sheet/SheetModel.swift`
- `Sheet/SheetRootEditorView.swift`
- `Sheet/SheetRootModel.swift`
- `Sheet/SheetRootView.swift`
- `Sheet/SheetView.swift`
- `Sheet/TableRootSheet.swift`
- `Sheet/TableSheetView.swift`

### Stores

- `Stores/DebouncerModel.swift`

### Tab Navigation

- `TabNavigation/ContentUnavailable.swift`
- `TabNavigation/ZoomTransitionViewModifier.swift`

### Text

- `Text/BlurText.swift`
- `Text/ContentAttributes.swift`
- `Text/ContentFormattingDefinition.swift`
- `Text/EntryTextParser.swift`
- `Text/OnboardingEmphasisAttribute.swift`

### View Modifiers

- `ViewModifiers/DeviceRotateViewModifier.swift`
- `ViewModifiers/FocusModifiers.swift`
- `ViewModifiers/IfModifier.swift`
- `ViewModifiers/KeyboardAvoiding.swift`
- `ViewModifiers/LinkDragViewModifier.swift`
- `ViewModifiers/NavigationVisibility.swift`
- `ViewModifiers/NumericViewModifier.swift`
- `ViewModifiers/RemoveItemViewModifier.swift`
- `ViewModifiers/SheetFullScreenModifier.swift`
- `ViewModifiers/TabBarMinimizeBehavior26.swift`
- `ViewModifiers/VerticalLabelStyle.swift`

### Views

- `Views/AnimatorView.swift`
- `Views/DropItemModuleArea.swift`
- `Views/FlipView.swift`
- `Views/GroupBoxTV.swift`
- `Views/HideKeyboardView.swift`
- `Views/InpectorUnavailableView.swift`
- `Views/RotatePhotoView.swift`
- `Views/SectionGroupEditorView.swift`
- `Views/SendFeedbackButton.swift`
