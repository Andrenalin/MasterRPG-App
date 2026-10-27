# MasterRPG App Intents / Siri / Shortcuts / Donations Code Audit (third pass, Siri AI experience, 2026-10-27)

Scope: the App Intents surface at HEAD `01164eb93` — the 12 module `Intent/` folders, `Modules/RolePlayGameKit/Intent/`, the shared CoreRPG intent layer (`Controllable/Intent*.swift`, `ItemEntityQuery*.swift`, `SiriItemContext.swift`, `IntentDonations.swift`, `Intent/EntitySummaryExport.swift`, `LGViews/SiriTipModifier.swift`), the Core Data Spotlight attribute sets (`Modules/*/Model/DataModel+Extensions.swift`), `Sources/MasterRPG/{MasterRPGShortcuts,MyAppPackage,MasterRPGApp}.swift`, the widget extension's intents and control, the donation call sites, the Now Playing code and the module string catalogs used by intent dialogs. Checked against the `/app-intent` skill references (in particular `siri-intelligence.md`, `assistant-schemas.md`, `onscreen-awareness.md`) and the **Xcode 27.2 RC / iOS 27.2 SDK** (`AppIntents.swiftinterface`, `Foundation.swiftinterface`). The deployment target is iOS 26.0 / macOS 26.0.

This is the **third pass**, after `Docu/CODE_AUDIT_AppIntents.md` and `Docu/CODE_AUDIT_AppIntents2.md` (both from 2026-10-26, all findings fixed or decided). It does not repeat their findings. Its question is the one the user asked: **what is still missing for the best Siri / Apple Intelligence experience**, plus anything the earlier passes did not look at (they explicitly left out the localization of intent strings). Decisions recorded there (no `OwnershipProvidingEntity`, no `allowedExecutionTargets`, Pause stays an `AudioPlaybackIntent`, no audio schema, Create/Add allowed while locked, 10/10 shortcut slots) are respected; where this report re-raises one, it says so.

**Ground truth.** `xcodebuild build` of `MasterRPG` (iPhone 18 Pro simulator), after touching every `Intent/` source and the shortcuts provider: `BUILD SUCCEEDED`, **0 warnings**. Extracted App Intents metadata (`Metadata.appintents/extract.actionsdata` in DerivedData, 15 bundles): **82 actions, 12 entities**; **75 of 82 actions have no `descriptionMetadata`**; the three dice actions have no `outputType`; static titles are stored as bare keys (`{"key": "Create Adventure"}`) and **no dialog string is in the metadata**. One runtime probe was run with Xcode's `RunCodeSnippet` in the context of `CreateAdventureIntent.swift` (see §5.1).

**Evidence labels.** *Metadata-verified*, *SDK-verified*, *Code-confirmed* as in the earlier reports. *Runtime-probed* = the `RunCodeSnippet` probe of §5.1. Nothing was tested with real Siri or on a device.

---

## 0. Fix status (2026-10-27)

Fixed the same day, with the user's decisions: all four new action groups, value change as delta + set, entries linked through the Core Data index, the Dice History shortcut slot given to dice expressions, free rolls join a running game, table rolls are never shared, Join Game / a Next Turn control / master-only game control, and a `.reader` spike. Builds: iOS, visionOS, macOS, tvOS. New unit tests: `DiceExpressionTests`, `IntentEntityTextTests`, `TableRollTextTests`; UI test `testRollDiceExpressionRunsForNotation`. Nothing was tried with real Siri or on a device.

| § | Status | What was done |
|---|---|---|
| 4.1 | Fixed | `EntitySummaryExport.plainText/pdf` export the whole item (`IntentEntityText.document`, up to 50,000 characters; Character with calculated values). Text modules offer text first, media modules their file first. |
| 4.2 | Fixed | The Core Data Spotlight items carry `relatedAppEntityIdentifier` for their entity (`CSSearchableItemAttributeSet.relate(to:itemId:)`, iOS 27), so Siri can reach the full indexed text through the entity. |
| 4.3 | Fixed | `IntentEntityText.readable` turns links into labels and drops bold markers; Character's excerpt uses `LinkController.calculate`. |
| 4.4 | Fixed | Every Create, Add, Update, Search, Delete, Open and new action has an `IntentDescription` with category and keywords. |
| 4.5 | Fixed | `Update<Module>Intent` in all 12 modules (name, description, add/remove tags; `updateIntentItem`). `ChangeCharacterValueIntent` adds, subtracts or sets a number, keeps formulas (`base\|modifier`), asks which one when names repeat, and sends a player's change to the master. |
| 4.6 | Fixed | `DiceExpression` ("3d6+2", "2 W 20", "d20 plus 5", "d%"), `RollDiceExpressionIntent`; all roll intents return `ReturnsValue<Int>`. |
| 4.7 | Fixed | `RollTableIntent` rolls nested tables like Auto Roll and returns the text; never shared with players. Auto Roll in the app donates it. |
| 4.8 | Fixed | `NextTurnIntent`, `NextRoundIntent`, `EndBattleIntent` (confirms), `StopGameIntent` (confirms, needs an unlocked device), `JoinGameIntent` (foreground; needs the character chosen on the game screen beforehand), and a Control Center Next Turn control (`LiveActivityIntent`, so it runs in the app). |
| 4.9 | Fixed | `RunGeneratorIntent`: on-device Foundation Models, streamed with progress; `LongRunningIntent` + `performBackgroundTask` on the 27 releases. `CancellableIntent` is not adopted (26.4+ only, deployment target 26.0); cancelling the task still stops the generation. |
| 4.10 | Won't fix | Spiked and dropped: every `.reader` schema is documented for the Shortcuts experience only, not Siri; `.reader.document` requires a `documentKind` enum and `width`/`height` (a PDF has no single page size); `.reader.openPage` needs a separate page entity, and bookmarks are not pages. `.notes` waits for the deployment-target bump. |
| 4.11 | Fixed | Entities and the on-screen fast path show a subtitle: the folder, else the first line of the description. |
| 4.12 | Fixed | `DiceRollDialog`: spoken `full` text without emoji that names the dice and values, short `supporting` line. |
| 4.13 | Fixed | `ResumeAudioIntent`, `NextTrackIntent`; the player's play button donates `PlayAudioIntent`. Pause covers stop. |
| 4.14 | Fixed | Add/Append/Create return the updated entity. |
| 4.15 | Fixed | `intentMarkdown(from:)` writes emphasis, code, links, headings, lists and quotes as Markdown. |
| 4.16 | Open | Needs the two-window iPad / visionOS test first; not changed. |
| 5.1 | Fixed | `IntentDialog.localized(_:bundle:)`, `.localized(full:supporting:bundle:)` and `LocalizedStringResource.intent(_:bundle:)` with `.module` (`.ruleModule` in RuleRPG) at every dialog; a unit test resolves a reply in German from the module catalog. |
| 5.2 | Fixed | de/th for the Audio and Dice strings and for all new intent keys (about 480 in 15 catalogs). |
| 5.3 | Fixed | In a running game a free roll is a game dice set with one fixed id per run, shared like a sheet roll; otherwise it is the widget's last roll. `ShowDiceHistoryIntent` is titled "Show Last Roll". |
| 6 | Decided | Update intents require an unlocked device; value changes, rolls, audio and battle control stay open; Stop Game requires an unlocked device. |
| 7.1 | Fixed | `displayRepresentations(for:)` no longer waits for the database. |
| 8.1 | Fixed | The roll card is a `SnippetIntent` with a "Roll Again" button (`RollDiceAgainIntent`, not discoverable). |
| 9.1 | Fixed | Comments on `PdfEntity` and `RuleEntity` say why the root is kept. |
| 9.2 | Fixed | `RollDiceIntent` rewritten: stale comment and default flags gone, `supportedModes = .background`. |

App Shortcuts: "Dice History" was replaced by "Roll Dice Expression" ("Roll custom dice / Roll some dice / Make a dice roll in MasterRPG"); "Show Last Roll" stays available without a fixed phrase.

---

## 1. Executive summary

The plumbing is complete: every module has entities, queries, indexing, open/search schemas, donations and on-screen annotations. What holds the Siri experience back now is **what Siri hears and sees** (wrong-language replies, emoji read aloud, a content export without the content) and **what it can do** (no update, no dice expressions, no random tables, no game-mode control).

1. **[High]** Every spoken reply, follow-up question and re-prompt of the module intents is looked up in the **app** bundle, not the module bundle that holds the translations, so German and Thai users hear English. Runtime-probed — §5.1 — `Modules/AdventureRPG/Intent/CreateAdventureIntent.swift:49`.
2. **[High]** "Summarize this", Writing Tools and ChatGPT hand-offs get only **name + description**: 7 entity types export no entry text, and the first representation is a one-page PDF of those two fields. Only Rule exports its sections — §4.1 — `Modules/CoreRPG/Intent/EntitySummaryExport.swift:18-23`.
3. **[Medium]** Siri's semantic index sees at most **2,000 characters per item**. Entries are not entities, and the Core Data index, which has the full text, is not linked to the entities — §4.2 — `Modules/CoreRPG/Controllable/IntentEntityText.swift:13`.
4. **[Medium]** The indexed excerpt is raw Markdown with `RPG://` link URLs and unresolved formulas (`[HP](RPG://VALUES/0/…)+10`). Siri and the Use Model action read URLs instead of values — §4.3 — `IntentEntityText.swift:23-31`.
5. **[Medium]** 75 of 82 actions have no `IntentDescription`, which is the text Apple Intelligence and Shortcuts use to pick and explain an action — §4.4 — metadata-verified.
6. **[Medium]** No intent can **change** an item (rename, edit the description, tag, set a value such as HP), so Siri can only create, append, open and trash — §4.5.
7. **[Medium]** Dice intents can't take an expression ("roll 3d6+2") and return no value, although `RawDice(text:)` already parses notation — §4.6 — `Modules/DiceRPG/Model/RawDice.swift:30`.
8. **[Medium]** Random tables, the battle round (next turn / next round), stopping a game and joining with a code are not intents. These are the hands-free game-master actions used at the table — §4.7, §4.8.
9. **[Medium]** Spoken replies are a single string with emoji ("🎲 Rolled …", "💥 Critical Failure! …"), and there is no `full`/`supporting` split for AirPods or HomePod — §4.12.

---

## 2. Quick wins (≤30 min each)

- **Pass the module bundle to every intent dialog**: one CoreRPG helper, or `LocalizedStringResource(…, bundle: .atURL(Bundle.module.bundleURL))`, then replace the literals — §5.1. (Mechanical, but ~130 sites; under 30 minutes per module.)
- **Add de/th for the Audio playback strings** (`Playing "%@".`, `Paused the audio.`, `Which audio do you want to play?`) and th for the two dice-history strings — §5.2.
- **Drop the emoji from the spoken dialogs** and move them into `supporting` — §4.12.
- **Add `ReturnsValue<Int>`** to `RollDiceIntent` and `RollSpecificDiceIntent` — §4.6.
- **Fix the stale `RollDiceIntent` comment** ("iOS 18: Support for interactive widgets") — §9.2.
- **Fix the misleading "live model not stored" comment** on `PdfEntity` — §9.1.

---

## 3. Concurrency

_No findings._ The build has no concurrency diagnostics. The `@preconcurrency` / `nonisolated(unsafe)` escape hatches recorded in `CODE_AUDIT_AppIntents2` §3.1 are unchanged.

---

## 4. API modernity / Siri and Apple Intelligence depth

### 4.1 Entity export carries no content: "summarize this" gets name and description only
- **Location:** `Modules/CoreRPG/Intent/EntitySummaryExport.swift:18-23` (PDF of `name` + `description`) and `:45-53` (plain text of the same); used by `Modules/AdventureRPG/Intent/AdventureEntity.swift:84-94`, `Modules/CharacterRPG/Intent/CharacterEntity.swift:83-93`, `Modules/MapRPG/Intent/MapEntity.swift:84-92`, `Modules/TableRPG/Intent/TableEntity.swift:84-92`, `Modules/WeatherRPG/Intent/WeatherEntity.swift:85-93`, `Modules/GeneratorRPG/Intent/GeneratorEntity.swift:83-87`, `Modules/DiceRPG/Intent/DiceEntity.swift:98-104`. Counter-example: `Modules/RuleRPG/Intent/RuleEntity.swift:76-98` exports name, description and every section.
- **What:** On iOS 27 Siri forwards an on-screen entity through its `Transferable` representations ("summarize this adventure", "send this to Mail", Writing Tools, ChatGPT). For 7 of the 12 entity types the export is the item's one-line summary, not its body (adventure sections, character entries, table rows, map rooms). The PDF representation is listed first, so the preferred export is a rendered page with two lines of text.
- **Why:** The detail screens are already annotated (`SiriItemContext`), so Siri identifies the item correctly and then gets almost nothing to work on. For a campaign manager, "summarize this" or "what happens in this chapter" is the main Apple Intelligence use.
- **Action:** Build the plain-text export from the entries, as Rule does (one shared `EntitySummaryExport` variant that takes the entries, with hidden entries excluded), and put `.plainText` first for the text-centred modules. Keep the PDF for sharing, but render the same text. Bound it (for example 50 KB) so a huge rule book does not stall the hand-off.
- **Severity:** High

### 4.2 Siri's semantic index sees 2,000 characters per item; entries are invisible beyond that
- **Location:** `Modules/CoreRPG/Controllable/IntentEntityText.swift:13` (`excerptLimit = 2000`), `:19-35`; the entry-level Core Data items without any entity link in `Modules/AdventureRPG/Model/DataModel+Extensions.swift:38-48` (same pattern in the other modules' `DataModel+Extensions.swift`); routes that already address an entry: `Modules/CoreRPG/Route/KnownRoutes.swift:12` (`case pdfs(UUID?, UUID?)` and its siblings).
- **What:** Entries (adventure sections, rule sections, PDF bookmarks, map rooms, table rows) are not App Entities. An item contributes one bounded excerpt to the App Entity index. The Core Data Spotlight index holds every entry's full text, but its items have no `relatedAppEntityIdentifier` (iOS 27) / `associateAppEntity`, so Siri cannot connect a match there to an entity it can open or act on.
- **Why:** "What did the innkeeper in Moonlit Keep say about the dragon?" or "open the grappling rules" can only be answered when the words happen to be in the first 2,000 characters. This is a **re-raise** of `CODE_AUDIT_AppIntents` §5.4, which kept the two indexes unlinked because no duplicate rows were seen; the reason now is answer coverage, not duplicates.
- **Action:** Pick one: (a) on iOS 27, set `relatedAppEntityIdentifier` on the Core Data entry items to the parent item's entity (cheap, no new types); or (b) add entry-level `IndexedEntity` types for the modules where entries are the content (Rule section, Adventure section, PDF bookmark), each with an `OpenIntent` that takes the existing `(itemId, entryId)` route. (b) also enables "open the grappling section". Start with (a) and measure.
- **Severity:** Medium

### 4.3 The indexed excerpt is raw Markdown with link URLs and unresolved formulas
- **Location:** `Modules/CoreRPG/Controllable/IntentEntityText.swift:23-31` (appends `entry.name` and `entry.content` unchanged); link format as stored, e.g. `[HP](RPG://VALUES/0/<uuid>)` (see `Tests/` fixtures and `Modules/CoreRPG/Links/ReferenceScanner.swift:47`).
- **What:** Character values and table cells are mostly formulas built from links. The excerpt that feeds `textContent`, and the `content` property that the Shortcuts Use Model action serializes, contain the Markdown and the full `RPG://…/<uuid>` URLs (about 50 characters each) instead of the label or the calculated value.
- **Why:** Siri and the model read URLs and UUIDs, and those use up much of the 2,000-character budget (§4.2). "What is Grimbold's HP?" cannot be answered from `[KÖR](RPG://…)+[HÄ](RPG://…)+10`.
- **Action:** Before cutting the excerpt, replace each link with its label. For the Character module, prefer the calculated value (`LinkController.calculate`, the path the health fix of 2026-08-21 introduced). Strip Markdown emphasis. Add a unit test with a linked HP entry.
- **Severity:** Medium

### 4.4 75 of 82 actions have no `IntentDescription`
- **Location:** metadata-verified (`descriptionMetadata == null` for 75 actions). The 7 with a description: `RollDiceIntent`, `ShowDiceHistoryIntent` (`Modules/DiceRPG/Intent/DiceIntents.swift:14,75`), `RollSpecificDiceIntent` (`RollSpecificDiceIntent.swift:17`), `PlayAudioIntent`, `PauseAudioIntent` (`AudioPlaybackIntents.swift:13,43`), the widget's two. Missing on e.g. `CreateAdventureIntent.swift:8-10`, `StartAdventureGameIntent.swift:8-10`, `NavigateIntent.swift:7-10`, every `Add…`, `Delete…` and `Open…` intent.
- **What:** Apart from the title and parameter names, the intent description is the text the system has about an action. It is shown in Shortcuts, used for Spotlight/Siri action search (`searchKeywords`), and given to Apple Intelligence when it chooses which app action fits a request.
- **Why:** "Start Adventure Game" vs. "Open Adventure" vs. "Navigate to Section" look alike without a sentence that says what each does (start the game mode for the players, open the editor, switch tabs). With no keywords, synonyms such as "campaign", "session" or "encounter" can't find the actions.
- **Action:** Add `IntentDescription(_:categoryName:searchKeywords:)` to every non-schema intent, written for the reader: what it does, what it needs, what it returns. Use one `categoryName` per module so Shortcuts groups them. Add descriptions to the `@Parameter`s that are not obvious (`openWhenCreated`, `content`).
- **Severity:** Medium

### 4.5 No intent changes an existing item
- **Location:** the full intent list (Create ×12, Add/Append ×11, Open ×24, Search ×13, Delete ×12, Navigate, Roll ×3, Play/Pause, Start game); no `update`/`rename`/`set` intent in `Modules/*/Intent/`.
- **What:** Siri and Shortcuts can create an item, append an entry, open it and trash it, but cannot rename it, replace its description, add or remove a tag, move it to a folder, or change an entry's value.
- **Why:** At the table the most common voice edit is a value change ("Grimbold takes 5 damage", "set the goblin's HP to 3") and, outside the game, a rename or tag. Apple Intelligence's agentic flows ("tag every adventure that mentions dragons") need an update action to call. The schema pattern for updates (`$parameter.valueState` for "leave unchanged" vs. "clear") is documented in the skill.
- **Action:** Add one `Update<Item>Intent` per module (name, description, tags; optional parameters, `valueState` to tell unset from cleared) through `EditController`, with `requireReadyDatabase()` and reindexing. For Character, add a focused `ChangeCharacterValueIntent` (entry + delta or new value) that writes through the same delta path as the quick editor (memory: "player character sync gaps", fix 3). Decide per module whether these need `authenticationPolicy`.
- **Severity:** Medium

### 4.6 Dice: no dice expressions, and no returned values
- **Location:** `Modules/DiceRPG/Intent/DiceIntents.swift:12-44` (`RollDiceIntent`: one die from a fixed enum, `ProvidesDialog` only), `:73-87` (`ShowDiceHistoryIntent`: dialog only), `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:31` (`ProvidesDialog & ShowsSnippetView`, no value); parser already present at `Modules/DiceRPG/Model/RawDice.swift:30-31` (`init(text:)`). Metadata: `outputType == null` for all three.
- **What:** "Roll 3d6 plus 2", "roll two d20 with advantage" or "roll 4d6" can't be expressed: the free die types are D4…D100, one die each. None of the roll intents returns the result, so a shortcut or the Use Model action can't use the number.
- **Why:** Rolling dice by voice is the app's most natural Siri feature, and it is limited to the 7 fixed single dice and the saved sets.
- **Action:** Add `RollDiceExpressionIntent` with a `String` parameter parsed by `RawDice(text:)` (validate, re-prompt on garbage), plus one App Shortcut phrase if a slot is freed (`CODE_AUDIT_AppIntents2` §4.7: the budget is 10/10; "Roll D6" is the obvious candidate to replace). Return `ReturnsValue<Int>` from all roll intents. Optionally add an `Int` "count" parameter to `RollDiceIntent`.
- **Severity:** Medium

### 4.7 Random tables cannot be rolled from Siri or Shortcuts
- **Location:** `Modules/TableRPG/Controller/TableGenerationController.swift:132` (`autoRoll`), `:171` (`roll(…)`); `Modules/TableRPG/Intent/` has Create / Add Row / Search / Delete / Open only.
- **What:** The Table module is the random-table engine (encounters, loot, wild magic, with nested rolls), but there is no "roll on table" intent.
- **Why:** "Roll on the random encounter table in MasterRPG" is the second most natural game-master voice action after dice, and it returns text Siri can read out.
- **Action:** Add `RollTableIntent(target: TableEntity)`, returning the result row as `ReturnsValue<String>` with a dialog and a small snippet, and driving the same controller path as the UI (including the player broadcast during a game if that is what the UI does). Donate it from the UI roll as dice rolls are donated (`IntentDonations.donateThrottled`).
- **Severity:** Medium

### 4.8 Game mode has a Start intent and nothing else
- **Location:** `Modules/AdventureRPG/Intent/StartAdventureGameIntent.swift` (the only game intent); available actions without an intent: `Modules/GameRPG/Root/GameRoot.swift:505` (`stopGame()`), `:468` (`joinGame(…)`), `Modules/GameRPG/BattleRound/BattleRoundController.swift:171` (`nextAttacker()`), `:181` (`nextRound()`), `Modules/MapRPG/Controller/GameController+Battle.swift:144` (`endBattle`). `Modules/GameRPG/` has no `Intent/` folder.
- **What:** Once a game runs, nothing can be done hands-free: no "next turn", "next round", "end the battle", "end the game", and the player side has no "join the game with code 1234".
- **Why:** During a session the game master's hands are on miniatures and dice. The Action button, AirPods and Siri on Mac are exactly the surfaces for "next turn". Each of these calls an existing controller method.
- **Action:** Add a small `GameRPG/Intent/` with Next Attacker, Next Round, End Battle and Stop Game (foreground-free, `ProvidesDialog` that names whose turn it is), and Join Game for players (code as a `String` parameter, validated like the join screen). Route all of them through the existing broadcast helpers so the sharing rules of `CLAUDE.md` ("3D Game Table") still apply. Consider one Control Center control for "Next Turn".
- **Severity:** Medium

### 4.9 The Foundation Models generator has no intent
- **Location:** `Modules/GeneratorRPG/Intent/GeneratorManagementIntents.swift:10-150` (Create / Add Note / Search / Delete); generation engine `Modules/GeneratorRPG/BasicAI/Engine/ConversationEngine.swift:194-423`, `Modules/GeneratorRPG/Controller/GeneratorController.swift:163,266`.
- **What:** The app can generate content on device (conversation engine, PDF and table summaries), but no intent runs a generator ("generate a tavern NPC with MasterRPG") or returns its output.
- **Why:** This is the one place where the app itself offers an AI capability that Siri and Shortcuts could compose with other actions (generate → create character → add entry). `CODE_AUDIT_AppIntents` §4.9 already named it as the trigger for `LongRunningIntent`.
- **Action:** Add `RunGeneratorIntent(target: GeneratorEntity, prompt: String?)` returning `ReturnsValue<AttributedString>`. On iOS 27 make it a `LongRunningIntent` with progress (generation can exceed 30 s on older devices) plus `CancellableIntent`; on iOS 26 cap the output length. Fail with a clear dialog when Apple Intelligence is unavailable.
- **Severity:** Low

### 4.10 Two Apple domains now fit: `.reader` for PDFs, `.notes` for note intents
- **Location:** SDK-verified in `AppIntents.swiftinterface`: `AppSchema.reader` intents `openDocument`, `openPage`, `searchDocuments` and entities `document`, `page`, available **iOS 18.0** (so no sibling intent is needed on iOS 26); `AppSchema.notes` intents `createNote`, `appendText`, `updateNote` and entities `note`, `folder`, available iOS 27. App side: `Modules/PdfRPG/Intent/OpenPdfIntent.swift:10-23` (opens the PDF only), PDF bookmarks as entries with page labels (`Modules/PdfRPG/Pdf/PdfBookmarkPage.swift:18-33`); the five `Add…NoteIntent`s (Audio, Generator, Photo, Space, Weather).
- **What:** The decision record "no pre-trained domain fits an RPG manager" (`CODE_AUDIT_AppIntents` §4.9) predates these two domains. The PDF module is a document reader with bookmarks. The note intents are notes.
- **Why:** With `.reader`, "open page 112 of the Player's Handbook" or "find 'grapple' in my rulebook" work without fixed phrases. With `.notes.appendText`, "add to my session notes" can reach the app.
- **Action:** Spike `@AppEntity(schema: .reader.document)` on `PdfEntity` (or a sibling entity, since the schema prescribes its properties) and `.reader.openPage` mapped to the bookmark route. Evaluate `.notes` only after the deployment-target bump. Drop either if the macro requires siblings that don't fit.
- **Severity:** Low

### 4.11 Entities have no subtitle, so "which one?" is ambiguous
- **Location:** `displayRepresentation` of 11 entities has a title and an image only, e.g. `Modules/AdventureRPG/Intent/AdventureEntity.swift:21-26`, `Modules/CharacterRPG/Intent/CharacterEntity.swift:21-26`; the fast path `Modules/CoreRPG/Controllable/ItemEntityQuery.swift:105-116` likewise. Only `DiceEntity.swift:21-27` has a subtitle.
- **What:** Siri reuses the display representation for disambiguation, results and confirmation prompts. Two "Goblin" characters in different folders, or "Session 3" in two campaigns, show identically.
- **Why:** Siri asks "which one?" and the user can't tell. The Delete confirmation (with `requiresAuthentication`) shows the same bare title.
- **Action:** Add a subtitle: the parent folder name when the item is in a folder, else the first line of the description, cut short. Use the same rule in `displayRepresentations(for:)`.
- **Severity:** Low

### 4.12 Spoken replies contain emoji and have no voice-only form
- **Location:** `Modules/DiceRPG/Intent/DiceIntents.swift:41` (`"🎲 Rolled …"`), `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:46-55` (`"🎉 Critical Success! …"`, `"💥 Critical Failure! …"`, `"🎲 …"`); `grep IntentDialog(full` finds no use in the repo.
- **What:** Every dialog is a single string. On AirPods, HomePod or CarPlay Siri reads the `full` text, emoji included ("party popper Critical Success …"), and the snippet's breakdown is not spoken.
- **Why:** Voice-only use at the table is the main use case for the dice intents. `siri-intelligence.md`: the `full` string must stand on its own as spoken language.
- **Action:** Use `IntentDialog(full:supporting:)`: `full` without emoji and with the breakdown ("Critical success. Longsword: 17, from 12 plus 5"), `supporting` short for the screen next to the snippet. Apply the same to Start game and Play audio.
- **Severity:** Medium

### 4.13 Audio: UI playback is not donated, and there is no resume, stop or next
- **Location:** `Modules/AudioRPG/Intent/AudioPlaybackIntents.swift:11-55`; donation call sites (`grep donate`): open, start game and dice rolls only; no call from the audio player's play button. `Modules/AudioRPG/Audio/MediaPlayerManager.swift:84-128` already handles play, pause, next and previous as remote commands.
- **What:** Siri never learns that the user starts the "Tavern" playlist at the start of a session, because only Siri/Shortcuts runs of `PlayAudioIntent` are known to the system. There is no "resume the music" (Play requires a target) and no "next track".
- **Why:** Donations from the UI path are what make Siri Suggestions and Apple Intelligence offer "Play Tavern" at the right moment (`siri-intelligence.md`, "Interaction donations").
- **Action:** Donate `PlayAudioIntent` from the play button through `IntentDonations.donateThrottled`. Add `ResumeAudioIntent` and `NextTrackIntent` (or an optional target on Play that resumes when empty) using the same controller calls as the remote commands. Keep them out of the 10 App Shortcuts.
- **Severity:** Low

### 4.14 Add, Append and Create-from-voice return no entity to chain
- **Location:** the 11 `Add…`/`Append…` intents (e.g. `Modules/AdventureRPG/Intent/AppendAdventureSectionIntent.swift:29`, `Modules/MapRPG/Intent/MapManagementIntents.swift:78`) return `ProvidesDialog` only; Create returns `ReturnsValue<Entity>` (12 actions with `outputType` in the metadata).
- **What:** A shortcut or an Apple Intelligence plan can't continue with the updated item after an append (open it, export it, append again).
- **Why:** Small, but it is what makes intents composable ("add a section and open the adventure").
- **Action:** Return `ReturnsValue<Entity>` (the updated parent entity, which is already built for indexing) from the Add/Append intents.
- **Severity:** Low

### 4.15 Rich text from Shortcuts and the Use Model action is flattened
- **Location:** `Modules/CoreRPG/Controllable/IntentEntityHelpers.swift:18-20` (`intentPlainText` keeps only the characters); called by every Create and Add intent.
- **What:** The parameters are correctly `AttributedString`, but bold, italics, lists and headings are dropped before saving, while entries are stored and rendered as Markdown.
- **Why:** A model-written section ("**Hook:** …, - bullet …") arrives as one flat paragraph.
- **Action:** Convert the `AttributedString`'s inline presentation intents (emphasis, strong, code, links) and block intents (lists, headers) to Markdown in one CoreRPG helper with tests. There is no Foundation API for this, so it has to be written.
- **Severity:** Low

### 4.16 `TargetContentProvidingIntent` is iOS-only and has no scene handler
- **Location:** 42 conformances, all under `#if os(iOS)` (e.g. `Modules/AdventureRPG/Intent/OpenAdventureIntent.swift:29-31`); no `onAppIntentExecution` or `handlesExternalEvents(matching:)` for intents in `Modules/` or `Sources/` (only the two `handlesExternalEvents(preferring: [], allowing: [])` in `Sources/MasterRPG/Window/`). SDK-verified: the protocol is available on visionOS 26 too (unavailable on macOS).
- **What:** The conformance helps the system pick a scene only when a scene declares what it handles. None does, so in multi-window use (iPad, visionOS) the intent's `perform()` navigates whichever navigator the dependency holds.
- **Why:** On an iPad with two MasterRPG windows, or on visionOS with the game volume open, "Open Moonlit Keep" may push in the window the user is not looking at (compare memory "navigator current is last appeared"). Not reproduced.
- **Action:** Test with two iPad windows first. If it misroutes, mark the main scene with `handlesExternalEvents(matching:)` for the intents' target content and widen the `#if` to `os(iOS) || os(visionOS)`.
- **Severity:** Low

---

## 5. Bugs / logic errors

### 5.1 Intent replies and prompts are resolved in the app bundle, so de/th users hear English
- **Location:** every runtime `IntentDialog` literal in `Modules/*/Intent/`: 46 `.result(dialog: "…")` (e.g. `Modules/AdventureRPG/Intent/CreateAdventureIntent.swift:49`, `StartAdventureGameIntent.swift:32`, `Modules/AudioRPG/Intent/AudioPlaybackIntents.swift:36,53`), 6 `IntentDialog = "…"` / `dialog = "…"` (`DiceIntents.swift:41,84`, `RollSpecificDiceIntent.swift:48-54`), 51 `requestValueDialog: "…"` (e.g. `AppendAdventureSectionIntent.swift:15,18`), 31 `prompt: "…"` passed to `needsValueError` (e.g. `AppendAdventureSectionIntent.swift:34-35`). The translations live in the module catalogs (e.g. `Modules/AdventureRPG/Resources/Localizable.xcstrings`, key `Created "%@".` with `de`, `th`); the app catalog `Resources/Localizable.xcstrings` has none of these keys.
- **What:** SDK-verified: `IntentDialog(stringLiteral:)` / `(stringInterpolation:)` build a `LocalizedStringResource` whose bundle defaults to `.main` (`Foundation.swiftinterface`, `LocalizedStringResource.init(_:table:locale:bundle: = .main …)`). **Runtime-probed** in the AdventureRPG framework context: a literal reports `bundle: atURL(…/MasterRPG.app/)` and resolves in `de` to `Created "Moonlit Keep".`; the same key with `bundle: .atURL(Bundle.module.bundleURL)` resolves to `„Moonlit Keep" erstellt.`. Static titles are not affected (the metadata stores them as keys, resolved in the framework that ships the metadata). `CODE_AUDIT_AppIntents` §9.3 assumed the dialogs are "localized from the module bundle"; that holds only for the Delete dialogs, which call `AttributedString(localized:bundle: .module)`, and for `DatabaseNotReadyError`.
- **Why:** For German and Thai users Siri answers every Create, Add, Start, Play, Pause and Roll in English, and asks its follow-up questions ("Which adventure?") in English, although the translations exist. This is the most audible Siri defect in the app. Not heard in real Siri (the probe checks the string resource the dialog carries).
- **Action:** Add a CoreRPG helper that builds an `IntentDialog` from a `LocalizedStringResource` in a given bundle (each module passes `Bundle.module`, which already exists per module as `BundleModule.swift`), and replace the literals module by module, the same way views use `Text(…, bundle: .module)`. Then add a unit test per module that resolves one dialog key in `de` through the helper. Re-check §5.2 after the switch.
- **Severity:** High

### 5.2 Missing translations for the newest intent strings
- **Location:** `Modules/AudioRPG/Resources/Localizable.xcstrings`: `Playing "%@".`, `Paused the audio.`, `Which audio do you want to play?` have neither `de` nor `th`; `Modules/DiceRPG/Resources/Localizable.xcstrings`: `You haven't rolled any dice yet.` and `Last roll — %@: %lld` have no `th`. (Checked for all 97 dialog literals in `Modules/*/Intent/`; these 5 are the only gaps.)
- **What:** Even after §5.1, these replies stay English.
- **Why:** The play/pause intents are the ones used by voice at the table.
- **Action:** Add the translations; keep the check from §5.1's test as a guard for new keys.
- **Severity:** Low

### 5.3 "Roll a D20" from Siri bypasses the game and the in-app history
- **Location:** `Modules/DiceRPG/Intent/DiceIntents.swift:52-66` (`DiceIntentRoll.rollAndRecord`: rolls a bare `DieModel` and writes only the widget's last roll), used by `RollDiceIntent.perform()` (`:36-43`); compare `RollSpecificDiceIntent.swift:40` (`root.gameController.rollDice(itemId:rollSynced:)`).
- **What:** A Siri or Action-button D20 roll appears in the widget, but not in the app's roll history, not in a running game's log and not on the players' screens. `ShowDiceHistoryIntent` ("What did I roll") then reports that last roll and nothing else.
- **Why:** At the table a game master who rolls by voice expects the result where the other rolls are. This is by design for the widget's copy (extension process), but the app's intent runs in the app and could use the game controller.
- **Action:** Decide whether app-side free rolls should join the game. If yes, route the app's `RollDiceIntent` through `gameController` when a game is running, and keep `rollAndRecord` for the widget only. Rename `ShowDiceHistoryIntent`'s title to "Show Last Roll" or make it report the last few rolls.
- **Severity:** Low

---

## 6. Security

_No findings._ The locked-device decisions of `CODE_AUDIT_AppIntents2` §6.1 still hold. If §4.5 (update intents) and §4.8 (game control) are added, decide their `authenticationPolicy` together: value changes during play probably stay open, renames and stop-game probably should not.

---

## 7. Performance

### 7.1 Siri's on-screen fast path waits for the database like a full query
- **Location:** `Modules/CoreRPG/Controllable/ItemEntityQuery.swift:107` (`displayRepresentations(for:)` starts with `await DatabaseReadiness.wait()`), timeout in `Modules/CoreRPG/App/DatabaseReadiness.swift`.
- **What:** The fast path exists so Siri can resolve "the third one" at once. On a cold start it waits for the database (up to the readiness timeout) before it returns titles.
- **Why:** Siri gives up or asks again when resolution is slow (`onscreen-awareness.md`). In practice the rows on screen imply a loaded store, so the wait is usually zero; the risk is only the cold or locked case. Not measured.
- **Action:** Return immediately with what is in memory when the database is not ready yet, instead of waiting; keep the wait in `entities(for:)`.
- **Severity:** Low

---

## 8. SwiftUI / UI

### 8.1 The dice snippet is static: no "Roll again"
- **Location:** `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:57-60` (`ShowsSnippetView`), `:67-108` (`RollResultSnippetView`, no buttons).
- **What:** iOS 26 interactive snippets (`SnippetIntent` + `Button(intent:)`, `ShowsSnippetIntent`) let a result card re-run an action in place. The roll card can only be dismissed.
- **Why:** Rolling the same set again (damage after an attack) is the obvious follow-up and needs a new Siri request today.
- **Action:** Turn the card into a `SnippetIntent` with a "Roll Again" `Button(intent:)` that re-rolls the same set (non-discoverable helper intent). Keep `perform()` of the snippet intent pure, as the skill requires.
- **Severity:** Low

---

## 9. Dead code / duplication / refactor

### 9.1 `PdfEntity` and `RuleEntity` still store the root model, while the comment says the opposite
- **Location:** `Modules/PdfRPG/Intent/PdfEntity.swift:56` (`var root: PdfRootModel`) under the comment at `:58-61` ("The live model is deliberately not stored"); `Modules/RuleRPG/Intent/RuleEntity.swift:52`.
- **What:** Both entities keep the `@MainActor` root for their exports. That is harmless (the root is a singleton and main-actor isolated, hence `Sendable`), but the PDF comment describes the other entities, not this one.
- **Why:** A reader trusts the comment and moves code that depends on `root`.
- **Action:** Reword the comment ("the root is kept for the file export; the item model is re-resolved"), or resolve the root through `@Dependency` in the export as the queries do.
- **Severity:** Low

### 9.2 Stale comment and flag on the app's `RollDiceIntent`
- **Location:** `Modules/DiceRPG/Intent/DiceIntents.swift:16-18` (`// iOS 18: Support for interactive widgets`, `isDiscoverable = true`, `openAppWhenRun = false`).
- **What:** The widget has its own `RollDiceIntent` (`Sources/DiceRollerWidget/DiceRollerIntents.swift:10-31`); this one is not used by any widget. `isDiscoverable = true` is the default, and `openAppWhenRun = false` duplicates the default too.
- **Why:** Suggests a widget dependency that would make a later change look risky.
- **Action:** Remove the comment and the two default-valued properties (or set `supportedModes = .background` explicitly, which says what is meant).
- **Severity:** Low

---

## 10. Cross-cutting recommendations

1. **Make what Siri says correct before adding more (§5.1, §5.2, §4.12).** One dialog helper with the module bundle, then the voice-only `full` strings. Everything else in this report produces more dialogs, so do this first.
2. **Give Siri the content, not the label (§4.1, §4.2, §4.3).** One shared "item as text" builder in CoreRPG (entries in order, links replaced by labels or values, hidden entries skipped, bounded) feeds the export, the index excerpt and the Use Model `content` property. Today these are three different texts.
3. **Fill the verb gaps in the order players use them (§4.6, §4.7, §4.8, §4.5).** Dice expressions → random tables → next turn → value change. Each is a thin intent over an existing controller method. Keep the 10 App Shortcuts for the most-spoken ones and rely on descriptions (§4.4) and the semantic index for the rest.
4. **Describe every action (§4.4).** Writing a `IntentDescription` with `searchKeywords` per intent is the cheapest improvement to Apple Intelligence's tool choice and to Shortcuts search.
5. **Test the spoken layer.** Add one `AppIntentsTesting` or unit check per module that resolves a dialog in `de`, and a test that the excerpt of a linked character entry contains no `RPG://`.

### 10.1 Siri / Apple Intelligence capability matrix (state at HEAD)

| Capability | State | Where |
|---|---|---|
| Find content (semantic index) | Adopted 12/12; item-level only, 2,000 chars, raw Markdown | §4.2, §4.3 |
| Find content (Core Data full text) | Indexed, not linked to entities | §4.2 |
| Open (`.system.open` + legacy) | Adopted 12/12 | earlier audits |
| In-app search (`.system.searchInApp`) | Adopted, app-wide | earlier audits |
| On-screen identification | Detail activity + list rows + Now Playing | earlier audits |
| On-screen content transfer | Name + description only for 7 types | §4.1 |
| Spoken responses | English for de/th; emoji; no `full`/`supporting` | §5.1, §4.12 |
| Action descriptions | 7 of 82 | §4.4 |
| Create / Append / Delete | Adopted 12/12 | — |
| Update / rename / set value | **None** | §4.5 |
| Dice | Fixed die, saved set; no expression, no value | §4.6 |
| Random tables | **None** | §4.7 |
| Game control (turns, stop, join) | Start only | §4.8 |
| Generator (Foundation Models) | **None** | §4.9 |
| Apple domains | None; `.reader` (iOS 18) and `.notes` (27) now fit | §4.10 |
| Disambiguation (subtitle) | Dice only | §4.11 |
| Donations | Open, Start game, Dice roll; not Audio play | §4.13 |
| Interactive snippet | No | §8.1 |
| `LongRunningIntent` | Not needed until §4.9 | §4.9 |

---

## 11. What was NOT audited

- **Real Siri, Apple Intelligence, Spotlight and Shortcuts on a device.** §5.1 rests on an SDK check and a `RunCodeSnippet` probe of the string resource, not on hearing Siri; §4.1–§4.3 rest on the documented hand-off and indexing behaviour.
- **macOS, visionOS and tvOS builds** (only the iOS simulator scheme was built).
- **The `AppIntentsTesting` suites** were not re-run in this pass (49/49 passed on 2026-10-26; since the fix commit `d4163860c` no file under `Modules/*/Intent`, `Modules/CoreRPG/Controllable` or the intent sources in `Sources/MasterRPG` changed, per `git diff --stat`).
- **Wording and correctness of the translations**, only their presence (§5.2).
- **Widget timelines and visuals**, the share extension, Live Activities (none exist).
- **The internals of the Core Data Spotlight delegate** beyond the missing entity link.
- **Generator / Foundation Models behaviour** (only that no intent exposes it).
- **Swift concurrency and SwiftUI expert passes** were done inline: the intent layer has one snippet view and one modifier, and the build reported no diagnostics; no separate agents or `swiftui-expert-skill` run.
- **Prior audits** were used as context; their fixed findings were not re-verified except where this report cites them.

---

## 12. Verification

Open Xcode and command-click each reference; it should land on the cited line.

- **§5.1** — `Modules/AdventureRPG/Intent/CreateAdventureIntent.swift:49` (`.result(value: entity, dialog: "Created \"\(trimmedName)\".")`). SDK: `Foundation.swiftinterface`, `struct LocalizedStringResource`, initializer with `bundle: … = .main`; `AppIntents.swiftinterface:8571-8572` (`IntentDialog.init(stringLiteral:)`, `init(stringInterpolation:)`, no bundle). Catalog: `Modules/AdventureRPG/Resources/Localizable.xcstrings`, key `Created "%@".` (de, th); absent from `Resources/Localizable.xcstrings`. Probe (`RunCodeSnippet`, context `CreateAdventureIntent.swift`): literal → `bundle: atURL(…/MasterRPG.app/)`, de → `Created "Moonlit Keep".`; with `Bundle.module` → `„Moonlit Keep" erstellt.`. Counter-example: `Modules/AdventureRPG/Intent/DeleteAdventureIntent.swift:30-33` (`bundle: .module`).
- **§4.1** — `Modules/CoreRPG/Intent/EntitySummaryExport.swift:18-23` (only `name` and `description` rendered); `Modules/AdventureRPG/Intent/AdventureEntity.swift:84-94`; versus `Modules/RuleRPG/Intent/RuleEntity.swift:90-97` (entries appended).
- **§4.2** — `Modules/CoreRPG/Controllable/IntentEntityText.swift:13` and `:27` (`guard remaining > 0 else { return text }`); `Modules/AdventureRPG/Model/DataModel+Extensions.swift:40-47` (entry attribute set without an entity link).
- **§4.3** — `Modules/CoreRPG/Controllable/IntentEntityText.swift:24-30` (`entry.content` appended unchanged).
- **§4.4** — metadata: `…/Debug-iphonesimulator/*.framework/Metadata.appintents/extract.actionsdata`, 75 of 82 actions with `descriptionMetadata == null`; e.g. `actions.CreateAdventureIntent.descriptionMetadata`.
- **§4.6** — `Modules/DiceRPG/Intent/DiceIntents.swift:36` (`some IntentResult & ProvidesDialog`), `Modules/DiceRPG/Model/RawDice.swift:30-31` (`init(text:)`); metadata `outputType == null` for `RollDiceIntent`, `RollSpecificDiceIntent`, `ShowDiceHistoryIntent`.
- **§4.7** — `Modules/TableRPG/Controller/TableGenerationController.swift:171`; `ls Modules/TableRPG/Intent/` (no roll intent).
- **§4.8** — `Modules/GameRPG/BattleRound/BattleRoundController.swift:171,181`, `Modules/GameRPG/Root/GameRoot.swift:468,505`; `ls Modules/GameRPG` (no `Intent/`).
- **§4.12** — `Modules/DiceRPG/Intent/RollSpecificDiceIntent.swift:46-55`.

**Build:** `xcodebuild -scheme MasterRPG -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build` → `BUILD SUCCEEDED`, 0 warnings (all `Intent/` sources touched first).

If any finding does not reproduce when you visit the line, tell me the reference and I will re-investigate.
