# MasterRPG App Intents / Shortcuts / Siri / Donations Code Audit (re-audit, 2026-10-26)

Scope: the App Intents surface at HEAD `618f48a40` — the 12 module `Intent/` folders, `Modules/RolePlayGameKit/Intent/`, `Modules/CoreRPG/Controllable/Intent*.swift` / `ItemEntityQuery*.swift` / `SiriItemContext.swift`, `Modules/CoreRPG/App/{AppIntentContentInvalidator,DatabaseReadiness,UserActivity}.swift`, the Spotlight pipeline (`RpgSpotlightIndexerDelegate`, `MasterRPGSpotlightIndexer`), `Sources/MasterRPG/{MasterRPGShortcuts,MyAppPackage,MasterRPGApp}.swift`, `Resources/AppShortcuts.xcstrings`, `Sources/DiceRollerWidget/` intents and control, the donation call sites in the module views, and `Modules/AudioRPG/Audio/MediaPlayerManager.swift`. Checked against the `/app-intent` skill references and the **Xcode 27.2 RC / iOS 27.2 SDK** (`AppIntents.swiftinterface`). Deployment target is **iOS 26.0 / macOS 26.0**, so every iOS 27 API is availability-gated.

This is a **second pass on the same day** as `Docu/CODE_AUDIT_AppIntents.md` (27 findings, all fixed or decided). It does not repeat those findings. It (a) re-checks that the fixes hold, and (b) looks for what that audit did not examine. The previous audit file was not touched. The audit itself changed no code (it only refreshed the mtime of the intent sources to force a full recompile); the fixes came afterwards and are listed in §0.

**Compiler and metadata ground truth.** `xcodebuild build` of the `MasterRPG` scheme (iPhone 18 Pro simulator, 2,469 compile steps after touching every intent source) succeeded with **1 warning, unrelated** (`GeneratorRPG/BasicAI/Engine/TranscriptTokenCounting.swift:8`, non-exhaustive `switch`) and no App Intents diagnostics. The extracted App Intents metadata (`Metadata.appintents/extract.actionsdata` in `DerivedData`) holds **80 actions** in the 13 frameworks (12 modules + `RolePlayGameKit`), **12 entities, 12 queries**, **10 auto shortcuts** in the app, and **2 actions** in the widget extension. 25 of the 80 actions carry a system schema (12 × `system.open`, 12 × `system.search`, 1 × `system.searchInApp`). Several findings below rest on this metadata.

**Evidence labels.** *Metadata-verified* = read from the extracted metadata of this build. *SDK-verified* = checked in the iOS 27.2 SDK interface. *Code-confirmed* = read in source only. *Runtime-verified* = exercised through `AppIntentsTesting` (see §12 for this run's result). Nothing here was exercised on a physical device or with real Siri.

---

## 0. Fix status (2026-10-26, after the audit)

All findings were worked on the same day. Build: `MasterRPG` iOS, `MasterRPG` visionOS, `MasterMac` and `MasterTV` all `BUILD SUCCEEDED`. Evidence is the extracted metadata of the iOS build plus unit tests; **nothing was verified on a device or with real Siri**.

| § | Status | What was done |
|---|---|---|
| 3.1 | Not changed | Escape hatches are documented and stay until the SDK marks `CSSearchableIndexDescription` `Sendable`. |
| 4.1 | Fixed, device test still open | `AppModel.continueActivity(_:)` now also handles `CSSearchableItemActionType`: `SpotlightActivityRoute` (CoreRPG) maps the managed-object URI of a Core Data result to module, item and entry id; the scene delegate, the macOS delegate and `.onContinueUserActivity` all go through it. All 12 entities are `URLRepresentableEntity` (`RPG://<TOKEN>/0/<id>`) like `DiceEntity`, so App Entity results open on iOS 26 as well. Tests: `SpotlightActivityRouteTests` (CoreRPGTests, TableRPGTests with a real in-memory store), `EntityUrlRepresentationTests`. |
| 4.2 | Fixed | `isDiscoverable = false` on the 12 `Open<X>SchemaIntent` (metadata: `False`; the legacy `Open<X>Intent` stays `True`). |
| 4.3 | Fixed | `displayRepresentations(for:)` in the shared `ItemEntityQuery` (iOS 27): title and icon from the model, no entity. The SDK 27.2 signature has no `requestedComponents` parameter. |
| 4.4 | Fixed (without `LongRunningIntent`) | Optional `IntentFile` parameter on Create Photo, PDF, Audio and 3D Object. The type is checked against the module's `fileTypes` before anything is created (`intentFileData`); the file goes through `resetPhoto(data:)` / `resetFile(data:)`; if storing fails the item is removed again (`attachIntentFile`). `LongRunningIntent` not adopted: no import was measured above a few seconds. Tests: `IntentFileIntakeTests`. |
| 4.5 | Decision: not adopted | An audio-schema spike needs unrelated sibling intents and an `IntentValueQuery`; the current intents stay. Revisit at the deployment-target bump. |
| 4.6 | Partly fixed | Photo, Pdf, Map and Space return their **cached** thumbnail in `displayRepresentations(for:)` (never generated there). Not done: `thumbnailData` in the Spotlight attribute set (the attribute set is built synchronously, the cache is async). Type `synonyms` added to 11 entities (de + th). |
| 4.7 | Partly fixed | `negativePhrases` ("Play a movie / video / podcast in …") and the missing Thai phrases (Open and Start with target, Play audio, Pause audio, Dice history). No new shortcut slots: the budget is 10/10. |
| 4.8 | Not changed | `PauseAudioIntent` stays an `AudioPlaybackIntent`: the protocol may be what runs it in the app process that owns the player, and this cannot be tested without a device. |
| 4.9 | Fixed | `%lld maps` and `%lld weather settings` with en/de plural variations and th. |
| 5.1 | Fixed | `DatabaseReadiness.wait()` returns whether the database can take writes; `requireReadyDatabase()` throws `DatabaseNotReadyError` and starts every Create, Add and Delete intent. |
| 5.2 | Fixed | `.generator` in `UserActivity.extractModule`; `UserActivityTests` loops over the 12 detail modules. |
| 5.3 | Fixed | `indexIntentEntities` logs and continues; the 24 call sites no longer `try`. |
| 5.4 | Fixed | `updateAppShortcutParameters()` runs only when the sorted adventure names changed. |
| 5.5 | Fixed | `IntentDonations.donateThrottled`: one roll donation per dice set per 5 minutes. |
| 6.1 | Fixed (Delete only, by decision) | `authenticationPolicy = .requiresAuthentication` on the 12 Delete intents (metadata: `1`). |
| 6.2 | Fixed | The summary PDF is written to the temporary directory. |
| 7.1 | Partly fixed | `IntentEntityText.excerpt` cuts each part to the free space and tracks the length: O(limit) per entity. Not done: building the excerpt lazily only on the indexing path. Not measured. |
| 8.1 | Fixed | Default spacing, `accessibilityElement(children: .combine)`. |
| 8.2 | Fixed, not looked at | `siriTip(for:storageKey:)` (CoreRPG) shows a dismissible `SiriTipView` under the detail screens of Dice, Audio and Adventure on iOS and visionOS. The layout was not checked on screen. |
| 9.1 | Fixed | `NavigationOption` keeps only the cases, the display representations and `module`. |
| 9.2 | Fixed | The dead `isThumbnail` parameter is gone. |
| 9.3 | Fixed | `*ShortcutCatalog` renamed to `*IntentSupport` (12 files, `git mv`), the two stale header comments rewritten. |

---

## 1. Executive summary

No Critical findings. The intent layer is in good shape: 12/12 entities are `IndexedEntity` + `IndexedEntityQuery` + `SyncableEntity`, `OpenIntent` schema siblings exist for iOS 27, one app-level `.system.searchInApp` intent exists, Now Playing carries the playing `AudioEntity`, donations are deduplicated and deleted with the item, the provider sits exactly at the 10-shortcut cap with localized phrases, and incremental indexing replaced the full re-index. The open items are about **opening items from Spotlight on iOS 26**, **what happens when the database is not ready**, and **iOS 27 Siri-facing depth**.

1. **[High]** On iOS 26 no entity has an `OpenIntent` any more (the iOS 27 schema fix made the legacy intents plain `AppIntent`s), and the app handles no Core Data Spotlight tap at all — Spotlight results may not open the item — §4.1 — `Modules/AdventureRPG/Intent/OpenAdventureIntent.swift:12`, `Sources/MasterRPG/iOS/iOSSceneDelegate.swift:60`.
2. **[Medium]** Mutating intents (all Create/Add) report "Created" after the 20 s readiness timeout even if the database never started, and nothing is saved — §5.1 — `Modules/CoreRPG/App/DatabaseReadiness.swift:15,48`, `Modules/AdventureRPG/Intent/CreateAdventureIntent.swift:32`.
3. **[Medium]** `UserActivity.extractModule` has no Generator case, so Generator Handoff activities and `RPG://GENERATOR/…` links are dropped — §5.2 — `Modules/CoreRPG/App/UserActivity.swift:14-27`.
4. **[Medium]** On iOS 27, 13 intents claim the system search schema and 12 Open actions appear twice (legacy + schema), all discoverable — §4.2 — metadata-verified.
5. **[Medium]** Annotated list rows make Siri resolve entities through `entities(for:)`, which builds a full entity (including a 2,000-character text excerpt) per row; the `displayRepresentations` fast path is not implemented — §4.3, §7.1.
6. **[Medium]** No intent can receive a file: "Create Photo/Pdf/Audio/Space" creates an empty shell, and there is no `IntentFile` / `Transferable` import — §4.4.
7. **[Low]** 22 of 24 Create/Add intents fail *after* saving when the Spotlight call throws (Delete was already fixed for this) — §5.3.
8. **[Low]** Delete/Create/Add run without authentication from a locked device (`authenticationPolicy` = default) — §6.1.
9. **[Low]** Audio is the one module where an Apple audio schema (`.audio.playAudio`, `.audio.playlist`) might fit; the earlier "no domain fits" decision was not tested against SDK 27.2 — §4.5.

### Re-verified from the earlier audit (still holds)

| Earlier item | Check done now | Result |
|---|---|---|
| §5.1 annotation/donation gated to iOS 27 | `SiriItemContext.swift:25-36` has no iOS 27 gate | Holds |
| §5.2 blank-name / stale-target guards | `requiredIntentName` / `requiredIntentTarget` used in Create/Add (e.g. `MapManagementIntents.swift:84-85`) | Holds |
| §7.1 incremental indexing | dirty ids in `ItemDataModel.swift:142-150`, consumed in `IntentEntityHelpers.swift:127-129`; restore and trash both mark dirty (`ItemControllable.swift:239`) | Holds |
| §9.1 dead shortcut declarations | `MasterRPGShortcuts` is the only provider; metadata shows exactly 10 auto shortcuts | Holds |
| §4.3 Now Playing entity | `MediaPlayerManager.swift:51-57`, one call per item change (`AudioController.swift:331`) | Holds (builds only, no real playback) |
| §4.1/§4.2 schema siblings | metadata: `OpenXSchemaIntent` ×12 as `system.open`, `SearchInAppIntent` as `system.searchInApp` | Holds |
| `SyncableEntity` | metadata `entitySyncType: 1` on `AdventureEntity` | Holds |

---

## 2. Quick wins (≤30 min each)

- **Throttle roll donations** the way open donations are throttled (`IntentDonations.swift:35-43`) — §5.5.
- **Make the index call after save non-fatal in Create/Add** by using a log-and-continue variant of `indexIntentEntities` — §5.3.
- **Add `.generator` to `UserActivity.extractModule`** (one `case`) — §5.2.
- **Make `PauseAudioIntent` a plain `AppIntent`** — §4.8.
- **Delete the unused `NavigationOption.id/name/symbolName`** — §9.1.
- **Add the 3 missing Thai shortcut translations** (`Play audio`, `Pause audio`, `Show my dice history`) and the target phrase for the Thai "Open an adventure" — §4.7.
- **Add `en` and plural variants for the Map and Weather type names** — §4.9.
- **Set `.accessibilityElement(children: .combine)` and drop the fixed stack spacing** in the dice snippet — §8.1.

---

## 3. Concurrency

The build has no concurrency diagnostics in the intent files.

### 3.1 Documented escape hatches in the entity layer
- **Location:** `@preconcurrency` on `AdventureEntityQuery: ItemEntityQuery` (`Modules/AdventureRPG/Intent/AdventureEntity.swift:87`) and on the 12 `IndexedEntityQuery` extensions (e.g. `AdventureEntity.swift:104`, `TableEntity.swift:106`); `nonisolated(unsafe) static let properties/sortingOptions` in Adventure, Character and Dice (`AdventureEntity.swift:126,152`, `CharacterEntity.swift:122,148`, `DiceEntity.swift:171,197`).
- **What:** 15 `@preconcurrency` conformances and 6 `nonisolated(unsafe)` statics keep the `@MainActor` queries compiling against framework requirements that take a non-`Sendable` `CSSearchableIndexDescription` and a `QueryProperties` table.
- **Why:** Each one disables a data-race check. `TableEntity.swift:99-105` explains why the `@preconcurrency` is required (removing it fails to compile), and the statics are built once and never mutated, so no defect was found. The risk is future drift, not a current bug.
- **Action:** None now. Re-test removing them when the SDK marks `CSSearchableIndexDescription` `Sendable`.
- **Severity:** Low

---

## 4. API modernity (iOS 27 adoption)

### 4.1 Spotlight results may not open the item on iOS 26, and Core Data results never open it
- **Location:** `Modules/AdventureRPG/Intent/OpenAdventureIntent.swift:12` (legacy intent is a plain `AppIntent`; same in all 12 `Open*Intent.swift`); `Sources/MasterRPG/iOS/iOSSceneDelegate.swift:59-60` and `Sources/MasterRPG/macOS/macOSAppDelegate.swift:45-48` (both ignore every activity except `UserActivity.bundleIdentifierType`); `Modules/RolePlayGameKit/View/AppEnvironmentSetUpViewModifier.swift:130` (same filter); `Modules/CoreRPG/Persistence/RpgSpotlightIndexerDelegate.swift:27-55` and `Modules/AdventureRPG/Model/DataModel+Extensions.swift:17-49` (the Core Data index and its attribute sets); `Modules/CoreRPG/App/UserActivity.swift:51-55` (`isEligibleForSearch = false`).
- **What:** Metadata-verified: `OpenAdventureIntent` has `systemProtocols: []` — it is no longer an `OpenIntent` — and the iOS 27 `OpenAdventureSchemaIntent` is the only intent carrying `OpenEntity`. The earlier fix for "one `OpenIntent` per entity type" (§4.2) did that on purpose. Per the skill (`spotlight.md`, "Tap-to-open") a tap on an App Entity result is routed through the `OpenIntent` whose `target` is that entity type. On iOS 26 no such intent exists. Separately, results from the Core Data Spotlight delegate (the only index that carries entry text) deliver a `CSSearchableItemActionType` activity, which no handler in the repo reads (`grep` for `CSSearchableItemActionType` is empty); and the app's own search-eligible activity was switched off in the earlier §5.4 fix, so it no longer provides a third way in.
- **Why:** Spotlight can list an adventure and the tap may only bring the app to the front. iOS 26 is the whole current install base. The earlier audit's text for §4.2 says the legacy intents "still serve Spotlight taps", which the fix made untrue. **Not verified on a device**: the only evidence is the metadata and the documented routing rule.
- **Action:** First test on an iOS 26 and an iOS 27 device: search an item name, tap each result kind. If the tap does not open the item, pick one of: (a) conform every entity to `URLRepresentableEntity` with the existing `RPG://MODULE/0/<id>` links — `DiceEntity` already does this (`Modules/DiceRPG/Intent/DiceEntity.swift:105-116`) and the URL handler already resolves them; (b) keep one `OpenIntent` per entity on iOS 26 by moving the iOS 27 schema intents to a `#if`-separated target or dropping `.system.open` until the deployment target is 27; (c) handle `CSSearchableItemActionType` in the scene delegates, the SwiftUI modifier and the macOS delegate and map the unique identifier back to module and item id. Route Core Data results through (c) in any case.
- **Severity:** High

### 4.2 On iOS 27, 25 schema intents compete and Open appears twice per module
- **Location:** `@AppIntent(schema: .system.search)` in the 12 `Search*Intent.swift` (e.g. `SearchAdventuresIntent.swift:8`); `Modules/RolePlayGameKit/Intent/SearchInAppIntent.swift:15`; `@AppIntent(schema: .system.open)` in the 12 `Open*Intent.swift` (e.g. `OpenAdventureIntent.swift:38`).
- **What:** Metadata-verified: 12 × `system.search` + 1 × `system.searchInApp` + 12 × `system.open`, and every one of them, plus the 12 legacy `Open*Intent`s, has `isDiscoverable: true`. The schema `Open` intent has no `title` key in its metadata (the schema supplies it).
- **Why:** The search overlap is the known, accepted consequence of the earlier §4.1 (it disappears when the deployment target reaches 27 and the old name can go). New here: the Shortcuts library gets two "open" actions per module on iOS 27, one with a title and one with a schema-supplied title. Which of them Siri picks, and how the schema ones read in Shortcuts, is not verified.
- **Action:** Check the Shortcuts action list on an iOS 27 device. If the pairs read as duplicates, set `isDiscoverable = false` on the 12 schema intents (they serve Siri and Spotlight, not manual composition). Decide at the next deployment-target bump whether to drop the 12 deprecated search intents.
- **Severity:** Medium

### 4.3 `displayRepresentations` fast path is not implemented
- **Location:** `Modules/CoreRPG/Controllable/ItemEntityQuery.swift:87-95` (`entities(for:)` builds a full entity); `Modules/CoreRPG/LGViews/ListRowItemView.swift:91` (every list row carries `.appEntityIdentifier`); no `displayRepresentations` anywhere in `Modules/` or `Sources/`.
- **What:** Since the earlier §4.7 every visible list row is annotated. To resolve "open the third one" Siri looks up the visible entity ids; the only path is `entities(for:)`, which constructs the entity with tags, folder state and the entry-text excerpt (§7.1).
- **Why:** The skill (`onscreen-awareness.md`) warns that slow resolution makes Siri ask or give up. Only a title and subtitle are needed for that.
- **Action:** Implement the `displayRepresentations(for:requestedComponents:)` query method in the shared `ItemEntityQuery` extension, reading name and icon only from the model; keep `entities(for:)` for execution. Test with `viewAnnotations()` in `AppIntentsTesting`.
- **Severity:** Medium

### 4.4 No intent can receive a file or image
- **Location:** `Modules/PhotoRPG/Intent/PhotoManagementIntents.swift:10-56` (`CreatePhotoIntent`: name + description only, builds `PhotoModel(id:name:description:)`); the same in `PdfManagementIntents.swift:10`, `AudioManagementIntents.swift:10`, `SpaceManagementIntents.swift:10`. `grep` for `IntentFile`, `FileEntity` and `Transferable` import representations in `Modules/*/Intent` is empty.
- **What:** The four media modules (Photo, Pdf, Audio, Space) can export their content (`PhotoEntity.swift:79-100`) but cannot import any. "Create Photo" produces an item with no image.
- **Why:** The natural Shortcuts and Siri flow for a media library is "add this file / the photo I just took to MasterRPG". The shell item it creates today is unusable until the user attaches a file in the app. This also is the one place where `LongRunningIntent` (iOS 27) would apply, for large PDFs or audio files.
- **Action:** Decide whether file intake is wanted. If yes, give the four Create intents an `IntentFile` parameter, import through the same controller as the Share extension, and adopt `LongRunningIntent` + progress only if imports of real libraries exceed a few seconds.
- **Severity:** Medium

### 4.5 Apple audio schemas were not evaluated against SDK 27.2
- **Location:** `Modules/AudioRPG/Intent/AudioPlaybackIntents.swift:11-52`; `Modules/AudioRPG/Intent/AudioEntity.swift`.
- **What:** SDK-verified: `AppSchema.audio` offers intents `playAudio`, `addToPlaylist`, `warmupAudioQueue` and entities `playlist`, `ambientSound`, `audiobook`, among others, all `anyAppleOS 27.0`. The earlier §4.9 recorded "no pre-trained domain fits an RPG manager". For the Audio module (music and ambience played during a session) that is at least questionable.
- **Why:** Schema adoption is what lets Siri's media flow ("play the tavern ambience") reach the app without a fixed phrase. Cost: several schemas have required siblings and an `IntentValueQuery`.
- **Action:** Spike `.audio.ambientSound` / `.audio.playlist` for `AudioEntity` and `.audio.playAudio` for `PlayAudioIntent` in a branch; keep the current intents as the iOS 26 fallback. Drop the idea if the build demands unrelated siblings.
- **Severity:** Low

### 4.6 Entities have no images or synonyms
- **Location:** every `Modules/*/Intent/*Entity.swift` `displayRepresentation` (SF Symbol only, e.g. `PhotoEntity.swift:20-24`); no `attributeSet` override except `DiceEntity.swift:80`; `Modules/PhotoRPG/Intent/PhotoEntity+Image.swift:14-19`.
- **What:** Photo, Pdf, Map and Space items show a generic symbol in Siri responses, disambiguation and Spotlight. There is no `thumbnailData` / `thumbnailURL` in any entity attribute set and no `synonyms`.
- **Why:** Siri asks "which one?" using the display representation. Several photos or maps with similar names are indistinguishable.
- **Action:** Give the four visual modules a cached-thumbnail image in the display representation (the cache controller already produces thumbnails) and set `thumbnailData` in `attributeSet` from the same cache. Add `synonyms` where users name things differently ("Dice" / "Dice set").
- **Severity:** Low

### 4.7 App Shortcut phrases: no target phrases for audio and dice, no negative phrases, Thai gaps
- **Location:** `Sources/MasterRPG/MasterRPGShortcuts.swift:59-95`; `Resources/AppShortcuts.xcstrings` (keys `Play audio…`, `Pause audio…`, `Show my dice history…` have `en` and `de` only; the `th` value of `Open an adventure…` has 2 phrases and no `${target}` form).
- **What:** "Play audio" and "Roll my dice" need a target the user must answer in a second turn ("Which audio?"). There are no `\(\.$target)` forms for them. `negativePhrases` is not used although "Play", "Show", "Open" and "Start" overlap across Open Adventure, Start Adventure ("Play \(target)") and Play Audio.
- **Why:** Speaking "Play the Dragon Lair track" cannot resolve in one turn; "Play …" can be matched by two shortcuts. The shortcut budget is spent (10/10), so any addition must replace one.
- **Action:** Decide whether "Play <audio>" or "Roll <dice>" is worth a slot (they would replace Roll D6 or Dice History) and add `negativePhrases` to the two "Play" shortcuts. Fill the missing Thai values.
- **Severity:** Low

### 4.8 `PauseAudioIntent` is an `AudioPlaybackIntent`
- **Location:** `Modules/AudioRPG/Intent/AudioPlaybackIntents.swift:41-52`.
- **What:** Metadata-verified: both `PlayAudioIntent` and `PauseAudioIntent` have the system protocol `AudioStarting`. The protocol marks intents that *start* audio so the system prepares the audio session.
- **Why:** Harmless in the likely case, but a pause is not a start and the protocol may give it playback semantics (for example launching the app to the background audio state) that it does not need.
- **Action:** Make `PauseAudioIntent` a plain `AppIntent` unless a test shows the system needs the protocol to run it in the app process.
- **Severity:** Low

### 4.9 Entity type names: Map and Weather lack English and plural forms
- **Location:** `Modules/MapRPG/Intent/MapEntity.swift:16`, `Modules/WeatherRPG/Intent/WeatherEntity.swift:16` (`numericFormat`); the other ten modules have `en`, `de`, `th` with plural variations.
- **What:** `%lld Map` and `%lld Weather` have only `de` and `th`, no plural rule.
- **Why:** Siri says "3 Map" or "3 Weather" in English.
- **Action:** Add `en` and a plural variation; "Weather" is uncountable, so use "weather settings" or similar.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Mutating intents report success after the readiness timeout without checking readiness
- **Location:** `Modules/CoreRPG/App/DatabaseReadiness.swift:15,45-76` (`wait()` returns `Void` after 20 s); `Modules/RolePlayGameKit/Model/AppModel.swift:451-462` (`startDatabaseForBackgroundWork` returns without `markReady` if the context is `nil`); `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:85` (`dataControllable?.save()` is a no-op without a controller). Intent call sites: every `await DatabaseReadiness.wait()` in the Create/Add/Delete/Start intents, e.g. `Modules/AdventureRPG/Intent/CreateAdventureIntent.swift:32,44-52`. `grep` finds no use of `DatabaseReadiness.isReady` outside the type itself.
- **What:** If the Core Data stack did not start within 20 s (store load failure, migration problem, disk full), `wait()` returns anyway. A Create intent then inserts the model in memory, "saves" into nothing, indexes it and answers `Created "X"`. The doc comment on `DatabaseReadiness` describes exactly this failure mode as the reason for the gate.
- **Why:** The user is told an item exists that was never persisted, and the next `updates()` load removes it. Rare, but it is silent data loss from a voice command. Code-confirmed; not reproduced.
- **Action:** Have `wait()` report whether the app became ready (or expose `isReady`) and make every mutating intent fail with a dialog ("MasterRPG isn't ready — open the app") instead of continuing. Read-only queries may keep continuing.
- **Severity:** Medium

### 5.2 Generator is missing from `UserActivity.extractModule`
- **Location:** `Modules/CoreRPG/App/UserActivity.swift:14-27`; producer `Modules/GeneratorRPG/Root/DetailListView.swift:57-58`; consumers `Sources/MasterRPG/iOS/iOSSceneDelegate.swift:59-67`, `Sources/MasterRPG/macOS/macOSAppDelegate.swift:45-55`, `Modules/RolePlayGameKit/View/AppEnvironmentSetUpViewModifier.swift:137-144`, and `Modules/CoreRPG/App/URL+ItemId.swift:15-18` (`moduleIdentifier` for `RPG://…` links).
- **What:** The switch maps adventure, audio, dice, game, map, pdf, photo, rule, space, table, value, weather — not `NetworkModules.generator` (token `GENERATOR`, `NetworkModules.swift:48`). The Generator detail screen posts an activity with that token; on receipt `module(from:)` returns `.none` and the handler returns without navigating.
- **Why:** Handoff of a Generator item to another device, and any `RPG://GENERATOR/…` link, open nothing. The Siri on-screen annotation on the same screen is not affected (it uses the entity id).
- **Action:** Add the `generator` case, and add a test that round-trips every `NetworkModules` case that has a detail screen through `addPayLoad` / `module(from:)`.
- **Severity:** Medium

### 5.3 Create and Add intents fail after saving when the Spotlight call throws
- **Location:** 22 `try await indexIntentEntities(…)` calls after `save()`, e.g. `Modules/AdventureRPG/Intent/CreateAdventureIntent.swift:44`, `AppendAdventureSectionIntent.swift:45`, `PdfManagementIntents.swift:47,94`, `DiceManagementIntents.swift:51,89`, `WeatherManagementIntents.swift:46,92`, `CharacterManagementIntents.swift:49,100`, `PhotoManagementIntents.swift:47,93`, `RuleManagementIntents.swift:46,93`, `GeneratorManagementIntents.swift:48,94`, `MapManagementIntents.swift:47,94`, `TableManagementIntents.swift:48,95`, `AudioManagementIntents.swift:47,93`. Space uses `try?` (`SpaceManagementIntents.swift:50,97`). The helper: `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:63-66`.
- **What:** The item is already saved and the debounced invalidator will index it anyway (`ItemControllable+Sync.swift:95`). If `indexAppEntities` throws, the intent throws and the user sees a failure.
- **Why:** The same inconsistency the earlier §5.8 fixed for Delete: a retry of a "failed" create (a Shortcuts automation retries) makes a duplicate.
- **Action:** Use the log-and-continue pattern of `deleteIntentEntities` for the post-save index call, or drop the call and rely on the invalidator.
- **Severity:** Low

### 5.4 `updateAppShortcutParameters()` runs after every adventure edit
- **Location:** `Sources/MasterRPG/MasterRPGSpotlightIndexer.swift:47-52`; `Modules/AdventureRPG/Intent/AdventureShortcutCatalog.swift:21-24`.
- **What:** `hasChanges` is true whenever any adventure id is dirty, including edits to entry text (`ItemControllable.swift:239` marks the item on any `replace`). The parameterized phrases only depend on names.
- **Why:** After 1 s of typing pause the app refreshes the shortcut parameter list, which enumerates the adventure entities and builds their text excerpts (§7.1). Unmeasured; Apple recommends calling it when the candidate list changes.
- **Action:** Compare the sorted name list with the one used for the last refresh and call it only when it differs.
- **Severity:** Low

### 5.5 Dice roll donations are not throttled
- **Location:** `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:143-147`; call sites `Modules/DiceRPG/Game/Detail/DiceRollButton.swift:28`, `Modules/DiceRPG/View/DiceInline.swift:115`, `Modules/DiceRPG/Root/DetailRootView.swift:19`.
- **What:** Every UI roll donates `RollSpecificDiceIntent` and builds a `DiceEntity`. Open donations have a 2 s dwell and a 10 min repeat guard (`IntentDonations.swift:35-43`); roll donations have neither.
- **Why:** A combat round can mean dozens of rolls per hour. The skill warns the system may start ignoring a source that floods it. Rolls are real user actions, so donating is right; the volume is the question.
- **Action:** Donate at most once per dice set per few minutes, or only when the roll was started by the game master and is the first of a burst.
- **Severity:** Low

---

## 6. Security

### 6.1 Mutating intents run from a locked device
- **Location:** `authenticationPolicy` is not set anywhere in `Modules/` or `Sources/`; metadata shows `authenticationPolicy: 0` for `DeleteAdventureIntent` (and the others). Affected: the 12 `Delete*Intent`, 12 `Create*Intent`, 12 Add/Append intents, `StartAdventureGameIntent`.
- **What:** SDK-verified `static var authenticationPolicy: IntentAuthenticationPolicy` exists. The default lets Siri, an Action Button shortcut or a Lock Screen control run these intents with the device locked.
- **Why:** Delete is a recoverable soft delete and Create/Add only add data, so the exposure is small. For a game master's private campaign notes the worst case is someone trashing or appending to items from a lock screen.
- **Action:** Set `.requiresAuthentication` (or at least `.requiresLocalDeviceAuthentication`) on the Delete intents; leave dice and audio unauthenticated for table use.
- **Severity:** Low

### 6.2 Summary PDFs written for sharing stay in Caches
- **Location:** `Modules/CoreRPG/Intent/EntitySummaryExport.swift:18-39`.
- **What:** The PDF export of an item (name and description) is written to `URL.cachesDirectory/<id>.pdf` and never deleted; the file name is the item id, so repeated exports overwrite.
- **Why:** Bounded by the number of exported items and protected by the app sandbox, but the content is private campaign text that survives the item's deletion.
- **Action:** Write to the temporary directory, or remove the file for an item when it is purged.
- **Severity:** Low

---

## 7. Performance

### 7.1 Building an entity reads and copies entry text every time
- **Location:** `Modules/CoreRPG/Controllable/IntentEntityText.swift:16-29`; entity initialisers such as `Modules/AdventureRPG/Intent/AdventureEntity.swift:59-71`; callers `ItemEntityQuery.swift:77-120`, `ItemEntityQuery+Find.swift:15-47`, `IntentEntityHelpers.swift:116-142`, the donation helpers (`StartAdventureGameIntent.swift:43`, `RollSpecificDiceIntent.swift:143`) and `updateAppShortcutParameters()` (§5.4).
- **What:** `excerpt(of:)` walks the entries, appends each entry's *whole* content and only then cuts to 2,000 characters, and calls `text.count` (O(n)) on every loop iteration. Every `entities(for:)`, `entities(matching:)`, `allEntities()`, Find evaluation (one entity per item per predicate pass) and donation calls it on the main actor.
- **Why:** A library of a few hundred items with long entry texts makes Shortcuts pickers and the Find action do O(items × entry text) work on the main actor. Not profiled.
- **Action:** Stop at the limit inside the loop (take `prefix(remaining)` of each part, track the length as an `Int`), and compute the excerpt lazily only on the indexing path. Measure with Instruments on the largest example library.
- **Severity:** Medium

---

## 8. SwiftUI / UI

### 8.1 The dice result snippet has fixed spacing and no accessibility grouping
- **Location:** `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:67-100`.
- **What:** `VStack(spacing: 12)` and `.padding()` are hard-coded (project guidance asks to avoid fixed values), and the icon, title, name, sum and breakdown are separate accessibility elements.
- **Why:** VoiceOver reads five fragments for one roll result; the sum is the part users want.
- **Action:** Use default spacing, combine the children into one element with a label of the form "Critical success, Longsword, 17", and keep the 340 pt ceiling.
- **Severity:** Low

### 8.2 The Siri tip is only in Settings
- **Location:** `Modules/RolePlayGameKit/View/SettingsView.swift:104-114`.
- **What:** The only `SiriTipView` ("Roll a D20") sits in the Settings screen; nothing near the dice, the audio player or the start-game button points to the phrases.
- **Why:** Few users open Settings to look for voice commands. `NSAppIconComplementingColorNames` is still unset (known, design decision).
- **Action:** Show the tip on the dice detail screen (once, with `@AppStorage` dismissal), the audio player and the adventure start screen, using the matching intents.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 Unused members of `NavigationOption`
- **Location:** `Modules/RolePlayGameKit/Intent/NavigationOptions.swift:89,91-108,110-127` (`id`, `name`, `symbolName`); `grep` finds no use outside the file.
- **What:** `caseDisplayRepresentations` already holds the titles and symbols; the three computed properties and `Identifiable` / `Hashable` are unused copies.
- **Why:** Two places to update when a module is added (the `.character → .value` mapping is the kind of detail that drifts).
- **Action:** Delete them; derive `caseDisplayRepresentations` and `module` from one table if the enum grows.
- **Severity:** Low

### 9.2 `loadAssetData(isThumbnail:)` never loads a thumbnail
- **Location:** `Modules/PhotoRPG/Intent/PhotoEntity+Image.swift:9-19`, `Modules/PdfRPG/Intent/PdfEntity+Image.swift:8-18`.
- **What:** The only call passes `false`; the thumbnail branch is dead. It is the obvious source for §4.6.
- **Why:** Dead branch that suggests a feature the entities do not have.
- **Action:** Use it for §4.6 or remove the parameter.
- **Severity:** Low

### 9.3 Names and comments from the removed shortcut declarations
- **Location:** `Modules/*/Intent/*ShortcutCatalog.swift` (12 files, now `registerDonations` / `reindexChanged` / package type only); header of `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:9-19` ("these three functions… extraction carries none of that risk"); `Modules/CoreRPG/Controllable/ItemEntityQuery.swift:14-35`.
- **What:** The enums no longer hold shortcuts, and the helper file now has eight public functions while its header still describes three and cites a refactor decision (CODE_AUDIT_10 §9.3) that the later work reversed.
- **Why:** The next reader looks for shortcuts in the "catalog" files and trusts a stale risk statement.
- **Action:** Rename to `*IntentSupport` (or merge into `*Entity.swift`) and rewrite the two comments.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Decide the iOS 26 open path first (§4.1).** Every other Siri-facing item assumes users can get from a result to the item. One device test settles it.
2. **Make "database not ready" a first-class intent failure (§5.1).** A single `requireReadyDatabase()` helper in CoreRPG, called at the top of every mutating intent, replaces about 50 bare `wait()` calls in the intents and removes the silent-success mode.
3. **Round-trip tests for identifiers.** §5.2 is the kind of bug a loop over `NetworkModules.allCases` finds; the same loop would cover `URL.moduleIdentifier`, `IntentEntityIdentifiers` registration and `NavigationOption.module`.
4. **Keep one OS-gating pattern.** The sibling-intent pattern is applied consistently; keep new iOS 27 APIs behind `@available` + a sibling, as in the skill (`assistant-schemas.md`).
5. **Measure before more Siri depth.** §4.3 and §7.1 are plausible costs, not measured ones. Profile `entities(for:)` and `allEntities()` on the example library before adding more entity properties.

### 10.1 iOS 27 feature adoption matrix (state at HEAD)

| Feature | State | Where |
|---|---|---|
| `IndexedEntity` + `indexAppEntities` | Adopted 12/12, incremental, pruned | `IntentEntityHelpers.swift:116-170` |
| `IndexedEntityQuery` (reindex) | Adopted 12/12 | `*Entity.swift` |
| `SyncableEntity` | Adopted 12/12 (metadata `entitySyncType: 1`) | `*Entity.swift` |
| `.system.open` | Adopted as sibling ×12; iOS 26 tap path open | §4.1, §4.2 |
| `.system.searchInApp` | Adopted once, app-wide; 12 deprecated searches remain | §4.2 |
| `OwnershipProvidingEntity` | Removed on purpose (earlier §5.9) | — |
| Now Playing entity identifiers | Adopted | `MediaPlayerManager.swift:51-57` |
| On-screen annotation (activity, per-row) | Adopted; `forSelectionType` not applicable (lazy stack) | `SiriItemContext.swift`, `ListRowItemView.swift:91` |
| `displayRepresentations` fast path | **Not adopted** | §4.3 |
| `appEntityUIElements` (map canvas) | Not adopted; map pins are not entities | — |
| Donations | Open (dwell + repeat), Start game, UI dice rolls; deleted with the item | §5.5 |
| `RelevantEntities` | Not applicable: SDK 27.2 only offers `.audio(.nowPlaying)` | SDK-verified |
| `allowedExecutionTargets` | Deferred (no App Intents extension) | earlier §4.8 |
| `LongRunningIntent` / `CancellableIntent` | Not needed today; becomes relevant with file intake | §4.4 |
| `EntityCollection` | Not applicable (`DeleteIntent` needs `[Entity]`) | earlier §4.9 |
| `IntentValueQuery` / `@UnionValue` / `IntentValueRepresentation` | Not needed | earlier §4.9 |
| Apple domain schemas | None adopted; `.audio` worth a spike | §4.5 |
| `EntityPropertyQuery` / `@ComputedProperty` | Adventure, Character, Dice have Find; all 12 have indexing keys | `AdventureEntity.swift:119-170` |
| `AppIntentsPackage` per module | Adopted (13 packages) | `MyAppPackage.swift` |
| `AppShortcutsProvider` + catalog | 10/10, de + th, no negative phrases | §4.7 |
| `ShortcutsLink`, `SiriTipView`, tint key | Settings only; `NSAppIconComplementingColorNames` unset | §8.2 |
| Control widget | Roll D20 only; no audio or other controls | `DiceRollerWidget.swift:96-110` |
| `AppIntentsTesting` | Adopted: Item, Adventure, Dice, Navigate, Audio suites | §12 |
| `authenticationPolicy` | Not set | §6.1 |

---

## 11. What was NOT audited

- **Siri, Shortcuts and Spotlight behaviour on a physical device.** Spotlight tap routing (§4.1), flexible phrase matching, the look of the duplicated Open actions (§4.2) and Apple Intelligence use of the entities were not exercised.
- **iOS 26 runtime.** `AppIntentsTesting` needs iOS 27; the iOS 26 conclusions rest on SDK availability and extracted metadata.
- **macOS, visionOS and tvOS builds** of the intent code (only the iOS simulator scheme was built in this pass).
- **Instruments profiling.** §4.3, §5.4 and §7.1 are reasoned from the code, not measured.
- **Widget visuals and timelines** beyond the intent and control declarations; Live Activities (none exist); the Share extension's own intake.
- **Localization correctness** of the translations (presence of keys only).
- **Core Data / CloudKit internals** of the Spotlight delegate beyond how it overlaps the App Entity index.
- **Prior audits** (`Docu/CODE_AUDIT_*.md`, `Docu/App_Intents_Extension_Plan.md`) were used as context, not re-validated except where §1 says so.
- **Test code quality** of `Tests/MasterRPGUITests` (used as evidence only).

---

## 12. Verification

Open Xcode, command-click each reference; it should land on the cited line.

- **§4.1** — `Modules/AdventureRPG/Intent/OpenAdventureIntent.swift:12` (`AppIntent`, not `OpenIntent`) and `:38-39` (the only `OpenIntent`, schema, iOS 27). Metadata: `DerivedData/…/Debug-iphonesimulator/AdventureRPG.framework/Metadata.appintents/extract.actionsdata` → `actions.OpenAdventureIntent.systemProtocols == []`, `actions.OpenAdventureSchemaIntent.systemProtocols` contains `OpenEntity`. Then `Sources/MasterRPG/iOS/iOSSceneDelegate.swift:60` and `Sources/MasterRPG/macOS/macOSAppDelegate.swift:48` (only `UserActivity.bundleIdentifierType` passes), and `grep -rn CSSearchableItemActionType Modules Sources` (no hit). Counter-example for option (a): `Modules/DiceRPG/Intent/DiceEntity.swift:105-116`.
- **§4.2** — metadata of the 13 frameworks: 12 `system.open`, 12 `system.search`, 1 `system.searchInApp`; all have `visibilityMetadata.isDiscoverable == true`; `OpenAdventureSchemaIntent` has no `title`.
- **§4.3** — `Modules/CoreRPG/LGViews/ListRowItemView.swift:91` (annotation) and `Modules/CoreRPG/Controllable/ItemEntityQuery.swift:87-95` (`entities(for:)` builds `makeEntity`); `grep -rn displayRepresentations Modules Sources` (no hit).
- **§4.4** — `Modules/PhotoRPG/Intent/PhotoManagementIntents.swift:10-56` (parameters: `name`, `details`, `openWhenCreated`; no file); `grep -rn "IntentFile\|FileEntity" Modules/*/Intent` (no hit).
- **§4.5** — SDK interface `arm64e-apple-ios.swiftinterface`, search `var playAudio` and `var ambientSound` under `@available(anyAppleOS 27.0, *)`.
- **§4.8** — metadata `PauseAudioIntent.systemProtocols == ["…AudioStarting"]`; `Modules/AudioRPG/Intent/AudioPlaybackIntents.swift:41`.
- **§5.1** — `Modules/CoreRPG/App/DatabaseReadiness.swift:45-76` (returns `Void`, no result), `Modules/RolePlayGameKit/Model/AppModel.swift:451-462` (`guard let context … else { return }`), `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:85` (`dataControllable?`), `Modules/AdventureRPG/Intent/CreateAdventureIntent.swift:32-52`; `grep -rn "DatabaseReadiness.isReady" Modules Sources` finds none outside the type.
- **§5.2** — `Modules/CoreRPG/App/UserActivity.swift:14-27` (no `generator` case) versus `Modules/CoreRPG/Model/NetworkModules.swift:48` (token `GENERATOR`) and `Modules/GeneratorRPG/Root/DetailListView.swift:57-58`.
- **§5.3** — `grep -rn "try await indexIntentEntities" Modules` returns 22 lines; `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:63-66` throws; compare `deleteIntentEntities` (log-and-continue) at `:71-89`.
- **§5.4** — `Sources/MasterRPG/MasterRPGSpotlightIndexer.swift:47-52` and `Modules/CoreRPG/ItemList/ItemDataModel.swift:142-146`.
- **§6.1** — metadata `DeleteAdventureIntent.authenticationPolicy == 0`; `grep -rn authenticationPolicy Modules Sources` (no hit); SDK `static var authenticationPolicy` at `AppIntents.swiftinterface:7225`.
- **§7.1** — `Modules/CoreRPG/Controllable/IntentEntityText.swift:16-29` (`text.count` in the loop; `text += part` before `prefix`).

**Build:** `xcodebuild -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build` → `BUILD SUCCEEDED`, 1 unrelated warning.

**AppIntentsTesting run (Item, Adventure, Dice, Navigate, Audio suites, iPhone 18 Pro simulator, iOS 27.2):** **47 of 49 passed** (706 s). The two failures:
- `AdventureIntentTests.testStartGameRunsForAnAdventure` ("did not select the Game tab") — the known-flaky test from the earlier audit (its assertion is trivially true at launch and unreliable otherwise). Not related to this report's findings.
- `ItemIntentTests.testEmptyStringQueryFallsBackToSuggestions` — the Adventure module's `entities(matching: "")` returned 19 ids and `suggestedEntities()` 20 (one trailing id more) in the same test. It passed when re-run alone (1/1), so it looks like state changing between the two awaits in a long session (items created by earlier tests, or a sync/index pass). Not investigated further; worth keeping an eye on because the test compares two separate calls instead of one snapshot.

**After the fixes (same day):** the same five AppIntentsTesting suites ran again on the fixed tree: **49 of 49 passed** (550 s), including the two tests that failed in the first run. Unit tests added for the fixes (`UserActivityTests`, `EntityUrlRepresentationTests`, `IntentFileIntakeTests`, `SpotlightActivityRouteTests` in CoreRPGTests and TableRPGTests) pass. Builds: iOS, visionOS, macOS and tvOS `BUILD SUCCEEDED`.

If any finding does not reproduce when you visit the line, tell me the reference and I will re-investigate.
