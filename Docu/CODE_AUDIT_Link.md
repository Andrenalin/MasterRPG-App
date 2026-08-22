# Code Audit — `LinkControllable` and its usage across MasterRPG

**Scope:** `Modules/CoreRPG/Controllable/LinkControllable.swift`, all 12 conforming module `Controller/LinkController.swift` implementations (Adventure, Audio, Character, Dice, Generator, Map, Pdf, Photo, Rule, Space, Table, Weather), and the CoreRPG support/usage layer built on top of it: `SimpleLinkController`, `FakeLinkController`, `LinkHighlightTextModel`, `LinkReplaceController`, `LinkRegisterController`, `EditorLinkModel`, `QuickLinkEditor`/`QuickLinkTextRow`, the Inspector link views, and `URL+ItemId.swift`. This is a deep, single-subsystem audit, not a full-repository sweep — see §11.

**Method:** direct reading of every conformer plus three parallel investigation passes (concurrency/modernity, dead-code/duplication, bugs/security/performance), with every High-severity claim independently re-verified against the actual source before inclusion. One agent-reported finding (a claimed bug in `PdfRPG/Controller/LinkController.swift`) was traced, found to be a hallucination — that file has no `generateLink` override at all — and dropped; see §12.

---

## 1. Executive summary

1. **[High] Entry-level links are permanently broken for 5 of 12 modules** — `generateLink` looks up the wrong id and drops the entry path. §5.1 — `Modules/AudioRPG/Controller/LinkController.swift:72-75` (+4 more files).
2. **[High] Links embedded in Pdf/Photo/Audio/Space/Dice/Generator item text are never auto-repaired** when their target is renamed or deleted — these 6 modules silently inherit the no-op default instead of overriding `validateLinks`/`repairLinks`. §5.2.
3. **[High] Map, Character, and Table's link-repair chains are missing Pdf** (and Character's own unused `photoRoot`), contradicting what CLAUDE.md documents those modules as able to link to. §5.3.
4. **[High] "Collect Photos" and related traversal silently drops 6 of 11 module types** in Adventure's and Map's `collectLinks`, and Table doesn't implement it at all. §5.4.
5. **[High] Adventure's link-repair sweep never validates a deleted Dice reference** (`diceId`), unlike its sibling `photoId` handling in the same function and unlike Table/Character's equivalent code. §5.5.
6. **[High] A malformed or unexpected link command silently triggers a live network broadcast** in Map/Audio/Weather (no guard at all) and is only partially guarded in Pdf/Space — only Photo fully validates the command before acting. §6.1.
7. **[High] Dead handler with a commented-out body and zero callers** (`handleLink(url:for:in:editAction:)`) sits in the public protocol surface. §9.1.
8. Two `AttributedString`-based `toggleLink` overloads are unused, unreferenced API surface that silently no-ops if ever adopted. §9.2.
9. Nine of twelve modules' `toggleTextLink` implementations are 60-80% duplicated boilerplate — the exact copy-paste pattern that produced findings #1 and #6. §9.3.
10. Three provably-guarded-today but rule-violating force unwraps, one systemic `Task { @MainActor in }` redundancy pattern, and unnecessary `@unchecked Sendable` usage round out the concurrency/quality findings. §3, §5.8.

---

## 2. Quick wins (≤30 minutes each)

- **`FakeLinkController.fake` uses `var` where `let` suffices** — `Modules/CoreRPG/Fake/FakeLinkController.swift:27` (`var controller = ...; return controller`). Trivial cleanup.
- **Unused `WidgetKit` import** — `Modules/DiceRPG/Controller/LinkController.swift:7-9` (`#if !os(tvOS) import WidgetKit #endif`); nothing in the file references it.
- **Self-documented dead stub** — `Modules/CoreRPG/Links/LinkRegisterController.swift:276-279`, `effectedItems(targetId:targetEntryId:targetModule:)` always returns `[]`; the file's own comment (272-275) says the live implementation is elsewhere. Delete or wire it up.
- **`QuickLinkEditor.swift:44`** — `RoundedRectangle(cornerRadius: 12)` should be the static member `.rect(cornerRadius: 12)` per project convention (prefer static member lookup over struct instances).
- **Commented-out save call** — `Modules/CoreRPG/Editors/QuickLinkEditor.swift:83` (`//editController.save(with: ...)`). Either the Apply button is missing a persist step, or this is stale — resolve one way or the other rather than leaving it commented.

---

## 3. Concurrency

### 3.1 `Task { @MainActor in … }` is redundant at ~30 call sites, and that redundancy hides the one place it's actually required
- **Location:** every `toggleTextLink` conformer, e.g. `Modules/AudioRPG/Controller/LinkController.swift:24,38,50,56`; `Modules/PhotoRPG/Controller/LinkController.swift:25,30,36`; `Modules/PdfRPG/Controller/LinkController.swift:22,28,40`; `Modules/SpaceRPG/Controller/LinkController.swift:22,28,40`; `Modules/WeatherRPG/Controller/LinkController.swift:25,30,36`; `Modules/MapRPG/Controller/LinkController.swift:33,38,44`; `Modules/TableRPG/Controller/LinkController.swift:27,31,40`; `Modules/AdventureRPG/Controller/LinkController.swift:107,113`; `Modules/RuleRPG/Controller/LinkController.swift:97,106`; `Modules/CharacterRPG/Controller/LinkController.swift:33,41`.
- **What:** every one of these functions is already `@MainActor`-isolated (required by the protocol), so a plain `Task { … }` created inside it inherits that isolation automatically — the explicit `@MainActor in` annotation on the closure adds nothing. The codebase proves this itself: `Modules/MapRPG/Controller/LinkController.swift:100-102` uses a plain, unannotated `Task { await root.editController.resetImageSize(...) }` in the same kind of `@MainActor` context and it works identically.
- **Why:** the ~30 decorative occurrences visually erase the distinction from the one call site where the annotation is load-bearing — `Modules/CharacterRPG/Controller/LinkController.swift:307`, inside a `withObservationTracking(_:onChange:)` handler, whose closure Apple's Observation runtime can invoke off the main actor. A future "simplification" pass that treats all ~31 occurrences as equivalent could strip the one that matters and introduce a real data race.
- **Action:** drop the redundant `@MainActor in` annotation everywhere except `CharacterRPG/Controller/LinkController.swift:307`, and leave a short comment there explaining why it's required.
- **Severity:** Medium.

### 3.2 `@unchecked Sendable` used where checked `Sendable` would compile
- **Location:** `Modules/CoreRPG/Simple/SimpleLinkController.swift:13`, `Modules/CoreRPG/Fake/FakeLinkController.swift:5`.
- **What:** both are `final` classes whose only stored property is an immutable `let itemControllable: any ItemControllable`, and `ItemControllable` is itself `Sendable`. Neither needs the `@unchecked` escape hatch — the codebase demonstrates the correct alternative itself at `Modules/RuleRPG/Controller/LinkController.swift:7-10` (`@MainActor private final class RuleLinkRootReference: Sendable`, no `@unchecked`).
- **Why:** `@unchecked Sendable` opts out of compiler verification permanently. It buys nothing today but would silently swallow a real data race if either class ever grows a mutable or non-`Sendable` stored property later.
- **Action:** drop `@unchecked` and let the compiler verify checked `Sendable` conformance.
- **Severity:** Medium.

### 3.3 Inconsistent explicit `@MainActor` on protocol witnesses
- **Location:** `Modules/GeneratorRPG/Controller/LinkController.swift:13`; `Modules/CoreRPG/Simple/SimpleLinkController.swift:20,24` (vs. line 28 in the same file); `Modules/CoreRPG/Fake/FakeLinkController.swift:12,16` (vs. line 22).
- **What:** 9 of 12 module conformers explicitly annotate every witness `@MainActor`; these three leave some witnesses to rely on inference from the protocol requirement, inconsistently within the same file in the Simple/Fake cases.
- **Why:** compiles fine — Swift infers `@MainActor` for a witness satisfying an `@MainActor` requirement — but the inconsistency is confusing to read.
- **Action:** annotate uniformly, matching the other 9 conformers.
- **Severity:** Low.

---

## 4. API modernity

No deprecated-API, legacy-`Formatter`, `DispatchQueue`, `Task.sleep(nanoseconds:)`, `String(format:)`, or `ID`/`URL`-casing violations were found anywhere in the 28 files read for this audit. `Logger.linkController` usage throughout `LinkControllable.swift` (lines 217, 222, 227, 242) is modern `os.log` `Logger` with correct privacy annotations. `Task.sleep(for:)` is used correctly at `Modules/CharacterRPG/Controller/LinkController.swift:42`. No `@Published`/`ObservableObject`/`@StateObject`/`@EnvironmentObject` anywhere in scope; `LinkHighlightTextModel` and `EditorLinkModel` are both correctly `@MainActor @Observable`.

_No additional findings beyond §3's concurrency-adjacent items._

---

## 5. Bugs / logic errors

### 5.1 `generateLink` swaps `itemId` for `entryId` in 5 modules — entry-level links resolve to a dangling empty item
- **Location:** `Modules/AudioRPG/Controller/LinkController.swift:72-75`, `Modules/DiceRPG/Controller/LinkController.swift:54-57`, `Modules/PhotoRPG/Controller/LinkController.swift:58-61`, `Modules/SpaceRPG/Controller/LinkController.swift:55-58`, `Modules/WeatherRPG/Controller/LinkController.swift:68-71`.
- **What:** all five override the protocol default with the identical buggy body:
  ```
  guard let entryId else { return itemControllable.itemOrEmpty(for: itemId).url(linkNumber: linkNumber) }
  return itemControllable.itemOrEmpty(for: entryId).url(linkNumber: linkNumber)
  ```
  compared to the correct default at `Modules/CoreRPG/Controllable/LinkControllable.swift:111-114`, which looks the item up by `itemId` and calls the entry-aware `.url(linkNumber:entryId:)` overload. The override instead looks up an *item* whose id equals the child *entry's* id — which will essentially never match a real item — so `itemOrEmpty(for:)` (`Modules/CoreRPG/Controllable/ItemControllable.swift:477-480`) falls back to an empty placeholder model, and the resulting markdown link is empty-titled with the entry's UUID misused as the item-id path segment; the real item and the entry scoping are both lost.
- **Why:** confirmed reachable, not theoretical — every one of these same files' own `toggleTextLink` calls `generateLink(linkNumber:itemId:entryId:entryId)` internally with the same non-nil `entryId` that was threaded in from an existing link's URL (e.g. `Modules/PhotoRPG/Controller/LinkController.swift:19,52`, `Modules/AudioRPG/Controller/LinkController.swift:20,66`) — so toggling/expanding any already-existing entry-scoped link for these 5 modules hits this bug, and Dice/Pdf's own code explicitly branches on `item[entryId].content` a few lines away, proving entries are real addressable content there.
- **Action:** delete these 5 overrides entirely and let them inherit the correct protocol default (as Adventure, Character, Map, Photo... wait — as Adventure, Character, Map, Rule, Table already correctly do).
- **Severity:** High.

### 5.2 Six modules never override `validateLinks(on:)` / `repairLinks(_:in:)` — their embedded links are never auto-repaired
- **Location:** `Modules/PdfRPG`, `Modules/PhotoRPG`, `Modules/AudioRPG`, `Modules/SpaceRPG`, `Modules/DiceRPG`, `Modules/GeneratorRPG` — none of these `Controller/LinkController.swift` files define `validateLinks(on:)` or `repairLinks(_:in:)`, so both silently fall back to the protocol's no-op defaults (`Modules/CoreRPG/Controllable/LinkControllable.swift:210,264`).
- **What:** all of Pdf/Photo/Audio/Space/Dice have a real, user-editable, markdown-rendered CRDT `description: String` field (e.g. `PhotoModel.swift:62-66`, `AudioModel.swift:61-65`, `SpaceModel.swift:62-66`, `DiceModel.swift:98-102`) capable of embedding links to other items; Pdf additionally has real per-entry `content` (`PdfEntryModel.swift:28`). Generator's exposure is moot — `NetworkModules.generator` is never dispatched by any orchestrating module's `handleTextLink`/`repairLinks` switch, so Generator items are structurally outside the cross-module link graph regardless.
- **Why:** `LinkRegisterController.repairLinks(for:)` (`Modules/CoreRPG/Links/LinkRegisterController.swift:121-130`, documented as the hook that runs "on deletion or move") calls `linkController.validateLinks(on: link.source.itemId)` for the *source* module of every registered link. For these 5 real-exposure modules that call always lands on the no-op default and does nothing. Concretely: a Photo item's `description` embeds a link to a Map that later gets deleted — no automatic re-scan ever strips or repairs that now-dangling link; it sits there permanently (a tap still shows the "🚨 Link is broken" warning via `brokenTextLinkToggle`, but the automatic cleanup that Adventure/Map/Character/Table/Rule/Weather all get from their own `validateLinks`/`repairLinks` overrides never runs).
- **Action:** add `validateLinks(on:)`/`repairLinks(_:in:)` overrides to Pdf/Photo/Audio/Space/Dice following the pattern already used by Weather/Table (repair own description + entries, log, `resetLinkRegister`).
- **Severity:** High.

### 5.3 Map/Character/Table's `repairLinks` chains omit modules those items are documented to link to
- **Location:** `Modules/MapRPG/Controller/LinkController.swift:13-20` (struct fields) and `65-76` (`repairLinks` body); `Modules/CharacterRPG/Controller/LinkController.swift:11-20` (struct fields, note `photoRoot` at line 14) and `65-73` (`repairLinks` body); `Modules/TableRPG/Controller/LinkController.swift:9-14` (struct fields — only `diceRoot`) and `62-69` (`repairLinks` body).
- **What:** verified directly — `MapRPG`'s `LinkController` struct has no `pdfRoot` field at all, and its `repairLinks` chains only `audioRoot`/`diceRoot`/`photoRoot`/`tableRoot`/`characterRoot` + self. `CharacterRPG`'s struct *does* declare `photoRoot: PhotoRootModel` (used elsewhere in the same file at lines 90/99 for `photos`/`photoId` validation) but `repairLinks` never chains through it, and there is no `pdfRoot` field at all. `TableRPG`'s struct has only `diceRoot`; its `repairLinks` chains only that + self.
- **Why:** CLAUDE.md documents Map as able to link to "character, maps, dice, tables, audio, pdf and photo", Character as linking "tables, dice, photo and pdf", and Table as linking to "dice, pdf and tables." A description/entry-content link from any of these three modules to a Pdf item (and, for Character, to a Photo item) can never be auto-repaired when the target is renamed — the repair silently no-ops for that one module while working for the others. By contrast, `Modules/AdventureRPG/Controller/LinkController.swift:133-149` correctly chains all 10 other modules, and `Modules/RuleRPG/Controller/LinkController.swift:130-139` uses a strictly better pattern — `rootReference.rootManager?.rootModel(for: link.module)?.linkControllable.repairLink(...)` — that resolves *any* module dynamically instead of hardcoding a partial list, and would never drift out of sync as new modules are added.
- **Action:** wire `photoRoot` into Character's chain immediately (it's already a stored property); add `pdfRoot` to all three structs and their chains; consider adopting Rule's dynamic `rootModel(for:)` lookup pattern everywhere instead of hardcoded per-module lists, which would make this whole class of bug structurally impossible.
- **Severity:** High.

### 5.4 `collectLinks` silently drops most module types, and one module doesn't implement it at all
- **Location:** `Modules/AdventureRPG/Controller/LinkController.swift:195-224`, switch at 205-220 (`.photo`/`.value`/`.map`/`.weather`/`.adventure` handled, `default: break` at 218-219 drops `.audio`/`.dice`/`.pdf`/`.rule`/`.space`/`.table`); `Modules/MapRPG/Controller/LinkController.swift:128-145`, switch at 137-143 (only `.photo`/`.value` handled, everything else dropped); `Modules/TableRPG/Controller/LinkController.swift` has no `collectLinks` override at all, so it always returns `[]` via the protocol default (`LinkControllable.swift:311`).
- **What:** this traversal is the real, tested, production "Collect Photos" feature — `Modules/AdventureRPG/Controller/EditController.swift:337-343`'s `collectPhotos(itemId:entryId:)`, exercised by `Tests/AdventureRPGTests/EditControllerTests.swift:125` — which walks an item's entries looking for links to other items and recurses to find every reachable photo. Because Adventure's own switch only recurses through `.photo`/`.value`/`.map`/`.weather`/`.adventure` links, a photo reachable only via an Audio, Dice, Pdf, Rule, Space, or Table link in between is silently never found. The gap compounds through Map (which drops everything except `.photo`/`.value` despite its own `repairLinks` proving Map entries legitimately hold Audio/Dice/Table links too) and dead-ends completely at Table, which performs no traversal of its own entries regardless of what calls into it.
- **Why:** a real, callable, already-shipped feature quietly returns an incomplete result set with no error, warning, or log — a GM using "Collect Photos" on an item that links to a Table or Rule entry referencing photos will simply not see those photos, with no indication anything was skipped.
- **Action:** extend both switches to cover all `NetworkModules` cases relevant to what each module can link to (mirroring the `repairLinks` chain each module already has), and give Table a real `collectLinks` implementation instead of the empty default.
- **Severity:** High.

### 5.5 Adventure's link-repair sweep never validates a deleted `diceId`
- **Location:** `Modules/AdventureRPG/Controller/LinkController.swift:151-176` (full `validateLinks(on:)` body).
- **What:** the function validates and clears `replacedItem.photoId` (154-159) but never checks `replacedItem.diceId`, even though `AdventureModel.diceId: UUID?` (`Modules/AdventureRPG/Model/AdventureModel.swift:12,20`) is a real, live field consumed at game start by `Modules/AdventureRPG/Controller/GameController.swift:82-83` (`root.diceRoot.diceGameControllable.createGameDice(for: diceId, gameDiceId: nil)`). Compare `Modules/TableRPG/Controller/LinkController.swift:74-79` and `Modules/CharacterRPG/Controller/LinkController.swift:108-113`, both of which validate and clear their own `diceId` fields in the equivalent function.
- **Why:** delete a Dice item that's linked to an Adventure, and the dangling `diceId` is never detected or cleared by the "repair broken links" maintenance sweep. At the next game start, `createGameDice` resolves the stale id through `itemOrEmpty` to a blank/empty die — no crash, but the adventure's configured dice silently stops working with zero diagnostics pointing at why.
- **Action:** add the same `diceId` validate-and-clear block already present in Table/Character to Adventure's `validateLinks(on:)`.
- **Severity:** High.

### 5.6 RuleRPG: a nil cross-module reference silently misroutes instead of failing loudly
- **Location:** `Modules/RuleRPG/Controller/LinkController.swift:34-51` (`handleTextLink`), `130-139` (`repairLinks`), `setUp(rootManager:)` at `Modules/RuleRPG/Controller/LinkController.swift:26-29`, called once from `Modules/RuleRPG/Root/RuleRootModel.swift:150-151`.
- **What:** when a link's module isn't `.rule`, delegation is only attempted via `rootReference.rootManager?.rootModel(for: module)?.linkControllable` — if `rootReference.rootManager` happens to be nil, this optional chain fails silently and execution falls through to treat the URL as a `.rule` link anyway, looking the id up in Rule's own `itemController` (almost certainly finding nothing) and rendering blank/wrong content with no error or log. `Modules/AdventureRPG/Controller/LinkController.swift:28-33`'s equivalent uses `preconditionFailure` on a nil root manager instead — fail-fast rather than silent-wrong-behavior.
- **Why:** no production call path was found where link-handling runs before `setUp(rootManager:)`, so this isn't proven independently reachable today — but nothing in the code protects that ordering invariant the way Adventure's `preconditionFailure` does, making it a latent trap for any future caller (a test harness, an extension target, an early network-message handler) that touches this `LinkController` before setup completes.
- **Action:** either add the same `preconditionFailure` guard Adventure uses, or make `setUp` a required initializer parameter so the invariant is enforced by the type system.
- **Severity:** Medium.

### 5.7 DiceRPG's `toggleTextLink` is missing the toggler auto-trigger block every other module has
- **Location:** `Modules/DiceRPG/Controller/LinkController.swift:42-51` (else/no-command branch).
- **What:** every other non-stub module's else-branch opens with `if let toggler, entryId == nil, editAction == nil { Task { await toggler(...) } }` before building the result string (e.g. `Modules/PdfRPG/Controller/LinkController.swift:39-43`, `Modules/PhotoRPG/Controller/LinkController.swift:41-45`, `Modules/WeatherRPG/Controller/LinkController.swift:39-43`, and 6 more). Dice's equivalent branch goes straight to building `sendAction`/`showAction`/etc. with no such block.
- **Why:** since this line is otherwise copy-pasted verbatim across 9 files, its absence in Dice looks like an accidental drop during a copy-paste edit rather than a deliberate Dice-specific decision — nothing in the file explains why Dice item-level links wouldn't auto-toggle/expand the way every sibling module's do.
- **Action:** confirm with the author whether this is intentional; if not, add the missing block to match the other 9 modules.
- **Severity:** Medium.

### 5.8 Force unwraps that are safe today but violate the project's explicit rule and are one refactor away from crashing
- **Location:** `Modules/CharacterRPG/Controller/LinkController.swift:305` (`itemController.itemOrEmpty(for: detail.itemId)[detail.entryId!].value`, guarded only by a filter two call-frames away at lines 300-302); `Modules/CoreRPG/Model/EditorLinkModel.swift:159` (`item.urlName(entryId: entryId!)` immediately after a redundant `entryId == nil ? ... :` ternary that could simply be `if let entryId { ... } else { ... }`); `Modules/CoreRPG/Simple/SimpleSheetEditingSession.swift:111` (`rootManager: root.rootManager!`, safe only because it was assigned two lines earlier at line 93).
- **What:** none of these three crash as currently written, but each is a straightforward, CLAUDE.md-rule-violating force unwrap (project rule: "Avoid force unwraps... unless it is unrecoverable") whose safety depends on an invariant enforced several lines or call-frames away rather than at the unwrap site.
- **Action:** rewrite each as `if let` / `guard let`, or capture the known-non-nil value in a local `let` at the point where the invariant is established.
- **Severity:** Medium.

### 5.9 `EditorLinkModel` has two non-exhaustive switches over `NetworkModules` with a silent wrong-module fallback
- **Location:** `Modules/CoreRPG/Model/EditorLinkModel.swift:108-121` (`moduleListController`) and `125-138` (`selectionModel(for:)`).
- **What:** both switches cover 11 of `NetworkModules`'s 17 cases (adventure/audio/dice/map/pdf/photo/rule/space/table/value/weather) and fall back to `default: return rootManager.adventureRoot...` / `default: adventureSelectionModel` for the other 6 (`.none`, `.game`, `.setting`, `.editor`, `.search`, `.generator`). Verified this is not currently reachable: every production caller's `firstRow`/`secondRow` array literal (checked all 12 `EditorLinkModel(...)` call sites) only ever contains the 11 handled cases; the one place `.none` appears in a `firstRow` is a `#Preview` fixture (`Modules/CoreRPG/LGViews/EditorLinkView.swift:135`), not production code.
- **Why:** because the switch isn't exhaustive, the compiler gives no warning if a future change (e.g. wiring `.generator` into some module's link picker, per CLAUDE.md's "Planned in Character" note) silently starts showing/linking Adventure's data under a mislabeled tab, with no error anywhere.
- **Action:** make both switches exhaustive (even if the added cases just `return nil` / assert), so the compiler catches this the next time a module is added.
- **Severity:** Low (latent risk only, not currently reachable).

### 5.10 Minor misparse in `URL+ItemId.swift` on already-malformed input
- **Location:** `Modules/CoreRPG/App/URL+ItemId.swift`, `commandKey` (48-55) vs. `childId` (39-46).
- **What:** all of `moduleIdentifier`, `linkNumber`, `itemId`, `childId`, `commandKey` use safe `guard`/`Int(...)`/`UUID(uuidString:)` fallbacks — no force unwraps, no crash risk found even under adversarial/malformed network or import input. One edge case: if a link has 5 path components where the entry-id segment isn't a valid UUID but a command segment follows it, `childId` correctly returns `nil`, but `commandKey` then falls into the `childId == nil` branch and returns the invalid entry-id string instead of the real trailing command segment.
- **Why:** produces a wrong-but-harmless string (fails every `command == LinkType.….rawValue` check downstream) — only affects already-malformed input, no further consequence found.
- **Action:** low priority; align `commandKey`'s branch condition with `childId`'s actual parse result rather than re-deriving it.
- **Severity:** Low.

---

## 6. Security

### 6.1 Unrecognized or malformed link commands fail open into a live network broadcast, with inconsistent guarding across modules
- **Location:** `Modules/MapRPG/Controller/LinkController.swift:26-42` and `Modules/AudioRPG/Controller/LinkController.swift:49-53` and `Modules/WeatherRPG/Controller/LinkController.swift:27-31` (zero guards — any command not `.remove`/`.show` unconditionally reaches the share/broadcast `Task`); `Modules/PdfRPG/Controller/LinkController.swift:27` and `Modules/SpaceRPG/Controller/LinkController.swift:27` (`guard let shareResult else { return text }` present, but no check that `command` is actually `.share`); `Modules/PhotoRPG/Controller/LinkController.swift:28` (the only one of the six with both guards: `guard command == LinkType.share.rawValue else { return text }` *and* `guard let shareResult else { return text }`).
- **What:** `url.commandKey` (`Modules/CoreRPG/App/URL+ItemId.swift:48-55`) returns whatever string sits in that URL path segment, unvalidated against `LinkType`'s known cases, for any link that reaches a module's `toggleTextLink` (which is itself already gated to that module by `handleTextLink`'s `url.moduleIdentifier == itemControllable.config.module` check at `LinkControllable.swift:150` — but not gated on the command). In Map (concretely traced, `LinkController.swift:39-41`), Audio, and Weather, *any* command value other than `.remove`/`.show` — including one that doesn't match any `LinkType` case at all — unconditionally executes `shareResult?.networkActions?.shareId(...)` (in Map's case, `root.gameController.shareMap(id: itemId)`), broadcasting to connected players whenever `shareResult` happens to be non-nil (i.e., during an active game session).
- **Why:** under normal use this only ever fires for genuine `.share` links, since each module's own `specialLink(linkType:...)` never emits a command it doesn't itself check for. The exposure is to *unexpected* input: link text is freely user-editable, and links also arrive from SharePlay/Bonjour peers and imported files — any of which could carry a corrupted, foreign, or mismatched command string. Given this app's GM/player secrecy model (maps have hidden layers/rooms per CLAUDE.md), an unintended `shareMap` broadcast during a live session is a real disclosure-adjacent risk, not merely a logic bug — though whether `shareMap` itself already filters hidden content before sending was not traced as part of this audit (see §11).
- **Action:** add the `guard command == LinkType.share.rawValue else { return text }` check Photo already has to Map, Audio, Weather, Pdf, and Space — or better, replace the ad hoc string comparisons across all 6 modules with a single `switch LinkType(rawValue: command)` that defaults to a no-op, closing this class of gap everywhere at once.
- **Severity:** High.

_URL parsing itself (`URL+ItemId.swift`) was checked for injection/crash risk and found safe — see §5.10 for the one minor, non-security parsing quirk found there._

---

## 7. Performance

### 7.1 A suspected hot path turned out not to be live — but the dead feature behind it is a maintenance liability
- **Location:** `link(for module:)` / `linkEntries(for:)`, reimplemented with an `O(n log n)` full-item sort in `Modules/RuleRPG/Controller/LinkController.swift:178-184`, `Modules/AdventureRPG/Controller/LinkController.swift:181-184`, `Modules/MapRPG/Controller/LinkController.swift:113-116`, `Modules/CharacterRPG/Controller/LinkController.swift:165-178`, `Modules/DiceRPG/Controller/LinkController.swift:64-78`, and others.
- **What:** these were suspected as a per-keystroke hot path for live link autocomplete. Traced instead: the only consumer of their `[LinkEntryModel]` output, `scanReplace` (`Modules/CoreRPG/ItemList/EntryDataEditable.swift:427-444`), has zero callers anywhere in the app — `link(for module:)`/`linkEntries(for:)` are themselves called only from unit tests (e.g. `Tests/CharacterRPGTests/LinkControllerTests.swift:277-279`, `Tests/MapRPGTests/LinkControllerTests.swift:53-54`). No View or Controller in the shipping app calls either method.
- **Why:** not a live performance issue today. It is a fully-built, unit-tested, but entirely unwired feature ("auto-detect and replace name occurrences with links") independently reimplemented with near-identical sort logic in 6+ modules for no current runtime benefit — see §9.7 for the duplication angle. If this is ever wired up to a live editor UI without revisiting the per-call full-item sort, it would become a real hot-path risk then.
- **Action:** either wire `scanReplace` up to the `QuickLinkEditor` flow it appears designed for, or remove the dead call chain; if wired up, cache/memoize rather than sorting all items per call.
- **Severity:** Low (dead-code/maintenance risk, not a live perf bug).

---

## 8. SwiftUI / UI

### 8.1 `QuickLinkTextRow` defers a `@State` write into an unguarded `Task {}`, risking duplicate model construction
- **Location:** `Modules/CoreRPG/Editors/QuickLinkTextRow.swift:23-43`, specifically the `else` branch at 36-41.
- **What:** `updateEntryValues()` is called synchronously from the `linkTextModel` computed property, which is itself read during `body`. On first construction it builds a new `LinkHighlightTextModel` and defers the `_linkTextModel = linkModel` write into an unstructured `Task {}` rather than assigning it immediately (apparently to dodge SwiftUI's "modifying state during view update" diagnostic). Until that deferred task actually runs, `_linkTextModel` stays `nil`, so if `body` (or anything else reading `linkTextModel`) is evaluated again first, `updateEntryValues()` re-enters the same branch and allocates another `LinkHighlightTextModel` — each doing real markdown/link-parsing work in its initializer — with only the last deferred write actually winning.
- **Why:** not a crash, but a real correctness/perf smell with no reentrancy guard, isolated to this one file.
- **Action:** initialize `_linkTextModel` directly from the view's `init` (all its dependencies — `linkControllable`, `model`, `original` — are already available there, the same way `QuickLinkEditor`'s own `init` seeds `_beforeEntries` at `QuickLinkEditor.swift:16`), removing the need for the lazy-computed-property-plus-deferred-Task pattern entirely.
- **Severity:** Medium.

### 8.2 Commented-out save call may indicate dropped persistence
- **Location:** `Modules/CoreRPG/Editors/QuickLinkEditor.swift:83`.
- **What:** the "Apply" toolbar button only does `model.wrappedValue = afterEntries` and dismisses; a `//editController.save(with: ...)` call sits commented out immediately above it.
- **Why:** either the caller is expected to persist elsewhere (in which case the dead comment should just be deleted) or this is a real regression where Quick Link changes stop being explicitly saved.
- **Action:** resolve and remove the comment either way. Grouped with §2's quick wins.
- **Severity:** Low.

### 8.3 Static-member-lookup style deviation
- **Location:** `Modules/CoreRPG/Editors/QuickLinkEditor.swift:44` — `RoundedRectangle(cornerRadius: 12)` instead of `.rect(cornerRadius: 12)`.
- **Severity:** Low. (Also listed in §2.)

---

## 9. Dead code / duplication / refactor

### 9.1 `handleLink(url:for:in:editAction:)` — dead handler with a commented-out body
- **Location:** `Modules/CoreRPG/Controllable/LinkControllable.swift:160-166`.
- **What:** the default implementation's body is 3 commented-out lines calling a non-existent recursive overload, followed by a hardcoded `return (.discarded, text)`. Confirmed zero real call sites anywhere in the repository (only the declaration itself).
- **Why:** unreachable public API left with a stale, misleading commented-out body — reads as a real handler but never fires, and is discoverable via autocomplete by a future caller who has no way to know it's inert.
- **Action:** delete the method entirely, or finish implementing it if the commented-out call represents unfinished work.
- **Severity:** High (dead but discoverable public API, actively misleading).

### 9.2 Two `AttributedString`-based `toggleLink` overloads are unused
- **Location:** `Modules/CoreRPG/Controllable/LinkControllable.swift:193-198` (`toggleLink(linkNumber:itemId:entryId:in:textGetter:)`) and `200-204` (`toggleLink(linkNumber:itemId:entryId:command:in:shareResult:toggler:editAction:)`, which unconditionally `return text` — a no-op).
- **What:** confirmed no module overrides the `AttributedString`-taking `command:`-bearing overload, and confirmed no real caller of either overload exists outside `FakeLinkController` and tests. Production text-link toggling exclusively uses the `String`-based `handleTextLink`/`toggleTextLink` path (see `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:82`).
- **Action:** delete both overloads unless there's a concrete near-term plan to adopt `AttributedString`-based rendering.
- **Severity:** Medium.

### 9.3 `toggleTextLink` is 60-80% duplicated boilerplate across 9-10 module implementations
- **Location:** the `.remove`/`.show` command-handling block and the else-branch `sendAction`/`showAction`/`editLine`/`removeAction` assembly block, near-identically repeated across `Modules/AudioRPG/Controller/LinkController.swift:19-28,55-68`, `Modules/CharacterRPG/Controller/LinkController.swift:28-37,39-62`, `Modules/DiceRPG/Controller/LinkController.swift:21-24,30-35,42-51`, `Modules/MapRPG/Controller/LinkController.swift:28-37,43-62`, `Modules/PdfRPG/Controller/LinkController.swift:17-26,38-57`, `Modules/PhotoRPG/Controller/LinkController.swift:18-27,40-54`, `Modules/SpaceRPG/Controller/LinkController.swift:20-29,42-53`, `Modules/TableRPG/Controller/LinkController.swift:21-26,38-59`, `Modules/WeatherRPG/Controller/LinkController.swift:20-29,35-48`, `Modules/AdventureRPG/Controller/LinkController.swift:102-110,112-130`.
- **What:** roughly 60-80% of each file's `toggleTextLink` body (measured per-file: Pdf/Photo/Space/Weather ~75-78%, Map/Adventure ~70%, Table/Character/Dice ~50-63%, Audio ~48% due to its larger unique `.play` logic) is copy-pasted structure, with only the description-resolution and any module-specific command (`.play`, `.roll`) differing.
- **Why:** this is exactly the pattern that produced §5.1 (the `generateLink` copy-paste bug), §5.7 (Dice's missing toggler block), and §6.1 (the inconsistent share-command guard) — three independent defects all traceable to the same duplicated logic being hand-edited independently in each file rather than shared.
- **Action:** extract the two shared blocks into a `LinkControllable` protocol-extension helper parameterized by closures for the module-specific description text and any extra commands, following the shape the protocol extension already uses for `brokenTextLinkToggle`/`toggleLink(linkNumber:...)`. This single refactor would structurally prevent all three of the defects above from recurring.
- **Severity:** Medium.

### 9.4 Unused `effectedItems` stub
- **Location:** `Modules/CoreRPG/Links/LinkRegisterController.swift:276-279`. Self-documented as unimplemented by the file's own comment (272-275); zero callers confirmed. See §2.
- **Severity:** Low.

### 9.5 Unused `WidgetKit` import
- **Location:** `Modules/DiceRPG/Controller/LinkController.swift:7-9`. See §2.
- **Severity:** Low.

### 9.6 `var` where `let` suffices
- **Location:** `Modules/CoreRPG/Fake/FakeLinkController.swift:27`. See §2.
- **Severity:** Low.

### 9.7 `link(for module:)`/`linkEntries(for:)` — a fully-built, tested, but entirely unwired feature duplicated 6+ times
- **Location:** see §7.1 for the full file list and the reachability trace.
- **What:** the "auto-detect and replace name occurrences with links" feature (`scanReplace`, `Modules/CoreRPG/ItemList/EntryDataEditable.swift:427-444`) that these methods feed has no production caller anywhere.
- **Why:** 6+ modules each maintain their own near-identical, non-trivial sort-and-map implementation of a feature nothing in the shipping app currently uses — pure maintenance cost with no present benefit, and a duplication risk (independent implementations can drift, as `RuleRPG`'s does with its unique `guard module == .rule else { return [] }` early exit not mirrored elsewhere).
- **Action:** either delete the unused implementations and the `scanReplace` consumer together, or finish wiring the feature to `QuickLinkEditor` (which already exists and looks like the intended consumer) and then consolidate the 6+ duplicated sort implementations into one shared helper.
- **Severity:** Medium.

---

## 10. Cross-cutting recommendations

- **Centralize `toggleTextLink`'s shared command-dispatch logic** (§9.3) — this single refactor would have prevented §5.1, §5.7, and meaningfully reduced §6.1's surface, all three of which trace back to the same block being copy-pasted and then independently hand-edited across 9-10 files.
- **Replace hardcoded per-module root lists with the dynamic `rootManager.rootModel(for:)` lookup** that `RuleRPG/Controller/LinkController.swift:130-139` already uses correctly — this pattern is immune to the "forgot to add the new module" class of bug behind §5.3 and §5.4, and should be the template for `repairLinks`/`collectLinks` everywhere, not just Rule.
- **Delete rather than stub unreachable API surface** (§9.1, §9.2) — a dead method sitting in a public protocol extension is worse than no method at all, since it's discoverable via autocomplete with no signal that it doesn't work.
- **Prefer `if let`/`guard let` over a trailing forced unwrap**, even when a nearby condition currently makes it provably safe (§5.8) — the project's own CLAUDE.md rule exists precisely because "provably safe today" and "still safe after the next refactor" are different guarantees.
- **Make module-coverage switches over `NetworkModules` exhaustive** rather than leaning on `default:` (§5.9) — the type system can catch "forgot to handle the new module" for free, but only if nothing swallows it with a wildcard case.

---

## 11. What was NOT audited

- **Full-repository scope.** This audit was explicitly scoped by the user to `LinkControllable.swift` and its conformers/usages. Sibling protocols (`ItemControllable`, `EditControllable`, `ExportControllable`, `ImportControllable`, etc.) were read only where they intersect with linking, not audited in their own right.
- **No compiler build/warnings pass.** This audit relied on direct source reading and three independent agent investigations rather than `xcodebuild`/Xcode-MCP-captured compiler diagnostics. A real build's warning output could surface additional concurrency or deprecation issues not visible from static reading alone.
- **CoreData/CloudKit sync implications** of the link-repair gaps in §5.2-§5.4 were not traced end-to-end into `SyncDataController`.
- **Test execution.** The large `Tests/*RPGTests/LinkControllerTests.swift` suite was consulted only for call-site discovery (confirming reachability of findings), not actually run; whether any existing test exercises the specific buggy entry-scoped-link paths in §5.1 was not determined.
- **`shareMap`'s internal content-filtering logic** (referenced in §6.1) — whether it already redacts hidden map layers before broadcasting was not traced; the finding is scoped to the missing command guard, not a confirmed secrets leak.
- **visionOS/tvOS-specific link-rendering surfaces**, if any exist beyond the shared CoreRPG views covered here, were not separately reviewed.
- **Exhaustive edge-case verification of `LinkHighlightTextModel.components(for:...)`** (`Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift:151-258`) — this markdown/link text-parsing state machine was read and no bug was found, but deeply nested or malformed input (unmatched bold markers, nested expand markers) was not exhaustively traced against it.
- **Algorithmic/UI correctness of Table/Character/Map's non-link-specific game logic** — only the `LinkControllable` conformance surface of these files was audited, not their other responsibilities.

---

## 12. Verification

- **§5.1** (`generateLink` swap) — opened all 5 files directly: `Modules/AudioRPG/Controller/LinkController.swift:72-75`, `Modules/DiceRPG/Controller/LinkController.swift:54-57`, `Modules/PhotoRPG/Controller/LinkController.swift:58-61`, `Modules/SpaceRPG/Controller/LinkController.swift:55-58`, `Modules/WeatherRPG/Controller/LinkController.swift:68-71`; compared byte-for-byte against the correct default at `Modules/CoreRPG/Controllable/LinkControllable.swift:111-114`. **Note:** one investigating agent additionally claimed `Modules/PdfRPG/Controller/LinkController.swift:57-61` had this same bug — opened that file directly (it is only 58-59 lines total) and confirmed it has **no** `generateLink` override at all; that claim was a hallucination and is excluded from this report.
- **§5.2** (missing `validateLinks`/`repairLinks`) — grepped `func validateLinks(on` and `func repairLinks(` across all 12 module files to enumerate overriders; cross-checked each non-overriding module's model file for a real `description`/`content` field (`PhotoModel.swift:62-66`, `AudioModel.swift:61-65`, `SpaceModel.swift:62-66`, `DiceModel.swift:98-102`, `PdfEntryModel.swift:28`).
- **§5.3** (incomplete repair chains) — opened `Modules/CharacterRPG/Controller/LinkController.swift:11-24` directly and confirmed `photoRoot` is declared but absent from the `repairLinks` body at lines 65-73; opened `Modules/MapRPG/Controller/LinkController.swift:1-23` and confirmed no `pdfRoot` field; opened `Modules/TableRPG/Controller/LinkController.swift:1-15` and confirmed only `diceRoot` exists.
- **§5.4** (`collectLinks` gaps) — opened `Modules/AdventureRPG/Controller/LinkController.swift:195-224` and `Modules/MapRPG/Controller/LinkController.swift:128-145` directly, confirmed the `default: break` arms; grepped `collectLinks` in `Modules/TableRPG/Controller/LinkController.swift` and confirmed zero matches.
- **§5.5** (`diceId` not validated) — opened `Modules/AdventureRPG/Controller/LinkController.swift:151-176` in full; confirmed `AdventureModel.diceId` exists (`Modules/AdventureRPG/Model/AdventureModel.swift:12,20`) and is consumed at `Modules/AdventureRPG/Controller/GameController.swift:82-83`; confirmed Table/Character both validate their own `diceId` (`Modules/TableRPG/Controller/LinkController.swift:74-79`, `Modules/CharacterRPG/Controller/LinkController.swift:108-113`).
- **§6.1** (command fail-open) — opened `Modules/MapRPG/Controller/LinkController.swift:26-42`, `Modules/AudioRPG/Controller/LinkController.swift:49-53`, `Modules/WeatherRPG/Controller/LinkController.swift:27-31`, `Modules/PdfRPG/Controller/LinkController.swift:27`, `Modules/SpaceRPG/Controller/LinkController.swift:27`, and `Modules/PhotoRPG/Controller/LinkController.swift:28` directly and compared their guard clauses line by line.
- **§9.1** (dead `handleLink`) — opened `Modules/CoreRPG/Controllable/LinkControllable.swift:160-166` directly; grepped `\.handleLink(url:` across the full repository (zero matches beyond the declaration itself).

---

**Total findings: 25**, spanning 7 High, 9 Medium, 9 Low. No Critical findings — nothing found in this scope reaches the crash/data-loss/memory-corruption bar the Critical severity is reserved for.
