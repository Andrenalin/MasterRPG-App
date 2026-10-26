# MasterRPG App Intents / Siri / Shortcuts / Donations Code Audit

Generated 2026-10-26. Scope: the App Intents surface of 13 modules — about 60 Swift files under `Modules/*/Intent/`, `Modules/CoreRPG/Controllable/ItemEntityQuery.swift`, `IntentEntityHelpers.swift`, `Modules/CoreRPG/App/AppIntentContentInvalidator.swift` and `UserActivity.swift`, `Modules/CoreRPG/Persistence/RpgSpotlightIndexerDelegate.swift`, the 12 `DetailListView` donation call sites, `Sources/MasterRPG/` (`MasterRPGShortcuts`, `MyAppPackage`, `MasterRPGApp.init`, `MasterRPGSpotlightIndexer`), `Resources/AppShortcuts.xcstrings`, `Sources/DiceRollerWidget/` intents, and `AudioRPG/Audio/MediaPlayerManager.swift`. Verified against the `/app-intent` skill references and the **Xcode 27.2 RC / iOS 27.2 SDK** (`AppIntents.swiftinterface`, `MediaPlayer` headers). Deployment target is **iOS 26.0 / macOS 26.0** everywhere (20 build configurations), so every iOS 27 API must be availability-gated.

Placement follows the repo convention (`Docu/CODE_AUDIT_<Topic>.md`); the root `CODE_AUDIT.md` was not touched. No production code was changed. The only edits in the working tree from this session are the new `AppIntentsTesting` tests in `Tests/MasterRPGUITests/` (done earlier, separate task); two temporary probe tests used while auditing were deleted again.

**Compiler ground truth.** After touching every intent source, a full `xcodebuild build` of the `MasterRPG` scheme (iPhone 18 Pro simulator, ~2,200 Swift compile steps) produced **4 warnings, none about App Intents** (one unrelated non-exhaustive `switch` in `GeneratorRPG/BasicAI/Engine/TranscriptTokenCounting.swift:8`; two benign "metadata extraction skipped" notes for the resource bundles). The `.system.search` deprecation does **not** warn today because it is deprecated *as of 27.0* and the deployment target is 26 — it will start warning the day the target is raised. Findings below are therefore semantic, not compiler-reported.

**Evidence labels.** *SDK-verified* = checked in the iOS 27.2 SDK interface. *Runtime-verified* = exercised through `AppIntentsTesting` on the simulator. *Code-confirmed* = read in source only. Anything not runtime-verified is said so.

---

## 1. Executive summary

Overall: the intent layer is broad and mostly sound — all 12 content entities are `IndexedEntity` with `IndexedEntityQuery`, `SyncableEntity` and `OwnershipProvidingEntity`; there is one `AppShortcutsProvider` at exactly the 10-shortcut cap with a localized `AppShortcuts.xcstrings`; dependencies are registered in `App.init()`; and the new out-of-process tests pass (34/34). The main gaps are iOS 27 *Siri-facing* adoption and Spotlight index hygiene.

1. **[High]** On-screen entity annotation and interaction donation are skipped on iOS 26 although both APIs exist since iOS 18.2 / iOS 16 — §5.1 — `Modules/AdventureRPG/Intent/OpenAdventureIntent.swift:34-43` (×12 modules).
2. **[High]** 10 of 12 modules' Create/Add intents accept blank names and report success for deleted targets; only Adventure and Character validate — §5.2 — e.g. `Modules/PdfRPG/Intent/PdfManagementIntents.swift:10-97`.
3. **[High]** Every item save and every iCloud sync merge triggers a full re-index of all items in all 12 modules — §7.1 — `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:95`, `Modules/CoreRPG/App/AppIntentContentInvalidator.swift:23-31`.
4. **[Medium]** All 12 search intents use `.system.search`, deprecated in 27.0 in favour of `.system.searchInApp`; and 12 intents claim the same system schema — §4.1.
5. **[Medium]** `.system.open` (the iOS 27 "open X in this app" schema) is not adopted by any of the 12 `OpenIntent`s — §4.2.
6. **[Medium]** The App Entity Spotlight index is never pruned and indexes trashed items; in-app delete/trash and purge leave stale entries (code-confirmed, not runtime-confirmed) — §5.3.
7. **[Medium]** The same item is indexed by three independent pipelines (Core Data Spotlight delegate, App Entities, `NSUserActivity` with a generic "An item from MasterRPG" description) — §5.4.
8. **[Medium]** Audio playback never tells the system which `AudioEntity` is playing (`MPNowPlayingInfoPropertyAppEntityIdentifiers`, new in iOS 27) and there is no play/pause intent — §4.3, §4.6.
9. **[Medium]** 65 of the 75 `AppShortcut` declarations are dead (never reach the provider) and one unit test asserts on them — §9.1; the 10 live shortcuts carry one phrase each — §5.6.
10. **[Medium]** The dice result snippet hard-codes white text with no background; likely unreadable on a light snippet card — §8.1 (rendering not verified).

---

## 2. Quick wins (≤30 min each)

- **Lower the iOS 27 gates to the real minimums** in the 12 `addSiriContext` / `donateSiriViewingIntent` helpers (`NSUserActivity.appEntityIdentifier` is iOS 18.2+, `IntentDonationManager` iOS 16+) — §5.1.
- **Add the blank-name / stale-target guard** copied from `AddCharacterEntryIntent` (`Modules/CharacterRPG/Intent/CharacterManagementIntents.swift:89-98`) to the other 10 Create and Add intents — §5.2.
- **Filter trashed items out of every `reindexAll`** (reuse each query's `include(model:)`) — §5.3.
- **Drop the no-op `updateAppShortcutParameters()` calls** — the provider has no parameterized phrases — `Sources/MasterRPG/MasterRPGApp.swift:78,84` — §7.2.
- **Delete the 65 dead `AppShortcut` declarations** or move the live 10 to be built from them — §9.1.
- **Replace the 9 private copies** of `intentPlainText` / `indexIntentEntities` / `deleteIntentEntities` with the shared CoreRPG versions — §9.2.
- **Give the dice snippet a theme-aware foreground** (`.primary`) — `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:104` — §8.1.
- **Fix `DiceEntity.attributeSet`** (invalid `contentType`, starts from scratch) — `Modules/DiceRPG/Intent/DiceEntity.swift:64-81` — §5.5.

---

## 3. Concurrency

The build is clean for strict concurrency in the intent files (0 intent-related warnings). One structural note:

### 3.1 Entities keep live `@MainActor` models and root models alive
- **Location:** `Modules/AdventureRPG/Intent/AdventureEntity.swift:41-42`, `Modules/DiceRPG/Intent/DiceEntity.swift:44-45`, `Modules/RuleRPG/Intent/RuleEntity.swift:37-38`, `Modules/CharacterRPG/Intent/CharacterEntity.swift:41-42` (and the same pattern in the other `*Entity.swift`; `AudioEntity` already dropped `model`, see its comment citing CODE_AUDIT_Audio §3.2).
- **What:** `AppEntity` structs store the whole `root` and live `model` reference besides the eagerly captured display strings.
- **Why:** An entity is a value the system caches and passes around (Siri, Shortcuts, donations); holding the live reference keeps heavy `@MainActor` objects reachable from system-owned storage, and `Rule`'s `Transferable` reads `item.model` from the entity. Only `AudioEntity` is already minimal.
- **Action:** Store only what `Transferable`/`OpenIntent` need (the id) and re-resolve through the root when exporting, as `AudioEntity` does.
- **Severity:** Low
- **Status:** Fixed 2026-10-26. `model` is no longer stored on any entity; `root` is no longer stored on the seven entities that never read it (Adventure, Character, Dice, Generator, Map, Table, Weather had none) and stays only on Audio, Pdf, Photo, Space and Rule, whose export re-resolves the file or the rule through it. `RuleEntity` now builds its plain-text export from a fresh `itemSync(for:)` lookup (`exportedPlainText()`), and `RollSpecificDiceIntent` uses `dice.id`. Builds: iOS and macOS. Tests: 35/35 `AppIntentsTesting` tests pass, including the new `testExportedPlainTextCarriesNameDescriptionAndSections`.

---

## 4. API modernity (iOS 27 adoption)

### 4.1 `.system.search` is deprecated in 27.0; 12 intents claim the same system schema
- **Location:** `@AppIntent(schema: .system.search)` at `Modules/AdventureRPG/Intent/SearchAdventuresIntent.swift:8`; `AudioManagementIntents.swift:95`; `CharacterManagementIntents.swift:114`; `DiceManagementIntents.swift:91`; `GeneratorManagementIntents.swift:96`; `MapManagementIntents.swift:93`; `PdfManagementIntents.swift:93`; `PhotoManagementIntents.swift:95`; `RuleManagementIntents.swift:93`; `SpaceManagementIntents.swift:99`; `TableManagementIntents.swift:94`; `WeatherManagementIntents.swift:94`.
- **What:** SDK-verified: `AppSchema.SystemIntent.search` carries `deprecated: 27.0, "Use .system.searchInApp instead"`; `.system.searchInApp` is `anyAppleOS 27.0`. All 12 modules adopt the old name, so 12 separate `ShowInAppSearchResultsIntent`s claim one app-wide system schema.
- **Why:** The old name is on a removal path (no warning until the deployment target reaches 27). A system-level "search in app" schema is a single entry point; with 12 claimants it is undefined which one Siri picks. This is a design question that was **not** verified on a device.
- **Action:** Add an iOS 27-gated sibling using `.system.searchInApp` and keep the legacy intents for iOS 26 (the macro and schema are 27-only, so they must be separate types funnelling into the same action). Decide whether one app-level search intent that routes to the Search module (and optionally a module scope) replaces the 12 per-module ones.
- **Severity:** Medium

### 4.2 `.system.open` is not adopted
- **Location:** all 12 `Modules/*/Intent/Open*Intent.swift` (`OpenAdventureIntent.swift:12`, `OpenAudioIntent.swift:12`, `OpenCharacterIntent.swift:12`, `OpenDiceIntent.swift:11`, `OpenGeneratorIntent.swift:12`, `OpenMapIntent.swift:12`, `OpenPdfIntent.swift:11`, `OpenPhotoIntent.swift:11`, `OpenRuleIntent.swift:10`, `OpenSpaceIntent.swift:12`, `OpenTableIntent.swift:12`, `OpenWeatherIntent.swift:12`).
- **What:** SDK-verified: `.system.open` (`anyAppleOS 27.0`) is the generic open schema; Apple deprecates the domain variants (e.g. `.photos.openAsset`: "Use .system.open instead"). None of the `OpenIntent`s adopt it. The skill describes it as the intent that lets Siri resolve "open *X* in MyApp" against indexed entities.
- **Why:** Voice "open <name>" on iOS 27 depends on it; the existing `OpenIntent`s still serve Spotlight taps and Shortcuts. Whether one schema intent per entity type is allowed (and the exact parameter shape) is **not verified**.
- **Action:** Spike one module (Adventure) with an iOS 27-gated `@AppIntent(schema: .system.open)` sibling funnelling into the existing navigation route, check the Xcode fix-it and the metadata processor accept 12 of them, then roll out. Keep the legacy `OpenIntent` for iOS 26, and donate the one matching the running OS (§4.4).
- **Severity:** Medium

### 4.3 Now Playing does not carry the playing `AudioEntity` (iOS 27)
- **Location:** `Modules/AudioRPG/Audio/MediaPlayerManager.swift:28-52` (`handleItemChange`); `Modules/AudioRPG/Audio/PlayerTime.swift:34-42` (`PlaylistItem.id`).
- **What:** SDK-verified: `MPNowPlayingInfoPropertyAppEntityIdentifiers` exists (iOS/macOS/tvOS 27.0, `MPNowPlayingInfoCenter.h:194`). The app sets title/artist/queue info but never the entity identifier although `PlaylistItem.id` is the audio item's id.
- **Why:** Siri cannot act on "the track that is playing" (and the new Audio `RelevantEntities` context `.audio(.nowPlaying)`, the only context in this SDK, has nothing to anchor on). Annotations need a real `AppEntity`; `AudioEntity` qualifies.
- **Action:** Add the `EntityIdentifier(for: AudioEntity.self, identifier:)` array under an iOS 27 `#available` in `handleItemChange`; consider `RelevantEntities.updateEntities(_:for: .audio(.nowPlaying))` for the active game playlist.
- **Severity:** Medium

### 4.4 Donations cover only `Open…Intent` and never delete or vary by OS
- **Location:** `Modules/AdventureRPG/Intent/OpenAdventureIntent.swift:40-55` (and the 11 sibling `Open*Intent.swift`); call sites `Modules/AdventureRPG/View/DetailListView.swift:38-40` (and the other 11 `DetailListView.swift` — `GeneratorRPG/Root/DetailListView.swift:65`).
- **What:** (a) The only donated intent is the legacy `Open…Intent`, fired from a view `.task(id: model.id)` — i.e. on every selection change, not on a completed action. (b) Nothing donates the actions users repeat from the UI: rolling a dice set (`RollSpecificDiceIntent`), starting a game (`StartAdventureGameIntent`), creating an item. (c) `deleteDonations(matching:)` is never called (SDK-verified present, `IntentDonationMatchingPredicate.entityIdentifiers`), so deleted/trashed items stay in the donation history. (d) Once `.system.open` exists (§4.2) the matching intent per OS should be donated.
- **Why:** Donations teach Siri/Apple Intelligence the user's patterns; selection-driven donations on iPad/Mac (arrow-keying a list) flood the system, which may then ignore the app's donations; dice rolls are the clearest repeated UI action and are not learned.
- **Action:** Donate once per real open (debounce by item id), add donations for UI dice rolls / game start / create, and delete donations by `entityIdentifiers` when an item is trashed or purged. Combine with §5.1 so iOS 26 gets them too.
- **Severity:** Medium

### 4.5 Entities expose only name and description
- **Location:** every `Modules/*/Intent/*Entity.swift`, e.g. `AdventureEntity.swift:31-35`; `ItemEntityQuery.swift:39` (conforms to `EnumerableEntityQuery`, not `EntityPropertyQuery`).
- **What:** Each entity has two `@ComputedProperty(indexingKey:)` fields (`name`→`displayName`, `description`→`contentDescription`). There is no `@Property` anywhere (0 hits), no tags, category/folder, dates, or entry text, and no `EntityPropertyQuery`/`findIntentDescription`. `description` is the item's summary only — the body (adventure sections, rule sections, character entries) is not part of the App Entity.
- **Why:** The iOS 27 pitch is Siri answering questions over indexed entities and the Use Model action serializing `@Property` fields; with name+summary only, "which adventure mentions the dragon" cannot be answered from the entity index. (Only the Core Data delegate index, §5.4, carries entry text.) The `EnumerableEntityQuery` conformance already gives a basic name-only Find action.
- **Action:** Expose tags, folder/category and modification date as `@Property`/`@ComputedProperty`; map a bounded excerpt of entry text to `contentDescription`/`textContent` via the attribute set; add `EntityPropertyQuery` for the modules where filtering matters (Adventure, Character, Dice).
- **Severity:** Medium

### 4.6 No Siri/Shortcuts way to play or control audio
- **Location:** `Modules/AudioRPG/Intent/` (only Create / Add Note / Search / Delete / Open).
- **What:** The Audio module is the in-game music player, but no `AudioPlaybackIntent`/play/pause/next intent exists, so "play <track> in MasterRPG" or pausing mid-session from Siri or an AirPods/CarPlay surface is impossible.
- **Why:** This is the most natural hands-free Game-Master action in the app. It also gives §4.3 an intent to pair with.
- **Action:** Add a Play (and Pause/Stop) intent on `AudioPlaybackIntent` taking `AudioEntity`, reusing the `AudioController`; no new iOS 27 API required.
- **Severity:** Medium

### 4.7 Lists are not annotated for on-screen awareness
- **Location:** the item list screen of each module; only the detail screens carry `.userActivity` + `appEntityIdentifier` (§5.1).
- **What:** No `.appEntityIdentifier(forSelectionType:)` or per-row annotation (0 hits).
- **Why:** "Open the third one" / "delete this" on a list screen cannot resolve to an entity; the list is the app's main screen.
- **Action:** Annotate the module list container with the selection-type form (lazy, survives scrolling).
- **Severity:** Low

### 4.8 `allowedExecutionTargets` is not set on app-only intents
- **Location:** every intent with `@Dependency var root:` (e.g. `Modules/AdventureRPG/Intent/CreateAdventureIntent.swift:25-26`).
- **What:** SDK-verified API (`IntentExecutionTargets` `.main`/`.appIntentsExtension`/`.widgetKitExtension`). None of the intents constrain it. The widget extension has no `AppIntentsPackage` and declares its own `RollDiceIntent`/`IntentDiceType` (`Sources/DiceRollerWidget/DiceRollerIntents.swift:10-80`), so today the app-only intents are not exposed there.
- **Why:** Pure hardening: if an extension is later added to the package graph, intents whose `@Dependency` is only registered in `MasterRPGApp.init()` could be scheduled in a process where it does not exist.
- **Action:** Add `[.main]` to the mutating/navigating intents when an App Intents extension is introduced; leave the dice roll intents unconstrained.
- **Severity:** Low

### 4.9 iOS 27 APIs evaluated and intentionally not needed (decision record)
- **Location:** n/a (see the adoption matrix in §10.1).
- **What:** `LongRunningIntent`/`CancellableIntent` (no intent exceeds ~1 s; all work is in-memory + save), `EntityCollection` (SDK-verified: `DeleteIntent.entities` must be `[Entity]`, so the delete intents cannot use it), `IntentValueQuery`/`@UnionValue` (content is local and indexed), `IntentValueRepresentation` (no structured system types), `displayRepresentations` fast path (entities are in-memory), assistant domain schemas (none of the pre-trained domains fits an RPG manager).
- **Why:** Recording the decision stops these being re-raised as gaps.
- **Action:** Revisit `LongRunningIntent` only if an import/export or "Generate with AI" intent is added.
- **Severity:** Low

### 4.10 No in-app discoverability
- **Location:** repo-wide (0 hits for `ShortcutsLink`, `SiriTipView`); no `NSAppIconActionTintColorName` / `NSAppIconComplementingColorNames` in the plists.
- **What:** The app has TipKit (`MasterRPGTips`) but never points users at its Siri/Shortcuts actions.
- **Why:** Ten registered shortcuts that nobody knows about.
- **Action:** Add `ShortcutsLink` to Settings and a `SiriTipView` for Roll Dice; add the two Info.plist tint keys.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 On-screen annotation and donation silently disabled on iOS 26
- **Location:** `Modules/AdventureRPG/Intent/OpenAdventureIntent.swift:34-36` (`addSiriContext`) and `:40-43` (`donateSiriViewingIntent`); the same two guards in `OpenAudioIntent.swift:32…`, `OpenCharacterIntent`, `OpenDiceIntent`, `OpenGeneratorIntent`, `OpenMapIntent`, `OpenPdfIntent`, `OpenPhotoIntent`, `OpenRuleIntent`, `OpenSpaceIntent`, `OpenTableIntent`, `OpenWeatherIntent`; callers e.g. `Modules/AdventureRPG/View/DetailListView.swift:34,39`.
- **What:** Both helpers start with `guard #available(iOS 27, macOS 27, visionOS 27, *) else { return }`. SDK-verified: `NSUserActivity.appEntityIdentifier` is `iOS 18.2 / macOS 15.2 / visionOS 2.2` (`AppEntityAnnotatable`), and `IntentDonationManager` is `iOS 16 / macOS 13`. The `OpenIntent`s themselves are available on 26.
- **Why:** The app's deployment target is 26.0, so every iOS 26 user (the whole current install base) gets no on-screen entity context and no donations; the features only start on iOS 27.
- **Action:** Gate on the real minimums (the activity property needs no gate at iOS 26; donation needs none). Keep `#available(iOS 27…)` only for the parts that really are 27-only (`.system.open`, `OwnershipProvidingEntity`, `IndexedEntityQuery`).
- **Severity:** High

### 5.2 Create and Add intents in 10 of 12 modules lack input validation
- **Location:** Create — `AudioManagementIntents.swift:10`, `DiceManagementIntents.swift:10`, `GeneratorManagementIntents.swift:10`, `MapManagementIntents.swift:10`, `PdfManagementIntents.swift:10`, `PhotoManagementIntents.swift:10`, `RuleManagementIntents.swift:10`, `SpaceManagementIntents.swift:10`, `TableManagementIntents.swift:10`, `WeatherManagementIntents.swift:10`. Add — `AudioManagementIntents.swift:55`, `DiceManagementIntents.swift:59`, `GeneratorManagementIntents.swift:56`, `MapManagementIntents.swift:55`, `PdfManagementIntents.swift:55`, `PhotoManagementIntents.swift:55`, `RuleManagementIntents.swift:53`, `SpaceManagementIntents.swift:58`, `TableManagementIntents.swift:56`, `WeatherManagementIntents.swift:54`. Reference implementation: `Modules/CharacterRPG/Intent/CharacterManagementIntents.swift:89-98`, `Modules/AdventureRPG/Intent/CreateAdventureIntent.swift:37-40`.
- **What:** Code-confirmed (script over all 12 files): only `CreateAdventureIntent`, `AppendAdventureSectionIntent`, `CreateCharacterIntent` and `AddCharacterEntryIntent` trim the text and call `needsValueError`; the Add intents also only guard against a deleted `target` in Adventure/Character. The other 20 intents write a blank-named item or entry, and Add intents call `editController.add(…)` on a stale `target` then return a success dialog.
- **Why:** Siri/Shortcuts can pass empty text; the user gets a blank, unusable item and a "Created" dialog. Runtime-verified for Adventure only (the new `AdventureIntentTests` assert the re-prompt); the other modules were not run, but the code paths are identical copies without the guard.
- **Action:** Extract one shared validation helper in CoreRPG (trim + re-prompt + "target still exists") and use it in all Create/Add intents; extend `ItemIntentTests` with a blank-name test per module (it will fail first — that is the regression test).
- **Severity:** High

### 5.3 The App Entity Spotlight index is never pruned and includes trashed items
- **Location:** `reindexAll` in every `*ShortcutCatalog.swift` (`AdventureShortcutCatalog.swift:91`, `AudioShortcutCatalog.swift:78`, `DiceShortcutCatalog.swift:130`, … `WeatherShortcutCatalog.swift:78`; Rule filters only `specialCategory`, `RuleShortcutCatalog.swift:66-69`); `deleteAppEntities` is called only from the Delete intents (shared helper `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:29-43` and the private copies, §9.2); contrast with `Modules/CoreRPG/Controllable/ExportControllable.swift:61`, which has to filter trashed items out of `itemDataModel.items` explicitly.
- **What:** `reindexAll` indexes every id in `itemDataModel.items`, which includes trashed items (`markForDeletion` only flips `displayState`, `EditControllable.swift:729-736`), while the queries hide them via `include(model:)` (`ItemEntityQuery.swift:72-75`). Nothing removes an entity from the index when the user trashes or purges an item in the UI — only the Delete *intent* does.
- **Why:** Stale and trashed entries stay searchable; Siri/Spotlight finds "Dragon Lair", the `OpenIntent` target then fails to resolve. **Runtime result:** a probe deleting an Adventure through the intent and re-querying Spotlight for 8 s saw 0 hits — but `AppEntityDefinition.spotlightQuery` appears to resolve hits back through the entity query (which already hides trashed items), so the probe cannot show whether the raw index still holds the item. This finding is code-confirmed, **not** runtime-confirmed.
- **Action:** Make `reindexAll` use each query's `include` filter, and on any trash/purge/import-replace call the shared delete helper (or diff-and-prune against the previous id set). Prefer incremental indexing of the changed ids (§7.1).
- **Severity:** Medium

### 5.4 Three Spotlight pipelines index the same item
- **Location:** (1) `Modules/CoreRPG/Persistence/RpgSpotlightIndexerDelegate.swift:27-55` (`NSCoreDataCoreSpotlightDelegate`, `domainIdentifier`/`indexName` "masterRPG-index"), started at `CoreDataPersistenceController.swift:184,224` and `CloudKitCoreDataPersistenceController.swift:85,152`, with per-entity attribute sets such as `Modules/AdventureRPG/Model/DataModel+Extensions.swift:17-49`; (2) the App Entity index (`indexIntentEntities`, `reindexAll`); (3) `Modules/CoreRPG/App/UserActivity.swift:49-65` — `isEligibleForSearch = true`, `isEligibleForHandoff = true`, `contentDescription = "An item from MasterRPG"`.
- **What:** Each item can appear as a Core Data item, an App Entity item and an activity item, each with different titles/descriptions; the third carries the same generic description for every item.
- **Why:** Duplicate Spotlight results and conflicting cards; the skill says to pick one approach per entity. The Core Data delegate handles deletions automatically and indexes entry text, the App Entity index feeds Siri's semantic search — they are complementary today, but nothing relates them. Duplicate rows were **not** observed on a device.
- **Action:** Decide the split explicitly: keep the Core Data index for full text and associate it with the entity (`CSSearchableItem.associateAppEntity`), or fold entry text into the App Entity; drop `isEligibleForSearch` and the generic description from `UserActivity.addPayLoad` (keep the activity for Handoff/on-screen context only).
- **Severity:** Medium

### 5.5 `DiceEntity.attributeSet` is built from scratch with invalid values
- **Location:** `Modules/DiceRPG/Intent/DiceEntity.swift:64-81`.
- **What:** It creates `CSSearchableItemAttributeSet(contentType: .item)` instead of `defaultAttributeSet`, assigns `contentType = "Dice"` and `contentTypeTree = ["Dice","Game","RPG"]` (not UTIs), overwrites keywords, and puts the die size into `comment`. Dice is the only entity with a custom set.
- **Why:** The skill's anti-pattern: building from scratch loses the system defaults and the `@ComputedProperty(indexingKey:)` mapping; non-UTI content types are ignored or mis-classified by Spotlight. Effect on ranking not measured.
- **Action:** Start from `defaultAttributeSet`, drop the two content-type lines, keep keywords/`relatedAppEntityIdentifier`.
- **Severity:** Medium

### 5.6 The 10-shortcut budget is spent on one phrase each and on a destructive action
- **Location:** `Sources/MasterRPG/MasterRPGShortcuts.swift:13-96`; `Resources/AppShortcuts.xcstrings` (10 keys).
- **What:** Navigate (1), Adventure Open/Create/Append/Start/Search/**Delete** (6), Roll my dice / D20 / D6 (3) = 10, the hard cap; every shortcut has exactly one phrase, none is parameterized, and the other 11 modules have no Siri phrase at all. "Delete an adventure" occupies a slot; "Show dice history" (`ShowDiceHistoryIntent`) does not.
- **Why:** Flexible matching works best with several wordings; the budget is spent on six Adventure actions and a delete. Parameterized phrases ("Open \<name\>") that the catalogs draft (`AdventureShortcutCatalog.swift:27`, `:61`) never reach the system.
- **Action:** Re-pick the 10 (e.g. open/start by name, roll, history, navigate, create), add 2-3 wordings each (negative phrases where they collide), and add the parameterized open/start/roll phrases — then `updateAppShortcutParameters()` becomes meaningful (§7.2). Localize new phrases in `AppShortcuts.xcstrings`.
- **Severity:** Medium

### 5.7 Create intents open the app by default
- **Location:** `Modules/AdventureRPG/Intent/CreateAdventureIntent.swift:23-24,49-52` (same in the 11 other Create intents).
- **What:** `openWhenCreated` defaults to `true`, and the intent then navigates and calls `continueInForeground(alwaysConfirm: false)`.
- **Why:** A Shortcuts automation that creates items brings the app to the foreground every time; the skill's guidance is to stay in the background by default (`supportedModes` already allows both).
- **Action:** Default to `false`, keep the parameter for "create and open".
- **Severity:** Low

### 5.8 Spotlight delete errors are handled inconsistently
- **Location:** `Modules/SpaceRPG/Intent/SpaceManagementIntents.swift:141` (`try?`) versus `try await` in the other Delete intents (e.g. `PdfManagementIntents.swift:134`, `Modules/AdventureRPG/Intent/DeleteAdventureIntent.swift:31`).
- **What:** After the item is already trashed and saved, a failing Spotlight delete throws in 11 modules (the user sees "failed" although the item is deleted) and is swallowed in Space.
- **Why:** Inconsistent outcome for the same event; the index failure should not fail the delete.
- **Action:** Log-and-continue everywhere (as Space does) via the shared helper.
- **Severity:** Low

### 5.9 `OwnershipProvidingEntity` always reports `.unknown`
- **Location:** `AdventureEntity.swift:88`, `AudioEntity.swift:96`, `CharacterEntity.swift:84`, `DiceEntity.swift:135`, `GeneratorEntity.swift:80`, `MapEntity.swift:84`, `PdfEntity.swift:99`, `PhotoEntity.swift:103`, `RuleEntity.swift:99`, `SpaceEntity.swift:98`, `TableEntity.swift:84`, `WeatherEntity.swift:82`.
- **What:** SDK-verified: `EntityOwnership` is an option set (`unknown`, `shared`, `public`). All 12 conform and return the constant `.unknown`.
- **Why:** The conformance gives Siri no signal, so the protocol is adopted but inert. Items shared via SharePlay/game mode are session-scoped, not "shared content", so `.unknown` may well be right — but then the conformance adds nothing.
- **Action:** Either remove the conformance or return `.shared` for items currently pushed to players / exported publicly.
- **Severity:** Low

---

## 6. Security

_No findings._ Checked: Delete intents are soft deletes (trash, recoverable) and conform to `DeleteIntent` so the system can confirm; `Rule` delete skips special categories; Transferable exports are local, on-device representations of the user's own items; no secrets, tokens or network access in any intent; `@Dependency` objects are registered in `App.init()` before any intent can run; no authentication inside `perform()`. The one ownership-related item is §5.9.

---

## 7. Performance

### 7.1 Every save and sync merge re-indexes all items of all modules
- **Location:** `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:95` (`save()`), `Modules/AdventureRPG/Root/AdventureRootModel.swift:325`, `Modules/CoreRPG/App/AppIntentContentInvalidator.swift:23-31`, `Sources/MasterRPG/MasterRPGSpotlightIndexer.swift:19-33`, `reindexAll` in the 12 catalogs.
- **What:** `invalidate()` is called from `save()` of every item controller (including the iCloud sync merge path) and from the Adventure root's import flush. After 1 s idle it runs `reindexAll` for all 12 modules: each builds an entity for every id and calls `indexAppEntities` with the full list on the main actor. The `IndexedEntityQuery.reindexEntities(for:)` methods exist but only the system calls them.
- **Why:** Cost grows with library size × save frequency; every edit, game update, dice roll that saves, or CloudKit merge repeats a full library re-index, plus Spotlight IPC. Not profiled, but the work is O(all items) per save.
- **Action:** Index the changed ids only (the save path knows them), keep one full reindex for first launch/the system's `reindexAllEntities`, and cancel/coalesce per module. Pairs with §5.3.
- **Severity:** High

### 7.2 `updateAppShortcutParameters()` is called for a provider without parameterized phrases
- **Location:** `Sources/MasterRPG/MasterRPGApp.swift:78,84`; `Modules/CoreRPG/App/AppIntentContentInvalidator.swift:28`.
- **What:** `MasterRPGShortcuts` has no `\(\.$param)` phrase, so there is no candidate cache to refresh.
- **Why:** Wasted work on each debounced invalidation; becomes correct only after §5.6 adds parameterized phrases.
- **Action:** Remove until parameterized phrases exist, or add them.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 Dice result snippet uses fixed white text and no background
- **Location:** `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:104` (`.foregroundStyle(.white)`) and `:13` (`.background(.black)` only in the `#Preview`).
- **What:** `RollResultSnippetView` is returned inline via `ShowsSnippetView`; it draws white text with no own background — the black background exists only in the preview.
- **Why:** Snippets are rendered over the system card, which is light in Light Mode; white-on-light would be unreadable. **Rendering on a device/simulator was not verified.**
- **Action:** Use `.primary`/`.secondary` styles (as for the subtitle) or give the view its own container background; keep it within the 340 pt height ceiling (it is).
- **Severity:** Medium

---

## 9. Dead code / duplication / refactor

### 9.1 65 of 75 `AppShortcut` declarations never reach the system
- **Location:** `Modules/*/Intent/*ShortcutCatalog.swift` — 65 declarations (Adventure 6, Audio 5, Character 5, Dice 9, Generator 5, Map 5, Pdf 5, Photo 5, Rule 5, Space 5, Table 5, Weather 5); the single provider is `Sources/MasterRPG/MasterRPGShortcuts.swift:10`. `Tests/AdventureRPGTests/AppIntentTests.swift:16` asserts `AdventureShortcutCatalog.all.count == 6`.
- **What:** Only `AppShortcutsProvider.appShortcuts` is scanned; the catalogs' `static var` shortcuts are never referenced from it (`grep` finds the catalog `.all` only in that test). The catalog files are live only for `reindexAll` and the `…FrameworkPackage` types.
- **Why:** Two drifting copies of the phrase set (the catalogs hold parameterized phrases and extra intents the provider lacks), and a test that pins dead code. The catalogs' phrases are not in `AppShortcuts.xcstrings`.
- **Action:** Delete the dead declarations (move `reindexAll` and the package types into proper files), or turn the catalogs into the single source that the provider composes (respecting the cap).
- **Severity:** Medium

### 9.2 Nine private copies of the Spotlight/text helpers
- **Location:** `Modules/PdfRPG/Intent/PdfManagementIntents.swift:149-171`, `DiceManagementIntents.swift:164-186`, `WeatherManagementIntents.swift:150-182`, `CharacterManagementIntents.swift:170-192`, `PhotoManagementIntents.swift:151-183`, `MapManagementIntents.swift:149-171`, `SpaceManagementIntents.swift:156-188`, `GeneratorManagementIntents.swift:148-180`, `AudioManagementIntents.swift:151-183`; Rule has its own variants (`RuleManagementIntents.swift:144-160`). The shared versions are `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:20-43`, used by Adventure and Table.
- **What:** `private func intentPlainText/indexIntentEntities/deleteIntentEntities` shadow the public CoreRPG helpers. `IntentEntityHelpers.swift`'s own header claims the extraction was done (CODE_AUDIT §9.8).
- **Why:** Any fix (e.g. §5.8) has to be made 10 times; the comment misleads.
- **Action:** Delete the private copies; make Rule's variants generic over the shared helper.
- **Severity:** Medium

### 9.3 Per-module Entity / Query / Create / Add / Search / Delete / Open copies
- **Location:** `Modules/*/Intent/` (~6,200 lines).
- **What:** Twelve near-identical sets. `ItemEntityQuery` already shares the query CRUD; CODE_AUDIT_10 §9.3 explicitly declined a shared base for the intents and entities because Siri/Shortcuts/Spotlight regressions could not be verified without a device.
- **Why:** That reason no longer holds as strongly: the out-of-process `AppIntentsTesting` suite added in `Tests/MasterRPGUITests` (34 tests, passing) exercises create / query / Spotlight / open / delete for all 12 modules, so a shared generic base now has a regression net.
- **Action:** After §5.2 and §5.3, consider a generic create/add/delete implementation parameterized by module; keep per-module `Entity` conformances.
- **Severity:** Low

### 9.4 Annotation and donation boilerplate repeated 12 times
- **Location:** `addSiriContext`/`donateSiriViewingIntent` in each `Open*Intent.swift` and the two modifiers in each `DetailListView.swift`.
- **What:** Same code with a different entity type.
- **Why:** Fixing §5.1 and §4.4 means 12 edits.
- **Action:** One generic helper in CoreRPG taking the entity factory and intent factory.
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Use the new tests as the safety net for the Spotlight/Siri work.** `Tests/MasterRPGUITests` runs every intent, query and Spotlight lookup out of process. Add failing tests first for §5.2 (blank names, all modules) and a raw-index check for §5.3 — `spotlightQuery` resolves through the entity query, so use a test-only DEBUG intent that lists the raw `CSSearchableIndex` identifiers.
2. **One indexing owner.** Collapse §5.3, §5.4, §7.1 into a single incremental indexer that knows adds, edits, trash, restore and purge, and decide how the Core Data delegate relates to it.
3. **A single OS-gating pattern for iOS 27.** Deployment is 26: `.system.open`, `.system.searchInApp`, `IndexedEntityQuery`, `OwnershipProvidingEntity`, and the Now Playing key are 27-only, while annotation and donation are not (§5.1). Use sibling intents for schema adoption and `#available` only where the API is truly new.
4. **Validate once.** One shared helper for trim / blank / stale-target checks removes §5.2 and the drift risk.
5. **Decide the Siri surface.** The 10-slot budget (§5.6), the open/search schemas (§4.1, §4.2), audio control (§4.6) and donations (§4.4) are the same decision: which five or six actions should be speakable.

### 10.1 iOS 27 feature adoption matrix

| Feature | State | Where |
|---|---|---|
| `IndexedEntity` + `indexAppEntities` | Adopted (12/12) | entities, `reindexAll` |
| `IndexedEntityQuery` | Adopted (12/12) | `*EntityQuery` extensions |
| `SyncableEntity` | Adopted (12/12); ids are CloudKit-stable UUIDs | `*Entity.swift` |
| `OwnershipProvidingEntity` | Adopted but constant `.unknown` | §5.9 |
| `.system.searchInApp` | **Not adopted** (old `.system.search` ×12) | §4.1 |
| `.system.open` | **Not adopted** | §4.2 |
| Now Playing entity identifiers | **Not adopted** | §4.3 |
| `NSUserActivity.appEntityIdentifier` (18.2+) | Adopted, but gated to iOS 27 by mistake | §5.1 |
| Interaction donation (`IntentDonationManager`) | Partly (Open only), gated to 27 by mistake, no deletion | §4.4, §5.1 |
| Collection annotation `appEntityIdentifier(forSelectionType:)` | Not adopted | §4.7 |
| `RelevantEntities` | Not adopted (only `.audio(.nowPlaying)` context exists) | §4.3 |
| `allowedExecutionTargets` | Not adopted (hardening) | §4.8 |
| `LongRunningIntent` / `CancellableIntent` | Not needed | §4.9 |
| `EntityCollection` | Not applicable (`DeleteIntent` needs `[Entity]`) | §4.9 |
| `IntentValueQuery`, `@UnionValue`, `IntentValueRepresentation`, `displayRepresentations` | Not needed | §4.9 |
| `EntityPropertyQuery` / `@Property` | Not adopted | §4.5 |
| Assistant domain schemas (`@AppEntity(schema:)`) | None fit | §4.9 |
| `AppIntentsPackage` per module | Adopted | `MyAppPackage.swift` |
| `AppShortcutsProvider` + `AppShortcuts.xcstrings` | Adopted (at the cap of 10) | §5.6 |
| `ShortcutsLink` / `SiriTipView` / tint keys | Not adopted | §4.10 |
| `AppIntentsTesting` | Adopted in `Tests/MasterRPGUITests` (34 tests) | — |

---

## 11. What was NOT audited

- **Siri, Shortcuts and Spotlight behavior on a physical device.** Everything runtime-verified ran in the iOS 27.2 simulator through `AppIntentsTesting`; voice phrase matching, flexible matching, Spotlight ranking/duplicates and Apple Intelligence consumption were not exercised.
- **macOS, visionOS and tvOS builds** of the intent code (only the iOS simulator build was run; platform `#if` branches were read, not compiled).
- **Localization correctness** of intent titles, dialogs and `AppShortcuts.xcstrings` (existence only: 10 keys × de/en/th).
- **Widget visuals** and timelines in `Sources/DiceRollerWidget/` beyond their intents (see the `widgets` skill); Live Activities, controls.
- **Entitlements, App Group wiring, background modes** (only noted that the widget uses its own intents).
- **`GeneratorRPG` Foundation Models flows** and any Apple Intelligence "Generate" intent (none exists).
- **Prior audits** (`Docu/CODE_AUDIT_*.md`, `Docu/App_Intents_Extension_Plan.md`) were not re-validated; findings already fixed there (e.g. blank-name guards for Adventure/Character) are treated as such.
- **Core Data / CloudKit internals** of `RpgSpotlightIndexerDelegate` beyond how it overlaps the App Entity index.
- **Test code quality** of the previous task's `Tests/MasterRPGUITests` (only used as evidence).

---

## 12. Verification

Open Xcode, command-click each reference — it should land on the cited line. For the High items and the key Mediums:

- **§5.1** — open `Modules/AdventureRPG/Intent/OpenAdventureIntent.swift`, lines `34-36` and `40-43`: both start with `guard #available(iOS 27, …)`. Then open the SDK interface `…/iPhoneOS.sdk/System/Library/Frameworks/AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface`, search `extension Foundation::NSUserActivity : AppIntents::AppEntityAnnotatable` (preceded by `@available(macOS 15.2, iOS 18.2 …)`) and `public struct IntentDonationManager` (preceded by `@available(macOS 13.0, iOS 16.0 …)`).
- **§5.2** — open `Modules/PdfRPG/Intent/PdfManagementIntents.swift`, lines `10-52` (`CreatePdfIntent.perform` uses `name` directly, no trim/guard) and `55-90` (`AddPdfBookmarkIntent` calls `editController.add` with no `itemSync` check); compare `Modules/CharacterRPG/Intent/CharacterManagementIntents.swift`, lines `89-98`.
- **§7.1** — open `Modules/CoreRPG/Controllable/ItemControllable+Sync.swift:95` (`AppIntentContentInvalidator.invalidate()` at the end of `save()`), then `Modules/CoreRPG/App/AppIntentContentInvalidator.swift:23-31` (1 s debounce, then `reindexContent`), then `Sources/MasterRPG/MasterRPGSpotlightIndexer.swift:19-33` (all 12 modules) and `Modules/AdventureRPG/Intent/AdventureShortcutCatalog.swift:91-96` (builds an entity for every id).
- **§4.1** — SDK interface, search `Use .system.searchInApp instead` (deprecated: 27.0) and `public var searchInApp` under `@available(anyAppleOS 27.0, *)`; any `SearchAdventuresIntent.swift:8`.
- **§4.2** — SDK interface, search `AppSchema.Intent("OpenIntent")` under `@available(anyAppleOS 27.0, *)`; then `OpenAdventureIntent.swift:12` (plain `OpenIntent`, no schema).
- **§4.3** — `…/MediaPlayer.framework/Headers/MPNowPlayingInfoCenter.h:194` (`MPNowPlayingInfoPropertyAppEntityIdentifiers`, iOS 27.0); `Modules/AudioRPG/Audio/MediaPlayerManager.swift:28-52` has no such key.
- **§5.3** — `Modules/CoreRPG/Controllable/ExportControllable.swift:61` (filters trashed ids out of `items`) versus `AdventureShortcutCatalog.swift:91-96` (does not); `EditControllable.swift:729-736` (trash only flips `displayState`). Runtime note: a probe through `AppIntentsTesting` showed 0 Spotlight hits for a deleted item for 8 s, which does not distinguish "removed" from "filtered by the entity query".
- **§5.4** — `RpgSpotlightIndexerDelegate.swift:27-55`, `CoreDataPersistenceController.swift:224`, `CloudKitCoreDataPersistenceController.swift:152` (delegate indexing is started), and `UserActivity.swift:50,63`.
- **§9.1** — `grep -rn "AppShortcut(" Modules Sources` returns 75 declarations; only the 10 in `Sources/MasterRPG/MasterRPGShortcuts.swift:13-96` are inside an `AppShortcutsProvider`; `grep -rn "ShortcutCatalog.all"` finds only `Tests/AdventureRPGTests/AppIntentTests.swift:16`.
- **§9.2** — `Modules/PdfRPG/Intent/PdfManagementIntents.swift:149-171` versus the public versions at `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:20-43`.

If any finding doesn't reproduce when you visit the line, tell me the reference and I'll re-investigate.
