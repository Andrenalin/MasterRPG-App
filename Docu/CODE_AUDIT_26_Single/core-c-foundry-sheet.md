Area: Modules/CoreRPG/{Foundry,Sheet,Settings,Tips,Text} (about 14k LOC; all of Foundry, Text, Tips core, Settings and the model/root/view layer of Sheet were read; Sheet leaf button/preview views were skimmed). Note: the Sheet folder contains no PDF export code (no ImageRenderer/PDFKit use); it is the recursive sheet model/view layer. Sheet, Settings and Tips are in good shape (CLAUDE.md rules are followed: Label-based buttons, no onTapGesture, Observation correct, reconcile Tasks cancel-then-replace); the substantive findings are in Foundry, one parser bug in Text, and a few Sheet performance/edge issues.

Files read in full for Foundry: ZIP archive, data source, import reader, import models, decoder collection decoding, package resolution, rule models, LevelDB table/WAL/manifest readers, bridge decoder, archive sanitizer, system package reader, system compendium decoding, UniversalVTT reader, artifact detector, text decoder, value hierarchy, import archive store, base64/line/budget helpers (about 8k LOC). Overall health of Foundry: the ZIP reader, LevelDB readers, bounded base64, depth-guarded JSON and path normalisation are carefully hardened (checked arithmetic, entry/total size caps, CRC, duplicate paths, symlink handling, traversal checks all hold up). The remaining risk is in what the hardening does not cover: unbounded recursion/exponential work in template resolution, quadratic scans, memory limits sized for macOS but used on iOS/tvOS/visionOS, and one privacy-scrub gap.

## Foundry findings

### Template inheritance resolution is exponential and unboundedly recursive (crash/hang on hostile system.json package)
- Category: Security
- Location: Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:456-476 (resolveTemplate), 418-453 (decode)
- What: `resolveTemplate` recurses once per entry of a template's `templates` list with no memoisation, no depth cap and no `Task.checkCancellation()`; cycle detection only catches true cycles.
- Why: A tiny `template.json` where template t_i lists `[t_{i+1}, t_{i+1}]` (diamond chain, duplicates allowed) costs 2^n resolutions, so n=40 hangs the import in an uncancellable CPU loop. A plain chain t_0 -> t_1 -> ... -> t_5000 (non-cyclic, a few hundred KB of JSON, well under every size cap and under the 128 JSON-depth guard because the structure is flat) recurses 5000 frames deep on a Swift concurrency worker thread (512 KB stack) and can overflow the stack, which is a process crash, not a catchable error. Subtype resolution repeats the same work for every declared subtype.
- Action: Resolve templates iteratively or with a memo table keyed by template name (each template resolved once), cap inheritance depth (e.g. 32) and total template count, dedupe the `templates` list, and check cancellation in the loop.
- Severity: High
- Status: NEW

### sanitizer does not scrub `_stats.lastModifiedBy` (user id leaks when "include users" is off)
- Category: Security
- Location: Modules/CoreRPG/Foundry/FoundryVTTArchiveSanitizer.swift:138-141 (identityKeys), 204-208
- What: `identityKeys` contains `modifiedby` and `createdby` but not `lastmodifiedby`; Foundry v11/v12 documents carry `_stats.lastModifiedBy` (a User id). Verified: no occurrence of `lastModifiedBy` anywhere in Modules/CoreRPG or Tests.
- Why: With `includingUsers == false` the archive that is persisted (and iCloud-synced as the RuleRPG hand-off) still contains the id of the Foundry user who last edited every document, contradicting the type's documented privacy boundary ("private ... user identifiers").
- Action: Add `lastmodifiedby` (and review `lastmodifiedbyid`/`updatedby`) to `identityKeys`; add a sanitizer test with a realistic `_stats` block.
- Severity: Medium
- Status: NEW

### Embedded-document mapping tables are duplicated and have already drifted (`.level` missing in sanitizer)
- Category: Duplication
- Location: Modules/CoreRPG/Foundry/FoundryVTTArchiveSanitizer.swift:284-304 vs Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1011-1038
- What: `State.embeddedMappings` repeats `FoundryVTTEmbeddedExtractor.standardMappings`/`adventureMappings`; the `.level` entry (tokens, walls, lights ... under a Level) exists only in the extractor.
- Why: For Level documents `removingRepresentedEmbeddedArrays` never strips the represented arrays, so the embedded token/wall/... JSON is stored twice in the durable archive (once as embedded documents, once inside the Level `rawData`), contradicting the "duplicate raw container arrays are deliberately absent" contract of FoundryImportArchive and growing the archive toward its 512 MiB save cap.
- Action: Make one shared table (internal enum) used by both; add a test asserting the two agree.
- Severity: Low
- Status: NEW

### Quadratic scans of the archive path list during collection discovery
- Category: Performance
- Location: Modules/CoreRPG/Foundry/FoundryVTTDecoder+CollectionDecoding.swift:28-37, 96-98; Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:546-550; Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:131-156
- What: For every collection spec / manifest pack the code filters the whole `source.paths` (up to 100 000 entries, with `lowercased()` per path) and `levelDBDirectories` does `specs.contains` per directory; `liveLevelDBPaths` does `source.paths.first` per spec.
- Why: A crafted ZIP with ~50 000 tiny valid `.ldb` files in distinct directories (or a manifest declaring many packs) costs specs x paths ~ 10^9-10^10 string operations; the work has only coarse cancellation points, so import appears hung for minutes. The 100 000 spec cap does not bound the product.
- Action: Build a directory -> [path] index once in `FoundryVTTDataSource` (and a lowercase-suffix index), look specs up in O(1); cap spec count to something realistic (e.g. 1 000).
- Severity: Medium
- Status: NEW

### Memory ceilings are sized for macOS but apply on iOS/tvOS/visionOS
- Category: Performance
- Location: Modules/CoreRPG/Foundry/FoundryRuleModels.swift:745-755 (defaults 1 GiB archive, 64 MiB entry, 512 MiB rule data/resource batch); Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1241-1278 (bridge resource cache); Modules/CoreRPG/Foundry/FoundryVTTBridgeDecoding.swift:183-192, 293-318
- What: One `FoundryImportLimits.default` for all platforms; `FoundryJSONValue` trees of up to 512 MiB of JSON are built (typically 5-10x expansion, plus each document keeps its own `rawData` and every embedded document repeats the parent's nested array, plus the Sanitizer makes another full copy), the bridge resource cache keeps every decoded asset (up to 512 MiB) alive until the next preflight, and a bridge asset line transiently holds the 86 MB line copy + the JSON String + the decoded Data.
- Why: On an iPhone/Apple TV a large Foundry world import is killed by jetsam rather than rejected with `fileTooLarge`; the app loses the whole session. On macOS it is merely slow.
- Action: Platform-specific default limits (e.g. 128 MiB rule data, 128 MiB resource batch on iOS/tvOS/visionOS), drop the bridge resource cache after the commit finishes (or make it load assets on demand by file offset), and stream asset lines instead of materialising them as JSON strings.
- Severity: Medium
- Status: NEW

### Bridge size guard runs after the whole file was decoded and hashed
- Category: Bug
- Location: Modules/CoreRPG/Foundry/FoundryVTTBridgeDecoding.swift:23 vs 57
- What: `decodePackage` calls `decodeContents` (JSON-decodes every line, base64-decodes and SHA-256s every asset) before `guard data.count <= maximumRuleDataSize`. `maximumArchiveSize` is 1 GiB but `maximumRuleDataSize` is 512 MiB, and the budget is initialised with the whole file size.
- Why: Any bridge file between 512 MiB and 1 GiB is accepted by the earlier checks, fully decoded (hundreds of MB of allocations) and only then rejected with `fileTooLarge`; the two limits also contradict each other (assets alone may be 512 MiB decoded = 683 MB encoded, which can never pass the later check).
- Action: Move the guard before `decodeContents` and decide on one consistent limit for bridge files (document vs asset bytes budgeted separately).
- Severity: Low
- Status: NEW

### One malformed bridge `assetReference` aborts the whole import
- Category: Bug
- Location: Modules/CoreRPG/Foundry/FoundryVTTBridgeDecoding.swift:320-331, 437-447
- What: `normalizeReferencePath` throws `invalidArchive` for a `remote` reference that `URLComponents(string:)` rejects (unescaped spaces, non-ASCII, brackets are common in user-typed image URLs) and for local/core paths containing a backslash or `..`.
- Why: A world with a single odd image URL cannot be imported at all; the reference is only metadata (status `unresolved` would be adequate). Unverified: depends on whether the Foundry-side exporter percent-encodes.
- Action: Downgrade to an `unresolved` resource plus a capped diagnostic instead of throwing.
- Severity: Low
- Status: NEW

### Bit-wise CRC-32C and per-byte Snappy copies make LevelDB reading slow
- Category: Performance
- Location: Modules/CoreRPG/Foundry/FoundryLevelDBReader.swift:360-371 (checksum), 119 (`Array(bytes[contentRange]) + [compression]`), 345-347 (appendCopy), Modules/CoreRPG/Foundry/FoundryLevelDBWriteAheadLogReader.swift:73
- What: CRC32C is computed with 8 shift/xor steps per byte and the input is first copied into new arrays; Snappy back-references append one byte at a time with an array index per byte.
- Why: Verifying up to 512 MiB of table blocks costs billions of iterations (tens of seconds) before any document is decoded; hardware CRC32C or a 256-entry table is ~20x faster. Not a correctness issue.
- Action: Table-driven (or `__crc32cb` intrinsic) CRC32C over slices without copies; use `append(contentsOf:)` for non-overlapping Snappy copies.
- Severity: Low
- Status: NEW

### UniversalVTT reader parses a file of up to 1 GiB into a JSON tree
- Category: Security
- Location: Modules/CoreRPG/Foundry/UniversalVTTReader.swift:268-279, 289-313; Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:191-194
- What: `boundedData` allows `maximumArchiveSize` (1 GiB) although the only large legitimate member is a base64 image capped at 64 MiB decoded (~86 MB encoded); the entire file is decoded into `FoundryJSONValue` (every unknown field retained), and `resourceData` re-parses the whole file again just to fetch the image.
- Why: A `.dd2vtt` padded with a huge unused field is accepted and consumes several GiB; on iOS this is a jetsam kill. Each image fetch repeats the full parse.
- Action: Limit UVTT file size to about `maximumEntrySize * 4/3 + 8 MiB`; cache the decoded image bytes or file offset from preflight.
- Severity: Medium
- Status: NEW

### Artifact detection parses whole JSON files twice with Foundation's object tree
- Category: Performance
- Location: Modules/CoreRPG/Foundry/FoundryArtifactDetector.swift:107-111, 130-139
- What: For any `.json` up to 1 GiB, `detect` runs `JSONSerialization` over the entire file in `isJSONObjectOrArray` and again in `looksLikeUniversalVTT`, building two NSObject graphs just to classify the file; the archive branch also maps the full ZIP and parses the central directory.
- Why: Choosing a file in the picker can stall for a long time and allocate multiples of the file size. A cheap check (first non-whitespace byte `{`/`[` and a bounded scan for `"image"`/`"map_size"` in the first N MB) suffices for detection.
- Action: Peek at a bounded prefix (e.g. 256 KB) and decide from keys found there; leave the full parse to the reader.
- Severity: Low
- Status: NEW

### HTML-to-text regexes are quadratic on unterminated tags and rebuilt on every call
- Category: Performance
- Location: Modules/CoreRPG/Foundry/FoundryTextDecoder.swift:23-41
- What: `(?is)<!--.*?-->` and `(?is)<\s*(script|style|template|noscript)\b[^>]*>.*?<\s*/\s*\1\s*>` are lazy scans that run to the end of input for every unterminated opener; the four `NSRegularExpression` objects are compiled on every `plainText` call.
- Why: A description field of a few MB made of repeated `<!--` or `<script>` without a closer takes O(n^2) (each opener scans to the end), and mapping of thousands of documents recompiles four patterns each time.
- Action: Hoist the expressions into static lets, and replace the two lazy patterns with a single linear scanner (find the opener, `range(of:)` for the closer once, stop if absent).
- Severity: Medium
- Status: NEW

### `decodeEntities` scans to end of string for every `&` without a semicolon
- Category: Performance
- Location: Modules/CoreRPG/Foundry/FoundryTextDecoder.swift:233-240
- What: `source[current...].firstIndex(of: ";")` is evaluated before the 34-character distance check, so each `&` is O(remaining length).
- Why: A text field consisting of many `&` and no `;` (also plausible in legitimate text such as "R&D & A&B" repeated) is O(n^2); 1 MB of `&` is 10^12 comparisons.
- Action: Search only a 34-character window (`source[current...].prefix(35)`).
- Severity: Medium
- Status: NEW

### `FoundryValueHierarchy.nodes(from: [FoundryRuleValue])` copies a whole dictionary per insert on wide levels
- Category: Performance
- Location: Modules/CoreRPG/Foundry/FoundryValueHierarchy.swift:80-88
- What: `var child = children[component] ?? NodeBuilder(); child.insert(...); children[component] = child` keeps two references to the child's storage while mutating, so the child's `children` dictionary is copied on every insert.
- Why: A rule with thousands of sibling paths under one key (rolltable rows, spell lists, big `system.*` maps) is inserted in O(n^2) dictionary-entry copies; editing/opening a large rule stalls the UI thread.
- Action: Remove the entry from the dictionary before mutating (`children.removeValue`) or mutate through `children[component, default: NodeBuilder()].insert(...)`.
- Severity: Low
- Status: NEW

### Asset-path collection allocates a byte array and a `URL` per string
- Category: Performance
- Location: Modules/CoreRPG/Foundry/FoundryPackageResolution.swift:124-133, 141-142; Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:516-530 (`FoundryReferenceDecoder.visit`)
- What: For every string in every raw document `htmlAttributeReferences` copies the string to `[UInt8]`, then `URL(filePath:)` is built to read the extension; `FoundryReferenceDecoder.visit` builds `path + [key]` arrays and runs six `range(of:)` searches per string. Embedded documents are walked again as part of every ancestor's raw JSON.
- Why: Up to 512 MiB of JSON yields tens of millions of strings; preflight time is dominated by this allocation churn. Strings without `<` or `.` can be skipped immediately.
- Action: Fast-path: skip strings without `.` for the extension test and without `<` for the HTML scan, use `utf8` view search and `lastIndex(of: ".")` instead of `URL`; only build the path string lazily when a marker is found.
- Severity: Low
- Status: NEW

### Packaged resource resolution reads, inflates and hashes every referenced asset during preflight and counts duplicates
- Category: Performance
- Location: Modules/CoreRPG/Foundry/FoundryPackageResolution.swift:243-272
- What: `resolve` calls `data(candidate)` (full inflate + CRC) and SHA-256 for each unique logical path; different spellings of the same file (`a.png`, `./a.png`, `a.png?x=1`, `a.png#f`) are separate logical paths that each re-read the file and each add to `packagedBytes`.
- Why: Preflight must inflate up to 512 MiB of images/audio it will not use if the user deselects them; a hostile archive referencing one 64 MiB entry through 9 spellings makes the import fail with `fileTooLarge`, and a legitimate package using query-string cache busters can hit the same limit.
- Action: Cache hash/size per resolved package path, count each package path once, and consider hashing lazily from the ZIP central-directory CRC (already verified) with SHA-256 computed at commit time.
- Severity: Low
- Status: NEW

### `FoundrySystemPackageReader.readResources` re-opens (re-hashes) the whole archive on every call
- Category: Performance
- Location: Modules/CoreRPG/Foundry/FoundrySystemPackageReader.swift:43-93
- What: Each call builds a new `FoundryVTTDataSource(url:)`, which reads the file and SHA-256-hashes up to 1 GiB, then re-decodes the manifest; the world/module reader got a cache for exactly this (`FoundryZIPDataSourceCache`, CODE_AUDIT §7.1) but the system reader did not. Only tests reference this type outside Foundry (the domain mapper uses `FoundryVTTImportReader`), so it may also be dead in production.
- Why: N resource fetches cost N full archive reads and hashes. If it is dead code it is 700 lines of maintenance for nothing.
- Action: Confirm callers; if unused remove `readResources`/`readResource`/`read(from:)` public surface (keep `read(reusingArchive:)`), otherwise use the shared cache.
- Severity: Low
- Status: NEW

### Memory-mapped source files are cached for the life of the reader
- Category: Concurrency
- Location: Modules/CoreRPG/Foundry/FoundryVTTDataSource.swift:34, 118-143; Modules/CoreRPG/Foundry/FoundryVTTImportReader.swift:1210-1235
- What: Archives are loaded with `Data(contentsOf:options: .mappedIfSafe)` and the parsed source (holding the mapping) is cached by `FoundryZIPDataSourceCache` for later resource reads; the security-scoped access is released after each call.
- Why: If the user's file is truncated, replaced or its iCloud/removable volume goes away while a mapping is cached, later page reads raise SIGBUS (process crash) instead of an error, and the cached `sourceSHA256` makes the `sourceMismatch` check compare the cache with itself on calls after the first.
- Action: Read with `.alwaysMapped`-free semantics for files outside the app container (plain read or `F_NOCACHE` streaming), or drop the cache at the end of the import; re-stat size/modification date before reusing the cache.
- Severity: Low
- Status: NEW

### `FoundryImportArchiveStore.archive(id:)` has no size cap and `save` checks size only after encoding
- Category: Performance
- Location: Modules/CoreRPG/Foundry/FoundryImportArchive.swift:125-146
- What: `save` encodes the whole archive with a pretty sorted-keys encoder before checking `maximumEncodedByteCount`; `archive(id:)` reads and decodes the file without the size check that `mapArchives` applies.
- Why: A 400 MiB package tree is encoded (several GiB transient) before it can be refused; a synced oversized or corrupt archive file is read in full on direct lookup.
- Action: Check `fileSize` before reading; estimate package size from the preflight statistics (raw bytes) before encoding.
- Severity: Low
- Status: NEW

### Test gaps in the importers
- Category: Test gap
- Location: Tests/CoreRPGTests/Foundry
- What: No test covers deeply chained / diamond `template.json`, a bridge file between 512 MiB and 1 GiB (can be synthesised sparsely), the `_stats` user-id scrub, `&`-only and unterminated-comment text for `FoundryTextDecoder`, or wide-level `FoundryValueHierarchy`.
- Why: These are exactly the inputs behind the findings above.
- Action: Add focused tests (with time limits) when fixing.
- Severity: Low
- Status: NEW

## Text, Sheet, Tips, Settings findings

### `TableRollRange` reads "00" as 0, so d100 rows such as "96-00" never match rolls 97-100
- Category: Bug
- Location: Modules/CoreRPG/Text/TableRollRange.swift:12-23 (consumers Modules/TableRPG/Controller/TableGenerationController.swift:241-254, Modules/TableRPG/Controller/GameController.swift:139-148, Modules/CoreRPG/Links/QuickLinkScanner.swift:35)
- What: The selector is parsed into integers with `Int($0)`, so "00" becomes 0 and "96-00" becomes `0...96`. The d100 convention (and most printed/PDF tables) uses 00 for 100. Non-ASCII numerals (`isNumber` accepts "½", "²") are silently dropped by `compactMap`, which shifts the remaining values, and negative selectors ("-1 to 2") are not supported. There is no test for this type (grep of Tests finds none).
- Why: A rolled 97-100 on a "96-00" row finds no entry (the row only matches 0...96, which earlier rows already claim), so the roll result is empty in the live roll UI and in game mode for the most common table size. Imported tables from PDFs hit this directly.
- Action: Treat an all-zero token with length >= 2 as the die maximum (100, or 10 for "0" on a d10 if the table size is known); restrict digits to ASCII (`isASCII && isNumber`); add table-driven tests ("1-5", "96-00", "00", "7", en/em dash, "5 – 10", "*12*").
- Severity: High
- Status: NEW

### `TableRootSheet` builds (and discards) a full `SheetRootModel` on every `init`
- Category: Performance
- Location: Modules/CoreRPG/Sheet/TableRootSheet.swift:21-45
- What: `_sheetRootModel = State(wrappedValue: SheetRootModel(...))` evaluates the model, and therefore `sheetControllable.sheet(...)` for the whole item tree, every time the parent re-evaluates its body, although `@State` only keeps the first value. The per-init comment explains why the external-model path cannot reset, but the non-external path pays full price on each re-render. `preconditionFailure` also crashes if `rootManager` is not set yet.
- Why: Opening a large Character/Table sheet in a sheet/window while the parent updates (game state, search, selection) rebuilds the complete sheet tree repeatedly on the main actor; this violates the "@State initialised from a passed value" rule in the brief.
- Action: Create the model lazily (`@State private var sheetRootModel: SheetRootModel?` created in `.task(id: itemId)` / `onAppear`, or make an owner type that builds it once), and replace the precondition with an empty-state view.
- Severity: Medium
- Status: NEW

### Search resets every cached link model on each keystroke
- Category: Performance
- Location: Modules/CoreRPG/Sheet/SheetRootModel+Search.swift:31-35 (also SheetRootModel.swift:~126-146 `searchText.didSet`)
- What: Each change of `searchText` re-filters the whole tree and then calls `reset(highlightedText:)` on every entry in `linkTextModel`, a cache that is never pruned except on `reset(itemId:)`/entry removal; there is no debounce between keystrokes and the filter.
- Why: In a large Character sheet with hundreds of link-bearing rows, each typed character costs O(rows) attributed-string work on the main actor.
- Action: Debounce (cancel-then-replace) the filter/reset, and only reset models whose row is visible or whose text contains the previous/new term.
- Severity: Low
- Status: NEW

### Rows created while a search is active lose their expanded state (`lastIsShown` defaults to false)
- Category: Bug
- Location: Modules/CoreRPG/Sheet/SheetModel.swift:~105-130 (`filter`), Modules/CoreRPG/Sheet/SheetRootModel+Search.swift:18-29, Modules/CoreRPG/Sheet/SheetRootModel+Links.swift:60-72
- What: `saveIsShownState` runs once when a search starts; a link sheet toggled open afterwards (or a reconcile that creates rows) has `lastIsShown == false`, and the next keystroke executes `isShown = lastIsShown`, and clearing the search restores `false`. Unverified at runtime.
- Why: A link the user expanded while searching collapses on the next character or when the search is cleared.
- Action: Initialise `lastIsShown = isShown` when a row is appended (toggle/reconcile) or in `filter` when the row was not part of the saved snapshot.
- Severity: Low
- Status: NEW

### Reorder/move index math counts non-entry rows that share `entries`
- Category: Bug
- Location: Modules/CoreRPG/Sheet/SheetRootModel+ContextMenu.swift:12-30 (moveEntry up/down), 32-58 (reorderEntry); append sites Modules/CoreRPG/Sheet/SheetRootModel+Links.swift:61-72
- What: Link toggles append expanded linked sheets (no `entryId`) into the same `entries` array that move/reorder index into, but persistence is called with `compactMap { $0.source.entryId }`. Moving the last real entry down past an expanded root-level link sheet is accepted by the UI (`newIndex <= count`) but changes nothing in the persisted order; the next reconcile snaps it back. Unverified at runtime.
- Why: Confusing "entry moves then jumps back" behaviour in item sheets that have an expanded link in the header text.
- Action: Compute positions only among rows that have an `entryId` (filter first, translate index back) or keep linked sheets in a separate array.
- Severity: Low
- Status: NEW

### `removeEntry` updates the UI even if the edit controller could not remove the entry
- Category: Bug
- Location: Modules/CoreRPG/Sheet/SheetRootModel+Editor.swift:6-24 (also `commitAIEntry` in SheetRootModel+AIGeneration.swift:39-48 discards the insert result)
- What: `entryDataEditable(for:)?.removeEntry(...)` returns nothing and its absence is not checked before the row is removed from `parentModel.entries`; `commitAIEntry` drops the generated draft from `aiGeneratedEntries` regardless of `insertEntry` returning nil.
- Why: If the module controller is missing or the write fails, the user sees the row disappear (or the AI draft vanish) although nothing was persisted, i.e. silent data loss until the next reconcile.
- Action: Only mutate the view model after the controller reports success; keep the AI draft on failure.
- Severity: Low
- Status: NEW

### `moveEntry(fromItemId:entryId:toItemId:afterEntry:)` parameter name promises an insertion position it does not honour
- Category: Refactor
- Location: Modules/CoreRPG/Sheet/SheetRootModel+ContextMenu.swift:60-70, call site :104-110
- What: `afterEntry` is used only for its module type; the moved entry is appended wherever `move(itemId:entryId:into:)` puts it, not after the drop target.
- Why: Misleading API; a drop between two rows of another item lands at the end.
- Action: Either pass the target entry id to the controller for positional insert or rename to `targetEntry`/drop the parameter.
- Severity: Low
- Status: NEW

### Dead `rowColor(for:)` and the colour-scheme environment read in `SheetEntryView`
- Category: Dead code
- Location: Modules/CoreRPG/Sheet/SheetEntryView.swift:30 (`@Environment(\.colorScheme)`) and :170-177 (`rowColor`)
- What: `rowColor(for:)` has no caller (the border modifier has its own copy in SheetBorderViewModifier.swift:24), so `colorScheme` is read only for dead code.
- Why: Every entry row subscribes to appearance changes for nothing, and the duplicated colour logic can drift.
- Action: Delete the method and the environment property.
- Severity: Low
- Status: NEW

### Close button uses an image-only label; hard-coded spacing/margins in the table sheet
- Category: SwiftUI
- Location: Modules/CoreRPG/Sheet/TableRootSheet.swift:104-114 (image-only `Button` with a separate accessibility label); Modules/CoreRPG/Sheet/TableSheetView.swift:36, 55 (`LazyVStack(spacing: 2)`, `.contentMargins(.horizontal, 8, ...)`); Modules/CoreRPG/Sheet/SheetView.swift (`nestedSheetLeadingInset`)
- What: CLAUDE.md requires `Button("Close", systemImage:)` for image buttons and avoiding hard-coded stack spacing/padding.
- Why: Rule violations (minor); the accessibility label is correct, so only the convention is broken.
- Action: `Button("Close", systemImage: "xmark.circle", action:)` with `.labelStyle(.iconOnly)`; use default spacing/margins or named constants (already done for the inset).
- Severity: Low
- Status: NEW

### `EntryTextParser.removeLineBreaks` leaves a trailing space and drops real hyphens
- Category: Bug
- Location: Modules/CoreRPG/Text/EntryTextParser.swift:78-110
- What: Every non-hyphen content line gets `" "` appended, so each paragraph ends with a trailing space; a line ending in "-" always has it removed, joining genuine compound words ("Half-" / "Orc" becomes "HalfOrc").
- Why: PDF-copy cleanup produces stray trailing whitespace in entry content (visible in diffs/merge comparisons) and corrupts hyphenated names at line ends.
- Action: Join with single spaces and trim once at paragraph end; only drop the hyphen when the next line starts with a lowercase letter.
- Severity: Low
- Status: NEW

### `MasterRPGTips.refreshEligibility` walks every item of every module on the main actor after each add
- Category: Performance
- Location: Modules/CoreRPG/Tips/MasterRPGTips.swift:196-264, called from Modules/CoreRPG/Sheet/SheetEntryAddButton.swift:24, Modules/CoreRPG/Controllable/FolderListControllable.swift:373, Modules/CoreRPG/Menu/AddItemButton.swift:17, AddFolderButton.swift:23, AddCollectionButton.swift:17
- What: Each call iterates all stored models of all modules and sums `entries.count`/links, to derive six counters for tip eligibility.
- Why: In a library with tens of thousands of items every "new item/entry" tap pays an O(total) main-actor scan, only to feed tips that stop mattering after the first few uses.
- Action: Skip the scan once all count-based tips are invalidated (`MasterRPGTipState` already knows), or maintain counters incrementally; at minimum early-exit when tips are disabled.
- Severity: Low
- Status: NEW

### Test gaps (Sheet/Text)
- Category: Test gap
- Location: Tests/CoreRPGTests
- What: No tests for `TableRollRange` or `EntryTextParser.removeLineBreaks`; the sheet move/reorder index math and search `lastIsShown` restore are only exercised indirectly.
- Why: These are pure functions with known edge cases (see above).
- Action: Add focused table-driven tests with the fixes.
- Severity: Low
- Status: NEW

Not audited in this area: Settings theme views beyond a read of ThemeSettingsView/ThemeMiniature (decorative, no findings); Sheet leaf button views and preview fixtures (SheetEntry*Button, SheetEntryReview* views, SheetContextMenuView, SheetEntryConvertToGroupView) were only skimmed with pattern greps; Tips structs in MasterRPGTips+*.swift (declarative TipKit definitions); runtime behaviour of any finding marked unverified; the RuleRPG/RolePlayGameKit domain mapper that consumes the Foundry package (outside this area).
