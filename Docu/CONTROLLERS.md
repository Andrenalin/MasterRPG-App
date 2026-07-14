# Controllers

This document explains the controller families behind the `xRootModel` setup.
It keeps controller responsibilities here and leaves low-level game transport,
message counters, proxy topology, and message examples in
[Game Connections](GAME_CONNECTIONS.md).

Related docs:

- [Root Models And Setup](ROOT_MODELS.md)
- [Database Handling](DATABASE.md)
- [File Handling](FILES.md)
- [Game Connections](GAME_CONNECTIONS.md)

## Controller Map

Each content root owns module-specific controller structs, then exposes them
through `ItemRootController` so views and shared infrastructure can work through
protocols.

```mermaid
flowchart TD
    "xRootModel" --> "ItemRootController"
    "ItemRootController" --> "ItemController"
    "ItemRootController" --> "EditController"
    "ItemRootController" --> "ImportController"
    "ItemRootController" --> "ExportController"
    "ItemRootController" --> "GameController"
    "ItemRootController" --> "LinkController"
    "ItemRootController" --> "FolderListController"
    "ItemRootController" --> "SearchController"
    "ItemRootController" --> "SheetController"
    "File-backed roots" --> "CacheController"
    "GameRoot" --> "MasterController"
    "GameRoot" --> "PlayerController"
    "GameRoot" --> "GameNetworkController"
```

## ItemController

`ItemController` owns the in-memory item list and the module's `ItemDataModel`.
The shared `ItemControllable` extension supplies most behavior:

- create items from `Model.empty.copy()`
- delete items, optionally deleting backing files
- replace items in Core Data or game memory
- merge imported/game updates with CRDT-aware models
- batch reset all data
- fetch item children and partial folder/collection exports
- expose `fileUrlDataController` and `cacheControllable` when the module is file-backed

Important game behavior: if `itemDataModel.isGameMode` is true and an update is
not forced to save, `replace(model:isInsert:)` writes to `gameItemData` instead
of Core Data. The explicit game path is `replaceForGame(model:isInsert:policy:)`
with `.memoryOnly` or `.persist`.

## EditController

`EditController` works on copies of items, validates before save, updates tags,
handles folder/collection membership, resets files, duplicates/restores/deletes
items, and owns editor undo state.

The important save path is:

1. `editModel(for:)` returns a copy.
2. The edit method changes the copy.
3. `save(updated:message:)` calls `saveChanges(to:name:)`.
4. `saveChanges` compares old/new link-register models.
5. Removed links are deregistered, new links are registered.
6. Undo history is updated.
7. `ItemController.replace` persists or updates game memory depending on mode.

Import does not naturally pass through the full editor save path, so
`ConvertController.repairImportedItems` rebuilds link-register entries for
imported items after import.

## DataController

Each module has a small `DataController` that conforms to
`DataPersistenceControllable`. It maps domain models to Core Data entities and
back. The common Core Data implementation is `CoreDataController<Model, DataType>`.

Most current modules use sendable snapshot helpers so Core Data queue work does
not touch `@MainActor` domain models directly. Data controllers also pass
relationship key paths such as `["entries"]` into `CoreDataController` so fetches
prefetch relationships and avoid N+1 loads.

For store selection, contexts, local/CloudKit stores, and save aggregation, see
[Database Handling](DATABASE.md).

## SyncDataController

`SyncDataController` is the Core Data to memory bridge. `start()` fetches all
stored models once and calls `ItemControllable.updates`. Later CloudKit/history
events call `updateFromSync(deletedIds:insertedIds:updatedIds:)`:

- deleted ids remove in-memory items and caches without deleting database rows again
- inserted ids fetch from Core Data and call `resetModel`
- updated ids fetch from Core Data and call `mergeUpdates`

This avoids writing sync updates straight back to Core Data and causing feedback loops.

## ImportController

Module `ImportController` structs mostly conform to the shared
`ImportControllable` extension. The shared importer handles the `.gmz`/stream
format, merge modes, file tokens, and post-import repair. Modules can override
`additionalImport` for extra stream sections.

Import modes:

- `.merge`: merge with local item if present; skip unchanged imports.
- `.overwrite`: replace local item with the imported item.
- `.manual`: collect review items and deletion candidates without applying immediately.

The import stream reads module headers until it finds the module token. Unknown
module sections are skipped. A `file` token applies only to the next `item` token,
then it is cleared so later file-less items do not inherit the old bytes.

Post-import repair, unless in manual review:

- clean folder entries
- detach orphaned items from missing parents
- unhide orphaned hidden items
- normalize legacy categories/tags
- remove illegal photo entry grouping
- rebuild link-register entries for imported items

File import behavior is detailed in [File Handling](FILES.md#files-during-import).

## ExportController

Module `ExportController` structs conform to `ExportControllable`. The shared
exporter writes:

1. top-level file header for normal exports
2. one module header per exported module
3. optional `file` token bytes before the item
4. `item` token with JSON-encoded domain model

`ExportControllable.export(itemIds:into:)` calls the module-specific
`additionalExport`, then extracts the current module. After extracting a module,
it removes that module's ids from the pending `ItemModuleIds`, so the Adventure
root/hub can continue exporting the remaining modules.

Special export behavior:

- `exportingAll()` excludes items with `displayState == 2`.
- `exportingFolder(results:)` promotes complete folders and records partial folders.
- `item(for:fullIds:partialIds:)` strips partial folder entries so partial exports contain only the selected descendants.
- File-backed modules inline binary bytes unless `exportWithoutFileData` is true.
- Photo export can fall back to cached JPEG data when the original file data is not available.
- Module export controllers may recursively add linked item ids, as table export does for linked dice/PDF/table content.

The token format is shared with game payloads. See
[Game Connections - GameControllable Import/Export Contract](GAME_CONNECTIONS.md#14-gamecontrollable-importexport-contract).

## LinkController And LinkRegisterController

`LinkController` generates Markdown/RPG URLs, toggles link text into content,
validates broken links, repairs stale links by matching names, and collects links
for export/game dependency traversal.

`LinkRegisterController` is the global reverse index. It is keyed by destination
item id and stores `LinkRegisterModel` values from source item/entry to
destination item/entry. This supports "who uses this item?" lookups across all
modules.

Normal edits update the register through `EditControllable.saveChanges`.
Imported data is repaired through `ConvertController.resetLinkRegister(for:)`.

## FolderListController

`FolderListController` owns list and folder presentation state. It builds root
lists and scoped detail lists through `SearchRootControllable`, debounces/coalesces
searches, handles selection restore after model changes, and routes add/delete/move
operations into `EditController` and `ItemController`.

There are usually two instances:

- main list controller for module browsing
- link list controller for editor/link inspectors

## SearchController

`SearchController` implements flat, folder, inspector, and global searches. The
shared `SearchControllable` logic handles:

- global visible-item search for the game/search view
- list mode search
- folder mode recursive search
- inspector search including entry name/content matches
- relevance scoring and sorting

Search filtering uses localized comparisons in the shared code path and respects
display mode: compact searches names, medium adds description, regular adds tags.

## SheetController

`SheetController` renders item sheets for editor and game display. It receives
`RootManager` so a sheet can resolve links and nested module content. It supports
folded/unfolded sheet nodes and module depth to avoid unbounded traversal.

## CacheController

File-backed image/PDF/map modules expose `cacheControllable`. Cache controllers
load thumbnails or images through `FileUrlDataController`, remove stale cache
entries when files change, and provide fallback data for game/export when the
original file has to be displayed quickly.

## Game Controllers

This section is a controller ownership summary only. The authoritative game
communication details live in:

- [Message envelope](GAME_CONNECTIONS.md#5-message-envelope)
- [Counters, deduplication, and logs](GAME_CONNECTIONS.md#6-counters-deduplication-and-logs)
- [General request and reply patterns](GAME_CONNECTIONS.md#9-general-request-and-reply-patterns)
- [Transport fan-out details](GAME_CONNECTIONS.md#10-transport-fan-out-details)
- [Proxy topology](GAME_CONNECTIONS.md#11-proxy-topology)
- [Common photo transfer scenarios](GAME_CONNECTIONS.md#12-common-photo-transfer-scenarios)
- [Module entry points to networking](GAME_CONNECTIONS.md#15-module-entry-points-to-networking)

### GameRoot

`GameRoot` is not an `ItemRootControllable`. It is an orchestration root that
holds every content root plus:

- `GameRootModel`: session state, selected master/player/adventure, roster, controls, logs, screen snapshots, SharePlay attachments, and active master/player controllers.
- `GameNetworkController networkStore`: direct local-network/SharePlay controller.
- `GameNetworkController networkProxyStore`: proxy relay controller.
- `MasterController`: active when this device is the game master or proxy master.
- `PlayerController`: active when this device is a player, observer, proxy, or local player.
- `LogGameController`: message log and screen data updates.
- `SearchGlobalController`: global game search.

### GameNetworkController

`GameNetworkController` wraps both Bonjour/local network controllers and SharePlay:

- direct mode (`proxy == false`) owns SharePlay and fans out received data to other peers
- proxy mode (`proxy == true`) avoids SharePlay fan-out to prevent relay loops
- `networkStore` is direct mode
- `networkProxyStore` is proxy mode

Local players can be enabled for same-device flows. When local player mode is on,
the network store can deliver master sends directly to the local player delegate.

### MasterController

`MasterController` is responsible for:

- starting/stopping master streaming
- starting the proxy server
- tracking connection ids to player ids
- atomically reserving `messageCounter`
- sending `GameNetworkModel` broadcasts and targeted repair responses
- serializing/deduplicating incoming messages through `GameMessagePipeline`
- resetting player-dependent module state: audio players, dice player names, map player pins
- handling player requests and returning full `NetworkCodableDataType` payloads
  to the requester
- processing ACKs and player reports
- keeping proxy clients private: serving requests locally when possible and
  remapping eligible upstream messages to the host player's identity

The master handles module-specific messages:

- audio: reveal/store full audio data, play audio, merge/apply audio lists
- dice: reveal/store dice and record dice results
- map: reveal maps, resend `mapState`, update pins, broadcast state
- PDF/photo/table/weather/space/value: reveal/store full payloads and apply updates
- game: record player screen snapshots

### PlayerController

`PlayerController` is responsible for:

- connecting to a browser-discovered master/proxy
- setting up local mode when acting as game master locally
- maintaining monotonic outgoing counters, response counters, deduplication, and
  bounded map/file-repair state
- sending the audio list immediately after ready, then scheduling character data
- applying master broadcasts atomically
- rejecting stale master-state snapshots
- filtering controls and `targetId` by player ID
- relaying messages to proxies
- responding with `.ok`, `.failed`, or "request full data"

Player response behavior is important:

- `.ok`: player applied the data; master can count that player as reported.
- `.failed`: player rejected or could not apply the message.
- same type/subtype with the original item id/type/version and no payload bytes:
  player is requesting full data.

### GameController

Each content module has a `GameController` conforming to `GameControllable`.
The shared `GameControllable` extension supplies the common store/reveal/update
flow:

- `ItemGameModel` keeps game-only item ids, game item data, focus ids, current players, and per-item player report state.
- `createGameData(for:)` exports the requested item and linked dependencies into an in-memory stream.
- `share(id:)` creates a metadata-only `NetworkCodableDataType`.
- `reveal(itemId:data:save:)` checks version and local file availability, importing payloads when needed.
- `updateGame(data:hide:deep:policy:)` imports stream data, applies it to game state, and optionally persists it.
- `importNetwork(from:)` routes game payloads back through the root import controller.

Game updates are not always persisted:

- `hide == true` or `.store` style messages usually go to memory-only game state.
- revealed/saved items can persist through `replaceForGame(..., policy: .persist)`.
- full item payloads are imported through normal import controllers, so game state benefits from the same file and link repair behavior as regular imports.
- `AdventureRootModel.startGame` marks every module `itemDataModel.isGameMode = true`, which changes `ItemController.replace` behavior.

Module game controllers add specifics:

- Adventure: starts game mode across all modules and supplies game title image.
- Audio: tracks current players, audio lists, SharePlay-aware playback coordination, and playlist loading.
- Dice: manages player dice names, dice results, and table result integration.
- Map: synchronizes map reveal, room state/fog, player pins, missing map images, and visionOS board state.
- Photo: synchronizes photo reveal and photo-space state.
- PDF: synchronizes file-backed PDF reveal/store.
- Table: reveals linked table data and receives dice/table result values.
- Character/Value: sends player character data, updates player values, and feeds map pins.
- Weather: reveals weather scenes, often linked to photos.
- Space: reveals 3D objects and synchronizes space transforms.
