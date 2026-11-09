// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

// MARK: - Messenger payload budget

enum SharePlayMessengerPayloadBudget {
    // GameNetworkModel deliberately uses `.withoutEscapingSlashes`, so Data has
    // only Base64's 4/3 expansion. Reserve one MB for the rest of the model so
    // every admitted raw payload fits the sender's 64 MB complete-message limit
    // without first materializing an undeliverable blob.
    nonisolated static let metadataHeadroom = ByteUnit.megabyte
    nonisolated static let maximumRawPayloadByteCount =
        ((SharePlaySingleQueuePackageSender.maxMessageByteCount - metadataHeadroom) / 4) * 3
    nonisolated static let maximumOutstandingRawPayloadByteCount = maximumRawPayloadByteCount * 2

    nonisolated static func accepts(rawPayloadByteCount: Int) -> Bool {
        rawPayloadByteCount >= 0 && rawPayloadByteCount <= maximumRawPayloadByteCount
    }
}
