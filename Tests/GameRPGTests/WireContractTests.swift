// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import CoreRPG
@testable import GameRPG

/// CODE_AUDIT_Game_Shareplay §4.1. The wire enums decode strictly, so a changed case list is a
/// change of the wire format and has to come with a new `GameNetworkModel.currentVersion`.
/// This file pins both: it fails when only one of them moves.
@Suite("Wire contract")
struct WireContractTests {
    /// The version the pinned cases below belong to. Change it together with the lists.
    static let pinnedVersion = 3

    static let pinnedModules: Set<Int> = [0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]
    static let pinnedMessageTypes: Set<Int> = [1, 2, 3]
    static let pinnedActionTypes: Set<Int> = [1, 2, 3, 4, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 200, 300, 400]

    private static let scanLimit = 1024

    private static func rawValues<E: RawRepresentable>(of _: E.Type) -> Set<Int> where E.RawValue == Int {
        Set((0 ..< scanLimit).filter { E(rawValue: $0) != nil })
    }

    @Test("The wire enums and the wire version only change together")
    func enumsAndVersionArePinnedTogether() {
        let message = "A case of a wire enum changed. Bump GameNetworkModel.currentVersion, then update WireContractTests (pinnedVersion and the pinned lists)."
        #expect(Self.rawValues(of: NetworkModules.self) == Self.pinnedModules, Comment(rawValue: message))
        #expect(Self.rawValues(of: RPGMessageType.self) == Self.pinnedMessageTypes, Comment(rawValue: message))
        #expect(Self.rawValues(of: RPGMessageActionType.self) == Self.pinnedActionTypes, Comment(rawValue: message))
        #expect(GameNetworkModel.currentVersion == Self.pinnedVersion, Comment(rawValue: message))
    }

    @Test("Every module case is on the wire list")
    func everyModuleIsPinned() {
        #expect(Set(NetworkModules.allCases.map(\.rawValue)) == Self.pinnedModules)
    }

    @Test("An envelope with a case this version does not know is dropped, not misread")
    func unknownCaseIsDropped() throws {
        let known = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            gameConfig: GameConfigModel(id: UUID(), state: .started, master: .empty),
            data: NetworkCodableDataType(id: UUID(), type: .value, version: 1, data: nil)
        )
        let bytes = try #require(known.encodeData())
        #expect(GameNetworkModel.decodeData(of: bytes) != nil)

        for (key, unknown) in [("subType", 999), ("type", 999)] {
            var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            json[key] = unknown
            let changed = try JSONSerialization.data(withJSONObject: json)
            #expect(GameNetworkModel.decodeData(of: changed) == nil, "unknown \(key)")
        }

        var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var data = try #require(json["data"] as? [String: Any])
        data["type"] = 999
        json["data"] = data
        let changed = try JSONSerialization.data(withJSONObject: json)
        #expect(GameNetworkModel.decodeData(of: changed) == nil, "unknown module")
    }

    @Test("An envelope of another wire version is refused")
    func otherVersionIsRefused() throws {
        let known = GameNetworkModel(
            counter: 1,
            proxyCounter: 0,
            type: .update,
            subType: .generic,
            gameConfig: GameConfigModel(id: UUID(), state: .started, master: .empty),
            data: NetworkCodableDataType(id: UUID(), type: .value, version: 1, data: nil)
        )
        let bytes = try #require(known.encodeData())
        var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        json["version"] = GameNetworkModel.currentVersion + 1

        let changed = try JSONSerialization.data(withJSONObject: json)

        #expect(GameNetworkModel.decodeData(of: changed) == nil)
    }
}
#endif
