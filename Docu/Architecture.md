# MasterRPG Architecture

MasterRPG is a multi-platform Apple app (iOS, macOS, tvOS, visionOS) for managing RPG data during tabletop game sessions. It supports Adventures, Characters, Maps, Photos, Audio, PDFs, 3D Objects, Tables, and Weather, with a live game mode where players join via SharePlay or local network.

Related deep dives:

- [Root Models And Setup](ROOT_MODELS.md)
- [Controllers](CONTROLLERS.md)
- [Database Handling](DATABASE.md)
- [File Handling](FILES.md)
- [Link System](LINKS.md)
- [Game Connections](GAME_CONNECTIONS.md)

---

## App Entry Point

**`Sources/MasterRPG/MasterRPGApp.swift`** — `@main struct MasterRPGApp: App`

Initializes all module roots via `AppDependencyManager`, registers RealityKit components, and creates a multi-scene environment:

| Scene | Purpose |
|---|---|
| Game Window | Active game play view |
| Editor Window | Content creation/editing |
| Viewer Windows | Per-module fullscreen viewers |
| Link Windows | Cross-module link viewing |
| Settings/Search | Utility panels |

---

## App State — `AppModel`

**`Modules/RolePlayGameKit/Model/AppModel.swift`**

`@MainActor @Observable public final class AppModel` — the top-level state container injected everywhere via `@Environment(AppModel.self)`.

Key properties:

| Property | Type | Purpose |
|---|---|---|
| `databaseModel` | `DataBaseModel` | CoreData/CloudKit stack |
| `scenesManager` | `ScenesManager` | Window management |
| `settingsModel` | `SettingsModel` | App preferences |
| `appGameStateModel` | `AppGameStateModel` | `isGameRunning`, `gameModus` |
| `selectedModule` | `RootRoute?` | Active tab |
| `selectedEditorModule` | `RootRoute?` | Editor tab |
| `selectedExtendedModule` | `ExtendedTabRoute?` | Extended editor tab |
| `adventureRoot` … `weatherRoot` | Module roots | All 10 content module roots |

---

## Navigation Layer

### Route Enums

**`RootRoute`** — top-level tabs:
```
adventures | audios | dice | editors | game | generator | maps | pdfs | photos | search | settings | space | tables | values | weathers
```

**`ExtendedTabRoute`** — secondary editor tabs (modules surfaced in editor sidebar):
```
audios | dice | generator | maps | pdfs | photos | space | tables | weathers | settings
```

**`NetworkModules`** — maps each module to its network token, icon, color, and `SceneId` for window routing.

### Navigator

**`Modules/CoreRPG/Navigator/Core/Navigator.swift`**

`@MainActor @Observable final class Navigator` — one instance per window. Manages:

| Property | Purpose |
|---|---|
| `path` | Navigation stack |
| `sheet` / `cover` | Modal presentation |
| `checkpoints` | Named back-navigation positions |
| `navigationLocks` | Prevents mid-game navigation |

### Navigation Views

**`Modules/RolePlayGameKit/View/`**

| View | Platform | Layout |
|---|---|---|
| `TabbedNavigation` | iOS/iPad | Tab bar with RootRoute tabs |
| `TabbedSplitNavigation` | iPad | Tabs + sidebar split |
| `SplitNavigation` | macOS | Sidebar + detail split |
| `SplitEditorNavigation` | macOS | Editor-specific split |
| `ExtendedTabBar` | iOS/iPad/macOS | Secondary editor tabs |

All use `ManagedNavigationStack` wired to their window's `Navigator`.

---

## Module Architecture (Standard Pattern)

Every module follows this folder layout:

```
Modules/<Name>RPG/
  Controller/   — business logic
  Model/        — @Observable domain models
  View/         — SwiftUI views
  Root/         — RootModel.swift (module entry point)
  Route/        — navigation route enums
  Intent/       — App Intents (Siri, Shortcuts)
  Menu/         — macOS/iPad menu commands
  Resources/    — CoreData .xcdatamodeld
```

### Controller Types (per module)

| Controller | Responsibility |
|---|---|
| `ItemController` | CRUD list management, triggers database saves |
| `EditController` | In-memory edit state during user editing |
| `DataController` | Maps domain models ↔ CoreData entities |
| `SyncDataController` | Merges CloudKit deltas into `ItemController` |
| `GameController` | Game-mode logic |
| `ImportController` | File/network import |
| `ExportController` | JSON/binary export for streaming |
| `LinkController` | Cross-module link generation and validation |
| `SearchController` | Filter and search |
| `FolderListController` | List/folder display and selection state |
| `SheetController` | Sheet/character-sheet rendering |

---

## Data Model Pattern

All domain models are `@Observable final class` with **CRDT-wrapped properties** for conflict-free sync during game networking.

```swift
@Observable public final class AdventureModel: Identifiable, @unchecked Sendable {
    public var id: UUID
    public var name: String                     // internally CRDT<String>
    public var description: String
    public var tags: [String]
    public var category: ItemListCategory
    public var entries: [AdventureEntryModel]   // CRDTDataUpdate
    public var photoId: UUID?
    public var parentId: UUID?                  // folder hierarchy
}
```

Each module has a parallel **CoreData entity** (e.g. `RPGAdventure`, `RPGPhoto`). `DataController` maps between the two; `SyncDataController` handles CloudKit merge conflicts via CRDT logic.

**Key invariant:** A domain model's version must remain stable across game export/import — CRDT properties only bump versions on genuine value changes, not on serialization.

---

## Module Walkthroughs

### AdventureRPG
The story hub. `AdventureModel` holds entries that can embed content from every other module (dice rolls, photos, maps, PDFs, audio, weather, characters). `AdventureRootModel` holds references to all other module roots.

**Key types:** `AdventureModel`, `AdventureEntryModel`, `AdventureRootModel`
**CoreData:** `RPGAdventure`, `RPGAdventureEntry`

---

### CharacterRPG
Manages characters, NPCs, and monsters. `ValueModel` organizes stat values into groups, linking dice, photos, PDFs, and tables. Character sheets are generated by `SheetController`.

**Key types:** `ValueModel`, `ValueEntryModel`, `ValueRootModel`
**CoreData:** `RPGValues`, `RPGValuesEntry`

---

### MapRPG
Photo-based maps with masking layers (rooms) to hide content from players. Has a dedicated `MapEditor`. Maps link to characters, dice, tables, audio, photos, PDFs, and other maps.

**Key types:** `MapModel`, `MapEntryModel`, `MapRootModel`
**CoreData:** `RPGMap`, `RPGMapEntry`

---

### DiceRPG
Dice rolling engine. `DiceModel` contains an array of `DieModel`s with modifiers, reroll rules, coup/fumble values, and compare options. Results feed the `DiceRollerWidget`.

**Key types:** `DiceModel`, `DieModel`, `DiceRootModel`
**CoreData:** `RPGDice`, `RPGDie`

---

### PhotoRPG
Photo/image management backed by iCloud file storage. `PhotoModel` holds a CRDT-wrapped `fileUrl: FileUrl?` plus metadata. `FileUrl.data` is a transient transport field used only during game streaming (excluded from equality/hash to prevent spurious version bumps).

**Key types:** `PhotoModel`, `PhotoEntryModel`, `PhotoRootModel`
**CoreData:** `RPGPhoto`, `RPGPhotoEntry`

---

### AudioRPG
Audio playback coordination with iCloud file storage. Similar file-backed pattern to PhotoRPG.

**Key types:** `AudioModel`, `AudioEntryModel`, `AudioRootModel`
**CoreData:** `RPGAudio`, `RPGAudioEntry`

---

### PdfRPG
PDF document management with iCloud file storage.

**Key types:** `PdfModel`, `PdfEntryModel`, `PdfRootModel`
**CoreData:** `RPGPdf`, `RPGPdfEntry`

---

### TableRPG
Lookup tables for random content. Can link to dice, PDFs, and other tables. Used heavily by character and adventure modules.

**Key types:** `TableModel`, `TableEntryModel`, `TableRootModel`
**CoreData:** `RPGTables`, `RPGTablesEntry`

---

### WeatherRPG
Weather effects, linkable to photos for atmospheric backdrops.

**Key types:** `WeatherModel`, `WeatherEntryModel`, `WeatherRootModel`
**CoreData:** `RPGWeather`, `RPGWeatherEntry`

---

### SpaceRPG
3D object management with iCloud file storage. Uses `RPGTabletopGameContent` (SPM) for visionOS 3D content.

**Key types:** `SpaceModel`, `SpaceEntryModel`, `SpaceRootModel`
**CoreData:** `RPGSpace`, `RPGSpaceEntry`

---

### GameRPG
Multiplayer game orchestration:
- `MasterController` — broadcasts game state to players
- `PlayerController` — receives and applies game state
- SharePlay + Bonjour/local network discovery
- `GameModel` — roster, selected character, active game master
- visionOS: `GameTableView` uses TableTopKit for spatial table display

**Key types:** `GameModel`, `GameRootModel`, `MasterController`, `PlayerController`

---

### GeneratorRPG
On-device AI content generation using Apple's FoundationModels framework. Active in PDF and Adventure modules; planned for Character.

---

### CoreRPG
Shared infrastructure used by all modules:
- `Navigator` — per-window navigation stack
- CRDT types — conflict-free replicated data
- `LinkRegisterController` — tracks cross-module references
- `AppGameStateModel` — global game running state
- `AppNavigationModel` — shared navigation helpers
- Shared view components, formatters, and utilities

---

### RolePlayGameKit
The assembly layer. Merges all modules and provides:
- `AppModel` — top-level state container
- All navigation views (`TabbedNavigation`, `SplitNavigation`, etc.)
- `WindowRouter` — routes URLs and events to the correct window
- `RootURLHandler` — deep link handling

---

## CoreData / Persistence

Each module defines its own `.xcdatamodeld` file. `NSPersistentCloudKitContainer` provides CloudKit sync. `DataController` per module maps between domain models and CoreData entities.

**CoreRPG shared entities:**
- `LinkReferenceDataModel` — cross-module link tracking
- `TagDataModel` — tag/category storage

---

## Data Flow

```
App Launch
  └─ AppModel init
       └─ All module RootModels registered via AppDependencyManager
            └─ DatabaseModel (CoreData + CloudKit) configured
                 └─ Each ItemController loads entities → maps to domain models

User Navigation
  └─ RootRoute selected → Navigator.path updated
       └─ ManagedNavigationStack renders matching View
            └─ Views read @Observable models, write back via EditController
                 └─ ItemController saves → DataController writes CoreData
                      └─ CloudKit syncs → SyncDataController merges CRDT deltas

Game Mode
  └─ AppGameStateModel.isGameRunning = true
       └─ MasterController / PlayerController stream ExportController output
            └─ CRDT values resolve conflicts → domain models update
                 └─ Views re-render via Observation framework
```

---

## Platform Conditionals

| Macro | Platforms |
|---|---|
| `#if os(iOS)` | iOS-specific tab bar, idle timer |
| `#if os(macOS)` | App delegate, window management, menu commands |
| `#if os(visionOS)` | 3D space models, spatial UI, TableTopKit |
| `#if os(tvOS)` | TV-specific layout |
| `#if !WIDGET_EXTENSION` | Excludes APIs unavailable in widget extension |

---

## App Groups & Entitlements

| Entitlement | Value |
|---|---|
| App Group | `group.de.andretrettin.MasterRPG` |
| iCloud Container | `iCloud.de.andretrettin.MasterRPG` |
| Background Modes | audio, airplay, remote-notification, fetch |

---

## Dependencies

| Dependency | Source | Purpose |
|---|---|---|
| `RPGTabletopGameContent` | SPM | visionOS 3D tabletop content |
