# Root Models, Controllers, Database, And Files

This page is now an index. The original combined deep dive has been split so
each topic has one clear owner.

## Deep Dives

- [Root Models And Setup](ROOT_MODELS.md): `xRootModel` construction, setup order, root facades, `RootManager`, and the module-root checklist.
- [Controllers](CONTROLLERS.md): controller family responsibilities, import/export controllers, link register repair, and game controller ownership.
- [Database Handling](DATABASE.md): `DataBaseModel`, local/CloudKit Core Data, contexts, `CoreDataController`, sync, and save aggregation.
- [File Handling](FILES.md): `FileUrl`, `FileUrlDataController`, `FileDataController`, content hashes, file-backed modules, and file import/export.
- [Game Connections](GAME_CONNECTIONS.md): authoritative game communication details, message envelope, counters, master/player/proxy behavior, photo transfer scenarios, and module network messages.

## How The Docs Fit

```mermaid
flowchart TD
    "Root Models And Setup" --> "Controllers"
    "Root Models And Setup" --> "Database Handling"
    "Controllers" --> "File Handling"
    "Controllers" --> "Game Connections"
    "Database Handling" --> "File Handling"
    "Game Connections" --> "File Handling"
```

Use this page when you need a map. Use the linked pages when you need the
actual implementation details.
