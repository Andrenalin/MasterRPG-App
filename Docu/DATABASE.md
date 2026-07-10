# Database Handling

This document explains how MasterRPG sets up persistence, how module data moves
between Core Data and in-memory controllers, and where CloudKit/local store
behavior differs.

Related docs:

- [Root Models And Setup](ROOT_MODELS.md)
- [Controllers](CONTROLLERS.md)
- [File Handling](FILES.md)

## Store Selection

`DataBaseModel` chooses the persistence stack:

- tvOS always uses local Core Data.
- other platforms use `settingsModel.useCloudKit` unless an in-memory preview/test store is requested.
- switching CloudKit/local through settings clears `hasContextSet`, forcing setup to rebuild contexts.

The root graph is created before a database context exists. After
`DataBaseModel.setup()` finishes, `AppModel.setupRootModels(context:batchContext:...)`
injects the context into the roots. `AdventureRootModel.setUp` then cascades
setup across all module roots and supplies the shared `LinkRegisterController`.

## Model Loading

All module Core Data bundles are merged with
`NSManagedObjectModel.mergedModel(from: DataBaseModel.rpgModuleBundles)`.
This includes CoreRPG plus every module bundle, and GeneratorRPG on non-tvOS.

Adding a new persisted module requires adding its bundle to
`DataBaseModel.rpgModuleBundles`, adding a module `DataController`, and wiring
that controller during the module root's `setUp`.

## Local Core Data

`CoreDataPersistenceController` creates:

- app group folder `Stores/Local`
- `MasterRPGLocal` persistent container
- `local.sqlite`
- persistent history tracking
- remote change notifications
- background context named `background_context`
- batch context named `batchContext`
- merge policy `NSMergeByPropertyObjectTrumpMergePolicy`
- transaction author from `AppPersistentActor`
- Spotlight indexing where supported
- persistent history tracker and daily cleaner

## CloudKit Core Data

`CloudKitCoreDataPersistenceController` creates:

- app group folder `Stores/Private`
- `MasterRPGCloudKit` persistent CloudKit container
- `private.sqlite`
- `NSPersistentCloudKitContainerOptions` for private database scope when sync is enabled
- the same background and batch contexts as local mode
- CloudKit event monitoring for setup/import/export progress
- persistent history tracking and cleanup

The CloudKit container identifier in code is
`iCloud.de.andretrettin.gamemaster`.

## Contexts

The app uses background contexts for module persistence:

- `context`: normal module item reads/writes
- `batchContext`: batch-style reads/writes

Module roots receive both contexts during `setUp`. A root attaches a
module-specific `DataController` to `itemController.itemDataModel.dataController`
and starts `SyncDataController` when a context exists.

Preview/test roots can be set up with nil contexts. That gives views/tests a full
controller graph with no Core Data writes.

## CoreDataController

`CoreDataController<Model, DataType>` is the generic mapper executor. It provides:

- fetch all, fetch ids, fetch by UUID
- replace existing or insert new
- queued replace operations
- sendable snapshot replace/fetch variants
- flush pending operations without saving
- save with pending flush
- batch replace
- context-delete batch delete

Two important implementation details:

- Pending replace operations are stored in a `Mutex`, not a task queue, so rapid edits preserve order and are visible to the next flush.
- Batch delete does not use `NSBatchDeleteRequest` because CloudKit mirroring would not see those deletes. It fetches matching objects into the context, deletes them, and saves.

## DataController

Each module has a small `DataController` that conforms to
`DataPersistenceControllable`. It maps domain models to Core Data entities and
back. Most current modules use sendable snapshot helpers so Core Data queue work
does not touch `@MainActor` domain models directly.

Data controllers also pass relationship key paths such as `["entries"]` into
`CoreDataController` so fetches prefetch relationships and avoid N+1 loads.

## SyncDataController

`SyncDataController` is the Core Data to memory bridge. `start()` fetches all
stored models once and calls `ItemControllable.updates`. Later CloudKit/history
events call `updateFromSync(deletedIds:insertedIds:updatedIds:)`:

- deleted ids remove in-memory items and caches without deleting database rows again
- inserted ids fetch from Core Data and call `resetModel`
- updated ids fetch from Core Data and call `mergeUpdates`

This avoids writing sync updates straight back to Core Data and causing feedback loops.

## Save Aggregation

`AdventureRootModel.save()` flushes pending operations for all module roots,
then saves pending links and tags, then calls `itemController.save()` once. That
single context save covers the flushed module updates. This is the main "save the
whole app" path used by `AppModel.save()`.

Game mode can bypass persistence. When `itemDataModel.isGameMode` is true and an
update is not forced to save, `ItemController.replace` writes to game memory
instead of Core Data. The explicit game path is
`replaceForGame(model:isInsert:policy:)` with `.memoryOnly` or `.persist`.

## Database And Files Boundary

Core Data stores structured item models and `FileUrl` metadata. It does not store
large media payloads as the normal file path. Item media lives in app-managed
folders, security-scoped locations, or iCloud document locations through
`FileUrlDataController`.

For media storage, content hashes, bookmarks, and import/export file behavior,
see [File Handling](FILES.md).
