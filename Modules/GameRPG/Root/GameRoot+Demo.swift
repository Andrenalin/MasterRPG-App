// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import GroupActivities
import os.log
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import SwiftUI
import WeatherRPG

// MARK: - Demo

extension GameRoot {
    /// Pacing between each photo reveal, and between map-state update steps, in the
    /// auto-playing demo sequence. See CODE_AUDIT §9.14.
    private nonisolated static let demoRevealPace: Duration = .seconds(3)
    /// Pacing before revealing each weather or map in the demo sequence — longer than
    /// `demoRevealPace` since these are bigger visual changes to let settle.
    /// See CODE_AUDIT §9.14.
    private nonisolated static let demoBigRevealPace: Duration = .seconds(5)

    func startDemo(supporterTier: SupporterTier = .none) async {
        // Cancel any previous demo loop before swapping `playerController` out from under it —
        // otherwise a still-running old task keeps sending reveal/mapState messages through its
        // own captured (now orphaned) controller, racing the new demo loop. See CODE_AUDIT.md §3.2.
        demoTask?.cancel()
        await startGame(to: nil, mode: .demo, supporterTier: supporterTier)

        guard let playerController = gameModel.playerController else { return }
        // `self` is bound strongly only for one step at a time, never across the paced
        // sleeps, so a missed teardown no longer keeps the root alive. See CODE_AUDIT_19 §3.11.
        demoTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard var steps = self?.demoRoundSteps(), !steps.isEmpty else { return }
                while !steps.isEmpty {
                    let step = steps.removeFirst()
                    do {
                        try await Task.sleep(for: step.pace)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, let followUp = await self?.performDemoStep(step, playerController: playerController) else { return }
                    steps.insert(contentsOf: followUp, at: 0)
                }
            }
        }
    }

    private enum DemoStep {
        case photo(UUID)
        case weather(UUID)
        case map(UUID)
        case mapState(UUID, data: NetworkCodableDataType, isLast: Bool)

        var pace: Duration {
            switch self {
            case .photo, .mapState: GameRoot.demoRevealPace
            case .weather, .map: GameRoot.demoBigRevealPace
            }
        }
    }

    /// One demo round: every photo, then every weather, then every map. `nil` once the game
    /// stopped; empty when there is nothing to show (no step would ever suspend).
    private func demoRoundSteps() -> [DemoStep]? {
        guard gameModel.gameConfig.state != .stopped else { return nil }
        let photos = photoRoot.itemControllable.itemDataModel.items.map(DemoStep.photo)
        let weathers = weatherRoot.itemControllable.itemDataModel.items.map(DemoStep.weather)
        let maps = mapRoot.itemControllable.itemDataModel.items.map(DemoStep.map)
        return photos + weathers + maps
    }

    /// Sends one demo step and returns the steps that must follow it right away (a revealed
    /// map's state updates).
    private func performDemoStep(_ step: DemoStep, playerController: PlayerController) async -> [DemoStep] {
        let gameNetworkModel: GameNetworkModel
        var followUp: [DemoStep] = []
        switch step {
        case .photo(let id):
            let data = await photoRoot.gameControllable.share(id: id)
            gameNetworkModel = gameModel.outgoingMessage(counter: 1, type: .reveal, subType: .show, asMaster: true, data: data)
        case .weather(let id):
            let data = await weatherRoot.gameControllable.share(id: id)
            gameNetworkModel = gameModel.outgoingMessage(counter: 2, type: .reveal, subType: .show, asMaster: true, data: data)
        case .map(let id):
            let data = await mapRoot.mapGameControllable.shareMap(id: id)
            gameNetworkModel = gameModel.outgoingMessage(counter: 2, type: .reveal, subType: .show, asMaster: true, data: data)
            followUp = nextDemoMapState(for: id)
        case .mapState(let id, let data, let isLast):
            gameNetworkModel = gameModel.outgoingMessage(counter: 2, type: .update, subType: .mapState, asMaster: true, data: data)
            if !isLast {
                followUp = nextDemoMapState(for: id)
            }
        }
        await playerController.receivedProcess(gameNetworkModel)
        return followUp
    }

    /// The map's next demo state; after the last one the map is restarted once and the demo
    /// moves on.
    private func nextDemoMapState(for id: UUID) -> [DemoStep] {
        if let data = mapRoot.mapGameControllable.demoNextMap(itemId: id, restart: false) {
            return [.mapState(id, data: data, isLast: false)]
        }
        guard let data = mapRoot.mapGameControllable.demoNextMap(itemId: id, restart: true) else { return [] }
        return [.mapState(id, data: data, isLast: true)]
    }
}
