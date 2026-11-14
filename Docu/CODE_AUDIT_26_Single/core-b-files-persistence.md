Files read in full: all of Modules/CoreRPG/Files (18 files, ~4.1k LOC), Persistence (16 files, ~2.5k LOC), Cache, Stores, App, AppModels, Intent (12 files, ~1.3k LOC), Instrumentation, Platform, Debug, Widget, plus the riskier files of Model (FolderListModel, LinkDataTransferable, QuickDiceSlotsModel, TablePlayerModel, CloudFolderScanModel, ItemDataExportModel, DeterministicUUID, StableVersionDigest, KeepAwakeModel, NetworkCodableDataType, ItemGeneration, ItemTransferStatus). Roughly 11k of the ~13k LOC. Overall health: very good. The file-coordination layer (limiter, cancellation, non-replacing copies, pending-deletion ordering), the bookmark store, the Core Data flush/rollback ledger and the CloudKit setup are carefully built and carry the fixes of CODE_AUDIT 15 to 25; none of the earlier "Fixed" items regressed. No Critical or High finding survived verification. The findings below are residual edge cases, dead code and test gaps. Greps for `try!`, `as!`, `fatalError`, GCD, `ObservableObject`, `@Published`, `print(`, legacy formatters and `onTapGesture` over the whole area found nothing outside comments; `nonisolated(unsafe)` (1) and `@unchecked Sendable` (6) sites are all justified and documented.

### download(fileUrl:) passes a percent-encoded path as a file path
- Category: Bug
- Location: Modules/CoreRPG/Files/FileUrlDataController+Create.swift:511-519 (feeds CloudDocumentController.download(filePath:) at Modules/CoreRPG/Files/CloudDocumentController.swift:127-131 and fullUrl(filePath:) at :87-89); callers Modules/PdfRPG/Controller/ItemController.swift:43, Modules/CoreRPG/Controllable/ImageCacheControllable.swift:174
- What: `download(fileUrl:)` hands `fileUrl.rawUrl.absoluteString` (percent-encoded, e.g. `/Map%20Name.png`) to `fullUrl(filePath:)`, which splits it on `/` and calls `URL.append(path:)`, which encodes the `%` again.
- Why: Verified with a scratch program: `append(path: "Map%20Name%20%C3%A9.png")` yields a path whose file name literally contains `%20`. For any `.newCloud` file whose name has a space, accent, `#`, `?` or other encoded character, the explicit iCloud download request targets a non-existent file and throws (Pdf logs an error, the image cache swallows it with `try?`). Every other call site uses `path(percentEncoded: false)` or `pathComponents`. The later coordinated read still pulls the bytes, so the effect is a missing prefetch plus error logs, not data loss.
- Action: Resolve through `cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl)` (decoded components) instead of the absolute string, and add a test with a name containing a space and a non-ASCII character (no test calls `download(fileUrl:)` today).
- Severity: Medium
- Status: NEW

### Existence checks coordinate as full reads and can download evicted iCloud files
- Category: Performance
- Location: Modules/CoreRPG/Files/FileManager+Coordination.swift:8-16 (`fileExists(coordinatingAccessAt:)`); callers Modules/CoreRPG/Files/CloudDocumentController.swift:249-257 (`suggestedFileName`), Modules/CoreRPG/Files/FileUrlDataController+Create.swift:40, :375
- What: `fileExists` takes `NSFileCoordinator.coordinate(readingItemAt:options: [])` and even classifies itself as a "may wait for download" access (`mayWaitForDownloadOf: fileURL`). A plain read coordination on a not-downloaded iCloud item asks iCloud to materialize it; `.immediatelyAvailableMetadataOnly` is not used anywhere in the repo.
- Why: Importing or moving an item whose target name collides with an evicted file (a 200 MB audio or USDZ) probably downloads that file just to learn that the name is taken, and occupies a `.download` limiter slot (of 1-3) while it does so, which is the stall CODE_AUDIT_21 §3.8 worked around. Not verified on a device.
- Action: Pass `.immediatelyAvailableMetadataOnly` for the existence/directory-flag check (and keep the full read only where bytes are needed); verify with an evicted file on a device.
- Severity: Medium
- Status: NEW (unverified on device)

### CloudContainerCache caches a nil container for the whole session
- Category: Bug
- Location: Modules/CoreRPG/App/CloudContainerCache.swift:38-55; consumers Modules/CoreRPG/App/AppGroup.swift:80-82 (`preferredRootUrl`)
- What: When `ubiquityIdentityToken` is non-nil but `url(forUbiquityContainerIdentifier:)` returns nil (documented to happen while the container is still being provisioned, first launch after sign-in, or iCloud Drive off), `.resolved(nil)` is stored and only `NSUbiquityIdentityDidChange` invalidates it.
- Why: `preferredRootUrl` then falls back to the App Group container for the whole run. File-backed modules (Audio/Pdf/Photo/Space) look up their relative paths there, so iCloud files seem missing and new imports are written to a root that the next launch (with the container resolved) no longer reads. The token-less case is rightly cached (a sign-in posts the notification); the token-present case has no such signal.
- Action: Do not cache a nil result when an identity token exists (retry on the next read or after a short delay), or at least invalidate on `didBecomeActive`.
- Severity: Medium
- Status: NEW

### Legacy-migration move paths are unreferenced or test-only and use unsafe URL(string:) parsing
- Category: Dead code
- Location: Modules/CoreRPG/Files/FileUrlDataController+Manage.swift:14-51 (`move(fileUrl:name:category:)`, no caller in Modules, Sources or Tests) and :53-73 (`move(fileUrl:from:to:)`, only Tests/CoreRPGTests/FileUrlDataControllerFileOperationTests.swift:432); Modules/CoreRPG/Files/CloudDocumentController.swift:166-173 (`move(sourceUrl:destinationFilename:)`), :187-206 (`move(url:newCategory:)`), :245-247 (static `suggestedFileName(for:filename:category:)`)
- What: Two public `FileUrlDataController.move` overloads and three `CloudDocumentController` helpers are not reached by production code.
- Why: About 110 LOC that look live but are not. They also carry bugs the live `move(url:newName:)` already fixed (CODE_AUDIT_21 §5.15): `URL(string: newPath)` / `URL(string: destinationName)` cut a name at `#` or `?` (verified: `URL(string: "cat/a#b.png").path == "cat/a"`), the `.icloud` branch copies with a replacing write and never calls `suggestedFileName` (overwrites a file at the same relative path), and the stored result has no leading slash unlike every other stored path. If someone revives them the old bugs return.
- Action: Delete the two unreferenced overloads, the category move and its CloudDocumentController helpers, and the one test (or rebuild the category move on `move(url:newName:)`).
- Severity: Medium
- Status: NEW

### Create intents read the whole IntentFile with no size cap
- Category: Security
- Location: Modules/CoreRPG/Intent/IntentEntityHelpers.swift:217-224 (callers Modules/AudioRPG/Intent/AudioManagementIntents.swift:45, PdfRPG, PhotoRPG, SpaceRPG `*ManagementIntents.swift:45`)
- What: `intentFileData` checks the type, then loads `file.data` completely; every other path that accepts outside bytes (share extension, remote download, peer store) is bounded by `ByteLimits.maximumSourceFileBytes` (256 MiB).
- Why: A Shortcut that passes a multi-gigabyte file to "Create Audio/Pdf/Photo/3D Object" loads it into memory in the app process and can get it killed by the system (and written to iCloud as a huge item if it fits). The user controls the Shortcut, so this is robustness rather than an attack.
- Action: Reject files above `ByteLimits.maximumSourceFileBytes` with `IntentFileStoreError` (or a new size error) before reading the data.
- Severity: Low
- Status: NEW

### PeerFileDataStore.hold compares the whole old and new Data under its lock
- Category: Performance
- Location: Modules/CoreRPG/Files/PeerFileDataStore.swift:55-62
- What: `previous.data != data` runs inside `state.withLock`.
- Why: For a replaced hold of a file of up to 256 MiB the byte comparison is O(n) while every reader (`data(for:)`, `snapshot(for:)`, used by game readers) waits on the mutex.
- Action: Compare outside the lock (return both values) or use the generation/hash the caller already has.
- Severity: Low
- Status: NEW

### CloudKitOperationCounter is a log-only counter with an unused parameter and a Task per save
- Category: Dead code
- Location: Modules/CoreRPG/Files/CloudDocumentController.swift:13-57 (`file:` parameter never read, ~25 call sites pass it); Modules/CoreRPG/Persistence/CoreDataController.swift:549-555
- What: Every save creates an unowned `Task` just to bump an actor counter whose only output is an `info` line with public privacy per operation and one warning at 1,000.
- Why: Noise in the unified log, an unstructured Task per save, and a misleading name (it counts file operations and saves, not CloudKit operations).
- Action: Replace with a `Mutex` counter (no Task, no actor hop), drop the `file:` parameter, log only the threshold crossing, or delete it.
- Severity: Low
- Status: NEW

### Bookmark and store saves swallow write errors; a second process can overwrite the bookmark store
- Category: Bug
- Location: Modules/CoreRPG/Persistence/FilePersistenceController.swift:82-92, Modules/CoreRPG/Files/FileDataController.swift:84-95, Modules/CoreRPG/Files/FileBookmarkController.swift:113-128; second process: Modules/PhotoRPG/Controller/ShareImportPhotoController.swift:40, :58 (builds a fresh `FileUrlDataController`, hence a fresh `FileBookmarkModel`, per call)
- What: `FilePersistenceController.save` logs a failed atomic write and returns, and `FileBookmarkModel.save` then clears `needsSave`. The bookmark store is a whole-file rewrite from each process's in-memory copy, and the App Group file is shared with the share extension.
- Why: A full disk or locked container loses bookmark changes silently (no `PersistenceIssueCenter` entry); a bookmark the extension saved can be overwritten by the app's next whole-file save (or vice versa). `.newCloud` files fall back to their path so the impact is limited to `.icloud`/`.other` picks.
- Action: Return a result from `save` and keep `needsSave` set on failure with a `recordFileError`; re-read before write or give the extension a separate bookmark file.
- Severity: Low
- Status: NEW

### Corrupt store backup overwrites the previous backup
- Category: Bug
- Location: Modules/CoreRPG/Persistence/FilePersistenceController.swift:57-66
- What: On an undecodable store the code removes an existing `<name>.json.corrupt` before moving the new corrupt file there.
- Why: Two corruptions in a row lose the first backup, which may be the more complete one.
- Action: Use a timestamped suffix or keep the oldest.
- Severity: Low
- Status: NEW

### suggestedFileName recurses with one coordinated check per collision
- Category: Performance
- Location: Modules/CoreRPG/Files/CloudDocumentController.swift:249-257 (also 149-157)
- What: The free-name search is recursive and does one coordinated `fileExists` (limiter slot plus OperationQueue hop) per candidate.
- Why: n same-named imports into one folder cost O(n) checks each, O(n²) overall, competing with real file work for the 2-4 limiter slots.
- Action: List the folder once and pick the first free `name-N` in memory; keep the non-replacing copy as the race guard.
- Severity: Low
- Status: NEW

### LinkDataTransferable: eleven near-identical structs that ignore their module parameter
- Category: Duplication
- Location: Modules/CoreRPG/Model/LinkDataTransferable.swift:56-300 (`LinkAdventureData` through `LinkWeatherData`; `LinkPdfData.module` is `var` while the others are `let`, line 191)
- What: Each struct repeats init, four stored properties and a two-line transfer representation; every init takes a `module:` parameter and then assigns a hard-coded module instead.
- Why: ~240 LOC for one concept; the ignored parameter is an API trap (passing another module silently has no effect) and the `var` is an inconsistency.
- Action: One generic struct (or a struct with a `contentType` per module) plus the `UTType` table; drop the dead parameter. Keep the exported UTType identifiers unchanged.
- Severity: Low
- Status: NEW

### Production Color.random lives in RainbowDebug.swift
- Category: Dead code
- Location: Modules/CoreRPG/Debug/RainbowDebug.swift:5-9; duplicate-named declaration Modules/CoreRPG/Extensions/RandomColor.swift:5-8; only user Modules/MapRPG/Controller/GameController+Pins.swift:26
- What: A file named "Debug" holds `Color.random`, used by production code to colour a player pin, next to a second `random` on `ShapeStyle where Self == Color`.
- Why: Easy to delete as "debug only" by mistake; two statics with one name resolve by context.
- Action: Move the single remaining `Color.random` out of Debug (or delete the ShapeStyle twin if unused) and delete RainbowDebug.swift.
- Severity: Low
- Status: NEW

### KeepAwakeModel does nothing on native macOS
- Category: Bug
- Location: Modules/CoreRPG/Model/KeepAwakeModel.swift:46-50
- What: `applyToApplication` only sets `UIApplication.isIdleTimerDisabled` under `canImport(UIKit)`; no `ProcessInfo.beginActivity` / `IOPMAssertion` exists elsewhere in the repo.
- Why: A game master running a long game on the Mac can see the display sleep or the screen saver start; the CODE_AUDIT_25 §3.2 fix covers iOS/visionOS only. May be intended (Macs are normally attended).
- Action: Decide; if wanted, hold a `ProcessInfo` `.idleDisplaySleepDisabled` activity while an owner is registered on macOS.
- Severity: Low
- Status: NEW

### ItemGenerationControllable returns AnyView
- Category: SwiftUI
- Location: Modules/CoreRPG/Model/ItemGeneration.swift:119-124
- What: The protocol requirement type-erases the generation sheet to `AnyView`, which CLAUDE.md forbids unless required.
- Why: Likely needed to keep GeneratorRPG types out of CoreRPG, but it is the only `AnyView` in the area and defeats SwiftUI diffing for that sheet.
- Action: Make the requirement return `some View` via an associated type or a generic container, or document why erasure is required.
- Severity: Low
- Status: NEW

### QuickDice slot defaults are never removed with their character
- Category: Bug
- Location: Modules/CoreRPG/Model/QuickDiceSlotsModel.swift:46-80
- What: `quickDiceSlots.<characterId>` keys are written per character and only removed when all slots are cleared.
- Why: Deleting or purging a character leaves its key in `UserDefaults` forever (tiny, but unbounded over years of campaigns).
- Action: Remove the key from the character purge path, or prune keys of unknown characters at launch.
- Severity: Low
- Status: NEW

### Persistence and file plumbing tests are missing for several risky pieces
- Category: Test gap
- Location: Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:14-335 (history merge, `lastCommonTransactionTimestamp`, cleanup), Modules/CoreRPG/Persistence/CoreDataChangeObserver.swift, Modules/CoreRPG/App/CloudContainerCache.swift, Modules/CoreRPG/Files/FileUrlDataController+Manage.swift:140-163 (`ensureRemoteCache`), `FileUrlDataController.download(fileUrl:)`
- What: Grepping Tests/ finds no reference to `PersistentHistoryProcessor`, `PersistentHistoryCleaner`, `observeCoreDataChanges`, `lastCommonTransactionTimestamp`, `ensureRemoteCache` or `download(fileUrl:)`.
- Why: These hold the 7-day floor that protects unexported CloudKit transactions, the timestamp-advance rule and the sync-deletion feed; a regression there shows up as slow data loss or a full re-mirror, not a crash.
- Action: Extract the timestamp rules into pure functions with tests; add an in-memory store test for the change observer; test `ensureRemoteCache` with an injected downloader (the seam exists: `remoteFileDownloader`).
- Severity: Low
- Status: NEW

Not audited in this area: Model files that are plain view models or value types read only by name or skimmed (SearchModel, ListDisplayModel, ItemSelectionModel, ChildEntryModel, TagFilterList, SearchResult, OpenFileWindowModel, GenerateMapAction, MapActions, SheetNumberLimit and similar small ones, about 1.5k LOC); the CloudKit schema and `.xcdatamodeld` files; runtime behaviour on a device (iCloud eviction, Spotlight, history merge); `Modules/CoreRPG/Extensions`, `Controllable`, `FileViews` (other agents' areas).
