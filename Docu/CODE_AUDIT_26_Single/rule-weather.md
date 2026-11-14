Scope: Modules/RuleRPG (43 files, ~3.3k LOC) and Modules/WeatherRPG (69 files, ~6.4k LOC), about 9.8k LOC. I read every file in both modules except the pure template files (the `Route/*`, `Root/*RootView`, `Menu/*` boilerplate and the PreviewData/MockData fixtures, which I skimmed), and I read the CoreRPG code each module leans on where a finding depended on it (`ItemControllable.replace/applyMergedUpdate`, `LinkRegisterController`, `EditIdentifierModel`, `ExportAudience`, `StableVersionDigest`, `FoundryTextDecoder`). Both modules are clean against the CLAUDE.md rules (no GCD, no `ObservableObject`, no legacy Formatters, no `onTapGesture`, no `GeometryReader`, no stray `print`, no TODO/FIXME; the only `AnyView` use is the `ViewControllable` protocol return type). Most earlier Weather findings (CODE_AUDIT_Weather, 22, 23, 24) are fixed and are not repeated. The remaining problems are logic errors the compiler cannot see: three in the Weather editors and link register that lose or mis-file user data, and a handful in the Rule editor/import path. Nothing reaches Critical. Items marked "reasoned" were traced in code but not run.

### Weather-to-Photo link is registered under the Adventure module and is dropped by every link validation
- Category: Bug
- Location: Modules/WeatherRPG/Model/WeatherModel.swift:208-219 (`changedLinkRegisterModels`, source `ItemRowModel(itemId: id, typeId: .adventure)`); no `linkRegisterModels` override, so the protocol default `[]` applies (Modules/CoreRPG/Links/LinkRegisterListModel.swift:117-118); consumers Modules/WeatherRPG/Controller/LinkController.swift:48 (`resetLinkRegister`), Modules/CoreRPG/Links/LinkRegisterController.swift:110, :133, Modules/CoreRPG/Controllable/LinkControllable.swift:322-327
- What: The source of the registered link names `.adventure` instead of `.weather` (copy-paste from AdventureModel), and `linkRegisterModels` (the full list used on first import, by `resetLinkRegister` and by `registerImportedLinks`) is not implemented, unlike `TableModel+Links.swift:7-9`.
- Why: `LinkRegisterController.used(for:)` resolves the source item in the Adventure module with a Weather id, gets nil and drops the row, so deleting or trashing a Photo shows no "used by Weather" warning. `repairLinks(for:)` calls the Adventure module's `validateLinks(on:)` with the Weather id, so a Weather whose Photo was deleted keeps a dangling `photoId`. `LinkController.validateLinks` ends in `resetLinkRegister(replacedItem)`, which clears the source's registered links and re-registers `[]`, so a Validate/Repair pass removes even a correctly registered Weather photo link. A weather imported from a file also never registers its photo.
- Action: Use `.weather` as the source type, add `linkRegisterModels` as `changedLinkRegisterModels(oldValue: .empty).added` like Table does, and let the next `validateLinks` pass re-register existing rows (the clear is keyed by source id, so rows saved with the wrong type are removed by it). Extend `Tests/WeatherRPGTests/LinkControllerTests.swift` to assert the source type and that `validateLinks` keeps a valid photo link.
- Severity: High
- Status: NEW

### Time, rain intensity and rain angle sliders edit the live model and are never saved
- Category: Bug
- Location: Modules/WeatherRPG/View/WeatherConditionEditor.swift:55-70 (`Slider(value: $model.time)`); Modules/WeatherRPG/View/WeatherStormEditor.swift:96-107 (`$model.rainIntensity`), :110-125 (`$model.rainAngle`); model source Modules/WeatherRPG/Route/WeatherRoute.swift:66 (`itemSync`, the stored instance)
- What: Three of the eight editable weather values bind a `@Bindable` slider straight to the stored `WeatherModel` and never call `EditController.save`; the other values (clouds, storm type, lightning, photo, direction) go through `EditIdentifierModel` and `editController.reset`. No other module binds a slider to a live model, and I found no autosave or observation-driven save in CoreRPG.
- Why: The change is visible at once, but it never goes through `replace(with:)`, so no Core Data write, no CloudKit sync, no `weatherUpdate` stamp, no undo and no game-memory/library separation (it edits the library item during a game). If nothing else is edited afterwards the value is lost on relaunch; if another property is saved later, `editModel(for:)` copies the mutated live item and persists the old slider edit by accident. Reasoned from code; please drag the Time slider, relaunch and compare.
- Action: Route the three sliders through `EditIdentifierModel` plus `editController.reset(...)` like the lightning sliders (add the missing `reset(time:)`, `reset(rainIntensity:)`, `reset(rainAngle:)` overloads), saving on the end of the drag.
- Severity: High
- Status: NEW (unverified at runtime)

### Lightning sliders save only when one change event jumps by 1 or more
- Category: Bug
- Location: Modules/WeatherRPG/View/WeatherThunderEditor.swift:150-170 (`SignificantChangeModifier`), used at :95, :113, :131
- What: `onChange(of:)` compares the previous event value with the new one and calls `editModel.save()` only if `abs(old - new) >= 1`, i.e. per event, not against the last saved value.
- Why: A normal drag of the Max Bolts slider (range 0-10, about 0.03 per point) or a slow drag of Frequency/Fork (0-100) produces deltas far below 1, so the new value is never saved; the slider shows the new value until the view resyncs, then snaps back to the stored one. Only fast swipes persist.
- Action: Save when the drag ends (`Slider(onEditingChanged:)`) or compare against the last saved value; use a step of 1 for the bolt count, which is a whole number anyway.
- Severity: High
- Status: NEW (reasoned)

### `replace(with:)` bumps `weatherUpdate` on every change, even when no weather value changed
- Category: Bug
- Location: Modules/WeatherRPG/Model/WeatherModel.swift:332 (`weatherUpdate_.wrappedValue = UUID()`), Modules/WeatherRPG/Model/WeatherModel+Sync.swift:8-30 (`merge` takes all weather fields from whichever side has the newer stamp), applied by Modules/CoreRPG/Controllable/ItemControllable.swift:250 and :745
- What: Every other field uses `<=>`, but the stamp is reassigned unconditionally in `replace`, so renaming, tagging, moving into a folder or applying a synced merge stamps "weather settings changed now".
- Why: The weather values (time, clouds, storm, lightning, photo) merge as one block by this stamp. A device that only renames an item from an older weather snapshot gets a newer stamp than another device's later weather edit, and on the next CloudKit merge its stale values win (lost update). Applying a synced model also re-stamps the in-memory copy, which is persisted with the next unrelated save.
- Action: Only bump the stamp when one of the weather fields actually differs from `model` (or adopt `model.weatherUpdate_` with `<=>` and let `EditController` stamp on weather edits).
- Severity: Medium
- Status: NEW

### Idle weather layers keep redrawing at display rate
- Category: Performance
- Location: Modules/WeatherRPG/View/WeatherEffectLayers.swift:15-40, Modules/WeatherRPG/Weather/StarsView.swift:21-57, LightningView.swift:21-45, CloudsView.swift:35-60, Modules/WeatherRPG/Weather/StarField.swift:19-26
- What: `StarsView` is always in the stack and only faded with `.opacity(starOpacity)`; its star alpha is zero for time 0.33-0.78, yet its `TimelineView(.animation)` keeps drawing every frame, and `change(size:)` creates one star per 1000 pt^2 without a cap (about 2000 on a 1920x1080 tvOS screen, more in a large visionOS window), each blooming star copying the context and applying a blur. `LightningView` redraws a full-screen transparent fill and two blur-filter passes every frame when `frequency < 1` or while waiting; `CloudsView` runs its timeline with zero clouds.
- Why: In game mode (`useGame`) four animated canvases run continuously on a phone/TV/headset for effects that are invisible, which costs battery and frame time.
- Action: Do not instantiate `StarsView` while `starOpacity == 0`, pause the lightning timeline in `.waiting` state with no periodic trigger, skip `CloudsView` for `.none`, and cap the star count.
- Severity: Medium
- Status: NEW

### Player packages carry the full lossless Foundry payload, and the version digest re-encodes it on every call
- Category: Performance
- Location: Modules/RuleRPG/Model/RuleModel.swift:234-238 (`version` = `StableVersionDigest.digest(CanonicalRuleContent)` incl. `sourcePayload`), :386-398 (`encode` writes `sourcePayload`); Modules/RuleRPG/Controller/ExportController.swift (no `playerExportData` override); Modules/CoreRPG/Controllable/ExportControllable.swift:395-402; Modules/CoreRPG/Controllable/GameControllable.swift:221, :318
- What: `RuleModel.version` JSON-encodes (sorted keys) and hashes the whole model including the raw `FoundryRuleDefinition`/document JSON each time it is asked, and the same payload is exported to players when a rule is revealed.
- Why: `hasItem(id:version:)` and the version lookup run on the main actor for every reveal/availability check, and a rule can carry hundreds of KB of raw JSON that players never see (the viewer shows only entries and metadata). It also ships the unprocessed source (unused fields) to every player over SharePlay/LAN, which is the slow channel documented in memory.
- Action: Override `playerExportData(for:)` to drop `sourcePayload`, and compute the version from the same player projection (master and player must agree, see GameControllable.swift:221); cache the version per edit counter if it stays hot.
- Severity: Medium
- Status: NEW

### Quick editor: a new section moved above a same-named one produces two entries with the same id
- Category: Bug
- Location: Modules/RuleRPG/Controller/EditController.swift:97-140 (`mergeEntries`), called from :84-88 and :146-170; reorder at Modules/RuleRPG/View/RuleQuickEntryEditor.swift:27
- What: `mergeEntries` resolves each imported entry in one pass: id match first, then a name+kind+parent fallback against still-unmatched existing entries. A new entry processed before the existing entry it resembles takes that entry's identity through the fallback; the existing entry (same id) then finds no unmatched partner and is returned as is.
- Why: Add a section named "Notes" while a "Notes" section exists, drag the new one above the old one, Save: the result holds two entries with the existing id (new content under the old id, plus the old entry). Duplicate ids break `ForEach` identity, `item[entryId]`, link targets and `changedLinkRegisterModels` (the dictionaries keep the first). Any importer that hands entries in a different order than `existing` can hit it too.
- Action: Match by id for all imported entries first, then run the name fallback only for the leftovers against existing entries that no id match claimed; add a regression test for the reordered case.
- Severity: Medium
- Status: NEW

### `mergeEntries` is O(imported x existing) and recomputes `withoutLink()` for every pair
- Category: Performance
- Location: Modules/RuleRPG/Controller/EditController.swift:107-123
- What: For each imported entry it scans `existing` for the id (linear) and always builds `hierarchyFallbackIndices`, even when the id matched, calling `existing[$0].name.withoutLink()` per candidate.
- Why: A Foundry rule projects up to about 500 value entries plus groups/effects; a quick-editor Save or re-import costs hundreds of thousands of string transforms on the main actor.
- Action: Index existing entries by id and by (name without link, kind, parentId) once; compute the fallback lazily only when the id lookup misses.
- Severity: Medium
- Status: NEW

### Rule quick editor does O(n) tree work per row on every keystroke
- Category: Performance
- Location: Modules/RuleRPG/View/RuleQuickEntryEditor.swift:130-175 (`RuleQuickEntrySectionEditor.body`, `kindSelection`, `parentSelection`)
- What: Every row receives `$entries` for the whole array, so each keystroke in any field re-evaluates all row bodies; each does `entries.firstIndex` and `RuleEntryTree.validParentGroups` (builds a child map and walks descendants) and a Picker listing every group.
- Why: For an imported rule with a few hundred entries that is O(n^2) per keystroke and makes typing laggy on the main actor.
- Action: Compute the group list once in the parent (or lazily when a Picker opens), give each row an entry binding instead of the whole array, and keep tree validation in the setters.
- Severity: Medium
- Status: NEW

### Foundry value contents, names and description are not passed through `inert`
- Category: Security
- Location: Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:34 (description), :266-267 and :283-286 (`content: presentation(value)`, `name: decodedText(node.component)`); `inert` documented at :186-194
- What: `inert` is applied to references, embedded-rule values and effects only; the main value entries and the description go to the Markdown renderer raw.
- Why: A package string such as `[x](https://...)` becomes a tappable link inside the rule, which the earlier fix for CODE_AUDIT_22 §6.5 / 23 §6.8 set out to prevent, and deterministic rule ids make `RPG://` links to other imported rules forgeable. Impact is low (the user chose to import the package).
- Action: Run values, node names and descriptions through the same neutralizer (keeping paragraph breaks in descriptions), or document that only the structured sections are neutralized.
- Severity: Low
- Status: NEW (gap in the CODE_AUDIT_22 §6.5 fix)

### Imported numbers are formatted with the device locale and rounded to 3 decimals
- Category: Bug
- Location: Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:344-349 (`presentation`: `.integer/.unsignedInteger` `formatted()`, `.number` `formatted(.number)`)
- What: Persisted entry content depends on the importing device's locale ("1,234.5" vs "1.234,5") and `.number` keeps at most 3 fraction digits.
- Why: The same package imported on two devices gives different content for the same deterministic entry ids (CRDT conflicts, different `RuleModel.version`), and values such as 0.12345 lose digits (the payload is lossless, the editable text is not).
- Action: Format stored content with a fixed locale and full precision.
- Severity: Low
- Status: NEW

### English text baked into persisted rule content; one header not localized
- Category: SwiftUI
- Location: Modules/RuleRPG/View/RuleQuickEntryEditor.swift:~148 (`Label(cond ? "Untitled Section" : name, systemImage:)` resolves to the `StringProtocol` overload, so it is verbatim; the key is not in Localizable.xcstrings); Modules/RuleRPG/Model/RuleModel+FoundryFactory.swift:101-132, :240-247 ("**Target:**", "Effect N", "Additional source values", "yes"/"no")
- What: The header shows English only; imported entries store English labels as content.
- Why: Non-English users see mixed languages; stored labels cannot be localized later.
- Action: Use `Text("Untitled Section", bundle: .ruleModule)` in a label closure; decide whether the stored labels stay English by design and note it.
- Severity: Low
- Status: NEW

### Quick-link controllers spawn unstructured Tasks; Rule's does nothing for the share command
- Category: Concurrency
- Location: Modules/RuleRPG/Controller/LinkController.swift:107-113 (empty `Task` for `share`, `shareResult` never used); Modules/WeatherRPG/Controller/LinkController.swift:24-27 (discarded `Task` for the share broadcast)
- What: Both start a `Task` with no handle; Rule's task body is empty when the command is `share`.
- Why: Dead work in Rule (and sharing a rule link silently does nothing, if that was meant to work); in Weather the broadcast cannot be cancelled with the caller.
- Action: Skip the Task for `.share` in Rule or implement it; make the toggle `async` or keep the Task handle.
- Severity: Low
- Status: Rule NEW; Weather [OPEN since CODE_AUDIT_Weather §3.3]

### Cloud and star elements pile up at one edge after a long pause; Storm divides by the canvas width
- Category: Bug
- Location: Modules/WeatherRPG/Weather/CloudGroup.swift:55-66 and Modules/WeatherRPG/Weather/StarField.swift:49-56 (unclamped `delta`, wrapped by assignment to one edge); Modules/WeatherRPG/Weather/Storm.swift:48-52 (`divisor = size.height / size.width`)
- What: CODE_AUDIT_23 §5.17 clamped only the Storm delta. After a pause (Reduce Motion toggled, view hidden) every cloud/star that left the range is set to the same `rightEdge`/`offScreenDistance`, so they re-enter as one column. A zero-width canvas makes `divisor` infinite, and drops with infinite `x` never wrap (the wrap only adds or subtracts 1.4), so rain is gone until the storm is rebuilt.
- Why: Cosmetic glitch after a pause; the zero-size case is unlikely because `WeatherViewer.containerSize` falls back to 320x64, but the Canvas itself does not guard.
- Action: Clamp `delta` as Storm does, use `truncatingRemainder` for the wrap, and `guard size.width > 0` in `Storm.update`.
- Severity: Low
- Status: NEW

### `ViewController.viewer` ignores its `configuration` argument
- Category: Bug
- Location: Modules/WeatherRPG/Controller/ViewController.swift:73-75
- What: `viewer(root:itemId:configuration:dismissAction:)` builds `ViewerConfiguration(closeButton: dismissAction != nil)` and drops the one passed in (Rule's equivalent passes it through, Modules/RuleRPG/Controller/ViewController.swift:36-41).
- Why: `isGame`, `addToolbar` and the caller's `closeButton` are lost for callers that go through `viewer`, e.g. `ViewerRouteDestinationView` passes `closeButton: appSizeModel.mode == .compact`.
- Action: Pass `configuration` through (and adjust `closeButton` only if intended).
- Severity: Low
- Status: NEW

### `WeatherRootModel.setUp` keeps the old sync controller when called without a context
- Category: Bug
- Location: Modules/WeatherRPG/Root/WeatherRootModel.swift:101-105 (compare Modules/RuleRPG/Root/RuleRootModel.swift:126-129)
- What: `syncTask?.cancel()` runs but `syncTask`/`syncDataController` are not cleared, so a second `setUp(context: nil, ...)` leaves a stale controller referencing the old context.
- Why: Only affects re-setup (tests, store switch); harmless in the normal launch path.
- Action: Set both to nil before the `if let` as Rule does.
- Severity: Low
- Status: NEW

### Unreferenced `EditController.reset(kind:itemId:entryId:)`
- Category: Dead code
- Location: Modules/RuleRPG/Controller/EditController.swift:168-176
- What: No caller in Modules, Sources or Tests (the quick editor changes kinds through `RuleEntryTree.settingKind`).
- Why: Dead code that also bypasses the tree's parent normalization (changing a group to text leaves its children pointing at it).
- Action: Delete it.
- Severity: Low
- Status: NEW

### Test gaps for the risky Weather and Rule logic
- Category: Test gap
- Location: Tests/WeatherRPGTests (no test touches `replace(with:)`/`weatherUpdate` semantics, `rainDirection` at zero angle, `linkRegisterModels`, or the `merge` stamp winner), Tests/RuleRPGTests (`mergeEntries` is tested for ordered input only; nothing for reordered or duplicate-named entries, `playerExport`, or the editor's save path)
- What: The behaviours behind the Weather link-register, stamp and slider findings, and the Rule reorder/duplicate-id case, have no test.
- Why: They are exactly the paths that regressed unnoticed.
- Action: Add tests with each fix: link source type survives `validateLinks`; a name-only `replace` keeps `weatherUpdate`; a reordered `mergeEntries` yields unique ids.
- Severity: Medium
- Status: NEW

Not audited in this area: visual/behavioural tuning of the particle math (cloud drift, star flicker, lightning bolt geometry, storm physics) beyond the bugs above; the Core Data models (`Rule.xcdatamodeld`, `Weather.xcdatamodeld`) and the localization catalogs' translations; the Foundry importer in CoreRPG (`FoundryVTTImportReader` and models, covered by the CoreRPG audits); RealityKit rendering was read but not run; none of the findings marked "reasoned" or "unverified" were reproduced on a device.
