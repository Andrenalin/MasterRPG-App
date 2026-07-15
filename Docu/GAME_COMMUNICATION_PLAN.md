# Game Communication Redesign — Implementation Record

Status: implemented and audited against the source on 2026-07-15.

This file records the redesign that repaired SharePlay delivery, photo/map
repair loops, sender ambiguity, and proxy routing. It is a historical change
record, not the primary description of the live system. See
[Game Connections](GAME_CONNECTIONS.md) for the current end-to-end contract.

## Goals

1. Make sender identity explicit and keep master state authoritative.
2. Keep the shipped 2.6/V1 envelope interoperable with current builds.
3. Target full repair payloads at the requester so another player's missing file
   cannot change everyone's current presentation.
4. Make duplicate, retry, SharePlay-session, and proxy behavior deterministic.

## Implemented Current Envelope

The redesign landed as the current in-memory V2 schema. There is no V3 wire
generation.

```swift
struct GameNetworkModel: Codable, Sendable {
    static let currentVersion = 2

    var version: Int
    var counter: Int
    var proxyCounter: Int
    var type: RPGMessageType
    var subType: RPGMessageActionType
    var masterId: UUID
    var sender: GameSenderModel
    var masterState: GameMasterStateModel?
    var targetId: UUID?
    var data: NetworkCodableDataType
}

struct GameSenderModel: Equatable, Codable, Sendable {
    var id: UUID
    var role: GameType
    var name: String
    var characterId: UUID?
}

struct GameMasterStateModel: Equatable, Codable, Sendable {
    var state: GameState
    var adventureId: UUID?
    var adventureTitle: String?
    var players: [PlayerGameModel]
    var controls: [SharingControlModel]
    var features: GameFeatureModel
}
```

Current rules:

- master messages contain `masterState`
- player/observer/proxy-origin messages contain only `sender`
- controls are matched by participant ID, never display name
- a player accepts master state only from a newer counter for that `masterId`
- `targetId` is a logical address applied by every player pipeline
- `adventureId` and `adventureTitle` remain in `masterState`
- `MasterGameModel.characterId` was removed from the transported master state;
  player character identity belongs to `sender.characterId`

## Compatibility

`GameNetworkModel.init(from:)` accepts:

- the shipped V1 envelope with roster, controls, and features inside
  `gameConfig`
- unreleased development layouts using `gameConfig` plus `gameRoster` and
  optional `gameControl`
- the current V2 `sender`/`masterState` layout

`encode(to:)` emits one compatibility superset containing current and legacy
keys. It deliberately writes wire `version == 1`, so shipped V1 clients accept
the bytes. Current in-memory construction still defaults to
`GameNetworkModel.currentVersion == 2`.

Bidirectional mapping is implemented by:

- `GameNetworkModelV1.v2Model`
- `GameNetworkModel.v1Model`

A current player message embeds that sender as the sole V1 roster entry so an
old peer can still recover the player's name and role.

## Regression Repairs

### Targeted Payload Responses

Missing-data answers carry `targetId == requesterId`. When a local-network
connection ID is known, the master sends only to that connection. SharePlay and
fallback delivery can still fan out physically, but non-target player pipelines
in current builds ignore the message. Shipped V1 clients have no `targetId`
field, so only physical direct-connection targeting protects them; a V1 peer can
still process a SharePlay/fallback broadcast containing this unknown key.

The host of a private proxy mirror forwards host-targeted answers downstream
with the target cleared. Messages targeted at a different ID are forwarded
unchanged because that ID may be behind the host.

### Map Asset, Metadata Update, State, And File Repair

- the first photo, PDF, or space show of each item version sends the full package;
  same-version shows use the ID/version reference
- a map has two independent versions: `assetVersion` fingerprints its background
  photo UUID plus that photo's content version, while `contentVersion` fingerprints
  the complete file-byte-free map metadata snapshot
- the first map show for an `assetVersion` publishes the full map/background package
  through the SharePlay journal; only a changed background asset republishes it
- editor changes such as `pinScale`, `hexMapScale`, rooms, geometry, and pin
  references send a semantic map update over `.update/.generic`; the update is
  chunked through the messenger and does not invalidate the journal publication
- the map-update payload is schema-versioned and contains the complete map metadata
  plus referenced photo IDs, but no photo bytes
- `.generic` is deliberately reused instead of adding an enum raw value: shipped
  V1 clients can decode the envelope and safely ignore the unknown payload shape
- `mapState` remains the volatile channel for room visibility/focus, pointer, and
  in-game pin movement
- `GameControllable.reveal` verifies local backing bytes, not only metadata
- photo/map repair sets bound repeated requests
- every applied map update or map-state snapshot rescans all pin photos; newly introduced pin
  photos repair through data-less `.store/.store` requests
  only when their IDs exist in neither the photo game controller nor item controller
- the map background is excluded from pin repair; it is checked separately and
  remains part of the full map payload sent through the SharePlay journal
- duplicate photo IDs are removed before requesting
- responses echo the original counter and strip incoming payload bytes
- a successful full response is marked sent even when it came through a request
  path

These rules prevent alternating photo responses from flipping every screen and
prevent a missing reference from driving an endless repair loop.

### Deduplication And Ordering

`GameMessagePipeline` is an actor with queued, current, pending, and recent keys.
Its key includes sender, counters, message/action, item identity/version, and
payload presence. A metadata-only journal event and the later full payload are
therefore distinct. Failed processing releases the key for retry; successful
processing remembers it in a 256-entry window.

Master and player-origin message counters now start at 1 and increase
independently. ACKs and requests copy the counter they answer. Older
authoritative master snapshots and map updates are ignored. A map update that
arrives before its full base map is retained and applied after the map arrives.

### SharePlay

- the session sequence is subscribed before activity activation
- configuration is gated by the current session ID, requested join, and joined
  state
- session-scoped tasks are cancelled on reset; the join loop survives for rejoin
- messenger payloads use ordered 64,000-byte raw packages so Codable/Base64 plus
  worst-case JSON escaping remains below the 256 KB message limit
- transient package-send failures retry twice; terminal failures are logged,
  streams remain bound to one session messenger, and reset removes partial receives
- journal publications are serialized per module; a replacement is committed
  before old-attachment cleanup, which runs without blocking later publications
- journal snapshots load only their newest visual file presentation and await
  file routing, preserving the newest map/photo/PDF/space reveal
- attachment data loading retries the transient CloudAsset `uploadInProgress`
  window; exhausted loads remain journal-retryable, reveals recover conditionally,
  and store/update failures explicitly request bytes through messenger
- messenger routing is awaited, and one visual presentation-intent sequence per
  master rejects older cross-module/transport payloads and stale repairs
- map updates use `.update/.generic` and the ordered chunked messenger; they are
  not journal attachments or new presentation intents
- map-state updates remain separate from structural map updates; targeted
  version-zero companions from older masters are accepted only when they match
  the current map intent
- cancelled messenger/journal work checks its session before delivery or mutation
- targeted non-audio repair payloads use messenger packages
- full `.store/.store` photo repairs choose packages while targeted, then become
  untargeted group stores and coalesce by photo ID/version; the cache resets for
  a joining participant
- targeted audio journal repairs become untargeted `.store/.show` metadata
- failed journal publication falls back to packages
- failed attachment loading still delivers metadata so normal repair can run

### Proxy Role

The proxy role is resolved: a proxy client is a private mirror, not a real-master
participant. The host does not add it to a roster. Messages that go upstream are
rebuilt with the host sender identity and a fresh host counter. Dice, map-pin,
and space-transform actions are applied on the host before remapping. ACKs,
screens, audio lists, and proxy character announcements are consumed locally.

### Reconnect

Ready connections receive the current presentation immediately. For a map, the
replay order is the current full-asset reference, the latest map update, and then
the latest map state. A proxy additionally receives the host's selected
character. Lost connections clear repair/order state so availability and
identity can be announced again safely.

## Verification Coverage

The implementation is covered by Swift Testing suites for:

- V1/current mapping and superset round trips
- current-master/V1-player and V1-master/current-player dice/photo exchange
- monotonic player counters and stale master-state rejection
- targeted photo repair across players, observers, and proxies
- metadata/full-payload dedup separation and retry after failed processing
- SharePlay package reassembly, lifecycle gating, and journal selection
- two-pin mapState repair requesting only the one pin photo absent from both local
  photo controllers, excluding the background from repair
- first full-map SharePlay broadcast selecting the journal transport
- scale/editor refresh sending a file-byte-free map update without replacing the
  journal attachment, while a background change creates a new publication
- late-join replay ordering the map reference before map update and map state
- three-player SharePlay photo repair coalescing over messenger packages
- proxy invisibility, host identity remapping, and host-target forwarding
- audio availability convergence and targeted pre-play transfers
- current-presentation replay after ready

The main files are listed at the top of [Game Connections](GAME_CONNECTIONS.md).

## Remaining Work

- Run and record a real two-device SharePlay smoke test on the current OS build;
  automated tests cover policy and lifecycle but not the system service.
- Decide on a legacy-safe repair policy for mixed V1/current SharePlay sessions,
  or formally retire that combination. V1 decoders ignore `targetId`, so logical
  targeting alone cannot prevent them from processing a fallback broadcast.
- Decide whether the journal should keep its current one-publication-per-module
  model or adopt per-item broadcast slots. Targeted repairs no longer replace a
  broadcast attachment, so this is now a capacity/product decision rather than
  the original correctness blocker.
- Either define and increment `proxyCounter` on proxy hops or remove it in a
  future negotiated envelope. Current code preserves it without incrementing.
- Recheck and remove the `@preconcurrency import GroupActivities` escape hatch
  when the deployment SDK's concurrency annotations allow it; until then keep
  mutable SharePlay state main-actor isolated and the detached join call free of
  controller-state access.
- When support for the shipped V1 generation is retired, replace the superset
  encoder with a negotiated V2-only wire format and update version tests first.
