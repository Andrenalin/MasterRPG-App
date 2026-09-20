// @copyright André Trettin

import Foundation

// MARK: - Read Budget Tracking

struct FoundryVTTReadBudget {
    var encodedBytes = 0
    var decodedBytes = 0
    var recordCount = 0

    mutating func includeEncoded(_ count: Int, limits: FoundryImportLimits) throws {
        let (next, overflow) = encodedBytes.addingReportingOverflow(count)
        guard !overflow, next <= limits.maximumRuleDataSize else {
            throw FoundryImportError.fileTooLarge(overflow ? Int.max : next)
        }
        encodedBytes = next
    }

    mutating func includeDecoded(_ count: Int, limits: FoundryImportLimits) throws {
        let (next, overflow) = decodedBytes.addingReportingOverflow(count)
        guard !overflow, next <= limits.maximumRuleDataSize else {
            throw FoundryImportError.fileTooLarge(overflow ? Int.max : next)
        }
        decodedBytes = next
    }

    mutating func includeRecord(limits: FoundryImportLimits) throws {
        let (next, overflow) = recordCount.addingReportingOverflow(1)
        guard !overflow, next <= limits.maximumDocumentCount else {
            throw FoundryImportError.tooManyDocuments(overflow ? Int.max : next)
        }
        recordCount = next
    }
}
