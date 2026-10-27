// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import Testing

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@testable import GameRPG
@testable import MapRPG

@MainActor
@Suite("Battle round number input")
struct BattleNumberInputTests {
    @Test("Whole numbers parse in the locale's own notation")
    func parsesLocaleNotation() {
        let english = Locale(identifier: "en_US")
        let german = Locale(identifier: "de_DE")

        #expect(BattleNumberInput.parse("12", locale: english) == 12)
        #expect(BattleNumberInput.parse("  12 ", locale: english) == 12)
        #expect(BattleNumberInput.parse("-3", locale: english) == -3)
        #expect(BattleNumberInput.parse("0", locale: english) == 0)
        // Grouping separators.
        #expect(BattleNumberInput.parse("1,000", locale: english) == 1000)
        #expect(BattleNumberInput.parse("1.000", locale: german) == 1000)
        // A typographic minus, as some keyboards and locales write it.
        #expect(BattleNumberInput.parse("\u{2212}4", locale: english) == -4)
        // Digits of another script.
        #expect(BattleNumberInput.parse("١٢", locale: Locale(identifier: "ar_EG")) == 12)
    }

    @Test("Anything that is not a whole number is rejected, not guessed")
    func rejectsWhatIsNotANumber() {
        let english = Locale(identifier: "en_US")

        #expect(BattleNumberInput.parse("", locale: english) == nil)
        #expect(BattleNumberInput.parse("   ", locale: english) == nil)
        #expect(BattleNumberInput.parse("abc", locale: english) == nil)
        #expect(BattleNumberInput.parse("12abc", locale: english) == nil)
        #expect(BattleNumberInput.parse("1d20", locale: english) == nil)
    }

    @Test("The field text reads back as the same number")
    func textRoundTrips() {
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "de_DE"), Locale(identifier: "ar_EG")] {
            for value in [0, 7, -12, 12_345] {
                let text = BattleNumberInput.text(for: value, locale: locale)
                #expect(BattleNumberInput.parse(text, locale: locale) == value, "\(value) in \(locale.identifier)")
            }
        }
        #expect(BattleNumberInput.text(for: nil) == "")
        #expect(BattleNumberInput.text(for: 12_345, locale: Locale(identifier: "en_US")) == "12345")
    }
}

@MainActor
@Suite("Battle round symbols")
struct BattleRoundSymbolTests {
    @Test("The dead toggle has one title, symbol and role per direction")
    func deadToggle() {
        let markDead = BattleDeadToggle(isDead: false)
        let markAlive = BattleDeadToggle(isDead: true)

        #expect(markDead.systemImage == "figure.fall")
        #expect(markDead.role == .destructive)
        #expect(markAlive.systemImage == "heart.fill")
        #expect(markAlive.role == nil)
        #expect(markDead.title != markAlive.title)
    }

    /// `skull.fill` shipped in a context menu although no such symbol exists:
    /// SwiftUI only logs a fault and draws nothing. This reads the symbol
    /// names out of the battle round sources and asks the system for each.
    @Test(
        "Every SF Symbol the battle round views name exists",
        .enabled(if: BattleRoundSymbolTests.sourcesAreOnDisk, "The sources are not on the machine that runs the tests (CI)")
    )
    func everySymbolExists() throws {
        let names = try Self.symbolNamesInSources()
        // The scan found the sources and their literals at all.
        #expect(names.contains("figure.fall"))
        #expect(names.count > 20)

        for name in names.sorted() {
            #expect(Self.symbolExists(name), "No SF Symbol named '\(name)'")
        }
    }

    /// String literals that name a symbol: those after `systemName:` /
    /// `systemImage:` (to the end of the line, so both branches of a ternary
    /// count), and those returned by the `systemImage` properties.
    nonisolated private static func repositoryRoot(filePath: String = #filePath) -> URL {
        URL(filePath: filePath)
            .deletingLastPathComponent()  // GameRPGTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repository root
    }

    /// `#filePath` is where the test bundle was built. A runner that only receives the built
    /// bundle (Xcode Cloud test runs) has no checkout there.
    nonisolated static var sourcesAreOnDisk: Bool {
        FileManager.default.fileExists(atPath: repositoryRoot().appending(path: "Modules/GameRPG/BattleRound").path(percentEncoded: false))
    }

    private static func symbolNamesInSources() throws -> Set<String> {
        let repository = repositoryRoot()
        let folders = [
            repository.appending(path: "Modules/GameRPG/BattleRound"),
            repository.appending(path: "Modules/GameRPG/GameViews")
        ]
        let literal = try Regex(#""([a-z0-9]+(?:\.[a-z0-9]+)*)""#, as: (Substring, Substring).self)
        var names: Set<String> = []
        for folder in folders {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "swift" {
                guard folder.lastPathComponent == "BattleRound" || file.lastPathComponent.hasPrefix("BattleRound") else {
                    continue
                }
                let source = try String(contentsOf: file, encoding: .utf8)
                var inSymbolProperty = false
                for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                    if line.contains("SystemImage: String {") || line.contains("systemImage: String {") {
                        inSymbolProperty = true
                    } else if inSymbolProperty, line.hasPrefix("    }") {
                        inSymbolProperty = false
                    }
                    let scanned: Substring
                    if let range = line.range(of: "systemName:") ?? line.range(of: "systemImage:") {
                        scanned = line[range.upperBound...]
                    } else if inSymbolProperty {
                        scanned = line
                    } else {
                        continue
                    }
                    for match in scanned.matches(of: literal) {
                        names.insert(String(match.1))
                    }
                }
            }
        }
        return names
    }

    private static func symbolExists(_ name: String) -> Bool {
#if canImport(UIKit)
        UIImage(systemName: name) != nil
#elseif canImport(AppKit)
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
#else
        true
#endif
    }
}

@MainActor
@Suite("Battle round broadcast")
struct BattleRoundBroadcastTests {
    @Test("The log passes a message once and again only when it changed")
    func logSkipsRepeats() {
        let log = BattleRoundBroadcastLog()
        let mapId = UUID()
        let first = BattleRoundNetworkState(mapId: mapId, isRunning: true, roundCounter: 1, activePinId: nil, sequence: 3)
        let second = BattleRoundNetworkState(mapId: mapId, isRunning: true, roundCounter: 1, activePinId: nil, sequence: 4)

        #expect(log.shouldSend(battleRound: first))
        #expect(!log.shouldSend(battleRound: first))
        #expect(log.shouldSend(battleRound: second))

        let generation = MapGameModel.AuthoritativeGeneration(version: 1, assetVersion: 1, contentVersion: 1)
        let pin = MapPinModel(id: UUID(), name: "Goblin")
        var woundedPin = pin
        woundedPin.healthPercent = 50
        let mapState = MapLiveState(mapId: mapId, generation: generation, rooms: [], pointer: pin, pins: [pin])
        let changedMapState = MapLiveState(mapId: mapId, generation: generation, rooms: [], pointer: pin, pins: [woundedPin])
        #expect(log.shouldSend(mapState: mapState))
        #expect(!log.shouldSend(mapState: mapState))
        #expect(log.shouldSend(mapState: changedMapState))

        log.reset()
        #expect(log.shouldSend(battleRound: second))
        #expect(log.shouldSend(mapState: changedMapState))
    }

    @Test("An action that changes nothing a participant sees sends nothing")
    func unchangedStateIsNotResent() async throws {
        // Given: a running battle whose state has gone out once.
        let fixture = try await BattleScreenFixture.make()
        let spy = BroadcastSpy()
        fixture.root.networkActions = spy.actions
        #expect(fixture.controller.nextRound())
        #expect(spy.actionsSent == [.mapState, .battleRound])
        spy.reset()

        // When: the configured values are scanned again and nothing changes.
        fixture.controller.refreshConfiguredValues()

        // Then: neither message is repeated.
        #expect(spy.actionsSent == [])

        // When: the turn moves on, both the pins and the round change.
        #expect(fixture.controller.nextAttacker())

        // Then
        #expect(spy.actionsSent == [.mapState, .battleRound])
    }

    @Test("Marking a combatant dead changes pins but not the round, so only the map goes out")
    func pinOnlyChangeSendsOnlyTheMap() async throws {
        let fixture = try await BattleScreenFixture.make()
        let spy = BroadcastSpy()
        fixture.root.networkActions = spy.actions
        #expect(fixture.controller.nextRound())
        spy.reset()

        // The goblin is not the active attacker and nobody's target.
        #expect(fixture.controller.model.activeAttackerId != fixture.goblin.id)
        #expect(fixture.controller.setDead(fixture.goblin.id, true))

        #expect(spy.actionsSent == [.mapState])
    }

    @Test("The initiative order can be set before the first battle and needs no broadcast")
    func initiativeOrderNeedsNoRunningBattle() async throws {
        // Given: the master's device, no battle started in this session.
        let root = try await MockRoot.createGameRoot()
        let masterId = UUID()
        root.gameModel.gameConfig = GameConfigModel(
            id: masterId,
            state: .started,
            master: MasterGameModel(id: masterId, type: .master, name: "Master")
        )
        let spy = BroadcastSpy()
        root.networkActions = spy.actions
        let settings = root.mapRoot.mapGameControllable.battleRoundSettings
        let previousOrder = settings.initiativeOrder
        defer { root.battleRoundController.setInitiativeOrder(previousOrder) }
        root.battleRoundController.setInitiativeOrder(.descending)
        #expect(root.battleRoundController.model.mapId == nil)

        // When
        #expect(root.battleRoundController.setInitiativeOrder(.ascending))

        // Then: saved, applied to the model, nothing sent.
        #expect(settings.initiativeOrder == .ascending)
        #expect(root.battleRoundController.model.initiativeOrder == .ascending)
        #expect(spy.actionsSent.isEmpty)
    }

    @Test("A player cannot change the initiative order")
    func playerCannotSetTheInitiativeOrder() async throws {
        let root = try await MockRoot.createGameRoot()
        let settings = root.mapRoot.mapGameControllable.battleRoundSettings
        let order = settings.initiativeOrder
        let other: BattleInitiativeOrder = order == .ascending ? .descending : .ascending

        #expect(!root.battleRoundController.setInitiativeOrder(other))
        #expect(settings.initiativeOrder == order)
    }
}

@MainActor
private final class BroadcastSpy {
    private(set) var actionsSent: [RPGMessageActionType] = []

    lazy var actions = NetworkActions(
        shareId: { _ in },
        send: { _ in },
        game: { [weak self] _, action, _ in
            self?.actionsSent.append(action)
        }
    )

    func reset() {
        actionsSent = []
    }
}
