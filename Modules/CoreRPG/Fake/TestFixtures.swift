// @copyright André Trettin

import Foundation

#if DEBUG
/// Deterministic test fixtures for dates and UUIDs.
///
/// These fixtures provide repeatable values for tests, ensuring F.I.R.S.T. principles
/// (especially Repeatable). Using fixed values instead of `Date()` or `UUID()` prevents
/// flaky tests and makes debugging easier.
///
/// **Usage:**
/// ```swift
/// let model = SomeModel(
///     id: .fixture1,
///     createdAt: .fixture2024Jan1
/// )
/// ```
public extension Date {
    /// January 1, 2024 00:00:00 UTC
    static let fixture2024Jan1 = Date(timeIntervalSince1970: 1704067200)

    /// June 15, 2024 12:00:00 UTC (mid-year reference point)
    static let fixture2024Jun15 = Date(timeIntervalSince1970: 1718452800)

    /// December 31, 2024 23:59:59 UTC
    static let fixture2024Dec31 = Date(timeIntervalSince1970: 1735689599)

    /// January 1, 2025 00:00:00 UTC
    static let fixture2025Jan1 = Date(timeIntervalSince1970: 1735689600)
}

public extension UUID {
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

    /// Fixed UUID for table entities
    static let fixtureTable = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!

    /// Fixed UUID for character entities
    static let fixtureCharacter = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
}
#endif
