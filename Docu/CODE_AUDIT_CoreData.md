# MasterRPG Code Audit — Core Data & CloudKit Sync

Generated 2026-09-15, fixes applied 2026-09-16. **Scope for this run is deliberately narrow**, per request: the Core Data persistence stack and CloudKit sync pipeline only — `Modules/CoreRPG/Persistence/*`, `Modules/CoreRPG/Controllable/SyncDataControllable.swift`, every module's `Controller/DataController.swift` / `Controller/SyncDataController.swift` / `XxxDataController.swift` (Adventure, Audio, Character, Dice, Generator, Map, Pdf, Photo, Rule, Space, Table, Weather, plus GameRPG's `GameStatisticsDataController`), all 14 `.xcdatamodeld` schemas, `Modules/RolePlayGameKit/Model/DataBaseModel.swift` + `ShareExtensionDatabaseService.swift`, `Modules/CoreRPG/App/AppGroup.swift`, `Modules/CoreRPG/AppModels/AppSettingsModel.swift`, and the Share Extension's use of that stack under `Sources/RPGShare/`. Roughly 4,000+ Swift LOC plus 14 Core Data schemas were read. `Dead/` is excluded per project convention. This is one of many audit passes on this codebase (see `Docu/CODE_AUDIT_*.md` for prior full-codebase runs); several fixes from those runs are visible as explanatory comments in the files reviewed here and are not re-flagged.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action; no code changes were made. Three findings were traced end-to-end and confirmed by opening the cited lines myself (not just trusting the sub-audit that found them) before being marked Critical.

## Fix status (2026-09-16)

All findings except §6.1 have been fixed and the full `MasterRPG` scheme (including the `RPGShare` Share Extension and `DiceRollerWidgetExtension` targets) builds clean (`xcodebuild -scheme MasterRPG -destination 'platform=iOS Simulator,id=C12570B6-1C33-488D-B515-3D5E35B67ABD' build` → `** BUILD SUCCEEDED **`) with these changes applied. §6.1 was explicitly left as-is per your decision (schema/store-topology change to a shipped, already-syncing app — too risky to make without a deliberate product call and a real device test pass).

Two changes need a follow-up outside this session before they take effect in a real device/TestFlight/App Store build:
- **§5.3** added `com.apple.developer.ubiquity-container-identifiers` to the RPGShare entitlements files. A simulator "Sign to Run Locally" build doesn't validate capabilities against a provisioning profile, so this compiled, but the App ID for the Share Extension target may need the iCloud Documents capability added in the Apple Developer portal (or via Xcode's Signing & Capabilities tab with automatic signing) before this takes effect on a real device or in TestFlight/App Store builds.
- **§5.1/§5.2** (Share Extension CloudKit-store fix) is code-complete and builds, but hasn't been exercised on-device — recommend a manual test pass before shipping: enable iCloud sync in the main app, share an item into the app via the Share Extension, and confirm it appears in the main app and syncs to a second device.

| § | Finding | Severity | Status |
|---|---|---|---|
| 3.1 | Sync burst resurrects deleted items | Critical | **Fixed** |
| 3.2 | Placeholder UUID for deleted objects | High | **Fixed** |
| 3.3 | `flushPendingOperations()` write-ordering race | Medium | **Fixed** |
| 5.1 | Share Extension always uses local store | Critical | **Fixed** |
| 5.2 | `useCloudKit` read from wrong UserDefaults domain | Critical | **Fixed** |
| 5.3 | Share Extension missing ubiquity entitlement | High | **Fixed** (needs portal/profile follow-up, see above) |
| 5.4 | GeneratorRPG orphaned entries | High | **Fixed** |
| 5.5 | Picker files never get a contentHash | Medium | **Fixed** |
| 6.1 | GameStatistics syncs via CloudKit | Medium | **No change** — user decision: leave as-is |
| 6.2 | Inconsistent log privacy annotations | Low | **Fixed** |
| 8.1 | Collapsed CKAccountStatus messaging | Medium | **Fixed** |
| 9.1 | Dead `batchContext` plumbing | Medium | **Fixed** |
| 9.2 | `CloudKitOperationCounter` write-only telemetry | Low | **Fixed** |
| 9.3 | RuleRPG hand-rolled `syncEntries` duplicate | Low | **Fixed** |
| 9.4 | Missing `.xccurrentversion` files | Low | **Fixed** |

---

## 1. Executive summary

1. **[Critical, Fixed] Share Extension always persisted to the local-only store, silently bypassing iCloud sync** — §5.1 — `Modules/RolePlayGameKit/Model/ShareExtensionDatabaseService.swift:26-47`. Anything shared into the app while iCloud sync is on used to be written to a store the main app never opens.
2. **[Critical, Fixed] Share Extension's CloudKit-mode detection read a UserDefaults domain the main app never writes to** — §5.2 — `Modules/CoreRPG/AppModels/AppSettingsModel.swift:8-11,142-147,161-163`. The root cause behind #1: the extension could never see the user's actual setting even if #1 were fixed alone.
3. **[Critical, Fixed] A burst of CloudKit merge notifications could cancel a delete loop mid-batch, silently resurrecting deleted items** — §3.1 — `Modules/CoreRPG/Controllable/SyncDataControllable.swift:42-97`. A user could end up re-creating (and re-syncing to every device) an item they already deleted, just by editing something else shortly after.
4. **[High, Fixed] The deleted-object id `CoreDataChangeObserver` reports could be a meaningless placeholder that its only consumer trusted as real** — §3.2 — now fixed by diffing against Core Data's actual current ids instead of trusting the reported id.
5. **[High, Fixed] Share Extension was missing the iCloud ubiquity-container entitlement** — §5.3 — `Sources/RPGShare/RPGShare-Debug.entitlements`, `RPGShare-Release.entitlements`. Files shared via the extension landed in a different storage location than the main app resolves to.
6. **[High, Fixed] GeneratorRPG never deleted entries removed from an incoming snapshot** — §5.4 — `Modules/GeneratorRPG/Controller/DataController.swift:39-56`. Orphaned rows leaked locally and re-exported to CloudKit as zombie records forever.
7. **[Medium, Fixed] `flushPendingOperations()` could apply queued writes out of order under concurrent flushes** — §3.3 — `Modules/CoreRPG/Persistence/CoreDataController.swift`.
8. **[Medium, No change] GameStatistics analytics data syncs through the user's private CloudKit database with no local-only isolation** — §6.1 — left as-is per explicit user decision.
9. **[Medium, Fixed] Picker-imported files never got a computed `contentHash`** — §5.5 — `Modules/CoreRPG/Files/FileUrlDataController.swift`.
10. **[Medium, Fixed] `CoreDataController.batchContext` was threaded through the entire app but never used for a write** — §9.1.

---

## 2. Quick wins (≤30 min each)

- ~~Persist `useCloudKit` to `UserDefaults.appGroup` instead of `.standard`~~ — **Fixed**, see §5.2.
- ~~Replace RuleRPG's hand-rolled entry-sync loop with the shared `syncEntries` helper~~ — **Fixed**, see §9.3.
- ~~Add `.xccurrentversion` to the 12 model bundles missing it~~ — **Fixed**, see §9.4.
- ~~Pick one privacy policy for CloudKit-error `os.log` calls and apply it uniformly~~ — **Fixed**, see §6.2.

---

## 3. Concurrency

### 3.1 CloudKit sync burst can cancel a delete loop mid-batch, silently resurrecting deleted items
- **Location:** `Modules/CoreRPG/Controllable/SyncDataControllable.swift:42-97` (the race); `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift:245-261` (burst source — one `mergeChanges` call per transaction inside a `forEach`, and a debounced fetch can return N>1 transactions at once); `Modules/CoreRPG/Controllable/ItemControllable.swift:128-156` (`delete(itemId:withFileData:withDatabase:)` with `withDatabase: false` only calls `itemDataModel.resetModel(id:)` — verified no Core Data write occurs); `Modules/CoreRPG/Persistence/CoreDataController.swift:105-115,152-175` (the resurrection mechanism: `replace`/`flushPendingOperations` take the "not found → `let new = DataType(context:)`" branch when a uuid the caller thinks exists is actually absent).
- **What:** `updateFromSync(deletedIds:insertedIds:updatedIds:)` cancelled the *previous* notification's still-running processing `Task` before starting a new one; each loop checked cancellation at the top of every iteration, so a delete loop that was interrupted mid-batch left the remaining ids' in-memory rows stale forever.
- **Why:** the row is already gone from Core Data/CloudKit, but the in-memory `ItemController` still thought it existed. If the user was viewing/editing that "ghost" item and saved, `CoreDataController.replace`/`flushPendingOperations` wouldn't find the row and would take the "create new" branch, resurrecting the deleted item and re-syncing it to every other device.
- **Action:** Make the deleted/inserted/updated application for one notification atomic (no per-item cancellation checkpoint), or track which ids a superseded task didn't reach and have the next task finish them.
- **Severity:** Critical
- **Fix applied:** `updateFromSync` now *chains* onto the previous notification's task (`await previousTask?.value`) instead of cancelling it, so overlapping batches apply strictly in arrival order and no partially-applied batch is ever dropped. All internal `try Task.checkCancellation()` checkpoints were removed since nothing cancels these tasks anymore.

### 3.2 `CoreDataChangeObserver`'s placeholder UUID for deleted objects defeats its own consumer's contract
- **Location:** `Modules/CoreRPG/Persistence/CoreDataChangeObserver.swift:74-90`; consumed at `Modules/CoreRPG/Controllable/SyncDataControllable.swift:62-65`.
- **What:** For a `.deleted` change, an already-faulted deleted object falls through to `return UUID()` — a fresh, meaningless random id. The code comment says this is fine because "consumers diff against fetched ids," but `updateFromSync` didn't diff against anything — it called `itemControllable.delete(itemId: deletedId, ...)` directly with the placeholder, which is a guaranteed no-op.
- **Why:** this made the ghost-item problem in §3.1 happen on an ordinary single remote deletion, no notification burst required.
- **Action:** Change `updateFromSync`'s deletion handling to actually re-fetch-and-diff against the current id set, honoring the producer's own documented contract.
- **Severity:** High
- **Fix applied:** Deletions are now resolved by diffing `itemControllable.itemDataModel.items` against a fresh `dataControllable.fetchIds()` result — the reported `deletedIds` list is only used as a trigger to check, never trusted directly, so a placeholder UUID can no longer cause a dropped deletion.

### 3.3 `flushPendingOperations()` can apply queued writes out of order under concurrent flushes
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift`.
- **What:** `flushPendingOperations()` drained the pending-operation queue atomically, but the subsequent `batchExists` → apply sequence wasn't atomic as a whole, so two concurrent calls could interleave their apply steps.
- **Why:** an older call's apply-step running after a newer call's could silently discard the newer edit with no error surfaced.
- **Action:** Serialize `flushPendingOperations()`/`save()` per `CoreDataController` instance.
- **Severity:** Medium
- **Fix applied:** Added `CoreDataModel.chainedFlush(_:)`, which atomically swaps in a new `Task<Void, Error>` under one `Mutex` acquisition and awaits the previous one before running new work — `flushPendingOperations()` now routes through it, guaranteeing calls apply in strict order with no interleaving.

---

## 4. API modernity

_No findings._ The persistence/sync layer already uses modern Swift concurrency throughout (`async`/`await`, `Task`, actors for `SwiftDataController`/`PersistentHistoryProcessor`, `NotificationCenter.notifications(named:)` async sequences instead of closure-based observers, `Duration`-based `Task.sleep(for:)`). No completion-handler APIs, no `DispatchQueue`, no deprecated Core Data/CloudKit APIs found in the audited files.

---

## 5. Bugs / logic errors

### 5.1 Share Extension always persists to the local-only store, ignoring the user's iCloud sync setting
- **Location:** `Modules/RolePlayGameKit/Model/ShareExtensionDatabaseService.swift:21,26-28,41-47`; contrast `Modules/RolePlayGameKit/Model/DataBaseModel.swift:88-103`, which correctly branches on the equivalent flag.
- **What:** `ShareExtensionDatabaseService.init(useCloudKit:)` stored the flag but `setup()` never read it — it unconditionally constructed `CoreDataPersistenceController` (the local-only controller).
- **Why:** for any user with iCloud sync enabled in the main app, everything saved through the Share Extension was written to a SQLite file the main app never opens while in cloud mode — effectively lost from the user's point of view and never reaching other devices.
- **Action:** Make `ShareExtensionDatabaseService.setup()` branch on `self.useCloudKit`, constructing `CloudKitCoreDataPersistenceController` when true.
- **Severity:** Critical
- **Fix applied:** `setup()` now branches on `useCloudKit`, constructing `CloudKitCoreDataPersistenceController` (stored in a new `cloudPersistence` property) when true, `CoreDataPersistenceController` (`localPersistence`) otherwise — mirroring `DataBaseModel.setup()` exactly.

### 5.2 Share Extension's CloudKit-mode detection reads a UserDefaults domain the main app never writes to
- **Location:** `Modules/CoreRPG/AppModels/AppSettingsModel.swift:8-11,142-147,161-163`; called from `Sources/RPGShare/SharingView.swift:50`.
- **What:** Despite being commented "Shared Settings Value in AppGroups," `useCloudKit` was persisted to `UserDefaults.standard` — process-local, not shared via the App Group. `readUseCloudKitFromDefaults()` also read `.standard`.
- **Why:** the Share Extension process has its own sandboxed `.standard` defaults, which never receive the main app's value — `readUseCloudKitFromDefaults()` always returned `false` in the extension regardless of the user's real setting, independently of and compounding §5.1.
- **Action:** Persist `useCloudKit` to `UserDefaults.appGroup` and read it from there everywhere.
- **Severity:** Critical
- **Fix applied:** `useCloudKit`'s `didSet`, `initSettings(from:)`, and `readUseCloudKitFromDefaults()` all now read/write `UserDefaults.appGroup` exclusively (falling back to `false` if the App Group is unavailable, matching this codebase's established nil-safe pattern), independent of whatever `defaults` instance the model itself was constructed with.

### 5.3 Share Extension is missing the iCloud ubiquity-container entitlement its own file-storage code depends on
- **Location:** `Sources/RPGShare/RPGShare-Debug.entitlements` and `RPGShare-Release.entitlements`; consumed at `Modules/CoreRPG/App/AppGroup.swift:49,61-63`.
- **What:** `FileManager.cloudURL` requires the ubiquity-container entitlement to resolve non-nil; without it, `preferredRootUrl` always fell through to the App Group container inside the Share Extension process.
- **Why:** photos/files saved by the Share Extension landed under a different root path than the main app resolves to for the same logical location when cloud mode is enabled.
- **Action:** Add `com.apple.developer.ubiquity-container-identifiers` (`iCloud.de.andretrettin.gamemaster`) to both RPGShare entitlements files.
- **Severity:** High
- **Fix applied:** Added `com.apple.developer.ubiquity-container-identifiers` and the `CloudDocuments` iCloud service to both `RPGShare-Debug.entitlements` and `RPGShare-Release.entitlements`, matching the main app's entitlements exactly. **Follow-up needed:** the Share Extension's App ID may need the iCloud Documents capability added in the Apple Developer portal / Xcode Signing & Capabilities before this takes effect on a real device or TestFlight/App Store build (a local simulator build doesn't validate this).

### 5.4 GeneratorRPG never deletes entries removed from an incoming snapshot
- **Location:** `Modules/GeneratorRPG/Controller/DataController.swift:39-56`; schema at `Modules/GeneratorRPG/Resources/Model.xcdatamodeld`.
- **What:** every other module uses the shared `CoreDataRelationship.syncEntries(incoming:current:childId:map:)` helper, which explicitly deletes children that fell out of the incoming set. GeneratorRPG hand-rolled the find-or-create half of that pattern but omitted the delete half.
- **Why:** every entry removed from a Generator leaked as an orphaned row locally and re-exported to CloudKit as a zombie record with no owner, forever.
- **Action:** Replace the hand-rolled loop with `model.syncEntries(incoming:current:childId:map:)`, matching every other module.
- **Severity:** High
- **Fix applied:** `applySnapshot` now calls `model.syncEntries(incoming:current:childId:map:)`. The now-dead `RPGGenerator.entryOrNew(for:)` helper (used only at this call site) was removed from `Modules/GeneratorRPG/Model/DataModel+Extensions.swift`.

### 5.5 Picker-imported files never get a computed `contentHash`
- **Location:** `Modules/CoreRPG/Files/FileUrlDataController.swift:323-354`.
- **What:** files added via the system file/photo picker always persisted with `contentHash == nil`, while imported files always got a real hash via `createNewFileUrl`.
- **Why:** `contentHash` feeds CloudKit conflict/version-determinism logic; a nil hash forced picker-added files onto a weaker fallback versioning path than imported files.
- **Action:** Compute `FileUrl.contentHash(of:)` from the picker's file data inside `createFileUrl` instead of defaulting silently to `nil`.
- **Severity:** Medium
- **Fix applied:** `createFileUrl` now reads the file's data via the existing `FileManager.contentsOfFile(coordinatingAccessAt:)` coordination helper and computes `FileUrl.contentHash(of:)` when the caller didn't already supply one, falling back to `nil` (with a logged error) only if the coordinated read itself fails.

---

## 6. Security

### 6.1 GameStatistics analytics data syncs through the user's private CloudKit database with no local-only isolation
- **Location:** `Modules/RolePlayGameKit/Model/DataBaseModel.swift:32-52,88-103`; `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift:60`; no `<configuration>` elements exist in any `.xcdatamodel`, including `Modules/GameRPG/Resources/GameStatistics.xcdatamodeld`.
- **What:** `GameRPG.Resources.bundle` is merged into the same single CloudKit-backed container as every other module — there is no second store description or Core Data configuration excluding GameStatistics entities from CloudKit.
- **Why:** per-event analytics (dice rolls, network messages, session/participant rows) sync through the user's private CloudKit database whenever iCloud sync is enabled, not staying device-local as the module's naming/purpose suggests.
- **Action:** Give `GameStatistics.xcdatamodeld` its own Core Data configuration and a second, non-CloudKit store description, or a fully separate container — or confirm this is intentional.
- **Severity:** Medium
- **Status: No change.** Explicitly deferred per your decision — any real fix means a schema/store-topology change to a shipped, already-syncing app's Core Data model, which carries production data-migration risk and needs a deliberate product decision plus a real device test pass, not a same-session code change. Revisit if/when GameStatistics's scope is intentionally reconsidered.

### 6.2 Inconsistent `os.log` privacy annotations around CloudKit-adjacent errors
- **Location:** `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift`, `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift`, `Modules/CoreRPG/Persistence/CloudKitAccountController.swift` (mostly force `.public`) vs. two "failed to create store folder" log lines that omitted the annotation, defaulting to private.
- **What:** an apparently unintentional inconsistency rather than a reviewed policy.
- **Why:** the accidental split suggests the `.public` choice wasn't deliberately reviewed at each call site.
- **Action:** Pick one policy and apply it uniformly.
- **Severity:** Low
- **Fix applied:** Aligned the two outlier log lines (in `CoreDataPersistenceController.swift` and `CloudKitCoreDataPersistenceController.swift`) to `, privacy: .public`, matching every sibling CloudKit/persistence error log in the same files — these are generic filesystem errors, not CloudKit record data, so `.public` is the safe, consistent choice here.

**Verified clean, no findings:** App Group id (`group.de.andretrettin.MasterRPG`) and CloudKit container id (`iCloud.de.andretrettin.gamemaster`) are byte-identical across every entitlements file and the single Swift source of truth (`AppGroup.swift`) — no typo'd duplicate. No force-unwrap of `FileManager.groupURL`/`cloudURL` anywhere in the persistence/App-Group code. Exactly one `NSPersistentCloudKitContainerOptions(containerIdentifier:)` call in the repo, no `#if DEBUG`-only container override. No CKShare/collaborative-sharing surface exists in this app (private-database-only sync), so that attack surface doesn't apply.

---

## 7. Performance

_No findings within this scope._ The debounced persistent-history processing, the chunked `batchReplace`/`batchDelete` operations, and the explicit avoidance of `NSBatchDeleteRequest` (which would bypass CloudKit mirroring) are all sound, deliberate designs — not flagged.

---

## 8. SwiftUI / UI

### 8.1 `CKAccountStatus.restricted` / `.temporarilyUnavailable` collapsed into a generic "Unavailable" message
- **Location:** `Modules/CoreRPG/Persistence/CloudKitAccountController.swift:33-40`; surfaced via `Modules/CoreRPG/FileViews/StorageOptionEditor.swift:30,78-81`.
- **What:** every non-`.available`/`.noAccount` `CKAccountStatus` — including `.restricted` (e.g. Screen Time/MDM restriction) and `.temporarilyUnavailable` (transient, often self-resolving) — mapped to the identical `.unavailable` case.
- **Why:** a user under a transient, self-resolving condition saw the same message and disabled toggle as a user under a parental-controls restriction, with no hint that retrying later might help.
- **Action:** Add distinct `CloudKitAccountStatus` cases with tailored copy.
- **Severity:** Medium
- **Fix applied:** Added `.restricted` and `.temporarilyUnavailable` cases to `CloudKitAccountStatus` with their own localized titles ("Restricted by Device Settings" / "Temporarily Unavailable"), and `checkAccountStatus()` now maps `CKAccountStatus.restricted`/`.temporarilyUnavailable`/`.couldNotDetermine` explicitly instead of collapsing them all into one `default`. `StorageOptionEditor` needed no changes — it already surfaces `.title` generically and its `disabledUseCloud` check (`!= .available`) still correctly disables the toggle for both new cases.

---

## 9. Dead code / duplication / refactor

### 9.1 `CoreDataController.batchContext` is threaded through the entire app but never used for a write
- **Location:** `Modules/CoreRPG/Persistence/CoreDataController.swift`; `Modules/CoreRPG/Persistence/CloudKitCoreDataPersistenceController.swift`; `Modules/CoreRPG/Persistence/PersistentHistoryTrackerManager.swift`.
- **What:** a dedicated second background context was created and threaded through every module's `RootModel`/`DataController` but never actually written through anywhere.
- **Why:** dead complexity whose surrounding comments assumed it was live; the persistent-history predicate's own-actor "batchContext" branch could never match anything real.
- **Action:** Remove the parameter and the now-pointless predicate branch/context creation.
- **Severity:** Medium
- **Fix applied:** Removed entirely — the second background context is no longer created in either persistence controller, `CoreDataInitModel`/`DataBaseModel`/`ShareExtensionDatabaseService` no longer carry a `batchContext` property, every module's `RootModel.setUp`/`DataController.init`/`CoreDataController.init` signature dropped the parameter, and `PersistentHistoryTrackerManager`'s dead "own actor, batchContext" predicate branch was removed (the current actor's own regular-context changes are now simply excluded from re-merge, which was always the correct effective behavior). All `PreviewData.swift` files and affected tests were updated to match. Full build verified clean afterward.

### 9.2 `CloudKitOperationCounter` is write-only telemetry with unbounded, unread growth
- **Location:** `Modules/CoreRPG/Files/CloudDocumentController.swift`.
- **What:** the counter incremented on every hot write path for the life of the process but was never read, never reset, and enforced nothing against CloudKit's operation-rate limits.
- **Why:** pure log noise wired into every save/sync/delete path, not an actual safeguard.
- **Action:** Either wire a periodic read (warn past a threshold, reset daily) or remove it.
- **Severity:** Low
- **Fix applied:** Wired up rather than removed (lower blast radius — this way none of its ~20 call sites needed touching). It now resets daily via a background task started in `init()`, and logs a one-time-per-window warning once the count crosses a documented heuristic threshold (1,000/day) — turning it from pure telemetry into an actual "is something chatty toward CloudKit today" signal.

### 9.3 RuleRPG hand-rolls the `syncEntries` pattern instead of the shared helper
- **Location:** `Modules/RuleRPG/Controller/DataController.swift:65-78`.
- **What:** functionally correct (unlike §5.4, it did delete orphans), but reimplemented the same find-or-new + diff + delete-orphans logic `syncEntries` already consolidates.
- **Why:** GeneratorRPG (§5.4) is direct proof a hand-rolled copy of this pattern can silently lose the delete step over time.
- **Action:** Replace the manual diff/delete block with `model.syncEntries(incoming:current:childId:map:)`.
- **Severity:** Low
- **Fix applied:** Replaced with `model.syncEntries(...)`, matching every other module. The now-dead `RPGRule.entryOrNew(for:)` helper was removed from `Modules/RuleRPG/Model/DataModel+Extensions.swift`.

### 9.4 Most `.xcdatamodeld` bundles are missing `.xccurrentversion`
- **Location:** 12 of 14 model bundles.
- **What:** each affected bundle currently contains exactly one `.xcdatamodel` version folder, so build tooling resolves it unambiguously today — no current failure, but a latent risk the next time any of them gets a second version.
- **Action:** Add `.xccurrentversion` now for consistency.
- **Severity:** Low
- **Fix applied:** Added `.xccurrentversion` to all 12 previously-missing model bundles (PdfRPG, WeatherRPG, SpaceRPG, TableRPG, AudioRPG, DiceRPG, RuleRPG, GeneratorRPG, MapRPG, GameRPG, CharacterRPG, PhotoRPG), each pointing at that bundle's single existing `.xcdatamodel`, matching the format Xcode itself generates (as seen in `AdventureRPG`/`CoreRPG`'s existing files).

---

## 10. Cross-cutting recommendations

1. **The Share Extension's config drift (§5.1, §5.2, §5.3) was one root problem, not three unrelated bugs.** Fixed at each individual site, but worth watching for recurrence: any future App-Group-shared setting should be written/read through `UserDefaults.appGroup` from the start, not `.standard`, and any new cross-process capability (file storage location, database choice) should be sourced from one shared flag rather than re-derived independently per process.
2. **Unused "safety" infrastructure kept appearing (`batchContext` §9.1, `CloudKitOperationCounter` §9.2).** Both were clearly built with a real purpose in mind and then never finished/wired up. Before adding new cross-cutting plumbing like this, prefer landing it fully wired in the same change, or not landing it at all.
3. **`syncEntries` adoption is now exhaustive** (§5.4, §9.3 both fixed) — worth a lint rule or review checklist item going forward so a future module doesn't reintroduce a third hand-rolled copy.
4. **The `updateFromSync` cancel-and-replace pattern (§3.1) now resumes instead of discarding.** Any future per-notification processing pipeline in this codebase should default to this "chain, don't cancel" shape when correctness (not dropping work) matters more than shedding stale work.

---

## 11. What was NOT audited

- Every other subsystem of this app — UI/SwiftUI views, the game/network/SharePlay layer, battle logic, link resolution, import/export, search, sheets — all covered by prior full-codebase audit rounds in `Docu/CODE_AUDIT_*.md`, not re-reviewed here.
- **Compiler warnings were not captured** as a dedicated Step 2 pass for this scoped run — a full `xcodebuild` was run after all fixes to verify a clean build (confirmed: `** BUILD SUCCEEDED **`, no new warnings in any touched file), but no systematic warning-diff was done against a pre-fix baseline.
- **Actual Core Data lightweight-migration behavior was not exercised.** §9.4's fix is a structural addition, not a test of migrating real data across a model version bump.
- **CKShare-based collaborative record sharing** is not used anywhere in this app, so that entire security surface doesn't apply.
- The `DiceRollerWidgetExtension` target's Core Data touchpoints were not deeply traced beyond confirming it only uses App-Group `UserDefaults`, not the Core Data store directly.
- Persistence-related test coverage under `Tests/*RPGTests/DataControllerTests.swift` — the batchContext-removal fix updated these files' call sites to keep them compiling, but did not add new test coverage for any of the other fixes (§3.1/§3.2's chained-sync behavior, §5.1/§5.2's Share Extension branch, §5.4's orphan deletion) — **recommend adding regression tests for these**, especially §3.1/§3.2 given how subtle the original bug was.
- **§5.1/§5.2/§5.3 were not exercised on a real device** — see Fix status note above.
- Algorithmic correctness of anything downstream of the mapped domain models — out of scope by design.
- Localization/accessibility of the persistence-adjacent UI beyond the messaging gap fixed in §8.1 (the two new status strings use the existing `.localizedString` fallback pattern; they aren't yet in any String Catalog translation table).

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference — it should land on the cited line (line numbers reflect the ORIGINAL, pre-fix code for historical findings above; re-open the file directly to see the current fixed state).

- **§5.1** — open `Modules/RolePlayGameKit/Model/ShareExtensionDatabaseService.swift` and confirm `setup()` now branches on `useCloudKit` between `CloudKitCoreDataPersistenceController` and `CoreDataPersistenceController`.
- **§5.2** — open `Modules/CoreRPG/AppModels/AppSettingsModel.swift` and confirm `useCloudKit`'s `didSet`, `initSettings(from:)`, and `readUseCloudKitFromDefaults()` all reference `UserDefaults.appGroup`, not `.standard`.
- **§3.1/§3.2** — open `Modules/CoreRPG/Controllable/SyncDataControllable.swift` and confirm `updateFromSync` awaits `previousTask?.value` (no `.cancel()` call), and that deletions are computed via `dataControllable.fetchIds()` diffed against `itemControllable.itemDataModel.items`.
- **§5.3** — open `Sources/RPGShare/RPGShare-Debug.entitlements` and confirm `com.apple.developer.ubiquity-container-identifiers` is present, matching `Resources/MasterRPG-Debug.entitlements`.
- **§5.4** — open `Modules/GeneratorRPG/Controller/DataController.swift` and confirm the entries block now calls `model.syncEntries(...)`.
- **Build** — `xcodebuild -scheme MasterRPG -destination 'platform=iOS Simulator,id=C12570B6-1C33-488D-B515-3D5E35B67ABD' build` from the repo root reproduces the clean build confirmed after these fixes.

If any finding doesn't reproduce when you visit the line, flag the specific reference and it'll be re-investigated.
