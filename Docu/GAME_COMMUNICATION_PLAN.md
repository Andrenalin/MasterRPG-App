# Game Communication Plan — Envelope Redesign And Regression Repair

Status: executed (2026-07-10) except the open questions at the end. Since V2
was never released, the redesign landed **in V2 itself** — no V3 generation.
The envelope now carries `sender` + master-only `masterState` + `targetId`;
only the shipped 2.6 app (V1) needs mappers.

Executed:

- A1/F1 targeted responses via `targetId` (applies to the master's local player too)
- A1/F2 covered by targeting (untargeted full-reveal broadcasts no longer occur)
- A1/F3 repair-loop guard (`requestedRepairIds`, released only on successful repair)
- A1/F4 `CloudDocumentController.fullUrl` reduces absolute urls below `Documents/<module>`
- A2/H1 V1 mappers + superset encoding (previous step)
- A2/H2 dedup key includes payload presence
- B: `GameSenderModel` + `GameMasterStateModel` in the V2 envelope; roster/controls
  only from master messages; controls filtering by id; `MasterGameModel.characterId`
  removed; `adventureId`/`adventureTitle` travel in `masterState`
- C2 done with H2; C1 done via `targetId`

Open: C3 (per-item journal slots), C4 (proxyCounter), two-device SharePlay
smoke test, observer/proxy role questions below.

Prerequisite (done): `GameNetworkModel` V1 restored with bidirectional mappers
(`GameNetworkModelV1.v2Model` / `GameNetworkModel.v1Model`), V2 stamped as
`currentVersion == 2`, superset encoding so V1 / intermediate / V2 peers decode
the same bytes. Covered by `GameNetworkModelVersionTests`.

## Goals

1. Fix the acute regressions: SharePlay not receiving, photos flip-flopping /
   two photos cycling, map instability.
2. Redesign the envelope so the sender role is explicit:
   - the master sends the authoritative block (roster, controls, features)
   - players send only their own identity
   - receivers can no longer corrupt master state from player messages
3. Keep every app generation playable together via the mapper ladder.

## Part A — Regression Root Causes And Fixes

Order matters: these are small, individually testable steps and come first.

### A1. Photos flip-flopping / two photos cycling

Suspected chain:

1. The master answers every missing-data request with a **broadcast** full
   `.reveal/.show` — to all peers including its own local player.
2. Every receiver's `handlePhoto .reveal` success path calls `setCurrent` and
   flips `gameUpdateType = .photo` — even on the "already have it" early
   return. Any player's request re-shows the photo on **everyone's** screen.
3. With two photos in play, interleaved responses cycle every screen between
   them. The master's local player flips the master's own UI.
4. Amplifier: `reveal` now re-imports when `hasLocalFileData` is false. If that
   check misreports for an item (FileUrl path-resolution bug — see known
   failing test `FileDuplicationTests`), the affected player re-requests
   forever and drives an endless broadcast cycle.

Fixes (each with a MultiConnection test):

- **F1 Targeted responses.** Answers to missing-data requests go only to the
  requester: connection id on local network, participant id on the SharePlay
  messenger, playerId-filtered controls as fallback (the mapState recovery
  already does this).
- **F2 Reveal idempotence.** The "already have it" path must not re-set the
  current item or flip `gameUpdateType` when the item is already current.
  `.store` repairs never flip the screen (already true — keep it tested).
- **F3 Repair-loop guard.** Per-item pending-request set (like
  `pendingMapRequests`) for photo/audio/pdf/space requests, and
  verify-after-import: if the file is still missing after importing a payload,
  stop re-requesting and log — never loop.
- **F4 FileUrl resolution.** Fix the double-path bug
  (`…/Documents/module//Users/…`) so `hasLocalData`/`loadData` agree with
  where `addFile` writes. This is the known failing
  `FileDuplicationTests.duplicateReturnsNilWhenNoData`.

### A2. SharePlay does not receive

Hypotheses, in order of likelihood:

- **H1 Mixed app versions (fixed).** A shipped-2.6 (V1) peer cannot decode the
  V2 layout at all, and a V2 peer decoding V1 got empty roster/controls, so the
  controls filter dropped everything. The V1/V2 mappers + superset encoding fix
  both directions. Verify with a mixed-version test: encode with
  `GameNetworkModelV1`, run through the full player pipeline.
- **H2 Dedup swallows re-emitted journal payloads.** After a failed attachment
  load we deliver the metadata-only model; its dedup key equals the key of the
  later successful load of the same attachment (same counter), so the real
  payload is dropped as a duplicate. Fix: include payload presence
  (`data.data != nil`) in `GameMessageKey`, or skip dedup for `.file`-origin
  events.
- **H3 Session/messenger lifecycle** on the current OS beta — add reception
  logging around `configureGroupSession` and verify with a two-device session.

### A3. Map

Mostly downstream of A1/A2 (map bundles and background-photo repair ride the
same reveal/journal/store paths). Additionally:

- Verify the targeted `.update/.mapState` recovery works over SharePlay — the
  playerId-filtered controls rely on **name** matching in
  `prepareForProcessing`; brittle. Superseded by R4 below (filter by id).

## Part B — Envelope V3: explicit master / player

Direction (agreed): master sends the master block, players send only their own
player model, one simplified config with an explicit role, only the master
sends controls.

### Proposed wire shape

```swift
enum GameRole: Int, Codable, Sendable { case master, player, observer, proxy }

/// The one simplified config: sender identity for every message.
struct GameSenderModel: Equatable, Codable, Sendable {
    var id: UUID
    var role: GameRole
    var name: String
    var characterId: UUID?      // players only
}

/// Master-only authoritative block. Present only when sender.role == .master.
struct GameMasterStateModel: Equatable, Codable, Sendable {
    var state: GameState
    var adventureTitle: String?
    var players: [PlayerGameModel]
    var controls: [SharingControlModel]
    var features: GameFeatureModel
}

struct GameNetworkModel {   // V3
    var version = 3
    var counter: Int
    var proxyCounter: Int
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var masterId: UUID                      // routing + V2 mapping
    var sender: GameSenderModel
    var masterState: GameMasterStateModel?  // nil in player messages
    var data: NetworkCodableDataType
}
```

### What this eliminates

- `isMaster` by id comparison → `sender.role == .master`.
- `senderName` roster lookups with `""` fallback → `sender.name` directly.
  The whole lost-player-name class disappears.
- Players echoing roster/controls back to the master → structurally impossible;
  the master takes only `sender` (identity) from player messages.
- Name-based controls filtering (**R4**): filter by `control.id` against the
  local player id instead of display-name matching.

### MasterGameModel trim (user question: adventureId / adventureTitle / characterId)

Grep results (2026-07-10):

- `master.characterId` — **no consumers**. Drop from the wire and the model.
- `master.adventureId` — used only master-locally (`MasterController.start`
  title image, `GameRootView` adventure display). Keep local, drop from the
  wire. Verify `GameRootView.swift:36` is master-only before dropping.
- `master.adventureTitle` — used for the SharePlay activity title and the
  widget game name, both read from the master's **local** state. Keep a copy in
  `GameMasterStateModel.adventureTitle` so players can display the session
  name; drop the rest.

### Compatibility

- Decode ladder in `init(from:)`: V3 keys present → V3; else existing
  V2 / intermediate / V1 handling (already implemented).
- Mappers: `v3 ↔ v2` added next to the existing `v2 ↔ v1`.
  - V3 → V2: `gameConfig` from `masterId` + `sender`; roster =
    `masterState?.players` or `[sender-as-player]` for player messages so V2
    peers can still resolve the sender name.
  - V2 → V3: `sender` derived from `gameConfig` + roster lookup; `masterState`
    only when the sender is the master.
- Encoding stays a superset (V1 + intermediate + V2 + V3 fields) until the
  2.6 app generation is retired; then reduce to V3-only behind a single flag in
  `GameNetworkModel.encode(to:)`.

## Part C — Delivery semantics (after B, same milestone or next)

- **C1** Formalize targeted sending: `send(..., to: PeerTarget)` covering
  connection id, SharePlay participant, proxy connection.
- **C2** Dedup key gains payload presence (from H2).
- **C3** Journal slots per item id for photo/map instead of per module, to stop
  replace-during-transfer churn when two items alternate.
- **C4** `proxyCounter`: increment on proxy hops or delete the field in V3.

## Sequencing

1. **A-fixes** F2 → F1 → H2 → F3 → F4, each with a failing-first
   MultiConnection test (photo-cycling scenario: 4 players, 2 photos, one
   repeatedly-requesting player; journal re-emission dedup test; mixed-version
   V1-peer test).
2. Two-device SharePlay smoke test (H1/H3 verification).
3. **B**: V3 types + mappers + decode ladder + superset encode, tests mirroring
   `GameNetworkModelVersionTests` for V3↔V2↔V1.
4. Migrate `MasterController`/`PlayerController` handlers to
   `sender`/`masterState`; remove name-based filtering (R4); trim
   `MasterGameModel`.
5. Update `GAME_CONNECTIONS.md` sections 5, 8, 18.

## Open questions

- Does any player-side UI need `adventureId` (not just the title)? Check
  `GameRootView` usage per platform before trimming.
- Observers in V3: `role == .observer` with `characterId == nil` — any place
  that needs to distinguish observer vs player beyond filtering?
- Proxy relay in V3: the proxy master relays upstream — does it rewrite
  `sender` (currently it substitutes the proxy host's identity for dice)?
  Decide per subtype and document.
