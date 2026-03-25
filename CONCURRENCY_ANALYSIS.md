# Swift Concurrency Analysis: MasterController & PlayerController

**Date:** 2026-03-24
**Analyzed Files:**
- `Modules/GameRPG/Controller/MasterController.swift`
- `Modules/GameRPG/Controller/PlayerController.swift`

**Project Configuration:**
- Swift Strict Concurrency: **complete** ✓
- This is excellent - the project has full data-race safety checking enabled

---

## Critical Issues Found

### 1. **Sendable Violations with `unowned let root: GameRoot!`**

**Location:** Both controllers (MasterController.swift:38, PlayerController.swift:70)

**Problem:**
```swift
final class MasterController: Sendable {
    unowned let root: GameRoot!  // ❌ GameRoot likely not Sendable
```

**Why This Is Dangerous:**
- Both controllers are marked `Sendable` but contain `unowned` references to `GameRoot`
- If `GameRoot` is not `Sendable`, this violates data-race safety
- The `unowned` reference doesn't prevent concurrent access issues
- Using implicitly unwrapped optional (`!`) with `unowned` is risky

**Fix Options:**

**Option A: Make GameRoot Sendable** (if it's immutable or actor-isolated):
```swift
// If GameRoot is actor-isolated:
@MainActor
final class GameRoot { ... }

// Then controllers can safely reference it
final class MasterController: Sendable {
    unowned let root: GameRoot  // Now safe - always accessed on @MainActor
```

**Option B: Remove Sendable conformance** (if controllers truly share mutable state):
```swift
// Remove Sendable if the controller needs shared mutable access
final class MasterController {  // No Sendable
    unowned let root: GameRoot!
```

**Recommendation:** Since these controllers perform network operations and coordinate game state, they should likely be **actors** instead of `Sendable` classes.

---

### 2. **Observable Model Classes Should Be @MainActor**

**Location:** MasterController.swift:17-35, PlayerController.swift:22-48

**Problem:**
```swift
@MainActor @Observable
final class MasterControllerModel: Sendable {  // ❌ Redundant Sendable
    var messageCounter: Int = 0
```

**Issues:**
- `@MainActor` types are automatically `Sendable` - no need for explicit conformance
- `@Observable` macro requires `@MainActor` isolation for SwiftUI observation
- These models are correctly marked `@MainActor`, but the `Sendable` conformance is redundant

**Fix:**
```swift
@MainActor @Observable
final class MasterControllerModel {  // ✓ Sendable is automatic
    var messageCounter: Int = 0
```

---

### 3. **Unstructured Task in Init Creates Hidden Complexity**

**Location:** MasterController.swift:47-53, PlayerController.swift:82-91

**Problem:**
```swift
@MainActor
init(root: GameRoot, asProxy: Bool) {
    // ...
    Task {  // ❌ Unstructured task - fire and forget
        if asProxy {
            await root.networkProxyStore.model.setMaster(delegate: self)
        } else {
            await root.networkStore.model.setMaster(delegate: self)
        }
    }
}
```

**Issues:**
- Unstructured `Task` in initializer means initialization "completes" before delegate is set
- No error handling - if `setMaster` fails, it's silently ignored
- Potential race condition: controller methods could be called before delegate setup completes
- Creates implicit ordering dependency that's not enforced

**Better Approach:**
```swift
// Option 1: Explicit async initialization
@MainActor
static func create(root: GameRoot, asProxy: Bool) async -> MasterController {
    let controller = MasterController(root: root)
    if asProxy {
        await root.networkProxyStore.model.setMaster(delegate: controller)
    } else {
        await root.networkStore.model.setMaster(delegate: controller)
    }
    return controller
}

private init(root: GameRoot) {
    self.root = root
    self.gameModel = MasterControllerModel()
}
```

```swift
// Option 2: Separate setup method
@MainActor
func setup(asProxy: Bool) async {
    if asProxy {
        await root.networkProxyStore.model.setMaster(delegate: self)
    } else {
        await root.networkStore.model.setMaster(delegate: self)
    }
}
```

---

### 4. **GameModelMessage Actor Has Flawed State Machine**

**Location:** PlayerController.swift:50-67

**Problem:**
```swift
actor GameModelMessage {
    private var messages: [GameNetworkModel] = []
    private var processing: Bool = false

    func next() -> GameNetworkModel? {
        guard !processing && !messages.isEmpty else { return nil }
        processing = true  // ❌ Race condition: multiple calls can interleave
        return messages.removeFirst()
    }

    func processed() {
        processing = false
    }
}
```

**Issues:**
- **Actor reentrancy bug**: Between checking `!processing` and setting `processing = true`, another call to `next()` could occur
- If two tasks call `next()` simultaneously, both could see `processing == false` before either sets it to `true`
- This defeats the entire purpose of the processing flag
- No protection against calling `processed()` without calling `next()`

**Fix with Proper Actor Isolation:**
```swift
actor GameModelMessage {
    private var messages: [GameNetworkModel] = []

    // Single atomic operation - no reentrancy issues
    func nextMessage() -> GameNetworkModel? {
        guard !messages.isEmpty else { return nil }
        return messages.removeFirst()
    }

    func append(_ message: GameNetworkModel) {
        messages.append(message)
    }

    var hasMessages: Bool {
        !messages.isEmpty
    }
}

// Usage (in PlayerController):
func processMessages() async {
    while let message = await gameModel.gameModelMessage.nextMessage() {
        let response = try? await handle(message)
        if let response {
            await send(model: response)
            if response.subType == .ok {
                await gameModel.increaseMessageCounter()
            }
        } else {
            await gameModel.increaseMessageCounter()
        }
    }
}
```

**Alternative with AsyncStream (more idiomatic):**
```swift
actor GameModelMessage {
    private var continuation: AsyncStream<GameNetworkModel>.Continuation?
    private let stream: AsyncStream<GameNetworkModel>

    init() {
        stream = AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func append(_ message: GameNetworkModel) {
        continuation?.yield(message)
    }

    var messages: AsyncStream<GameNetworkModel> {
        stream
    }
}

// Usage:
func processMessages() async {
    for await message in gameModel.gameModelMessage.messages {
        let response = try? await handle(message)
        // ... handle response
    }
}
```

---

### 5. **Multiple Isolation Domain Crossings in Send Methods**

**Location:** MasterController.swift:116-138, PlayerController.swift:148-163

**Problem:**
```swift
func send(type: RPGMessageType, subtype: RPGMessageActionType, updated: NetworkCodableDataType, connectionId: ConnectionController.ID? = nil, playerId: UUID? = nil) async {
    let counter = "\(await gameModel.messageCounter)"  // ❌ Crossing to @MainActor
    // ...
    var game = await root.gameModel.gameConfig  // ❌ Crossing to @MainActor again
    if let playerId {
        game.controls = game.controls.filter { $0.id == playerId }
    }
    let networtData = await GameNetworkModel(counter: gameModel.messageCounter, proxyCounter: 0, ...)  // ❌ Third crossing

    await root.logGameController.addMessage(...)  // ❌ Fourth crossing
    await gameModel.increaseMessageCounter()  // ❌ Fifth crossing
}
```

**Issues:**
- Five separate isolation domain crossings (5 suspension points)
- Each `await` is a potential suspension point where other tasks can interleave
- `gameModel.messageCounter` could change between reads
- Poor performance due to multiple actor hops

**Fix - Batch Actor Access:**
```swift
func send(type: RPGMessageType, subtype: RPGMessageActionType, updated: NetworkCodableDataType, connectionId: ConnectionController.ID? = nil, playerId: UUID? = nil) async {
    // Single atomic read from @MainActor
    let (counter, gameConfig) = await (gameModel.messageCounter, root.gameModel.gameConfig)

    Logger.networking.debug("MasterController: Send \(counter): \(type.debugDescription) - \(subtype.debugDescription) for \(updated.type.token) -> \(updated.id)")

    var game = gameConfig
    if let playerId {
        game.controls = game.controls.filter { $0.id == playerId }
    }

    let networkData = GameNetworkModel(
        counter: counter,
        proxyCounter: 0,
        type: type,
        subType: subtype,
        gameConfig: game,
        data: updated
    )

    // Batch the state updates
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            await self.root.logGameController.addMessage(
                counter: counter,
                type: type,
                subType: subtype,
                module: updated.type,
                itemId: updated.id
            )
        }
        group.addTask {
            await self.gameModel.increaseMessageCounter()
        }
    }

    // Send network data
    if await gameModel.asProxy {
        if let connectionId {
            await root.networkProxyStore.sendPlayer(networkData, to: connectionId)
        } else {
            await root.networkProxyStore.sendPlayer(data: networkData)
        }
    } else {
        await root.networkStore.sendPlayer(data: networkData, fileJournal: networkData.type == .reveal)
    }
}
```

---

### 6. **Task Creation Inside @MainActor Context**

**Location:** PlayerController.swift:359-363, 392-394, 403-406, etc.

**Problem:**
```swift
func handleMap(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
    // ... async work
    Task { @MainActor in  // ❌ Unstructured task for simple state update
        if gameModel.asGameMaster {
            gameModel.gameUpdateType = .map
        }
    }
}
```

**Issues:**
- Creating unstructured `Task` just to hop to `@MainActor`
- The function is already async - should use structured concurrency
- No guarantee about when the state update completes
- Return value doesn't reflect the state change

**Fix:**
```swift
func handleMap(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
    // ... async work

    // Direct MainActor-isolated call
    await setGameUpdateType(.map, ifGameMaster: true)

    return await response(for: model, isSuccess: true, requestData: false)
}

// Add helper method to PlayerControllerModel
@MainActor
extension PlayerControllerModel {
    func setGameUpdateType(_ type: NetworkModules, ifGameMaster: Bool) {
        if !ifGameMaster || asGameMaster {
            gameUpdateType = type
        }
    }
}
```

---

### 7. **Inconsistent Error Handling in Delegate Methods**

**Location:** MasterController.swift:191-193, PlayerController.swift:227-238

**Problem:**
```swift
// MasterController
} else if let requestedData = try? await handle(model) {  // ❌ Silently ignores errors
    await send(type: model.type, subtype: model.subType, updated: requestedData)
}

// PlayerController
let response = try? await handle(message)  // ❌ Error discarded
if let response {
    await send(model: response)
}
```

**Issues:**
- Errors are silently discarded with `try?`
- No logging, no recovery, no user notification
- Makes debugging networking issues nearly impossible
- In a game controller, dropped messages could cause desync

**Fix:**
```swift
// MasterController
} else {
    do {
        if let requestedData = try await handle(model) {
            await send(type: model.type, subtype: model.subType, updated: requestedData)
        }
    } catch {
        Logger.networking.error("MasterController: Failed to handle message \(model.counter): \(error.localizedDescription)")
        // Optionally send failure response
        await send(type: model.type, subtype: .failed, updated: model.data)
    }
}

// PlayerController
do {
    let response = try await handle(message)
    if let response {
        await send(model: response)
        if response.subType == .ok {
            await gameModel.increaseMessageCounter()
        }
    } else {
        await gameModel.increaseMessageCounter()
    }
} catch {
    Logger.networking.error("PlayerController: Failed to handle message: \(error.localizedDescription)")
    await gameModel.increaseMessageCounter()
}
```

---

### 8. **Potential Data Race in resetPlayers Methods**

**Location:** MasterController.swift:82-98, PlayerController.swift:124-129

**Problem:**
```swift
func resetPlayers() async {
    var players = await root.gameModel.gameConfig.controls.compactMap { $0.show ? $0.id : nil }.sorted()
    if await gameModel.asProxy {  // ❌ Another read - could have changed
        await players.append(root.gameModel.gameConfig.master.id)  // ❌ More reads
        players = players.sorted()
    }
    await root.audioRoot.gameControllable.gameModel.setCurrent(players: players)

    var playerNames = await root.gameModel.gameConfig.players.filter { ... }  // ❌ Yet another read
    // More interleaved reads...
}
```

**Issues:**
- Multiple reads of `gameModel.gameConfig` with suspension points between them
- `gameConfig` could change between reads, leading to inconsistent state
- Building `players` and `playerNames` from potentially different snapshots

**Fix:**
```swift
func resetPlayers() async {
    // Single atomic snapshot
    let snapshot = await (
        controls: root.gameModel.gameConfig.controls,
        masterId: root.gameModel.gameConfig.master.id,
        masterName: root.gameModel.gameConfig.master.name,
        players: root.gameModel.gameConfig.players,
        isProxy: gameModel.asProxy
    )

    // Compute all values from consistent snapshot
    var playerIds = snapshot.controls.compactMap { $0.show ? $0.id : nil }.sorted()
    var playerNames = snapshot.players.filter { $0.type != .observer }.map { $0.name }.sorted()

    if snapshot.isProxy {
        playerIds.append(snapshot.masterId)
        playerIds.sort()
        playerNames.append(snapshot.masterName)
        playerNames.sort()
    }

    // Now update dependent systems
    await root.audioRoot.gameControllable.gameModel.setCurrent(players: playerIds)
    await root.diceRoot.diceGameControllable.resetPlayerDice(to: playerNames)

    if !snapshot.isProxy {
        let nonObserverPlayers = snapshot.players.filter { $0.type != .observer }
        await root.mapRoot.mapGameControllable.resetPlayerPins(for: nonObserverPlayers)
    }
}
```

---

## Architectural Recommendations

### 1. **Consider Making Controllers Actors**

Both controllers coordinate concurrent operations and maintain state. They should likely be actors:

```swift
@MainActor  // Or custom actor if needed
actor MasterController {
    let root: GameRoot  // No longer needs 'unowned'
    let gameModel: MasterControllerModel

    init(root: GameRoot, asProxy: Bool) async {
        self.root = root
        self.gameModel = MasterControllerModel()
        gameModel.asProxy = asProxy

        // Now synchronous - guaranteed to complete before use
        if asProxy {
            await root.networkProxyStore.model.setMaster(delegate: self)
        } else {
            await root.networkStore.model.setMaster(delegate: self)
        }
    }
}
```

**Benefits:**
- Automatic serialization of all method calls
- Eliminates data races
- Clear isolation boundaries
- Proper lifecycle management

### 2. **Use Task Groups for Parallel Operations**

Several methods perform independent parallel operations:

```swift
// MasterController.swift:66-70
@MainActor
func start() async {
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            await self.root.networkStore.startMasterGame(
                game: self.root.gameModel.gameConfig,
                titleImage: self.root.adventureRoot.titleImage(for: self.root.gameModel.gameConfig.master.adventureId!)
            )
        }
        group.addTask {
            await self.root.networkProxyStore.startProxyServer()
        }
    }
}
```

### 3. **Introduce Message Counter Synchronization**

The message counter pattern suggests a need for ordered message processing:

```swift
@MainActor
actor MessageCoordinator {
    private var nextCounter = 0
    private var seenCounters: Set<Int> = []

    func nextMessageCounter() -> Int {
        let counter = nextCounter
        nextCounter += 1
        return counter
    }

    func markSeen(_ counter: Int) -> Bool {
        seenCounters.insert(counter).inserted
    }

    func shouldProcess(counter: Int, seen: Int) -> Bool {
        counter == 0 || seen < counter
    }
}
```

### 4. **Improve Delegate Pattern with Async Sequences**

Instead of delegate callbacks, consider using `AsyncStream` for events:

```swift
actor MasterController {
    private let connectionEvents = AsyncStream<ConnectionEvent>.makeStream()

    var events: AsyncStream<ConnectionEvent> {
        connectionEvents.stream
    }

    enum ConnectionEvent {
        case ready(ConnectionController.ID)
        case lostPlayer(ConnectionController.ID)
        case receivedMessage(GameNetworkModel, ConnectionController.ID?)
    }
}

// Usage:
Task {
    for await event in masterController.events {
        switch event {
        case .ready(let id):
            // Handle ready
        case .lostPlayer(let id):
            // Handle disconnect
        case .receivedMessage(let model, let id):
            // Handle message
        }
    }
}
```

---

## Priority Ranking

**P0 - Critical (Data Race Risks):**
1. Fix `GameModelMessage` actor reentrancy bug (PlayerController.swift:50-67)
2. Fix `unowned let root` Sendable violation (both files)
3. Add proper error handling to message processing (both files)

**P1 - High (Correctness Issues):**
4. Fix `resetPlayers()` snapshot consistency (both files)
5. Remove unstructured `Task` from initializers (both files)
6. Batch actor access in `send()` methods (both files)

**P2 - Medium (Code Quality):**
7. Replace unstructured `Task` with direct `await` in handlers (PlayerController)
8. Remove redundant `Sendable` from `@MainActor` types (both files)
9. Consider actor-based architecture (architectural change)

**P3 - Low (Future Improvements):**
10. Introduce `MessageCoordinator` actor for counter management
11. Replace delegates with `AsyncStream` for events
12. Add cancellation support to long-running operations

---

## Testing Recommendations

After making these changes, test for:

1. **Concurrency stress test**: Rapid message sending/receiving
2. **Race condition detection**: Use Thread Sanitizer
3. **Memory leaks**: Use Instruments (Leaks and Allocations)
4. **Actor deadlocks**: Monitor for hung tasks
5. **Message ordering**: Verify counter sequencing under load

---

## Summary

These controllers have good async/await adoption but suffer from:
- **Sendable violations** that compile but aren't truly thread-safe
- **Actor reentrancy bugs** in the message queue
- **Multiple suspension points** where state could change unexpectedly
- **Silent error swallowing** that hides network issues
- **Unstructured concurrency** where structured would be safer

The good news: With `SWIFT_STRICT_CONCURRENCY = complete` enabled, once you fix these issues, the compiler will enforce data-race safety going forward.

---

## Next Steps

1. Start with P0 critical fixes (GameModelMessage actor, Sendable violations, error handling)
2. Add comprehensive logging to track message flow
3. Run Thread Sanitizer to verify data race elimination
4. Consider architectural refactor to actor-based design for long-term maintainability
