// @copyright André Trettin

import Foundation

//#if DEBUG
/// Deterministic test fixtures for UUIDs.
///
/// These fixtures provide repeatable values for tests, ensuring F.I.R.S.T. principles
/// (especially Repeatable). Using fixed values instead of `UUID()` prevents
/// flaky tests and makes debugging easier.
///
/// **Usage:**
/// ```swift
/// let model = SomeModel(id: .fixture1)
/// ```
public extension UUID {
    /// A deterministic id for previews and tests, from a literal UUID string. Shared by the
    /// module preview fixtures, which each had their own private copy. See CODE_AUDIT_18 §9.14.
    nonisolated static func fixture(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid deterministic preview UUID: \(value)")
        }
        return id
    }

    /// Fixed UUID for primary test entities
    static let fixture1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Fixed UUID for secondary test entities
    static let fixture2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    /// Fixed UUID for tertiary test entities
    static let fixture3 = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    /// Fixed UUID for quaternary test entities
    static let fixture4 = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    /// Fixed UUID for quinary test entities
    static let fixture5 = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!

    /// Fixed UUID for photo/image entities
    static let fixturePhoto = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    /// Fixed UUID for audio entities
    static let fixtureAudio = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    /// Fixed UUID for map entities
    static let fixtureMap = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

}
//#endif
