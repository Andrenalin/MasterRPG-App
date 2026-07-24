// @copyright André Trettin

import Foundation

/// Decodes untrusted base64 only after proving that its decoded representation fits the
/// caller's byte budget. This avoids asking Foundation to allocate an attacker-controlled
/// decoded buffer before the import limits are applied.
enum FoundryBoundedBase64 {
    static func decode(
        _ encoded: String,
        maximumDecodedByteCount: Int,
        invalidMessage: String
    ) throws -> Data {
        guard maximumDecodedByteCount >= 0,
              let decodedByteCount = decodedByteCount(for: encoded) else {
            throw FoundryImportError.invalidArchive(invalidMessage)
        }
        guard decodedByteCount <= maximumDecodedByteCount else {
            throw FoundryImportError.fileTooLarge(decodedByteCount)
        }
        guard let data = Data(base64Encoded: encoded), data.count == decodedByteCount else {
            throw FoundryImportError.invalidArchive(invalidMessage)
        }
        return data
    }

    /// Returns the exact decoded length for canonical padded or unpadded base64 without
    /// allocating decoded storage. Foundation performs the full alphabet validation later.
    private static func decodedByteCount(for encoded: String) -> Int? {
        let bytes = encoded.utf8
        let encodedByteCount = bytes.count
        guard encodedByteCount > 0 else { return 0 }

        let remainder = encodedByteCount % 4
        guard remainder != 1 else { return nil }

        var padding = 0
        if bytes.last == 0x3d { // "="
            padding = 1
            if encodedByteCount >= 2,
               bytes[bytes.index(bytes.endIndex, offsetBy: -2)] == 0x3d {
                padding = 2
            }
        }
        guard padding == 0 || remainder == 0 else { return nil }

        let completeGroups = encodedByteCount / 4
        let (completeBytes, overflow) = completeGroups.multipliedReportingOverflow(by: 3)
        guard !overflow else { return nil }
        let remainderBytes = switch remainder {
        case 2: 1
        case 3: 2
        default: 0
        }
        let (withoutPadding, additionOverflow) = completeBytes.addingReportingOverflow(remainderBytes)
        guard !additionOverflow, withoutPadding >= padding else { return nil }
        return withoutPadding - padding
    }
}
