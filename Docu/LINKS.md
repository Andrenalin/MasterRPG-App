# Link System

This document describes every link mechanism used by MasterRPG: the URL format,
content editing, parsing, registration, Core Data persistence, rendering,
actions, sheet construction, deep-link navigation, validation, import/export,
and the identity rules that allow the same destination to be linked more than
once.

Related docs:

- [Architecture](Architecture.md)
- [Controllers](CONTROLLERS.md)
- [Database Handling](DATABASE.md)
- [Root Models And Setup](ROOT_MODELS.md)
- [Game Connections](GAME_CONNECTIONS.md)

## Terminology

The word "link" is used for several related but different things:

| Term | Meaning |
|---|---|
| Source | The item or entry that owns a reference. For Markdown links, this is the text containing the link. |
| Destination | The item or entry named by the reference. |
| Occurrence | One appearance of a destination in one source text, identified by `linkNumber`. |
| Embedded content link | Markdown stored in a domain model's text, such as an Adventure entry's content. |
| Structural reference | A typed UUID field such as `photoId` or `diceId`; it is not Markdown. |
| Action link | A generated Markdown link with a command such as `show`, `remove`, or `roll`. |
| Register entry | A `LinkRegisterModel` indexing one source-to-destination relationship. |
| Sheet occurrence | A `SheetModel` created for one linked appearance in a sheet tree. |
| Deep link | An `RPG://` URL opened by the operating system to navigate into the app. |
| Transfer link | A `Transferable` drag/drop payload used to create or move a link. |

The domain model remains the source of truth. Embedded Markdown and structural
UUID fields are persisted with their owning module. `LinkReferenceDataModel`
is a derived, persistent index used for fast incoming and outgoing lookups.

## Link Kinds At A Glance

| Kind | Stored where | Registered | Main purpose |
|---|---|---|---|
| Embedded item/entry link | Owning item's text field | Yes, for models that implement `ItemLinkRegistable` | Cross-module content and expandable sheet rows |
| Structural UUID reference | Owning item's typed property | Yes, where the model emits a register entry | Photos, dice, pins, and other non-text relationships |
| Action link | Normally generated into display text only | It may be parsed, but `command != nil` excludes it from sheets | Show, remove, play, roll, share |
| App deep link | Incoming URL or `NSUserActivity` | No | Navigate to a module, item, or entry |
| Drag/drop link | Codable `Transferable` payload | No; the resulting model edit is registered | Create a content or structural link |
| Legacy short link | Legacy Markdown `RPG://UUID[/COMMAND]` | Not used by the current register path | Compatibility parsing only |

## End-To-End Data Flow

```mermaid
flowchart TD
    "Link picker or drag/drop" --> "EntryDataEditable.add"
    "EntryDataEditable.add" --> "Domain text or structural UUID field"
    "Attributed EntryEditor" --> "Domain text or structural UUID field"
    "Domain text or structural UUID field" --> "EditControllable.saveChanges"
    "EditControllable.saveChanges" --> "ItemLinkRegistable diff"
    "ItemLinkRegistable diff" --> "LinkRegisterController"
    "LinkRegisterController" --> "Incoming index by destination"
    "LinkRegisterController" --> "Outgoing index by source"
    "LinkRegisterController" --> "LinkReferenceDataModel"
    "Domain text or structural UUID field" --> "Module Core Data model"
    "Domain text" --> "LinkReplaceController"
    "LinkReplaceController" --> "Link renderer and actions"
    "Outgoing index by source" --> "SheetController"
    "SheetController" --> "Occurrence-specific SheetModel"
```

## RPG URL Grammar

The app scheme is `RPG`. Scheme and module-host recognition are
case-insensitive.

### Stored content links

```text
[Name](RPG://MODULE/LINK_NUMBER/ITEM_UUID)
[Name](RPG://MODULE/LINK_NUMBER/ITEM_UUID/ENTRY_UUID)
```

Examples:

```text
[Orc](RPG://VALUES/0/11111111-1111-1111-1111-111111111111)
[Armor](RPG://TABLES/0/22222222-2222-2222-2222-222222222222/33333333-3333-3333-3333-333333333333)
```

### Action links

```text
[Action](RPG://MODULE/ACTION_NUMBER/ITEM_UUID/COMMAND)
[Action](RPG://MODULE/ACTION_NUMBER/ITEM_UUID/ENTRY_UUID/COMMAND)
```

Example:

```text
[Show](RPG://VALUES/601/11111111-1111-1111-1111-111111111111/show)
```

### URL component mapping

`URL+ItemId.swift` interprets an `RPG://` URL as follows:

| URL part | Property | Meaning |
|---|---|---|
| Host | `moduleIdentifier` | `NetworkModules` destination |
| First path component | `linkNumber` | Content occurrence or action number |
| Second path component | `itemId` | Destination item UUID |
| Third component, when it is a UUID | `childId` | Destination entry UUID |
| Third or fourth component | `commandKey` | Command, depending on whether an entry UUID exists |

An absent or invalid link number becomes `0`. An invalid item or entry UUID
becomes `nil`.

### Module tokens

Content and navigation links recognize these module hosts:

| Module | Token |
|---|---|
| Adventure | `ADVENTURES` |
| Audio | `AUDIOS` |
| Character/value | `VALUES` |
| Dice | `DICE` |
| Game | `GAME` |
| Map | `MAPS` |
| PDF | `PDFS` |
| Photo | `PHOTOS` |
| Rule | `RULES` |
| Space/3D object | `SPACES` |
| Table | `TABLES` |
| Weather | `WEATHERS` |

`NetworkModules` also defines tokens for app-only destinations such as editor,
generator, search, and settings, but `UserActivity.extractModule` does not
accept those as content-link destinations.

### Legacy formats

`ReferenceScanner.parseUrlsUuid` still recognizes:

```text
[Name](RPG://UUID)
[Name](RPG://UUID/COMMAND)
```

The active `LinkReplaceController` and link register use the module-addressed
format. The legacy short format is compatibility support, not the format for
new content.

## Parsing And Normalization

`ReferenceScanner` uses regular expressions to parse:

- item links with and without a command;
- entry links with and without a command;
- legacy short links with and without a command.

Names may contain any characters except `]`. Module and command tokens are
alphabetic. Link numbers are non-negative decimal integers. Item and entry
components are accepted by the regular expression first, then validated as
UUIDs. Invalid UUID links are ignored and logged.

`LinkReplaceController.links(for:)` converts scanner output into
`LinkReplaceModel` values containing:

- display name;
- destination module;
- link number;
- item and optional entry UUID;
- exact Markdown;
- optional command;
- range in the source string.

For regular links, it normalizes occurrence numbers in encounter order:

- item-level links count separately for each destination item UUID;
- entry-level links count separately for each destination item/entry pair;
- command links retain their encoded action number.

`linksRepair(for:linkControllable:)` also rewrites incorrect regular occurrence
numbers in the supplied text copy. `removeLinks(for:)` replaces recognized
Markdown with its display name. `updateLinks(for:)` upgrades the older
module-addressed format that omitted `LINK_NUMBER`.

The scanner returns command links before regular links and item links before
entry links. Callers that need source order must sort `LinkReplaceModel.range`,
as the renderer tests do.

## Occurrence Identity And Duplicate Links

The same item may be linked more than once from the same entry. These are not
duplicate database objects; they are distinct occurrences of one destination.

For two Orc links, the stored content is:

```text
[Orc](RPG://VALUES/0/ORC_UUID) [Orc](RPG://VALUES/1/ORC_UUID)
```

The identity layers are:

| Layer | Identity |
|---|---|
| Destination domain item | `ORC_UUID` |
| Content occurrence | source + destination + `linkNumber` + command |
| `LinkRegisterModel` instance | its own UUID `id` |
| Sheet occurrence | its own UUID `SheetModel.id`, plus `linkNumber` for link matching |

`EntryDataEditable.addLinkInEntry` calculates the next number by finding the
maximum existing number for the same destination item and optional destination
entry in that text, then adding one. The first Orc is `0`, the second is `1`.

`LinkRegisterListModel` does not deduplicate by destination UUID alone. Its
occurrence key is:

```text
source + destination + linkNumber + command
```

Consequently, two Orc links with numbers `0` and `1` produce two register
records with two UUIDs.

`SheetModel.id` is initialized with a new UUID and equality/hashing use only
that UUID. It deliberately does not use the destination item UUID, because the
same item can appear in multiple positions or branches. Rebuilding an entire
sheet creates new occurrence IDs; an in-place Adventure sheet update reconciles
children by source and link number so existing row IDs and UI state are
preserved when possible.

### Can both identical destinations be toggled?

Yes. `LinkHighlightTextModel` passes the clicked base occurrence to
`SheetRootModel`. The sheet lookup first matches:

```text
destination item UUID + linkNumber
```

Only an unnumbered structural child may use the fallback, and only if exactly
one such child exists. Therefore clicking Orc occurrence `0` toggles the first
Orc sheet, and clicking occurrence `1` toggles the second independently.

This guarantee is occurrence-scoped. It does not mean the Orc domain item has
two identities, and it does not require destination UUIDs to differ.

## Creating Links

### Model URL helpers

`ItemDataAccessable` is the canonical generator for regular Markdown:

- `urlAdr(linkNumber:)` builds an item URL;
- `urlAdr(linkNumber:entryId:)` builds an entry URL;
- `urlName` removes any nested link markup from the displayed name;
- `url(linkNumber:)` and its entry variant wrap the URL in Markdown.

`LinkControllable.generateLink` delegates to these helpers.

### Link picker

`EditorLinkModel` owns selection state for every linkable module. When the user
accepts selected rows, it resolves the destination model and calls the source
module's `EntryDataEditable.add`.

The default `add` implementation:

1. checks `canAddLink`;
2. trims the source entry content;
3. calculates the next occurrence for the destination;
4. appends Markdown with the requested separator;
5. saves the changed owning item.

The save invokes the normal link-register diff.

### Editor capabilities by source module

| Source editor | Offered destinations | Important behavior |
|---|---|---|
| Adventure | Adventure, Audio, Character, Dice, Map, PDF, Photo, Rule, Space, Table, Weather | Regular item or entry Markdown in Adventure entry content |
| Rule | Adventure, Audio, Character, Dice, Map, PDF, Photo, Rule, Space, Table, Weather | Regular item or entry Markdown in Rule entry content |
| Map | Audio, Character, Dice, Map, PDF, Photo, Table | Audio/Dice/Map/PDF/Photo are regular links; Table and Character accept item-level selections; Character also creates monster/pin data |
| Character | Character, Dice, PDF, Table | Character requires an entry and appends with `+`; Table entry links are stored in the source entry name; Dice sets `diceId`; PDF uses content |
| Table | Dice, PDF, Table | Regular Markdown in Table entry content |
| PDF | None | The entry editor exposes no link destinations |
| Other modules | Default none | They can still be destinations and may render links from model text |

The picker restrictions and the parser are separate. The parser can recognize a
valid URL even when a particular editor would not offer that combination.

### Quick-link scanning

`LinkControllable.link(for:)` and `linkEntries(for:)` expose candidate
`LinkEntryModel` values for name-based linking. Adventure, Character, Dice,
Map, Rule, and Table provide module-specific candidates.

`EntryDataEditable.scanReplace` can replace matching plain-text references with
candidate Markdown while:

- optionally matching case-insensitively;
- optionally requiring a word boundary;
- skipping ranges already inside links.

`QuickLinkConfig`, and `QuickLinkEditor` provide the
selection and before/after preview infrastructure. This path still produces the
same Markdown format and must save through the owning editor to update the
register.

### Drag and drop

Every supported module has a `LinkDataTransferable` Codable payload containing:

- module;
- item UUID;
- optional entry UUID;
- name;
- whether the operation is a move.

Module-specific `UTType` values prevent unrelated payloads from being accepted.
The proxy string representation always uses occurrence `0`, but the transfer
payload itself is not persisted in Core Data. The drop handler performs the
normal editor add or move operation, which assigns the final occurrence and
updates the domain model/register.

## Attributed Entry Editor

`EntryEditorContent` creates one `TextEditModel` with the global
`LinkRegisterController` and an exact source `ItemRowModel`.

`TextEditModel` keeps name and content independently:

- raw `name` and `text`;
- attributed `attributedName` and `attributedText`;
- occurrence arrays `nameLinks` and `links`.

When converting raw Markdown to attributed text:

1. the register controller parses the field;
2. it reuses an existing occurrence matching source, destination, number, and
   command, or registers a new one;
3. Markdown is replaced by the display name;
4. the attributed run receives the register UUID in `linkContent`.

When converting edited attributed text back to Markdown:

1. each run is inspected for `linkContent`;
2. the UUID is resolved from the field's local occurrence array first;
3. the global register is the fallback;
4. the exact transient `markDown` is restored, or `urlMarkDown` is rebuilt.

The local-array-first lookup is important for repeated destinations. It keeps
the first and second Orc runs tied to their own register records.

Updates are debounced by 100 milliseconds. tvOS uses the simpler plain-text
editing path; other platforms use the attributed editor.

## Structural And Direct Domain Relationships

Not every relationship displayed as a linked sheet is Markdown or a register
entry. Several modules construct sheet structure directly from typed domain
fields:

| Module | Direct relationship | Sheet behavior |
|---|---|---|
| Adventure | `photoId` | Inline photo |
| Adventure | entry `adventureId` | Nested Adventure/group sheet |
| Audio | entry `audioId` | Resolves the referenced track |
| Character/value | item `photoId` and `diceId` | Inline photo and dice |
| Character/value | entry `diceId` | Inline entry dice |
| Character/value | entry `valueId` | Nested Character/value group |
| Map | `photoId` | Inline map photo |
| Table | `diceId` | Inline dice |

These direct edges do not need a Markdown occurrence number. Some are also
emitted to the link register for incoming/"used by" queries, while others are
consumed only from the domain model. `parentId` and `groupId` are hierarchy
fields and are handled by folder/group logic rather than the content-link
system.

## Link Register

### `LinkRegisterModel`

A register entry stores:

| Property | Purpose |
|---|---|
| `id` | UUID for this registered occurrence |
| `name` | Display name; empty for structural references |
| `source` | Owning item and optional entry |
| `destination` | Referenced item and optional entry |
| `linkNumber` | Content occurrence; `nil` for structural references |
| `command` | Action command; normally `nil` for stored content |
| `markDown` | Transient exact source Markdown; not persisted in the register entity |

`isSheetLink` is true when `command == nil`.

The UUID `id` is useful for attributed runs, but registry equivalence does not
depend on it. There is no Core Data uniqueness constraint on the optional
`uuid` column. Correct deduplication is provided by the occurrence key.

### Dual in-memory indexes

`LinkRegisterListModel` keeps every relationship in both directions:

| Index | Key | Consumer |
|---|---|---|
| `items` | destination item UUID | `isUsed`, "used by", deletion repair |
| `sourceItems` | source item UUID | outgoing entry links and sheet construction |

`linksFrom(source:)` filters the outgoing bucket by the complete source
`ItemRowModel`. It currently requires a non-`nil` source entry UUID, so it is an
entry-link API rather than a general item-level outgoing lookup.

`pendingAffectedSourceIds` records which source items need their persisted index
rows replaced.

### Which domain models emit register entries?

| Module | Embedded text registered | Structural references registered |
|---|---|---|
| Adventure | Entry `content` | Item `photoId` |
| Character/value | Entry `name` and `value` | Item `photos` and item `diceId` |
| Map | Entry `content` | Main `photoId` and map-pin photo IDs |
| Rule | Item `description` and entry `content` | None |
| Table | Entry `content` | Item `diceId` |
| Weather | None | `photoId` through change diffs |
| Audio, Dice, Generator, PDF, Photo, Space | None by default | None by default |

Some unregistered module text is parsed directly by its sheet or renderer. For
example, Audio sheets parse track descriptions directly, and Rule sheets parse
entry content directly instead of relying on `linksFrom`.

### Registration lifecycle

`EditControllable.saveChanges` is the normal lifecycle boundary:

1. get the old saved domain item;
2. ask the new item for added and removed register models;
3. deregister removed occurrences;
4. register added occurrences;
5. update undo state;
6. replace the domain item.

For a new item, the complete `linkRegisterModels` array is registered.

Validation uses `resetLinkRegister`: remove all rows whose source item matches,
then register the current domain model's complete list. Import uses the same
rebuild pattern in `ConvertController`. External import snapshots both indexes
and the pending set so a failed import can restore the registry atomically.

## Core Data Persistence

The shared register is owned and set up by the Adventure root, then supplied to
the other module roots through `RootManager`.

### Persisted entity

The current `Model.xcdatamodel` defines `LinkReferenceDataModel`:

| Field | Type | Meaning |
|---|---|---|
| `uuid` | optional UUID | Register occurrence ID |
| `name` | String, default `""` | Display name; empty for structural links |
| `sourceId` | optional UUID | Source item |
| `sourceEntryId` | optional UUID | Source entry |
| `sourceModule` | Int16, default `0` | Source `NetworkModules.rawValue` |
| `destinationId` | optional UUID | Destination item |
| `destinationEntryId` | optional UUID | Destination entry |
| `destinationModule` | Int16, default `0` | Destination module |
| `linkNumber` | Int64, default `-1` | Occurrence; `-1` encodes `nil` |
| `command` | optional String | Action command |

The raw Markdown is intentionally absent. It is reconstructed from the other
fields or captured transiently while parsing the domain text.

### Startup

`LinkRegisterController.setup(context:)` fetches every
`LinkReferenceDataModel`, converts it to `LinkRegisterModel`, and fills both
in-memory indexes.

For rows written before occurrence persistence existed:

- a non-negative `linkNumber` is used directly;
- a negative number with a non-empty name is assigned the next legacy
  occurrence for that source/destination pair;
- a negative number with an empty name remains `nil`, preserving structural
  reference semantics;
- a missing persisted UUID receives a new in-memory UUID.

With a `nil` context, as in previews and some tests, the register works only in
memory.

### Saving

Register changes are coalesced by source item. `savePendingLinks`:

1. snapshots `pendingAffectedSourceIds`;
2. gathers the current in-memory relationships for those source IDs;
3. batch-deletes their existing `LinkReferenceDataModel` rows;
4. batch-inserts the current rows;
5. clears the pending set.

It does not call `context.save()` itself. `AdventureRootModel.save` first
flushes all module changes, then saves pending links and tags, then performs one
shared context save. `saveExternalImport` follows the same aggregation and
propagates the final persistence error.

`resetData` clears both indexes and batch-deletes all register rows.

### Model migration and CloudKit

CoreRPG currently has one development model version,
`Model.xcdatamodel`. Before the schema was shipped, the occurrence fields were
squashed into that V1 definition:

- optional `command`;
- `linkNumber` with default `-1`.

Both local and CloudKit persistent-store descriptions explicitly enable
automatic store migration and inferred mapping. There is no CoreRPG V1-to-V2
migration because the former V2 was never shipped and was folded back into V1.
For the next schema change after release, preserve this V1 model, create V2,
make V2 current, and test the inferred lightweight migration from V1.

The entity is CloudKit-syncable, and its attributes follow CloudKit-compatible
optional/default rules. After a CloudKit production schema is deployed,
existing record types and fields cannot be removed or changed incompatibly;
new fields must be deployed and tested in the CloudKit schema as part of a
release.

The generic `CoreDataController` explicitly avoids batch requests because
CloudKit mirroring may not export their changes. The link register currently
uses `NSBatchDeleteRequest` and `NSBatchInsertRequest`. This implementation
difference needs CloudKit integration verification; see
[Known Constraints And Review Findings](#known-constraints-and-review-findings).

## Display, Highlighting, And Interaction

`LinkHighlightTextModel.displayText` repairs occurrence numbers in a display
copy, splits the string into highlighted components, and attaches each
`LinkReplaceModel` to custom text attributes.

`LinkHighlightTextRenderer` measures link runs. `LinkHighlightTextView` places
accessible transparent `Button` overlays on those measured regions. A button
click calls `LinkHighlightTextModel.handle`.

Handling a click:

1. extracts the URL from the exact Markdown;
2. repairs regular occurrence numbers in a text copy;
3. converts an action number to its base occurrence with `linkNumber % 100`;
4. dispatches to the destination module's `LinkControllable`;
5. updates the rendered text.

Regular links expand inline. `String.toggleLink` encloses generated detail text
between the internal expansion markers `➡️` and `⬅️`. Clicking the same link
again removes that generated section. Remove actions replace the original
Markdown with its plain display name.

The Adventure link controller acts as the cross-module dispatcher for
Adventure-rendered content. Rule has a similar cross-module forwarding path for
Rule content.

## Action Links

`LinkType` reserves hundred ranges while preserving the base occurrence:

| Action | Command | Addition |
|---|---|---:|
| Play | `play` | 200 |
| Remove | `remove` | 300 |
| Roll | `roll` | 400 |
| Share | `share` | 500 |
| Show | `show` | 600 |
| Favorite | `favorite` | 700 |

For regular occurrence `1`, Show is `601`, Share is `501`, and Remove is `301`.
`specialLink` does not add another offset when the supplied number is already
at least `100`.

Action availability is context-sensitive:

| Destination module | Generated/handled actions |
|---|---|
| Adventure | Expand, Show, Remove |
| Audio | Expand, Play/Pause, Show, Share, Remove |
| Character/value | Expand, Show, Share, Remove |
| Dice | Roll, Show, Share, Remove |
| Map | Expand, Show, Share, Remove |
| PDF | Expand, entry Show, Share, Remove |
| Photo | Expand, Show, Share, Remove |
| Rule | Expand, entry Show, Remove; cross-module dispatch |
| Space | Expand, Show, Share, Remove |
| Table | Expand, entry Show, Share, Remove |
| Weather | Expand, Show, Share, Remove |
| Generator | No interactive link behavior |

Buttons are only generated when their required capability exists. Examples:
Show requires a sheet toggler, Share requires game/network actions, and Remove
requires an editor callback that allows editing the source row.

`favorite` has a reserved number, title, and icon but no current module handler
generates or executes it.

Action links are display controls, not independent content relationships.
Sheet controllers exclude `command != nil` links.

## Sheet Construction

Adventure, Character, Map, and Table sheet controllers obtain outgoing
entry links from `LinkRegisterController.linksFrom`. Audio and Rule currently
parse relevant text directly. All paths exclude action links.

For every eligible regular occurrence, the destination module's
`SheetController` creates a linked `SheetModel`, then copies the content
occurrence to `SheetModel.linkNumber`.

The linked row starts hidden. Linked Adventures and other recursive module
trees may be represented as folded placeholders and materialized only when
opened. This prevents recursively constructing the complete graph.

### Sheet identity

`SheetModel.id` is a UUID created for the sheet occurrence. It is:

- unique for the separately created rows under normal UUID generation;
- independent from `source.itemId`;
- the sole basis of `Equatable` and `Hashable`;
- not persisted as the destination's identity;
- preserved during supported in-place reconciliation, but not guaranteed
  across a complete sheet rebuild.

`source` identifies the domain item or entry represented by the row.
`destination` records the owning sheet context. Multiple rows may therefore
have the same `source` and still have different `id` and `linkNumber`.

### Toggle matching

`SheetRootModel` receives the base occurrence from the clicked text link. It
searches for an exact destination item plus link-number match. A fallback is
allowed only for one unnumbered structural child.

This exact match is why two links to the same Orc can coexist:

| Row | `source.itemId` | `linkNumber` | `SheetModel.id` |
|---|---|---:|---|
| First Orc | same Orc UUID | `0` | UUID A |
| Second Orc | same Orc UUID | `1` | UUID B |

Toggling row `0` does not change row `1`, and vice versa.

## Navigation And `NSUserActivity`

The same `RPG://` grammar is also accepted as an app URL, but navigation and
embedded-link handling are separate consumers.

`RootURLHandler`:

1. handles supported import-document URLs first;
2. extracts the module, item UUID, and optional entry UUID;
3. queues the route when app setup is not ready;
4. otherwise routes through the correct window's `Navigator`.

Navigation ignores link occurrence and action semantics. It uses the module,
item, and child UUID.

`NSUserActivity` stores:

- module token;
- item UUID;
- optional child UUID.

Activities are eligible for Search and Handoff. The iOS/visionOS/tvOS scene
delegate restores them through `routeToModuleWhenReady`.

Opening a deep link or activity does not create a `LinkReferenceDataModel`.
Only a domain model edit or register rebuild creates a persisted relationship.

`.gmz`, `.uvtt`, `.dd2vtt`, and `.mrpgfoundry` file URLs are import-document
requests, not RPG content links.

## Validation, Repair, And Deletion

`validateLink` checks that a destination item exists and, for an entry link,
that the entry exists.

Clicking a broken link replaces its expansion with a warning such as:

```text
🚨 Character Link is broken
```

`repairLink` tries a name-based recovery:

- for a missing entry, it first checks whether the destination item remains,
  then looks for a matching entry name;
- for a missing item, it searches the permitted destination categories by
  name;
- when recovery fails, it replaces Markdown with the plain link name.

Each module's `repairLinks` delegates to the destination controllers it permits.
`validateLinks(on:)` also cleans invalid structural UUID references and rebuilds
the source item's register rows.

Before deleting a destination, `resetUsedLink` removes matching incoming
relationships from both in-memory indexes and marks affected sources for
persistence. `repairLinks(for:)` asks each affected source module to validate
its actual domain data.

`used(for:)` resolves incoming register entries back to source item and optional
entry names for "used by" UI.

## Import, Export, And Game Data

Import does not always pass through `EditControllable.saveChanges`, so
`ConvertController` rebuilds the register for repaired imported items.
External import snapshots and restores both register indexes on rollback.

Export and game dependency traversal are module-specific through
`LinkControllable.collectLinks`. The persistent register is not the sole
dependency graph for export. Controllers may parse embedded text, inspect
structural UUID fields, and recursively add linked item IDs according to the
module's export contract.

When adding a new link-bearing field, update both:

1. its `ItemLinkRegistable` production/diff so "used by", sheets, and deletion
   repair see it;
2. the module's collection/export behavior if the destination must travel with
   exported or game data.

## Test Coverage

The principal regression suites are:

| Tests | Coverage |
|---|---|
| `Tests/CoreRPGTests/LinkReplaceControllerTests.swift` | Item/entry/action parsing and occurrence repair |
| `Tests/CoreRPGTests/StringLinkTests.swift` | Expansion, replacement, and nested expansion markers |
| `Tests/CoreRPGTests/LinkHighlightTextModelTests.swift` | Rendering components and clicked occurrence propagation |
| `Tests/CoreRPGTests/LinkHighLightLocationTests.swift` | Measured link hit regions |
| `Tests/CoreRPGTests/ResetEntryTests.swift` | Attributed editor Markdown round trips |
| `Tests/CoreRPGTests/URLRoutingTests.swift` | Case-insensitive scheme/module parsing |
| `Tests/CharacterRPGTests/LinkRegisterControllerTests.swift` | Dual source/destination indexing |
| Per-module `LinkControllerTests.swift` | Module action, expansion, repair, and collection behavior |
| Per-module `SheetControllerTests.swift` | Linked sheet materialization |
| `Tests/AdventureRPGTests/SheetControllerTests.swift` | Duplicate Orc end-to-end regression |

The duplicate-Orc regression verifies:

- two links are always present;
- they parse as occurrences `0` and `1`;
- the register contains two distinct UUIDs;
- `TextEditModel` displays both and restores the exact Markdown;
- the sheet contains two distinct `SheetModel.id` values;
- toggling either occurrence changes only that row.

`LinkHighlightTextModelTests.duplicateLinkTogglerReceivesClickedOccurrence`
also verifies that both a regular `1` link and a generated Show `601` action
route to base occurrence `1`.

## Extending The Link System

When introducing a new destination module, command, or source field:

1. add or confirm its `NetworkModules` token and `UserActivity` mapping;
2. add URL-generation support through `ItemDataAccessable`;
3. update the source editor's `linkModules`, `canAddLink`, and `add` behavior;
4. add a module-specific `LinkDataTransferable` and `UTType` when drag/drop is
   required;
5. parse the field in `ItemLinkRegistable` and implement accurate old/new diffs;
6. update `LinkController` handling, validation, repair, and dependency
   collection;
7. materialize eligible regular links in `SheetController`;
8. keep action links out of sheet rows;
9. verify local Core Data migration and CloudKit schema compatibility for any
   persistence changes;
10. test two occurrences of the same destination, not only two different
    destinations.

## Known Constraints And Review Findings

These describe the current implementation and should be considered when
changing link code:

1. **Occurrence numbers are field-local.** Numbering is computed inside one
   source string. It is not globally unique and is not intended to be.

2. **Character entry name and value share one register source.** They are parsed
   separately, but both use the same source item/entry. If the same destination
   receives the same occurrence number and command in both fields, the register
   occurrence key can collapse them. A future field discriminator or
   cross-field numbering policy would remove this ambiguity.

3. **Action ranges reserve two decimal digits for the base occurrence.**
   `LinkHighlightTextModel` uses `% 100`. Occurrences `0...99` route as
   intended; a source with 101 identical destinations would alias occurrence
   `100` to `0` during action/toggle routing.

4. **Character numeric-type checks are always true.** The Dice and Character
   link-add paths test `type != .number || type != .decimal`. Every value is
   unequal to at least one of those cases, so linking always resets the source
   entry type to `.number`, including an existing `.decimal`. Preserving both
   numeric types requires `&&`.

5. **Map-pin photo register sources use `.value`.** `MapModel` currently emits
   map-pin photo structural references with source module `.value`, while its
   main photo and entry links use `.map`. This can route "used by" validation
   through the wrong module.

6. **Weather photo register sources use `.adventure`.** `WeatherModel` currently
   emits its structural photo reference with source module `.adventure` rather
   than `.weather`.

7. **Weather does not override the complete `linkRegisterModels` property.**
   Its change-diff can register a photo during normal editing, but a full
   new-item/import rebuild receives the protocol's empty default. Its structural
   link may therefore be absent after that path.

8. **Not every direct sheet relationship is registered.** Adventure entry
   `adventureId`, Audio entry `audioId`, Character item `photoId`, and Character
   entry `diceId`/`valueId` are consumed directly from domain models. They are
   not emitted by the current `ItemLinkRegistable` implementations, so the
   register alone is not a complete sheet or dependency graph.

9. **`linksFrom` is entry-only.** It returns no results when `source.entryId` is
   `nil`. Item-level Rule description links and structural relationships must be
   consumed through direct parsing, incoming lookup, or another path.

10. **Register IDs have no persistent uniqueness constraint.** UUID generation
   makes collisions extremely unlikely, but correctness currently relies on the
   occurrence key, not Core Data enforcing unique `uuid`.

11. **Batch register persistence needs CloudKit verification.**
   `LinkRegisterController` uses Core Data batch delete/insert while the generic
   persistence controller avoids batch requests specifically because mirrored
   stores may not export them. The register is derived and repairable, but its
   cross-device persistence behavior should have an integration test.

12. **Malformed numbers are repaired first in a display copy.** Hand-authored
    or imported repeated links with incorrect numbers become correct when saved
    through the repair/editor flow. Rendering alone does not necessarily update
    the authoritative domain string.

13. **`favorite` is reserved but unimplemented.** It should not be treated as a
    supported user action until a module handler and tests exist.

14. **The current CoreRPG schema is a development-only V1 squash.** There is no
    V1-to-V2 migration to test because V2 was not shipped. The next schema
    version must retain V1 as its source model and add store-level lightweight
    migration coverage. CloudKit mirroring still needs an integration test.

## Source Map

The central implementation files are:

- `Modules/CoreRPG/App/URL+ItemId.swift`
- `Modules/CoreRPG/App/UserActivity.swift`
- `Modules/CoreRPG/Links/ReferenceScanner.swift`
- `Modules/CoreRPG/Links/ReferenceLinks.swift`
- `Modules/CoreRPG/Links/LinkReplaceController.swift`
- `Modules/CoreRPG/Links/LinkRegisterListModel.swift`
- `Modules/CoreRPG/Links/LinkRegisterController.swift`
- `Modules/CoreRPG/Controllable/LinkControllable.swift`
- `Modules/CoreRPG/ItemList/ItemDataAccessable.swift`
- `Modules/CoreRPG/ItemList/EntryDataEditable.swift`
- `Modules/CoreRPG/Links/QuickLinkConfig.swift`
- `Modules/CoreRPG/ItemViews/QuickEditorAction.swift`
- `Modules/CoreRPG/Editors/QuickLinkEditor.swift`
- `Modules/CoreRPG/EntryEditor/TextEditModel.swift`
- `Modules/CoreRPG/Model/EditorLinkModel.swift`
- `Modules/CoreRPG/Model/LinkDataTransferable.swift`
- `Modules/CoreRPG/LinkRenderer/LinkHighlightTextModel.swift`
- `Modules/CoreRPG/LinkRenderer/String+Link.swift`
- `Modules/CoreRPG/Sheet/SheetModel.swift`
- `Modules/CoreRPG/Sheet/SheetRootModel.swift`
- `Modules/RolePlayGameKit/Router/RootURLHandler.swift`
- each module's `Controller/LinkController.swift`,
  `Controller/SheetController.swift`, and link-bearing domain model.
