# Root Models And Setup

This document explains how MasterRPG wires each module root and why the
`xRootModel` classes are the stable ownership boundary for module state.

Related docs:

- [Controllers](CONTROLLERS.md)
- [Database Handling](DATABASE.md)
- [File Handling](FILES.md)
- [Game Connections](GAME_CONNECTIONS.md)

## Mental Model

MasterRPG is built around module roots. Each RPG domain has an `xRootModel`
(`AdventureRootModel`, `TableRootModel`, `PhotoRootModel`, and so on). A root
owns the module's controllers, lightweight UI state models, dependencies on other
modules, and an `ItemRootController` facade.

The app does not create controllers ad hoc inside views. `AppModel` creates all
roots once, builds a `RootManager` that can find every root by `NetworkModules`,
then injects the database contexts and shared link register during setup.

```mermaid
flowchart TD
    "MasterRPGApp" --> "AppModel.shared"
    "AppModel init" --> "Create module roots"
    "AppModel init" --> "Create GameRoot"
    "AppModel init" --> "Create RootManager"
    "DataBaseModel.setup()" --> "Core Data contexts"
    "AppModel.setupRootModels" --> "AdventureRootModel.setUp"
    "AdventureRootModel.setUp" --> "LinkRegisterController"
    "AdventureRootModel.setUp" --> "setUp on every content root"
    "Every content root" --> "ItemRootController facade"
```

Important source anchors:

- `Sources/MasterRPG/MasterRPGApp.swift` registers `AppModel`, navigators, and module roots in `AppDependencyManager`.
- `Modules/RolePlayGameKit/Model/AppModel.swift` creates roots, `GameRoot`, and `RootManager`, then exposes `setupRootModels`.
- `Modules/CoreRPG/Controllable/RootManager.swift` is the module lookup table.
- `Modules/AdventureRPG/Root/AdventureRootModel.swift` owns the setup cascade and shared link register.
- Representative module roots: `Modules/TableRPG/Root/TableRootModel.swift`, `Modules/MapRPG/Root/MapRootModel.swift`, `Modules/PdfRPG/Root/PdfRootModel.swift`, `Modules/DiceRPG/Root/DiceRootModel.swift`.

## Root Setup Lifecycle

### 1. Root Construction

`AppModel.init` builds roots in dependency order:

1. Independent roots first: dice, photo, audio, PDF, space, generator.
2. Roots that depend on other modules next: table depends on dice and PDF; weather depends on photo; character depends on dice, PDF, photo, and table; map depends on audio, dice, PDF, photo, table, and character.
3. `AdventureRootModel` is created last because it is the hub and links all modules.
4. `GameRoot` receives all content roots and owns game networking/session controllers.
5. `RootManager` receives all roots as `ItemRootControllable`.

This is visible in `AppModel.init`, where the roots are created before the
database is ready. Root constructors must not assume a Core Data context exists.

### 2. Root `init`

Each content root constructor creates the same categories of state:

- `ModuleConfiguration`: module token, icons, categories, file types, link selection rules.
- `ModuleNavigationModel`: selected detail item and module navigation state.
- `ItemSelectionModel`: selection state for list/link pickers.
- `RemoveEntryListModel`: UI state for removing entries.
- `SearchModel` and `ListDisplayModel`: search and list mode state.
- Module dependencies, such as `diceRoot`, `pdfRoot`, `photoRoot`, or `characterRoot`.
- Module controllers.
- `EditorLinkModel`: the cross-module picker model used by inspectors/editors.
- `OpenFileWindowModel`: routes file-backed items into viewer windows.
- `ItemRootController`: protocol facade for views and generic app infrastructure.

`TableRootModel` is the compact example. It builds `ItemController`,
`SheetController`, `ExportController`, `GameController`, `LinkController`,
`EditController`, `ImportController`, `SearchController`, two
`FolderListController` instances, `EditorLinkModel`, `OpenFileWindowModel`, and
the final `ItemRootController`.

`MapRootModel` shows a module with heavier cross-module dependencies. It stores
audio, dice, PDF, photo, table, and character roots, then lazily creates
controllers that need `self`, including map link/export/game/edit controllers.

### 3. Database Setup

The database is separate from root construction. `DataBaseModel.setup()` loads
Core Data either as a local store or CloudKit store, then exposes:

- `context`: the background context used by module `DataController`s.
- `batchContext`: a second background context for batch operations.
- `spotlightIndexer`: optional Spotlight indexer on platforms that support it.
- `coreDataInitModel`: setup state, error, and CloudKit sync state.

When the database is ready, `AppModel.setupRootModels(context:batchContext:...)`
calls:

```swift
tagController.setup(context: context)
adventureRoot.setUp(root: root, context: context, batchContext: batchContext)
```

The Adventure root then creates one shared `LinkRegisterController`, sets it up
with the same context, and injects that register into every module root. This is
why link registration is global, not per module.

Database internals live in [Database Handling](DATABASE.md).

### 4. Module `setUp`

Every regular content root follows the same `setUp` pattern:

1. Store `rootManager` in the `ItemRootController`.
2. Attach a module-specific `DataController` to `itemController.itemDataModel.dataController`.
3. Attach the shared `LinkRegisterController` to `itemController.itemDataModel.linkRegisterController`.
4. Point the `ExportController` at the Adventure root as `hubControllable`.
5. Build the editor `SheetRootModel` with the real `RootManager`.
6. Give `EditorLinkModel` the real `RootManager`.
7. Cancel any old sync task.
8. If a context exists, create `SyncDataController` and start it.

That last part hydrates in-memory item lists from Core Data and keeps
CloudKit-driven updates flowing back into controllers.

### 5. Preview And Test Roots

Preview/test roots often call `setUp(context: nil, batchContext: nil, ...)`.
That gives views and tests a full controller graph without database persistence.
Some modules first set up with `RootManager.preview(fake:)`, then rebuild with a
real `RootManager` once all dependent preview roots exist.

## Root Facades

`ItemRootControllable` is the shared root protocol. Views and generic
infrastructure use it instead of knowing a concrete module root type. It exposes:

- module configuration and navigation model
- selection and remove-entry models
- cache, edit, export, game, import, item, link, folder, search, sheet, and view controllers
- the module's `ItemRootController`

`ItemRootController` is a concrete `@Observable` facade containing the same
protocol properties. It is deliberately boring: it does not implement business
logic; it keeps the root graph addressable through common protocols.

`RootManager` is a `NetworkModules` switchboard. It maps `.adventure`, `.audio`,
`.dice`, `.map`, `.pdf`, `.photo`, `.space`, `.table`, `.value`, `.weather`, and
`.generator` to their `ItemRootControllable` roots. Link rendering, sheets,
global search, routes, and import/export use it whenever a module needs to cross
into another module.

## Adding Or Changing A Module Root

When adding a new module root, keep these invariants:

1. Construct controllers in `init` without assuming database context exists.
2. Expose everything through `ItemRootController`.
3. Implement `ItemRootControllable`.
4. Add the root to `RootManager`.
5. Add the root to `AppModel.init` in dependency order.
6. Add the module bundle to `DataBaseModel.rpgModuleBundles`.
7. In `setUp`, attach `DataController`, shared `LinkRegisterController`, `RootManager`, `SheetRootModel`, and `SyncDataController`.
8. If file-backed, create a `FileUrlDataController`, cache controller, and `FileUrlAccessible.saveFileUrl` implementation.
9. If game-capable, implement `GameControllable` and any module-specific game protocol used by `GameRoot`.
10. If the module links to other modules, make export include linked dependencies and make models produce correct `linkRegisterModels`.
