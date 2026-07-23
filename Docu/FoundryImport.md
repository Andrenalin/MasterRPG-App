# Foundry VTT and Universal VTT import

MasterRPG imports Foundry VTT content through a two-phase workflow:

1. **Preflight** detects and decodes the source without changing the library or writing assets.
2. **Review and commit** lets the user include or exclude content families and choose merge, replace, or skip for every projected item. Accepted items are applied as one partial import; content missing from the source is never treated as deleted.

The transport implementation lives in `CoreRPG/Foundry`. Domain projection and the SwiftUI workflow live in `RolePlayGameKit/Import/Foundry`. Original Foundry fields are also saved in a versioned `FoundryImportArchive`, which is the hand-off boundary for a later `RuleRPG` module.

## Accepted sources

`FoundryArtifactDetector` and `FoundryVTTImportReader` support:

- Foundry system, module, and world packages as a selected extracted package folder or a regular ZIP archive (a bare `system.json`, `module.json`, or `world.json` is rejected because its sibling packs/assets are outside the file grant);
- modern Foundry LevelDB compendiums and world collections, including complete multi-table databases, live write-ahead logs selected through `CURRENT`/`MANIFEST`, tombstones, and the primary/embedded document key hierarchy;
- legacy newline-delimited NeDB `.db` collections, including tombstones;
- standalone Foundry document JSON and JSON arrays;
- Foundry Adventure documents and their recursively embedded primary documents;
- `.mrpgfoundry` exports produced by the optional bridge module in `Integrations/FoundryVTT/masterrpg-bridge`;
- Universal VTT / DungeonDraft `.uvtt` and `.dd2vtt` maps.

Foundry `.bak` backup encoding is not treated as ZIP because Foundry does not document that internal encoding as a portable interchange contract. Restore a backup in Foundry and use the bridge, or select its extracted world data instead.

Foundry v11 and later stores packs as full LevelDB directories. MasterRPG merges current records across SSTables by sequence, honors deletion records, reconstructs embedded document keys recursively, and rejects ambiguous/corrupt records. The relevant Foundry references are [LevelDB compendium packs](https://foundryvtt.com/article/v11-leveldb-packs/), [document hierarchy](https://foundryvtt.com/article/v11-document-hierarchy/), and the official [Foundry CLI](https://github.com/foundryvtt/foundryvtt-cli).

## Projection into MasterRPG

Every enabled Foundry document remains present in the normalized source archive. Chat, User documents, and common ownership identifiers are recursively removed unless the user explicitly enables those privacy categories. Duplicate collection/embedded arrays are normalized into one document representation to bound archive size. Documents with a useful MasterRPG representation are additionally projected as follows:

| Foundry content | MasterRPG projection |
| --- | --- |
| Actor | Character, NPC, monster, or game-master `ValueModel`; scalar `system` leaves become typed entries |
| Embedded Actor Item | Hidden Character item group linked from its owner |
| Standalone Item / compendium rule | Character item; complete raw rule remains available to RuleRPG |
| Scene | Map plus packaged background Photo; Foundry v14 Levels become grouped Maps with elevation metadata |
| Token | Stable Map pin linked to its Actor and packaged token image when available |
| Wall / door | Native persisted `MapWallModel`, including movement/sight restrictions, door type/state, elevation, level metadata, source identity, and raw metadata |
| Journal / page | Adventure and entries; image/PDF pages link to imported media |
| RollTable / result | Table entries plus a Dice model for directly representable formulas |
| Playlist / sound | Audio playlist linked to imported tracks |
| Cards / Card | Table collection and entries; card art becomes Photo content |
| Adventure | Adventure/campaign linking all projected embedded documents |
| Combat / Combatant | Reference Adventure; it is not turned into live battle state |
| ChatMessage | One reviewable transcript per collection; disabled by default for privacy |
| Macro | Supplement text marked non-executable |
| Folder | Stable destination-specific folders with reconstructed parent hierarchy |
| Packaged image/audio/PDF/USDZ | Photo, Audio, PDF, or 3D model with lazy, hash-verified installation |

Active effects, permissions (when explicitly enabled), regions, drawings, tiles, light behavior, fog state, complex rolls, card hands/piles, unsupported codecs, custom document families, and system/module-specific fields remain field-complete in the normalized archive when MasterRPG has no faithful runtime equivalent. They are reported as raw-only rather than silently discarded or coerced into a misleading model.

Universal VTT conversion creates a Photo and Map, uses the declared map size and grid scale, converts grid-intersection coordinates and crop origin into image pixels, persists `line_of_sight` and `objects_line_of_sight` segments as walls, and converts portals into doors. The complete bounded VTT payload—not only its embedded image—is fingerprinted for source identity, so two maps that share artwork but contain different geometry remain distinct. Lights remain in the raw archive until MapRPG has a spatial-light model. Universal VTT is a community interchange convention rather than a single vendor-owned standard, so the reader accepts the commonly implemented fields conservatively.

## Stable identity and links

All projected IDs are deterministic UUID-v8 values derived from an explicit source-scope UUID, complete canonical Foundry identifier, destination, and semantic suffix. Names, localized labels, and package versions are not projected-item identity. For a source's first import, its scope converges across unsynchronized devices by preferring a bridge instance UUID, then a package semantic identifier, then a bounded source fingerprint; only sources without those facts fall back to physical file identity or path. A content hash can therefore seed the initial source scope, but later content changes do not replace a scope already recorded in the registry. A small coordinated `ExternalImportSourceRegistry` follows renames by file identity and is stored in the app's iCloud documents container when available. The versioned archive supplies a second synced identity ledger after reinstall or on another device. Systems/modules can reuse their unique semantic package identity; copied worlds, replaced paths, and arbitrary VTT files require the user to choose **Update existing import** or **Import as a new source**. An explicit new-copy choice receives a distinct scope. Commit atomically revalidates and claims that choice before domain mutation; a stale review is remapped or returned for a fresh choice instead of creating duplicate identities. Re-importing a later release therefore proposes updates to the same items without silently conflating copied sources.

Assets use package identity plus normalized logical path for identity and SHA-256 for content comparison. Replacing an asset updates the same item while unchanged bytes are reused. Foundry `@UUID[...]` references are rewritten to MasterRPG deep links when the destination can be resolved. The archive mapping ledger retains one-to-many Foundry-to-MasterRPG references for later repair and RuleRPG use.

## Review, commit, and rollback

`ExternalImportBatch` is a shared CoreRPG boundary for partial external imports. Staging creates domain models and lazy attachment closures only. It performs no Core Data insertion and no file write.

The review screen provides:

- source type and package statistics;
- content-family toggles;
- missing, remote, Foundry-installation, and unsupported asset reporting;
- license/attribution text found in the source;
- raw-only record counts and transport diagnostics;
- New / Changed / Up-to-date conflict labels, merge/replace/skip per item, bounded batch warnings, bulk decisions, and destructive confirmation for Replace All;
- commit and repair progress.

Commit orders dependencies as media → dice → tables/characters → maps → adventures, installs only accepted assets, repairs folders and links, flushes all module operations, and performs one consolidated save. It never infers deletion from an absent document. Asset writes must be durable and hash-verifiable before an item can be saved. On cancellation or error, imported items, repair-touched parents, link/tag indexes, and newly created files are rolled back and the restored snapshots are saved; persistence and cleanup failures are surfaced explicitly instead of being reported as successful. Replaced binaries are removed only after the new models are durably committed. An app-wide mutation token prevents Foundry import, native import, and validation from mutating concurrently, while reference-counted save deferrals cannot be cleared by another operation.

On supported Apple platforms, `.uvtt`, `.dd2vtt`, and `.mrpgfoundry` are registered as distinct document types and open directly into the Foundry review tab. Generic `.json` and `.zip` are intentionally not claimed by the app.

## Security and licensing

All VTT input is untrusted data:

- JavaScript and macros are never evaluated.
- Imported HTML is reduced to plain text for current views; original HTML remains only in the archive.
- ZIP paths, bridge paths, duplicate canonical IDs, traversal, encrypted entries, size/decompression/text/record/diagnostic budgets, CRCs, LevelDB checksums, asset lengths, and SHA-256 hashes are validated. Newline-delimited databases and bridge exports are scanned lazily rather than split into unbounded line arrays.
- Universal VTT resolution and geometry must be finite and remain within point/portal/light limits; Foundry scene geometry is range-checked before projection; Base64 length is checked before allocation and embedded images must have a valid PNG, JPEG, or WebP signature.
- Remote and Foundry-installation assets are reported but never fetched automatically.
- Chat and user information require deliberate handling. Both categories are off by default; disabled chat and User documents are not written to the RuleRPG archive, and common ownership identifiers are scrubbed unless enabled.
- The UI reminds the user to import and redistribute only content covered by the applicable world, system, module, and asset licenses.

## Foundry bridge

The optional v12–v14 bridge is a small Foundry module:

```text
Integrations/FoundryVTT/masterrpg-bridge/
```

Copy it to Foundry's `Data/modules` directory, enable **MasterRPG Bridge**, then use **Game Settings → Export for MasterRPG**. It emits UTF-8 JSON Lines with a versioned manifest, a stable per-export-source instance UUID, raw document records, hash-verified Base64 assets, explicit unresolved asset references, and a validated count footer. Only a GM can export. System/module assets, chat, and users have explicit privacy/licensing controls; disabling users also recursively removes common ownership metadata. Assets are fetched sequentially, never from remote URLs, and are capped at 64 MiB each / 128 MiB total. The module also exposes `exportWorld`, `exportAdventure`, and `exportDocuments` through its Foundry module API.

## RuleRPG boundary and DS4 validation

`FoundryRulePackage` remains the normalized, system-agnostic rule view of compatible system packages. `FoundryImportArchive` adds the complete generic document hierarchy, raw envelopes, resource descriptors, diagnostics, and projection ledger. A future RuleRPG module should consume those public CoreRPG types and implement reviewed system adapters; it must not execute Foundry system JavaScript.

The supplied DungeonSlayers 4 v2.0.5 package currently validates as:

| Compendium | Top-level rules | Embedded items | Active effects |
| --- | ---: | ---: | ---: |
| Special creature abilities | 58 | 0 | 1 |
| Languages and scripts | 11 | 0 | 0 |
| Equipment | 325 | 0 | 197 |
| Spells | 132 | 0 | 0 |
| Creatures | 105 | 394 | 5 |
| Racial abilities | 26 | 0 | 13 |
| Talents | 123 | 0 | 37 |
| **Total** | **780** | **394** | **253** |

The generic transport produces 7 collections, 780 top-level documents, 647 embedded documents, and 537 resource descriptors. The dedicated rule view still derives all 780 normalized rules. This fixture verifies the future RuleRPG boundary while the same input can now also project actors, items, folders, and licensed packaged media through the normal import review.
