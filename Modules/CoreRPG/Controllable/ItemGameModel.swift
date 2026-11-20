// @copyright André Trettin

import Foundation
import Observation
import os.log

@MainActor @Observable
public final class ItemGameModel {
    public typealias ModelType = Observable & Sendable
    
    public init(itemDataModel: ItemDataModel) {
        self.itemDataModel = itemDataModel
    }

    public let itemDataModel: ItemDataModel
    public var items: [UUID] {
        get { itemDataModel.gameItems }
        set { itemDataModel.gameItems = newValue }
    }
    public var itemData: [UUID: ModelType] {
        get { itemDataModel.gameItemData }
        set { itemDataModel.gameItemData = newValue }
    }
    public var focusItemIds: [UUID] = []

    public var currentItemId: UUID? {
        itemDataModel.isGameCurrentCleared ? nil : itemDataModel.gameItems.first
    }

    /// Takes the current item off the screen without dropping it: it and the other items keep
    /// their game copies, and showing one again makes it current. Ended by any other first item.
    public func clearCurrent() {
        itemDataModel.isGameCurrentCleared = true
    }

    public var currentPlayers: [UUID] = []

    // Per-item player-reporting state for the current game session.
    // Stored here (not on domain models) to avoid shared state across game sessions
    // and to prevent cross-test contamination when tests run in parallel.
    public var playerReports: [UUID: [UUID]] = [:]

    /// The running or last download of each item's file on this device, shown in the item's row.
    /// Only a player device downloads; the game master never gets another device's entries.
    public var transfers: [UUID: ItemTransferStatus] = [:]

    /// The game master's version of each item players report on. See `recordMasterVersion`.
    public private(set) var masterVersions: [UUID: Int] = [:]

    /// Records the game master's version of `itemId`. When it differs from the one recorded
    /// before, the item was replaced during the game: the reports made for the old version no
    /// longer count, so the players receive the new one. Returns whether reports were dropped.
    @discardableResult
    public func recordMasterVersion(_ version: Int, for itemId: UUID) -> Bool {
        defer { masterVersions[itemId] = version }
        guard let previous = masterVersions[itemId], previous != version else { return false }
        playerReports[itemId] = []
        return true
    }

    public func setCurrent(players: [UUID]) {
        currentPlayers = players
    }

    public func playerReport(for itemId: UUID) -> [UUID] {
        playerReports[itemId] ?? []
    }

    public func setPlayerReport(playerId: UUID, for itemId: UUID) {
        if !playerReports[itemId, default: []].contains(playerId) {
            playerReports[itemId, default: []].append(playerId)
        }
    }

    public func removePlayerReport(for playerId: UUID) {
        playerReports = playerReports.mapValues { players in
            players.filter { $0 != playerId }
        }
    }
    
    /// Idempotent: an id that is already listed is not listed twice. See CODE_AUDIT_26 §5.50.
    func append(itemId: UUID, item: ModelType) {
        if !items.contains(itemId) {
            items.append(itemId)
        }
        itemData[itemId] = item
    }

    /// Idempotent: an id that is already listed moves to the front instead of being listed twice.
    func insert(itemId: UUID, item: ModelType) {
        if let index = items.firstIndex(of: itemId) {
            items.remove(at: index)
        }
        items.insert(itemId, at: 0)
        itemData[itemId] = item
    }
    
    /// Finds `itemId` and moves it to the front in one synchronous step, so no `await` gap can
    /// shrink `items` between the lookup and the removal. Returns whether it was present.
    /// See CODE_AUDIT_16 §3.10.
    func moveToFront(itemId: UUID) -> Bool {
        guard let index = items.firstIndex(of: itemId) else { return false }
        itemDataModel.isGameCurrentCleared = false
        if index != 0 {
            items.remove(at: index)
            items.insert(itemId, at: 0)
        }
        return true
    }

    /// Shows `itemId` (moved to the front) or, for `hide`, only caches it. The list of "other
    /// newly visible items" it used to return was always empty; the dependents a delivery wrote
    /// come from the import instead. See CODE_AUDIT_EditItem §3.3, CODE_AUDIT_Folder §5.22.
    func apply(itemId: UUID, item: ModelType, hide: Bool) {
        if hide {
            if !items.contains(itemId) {
                items.append(itemId)
            }
        } else if let index = items.firstIndex(of: itemId) {
            itemDataModel.isGameCurrentCleared = false
            if index != 0 {
                items.remove(at: index)
                items.insert(itemId, at: 0)
            }
        } else {
            items.insert(itemId, at: 0)
        }

        itemData[itemId] = item
    }

    func item(for itemId: UUID) -> ModelType? {
        itemData[itemId]
    }
    
    /// Incremented by every `reset()`. A delivery or reveal compares it before and after its
    /// suspensions, so work that started in a game which has since been reset does not
    /// re-populate the cleared game model. See CODE_AUDIT_Folder §3.11.
    @ObservationIgnored public private(set) var resetGeneration = 0

    func reset() {
        resetGeneration &+= 1
        itemDataModel.isGameCurrentCleared = false
        items = []
        itemData.removeAll()
        playerReports.removeAll()
        transfers.removeAll()
        masterVersions.removeAll()
    }

    func focus(on focusIds: [UUID]) {
        focusItemIds = focusIds
    }
}
