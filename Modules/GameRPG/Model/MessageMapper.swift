// @copyright André Trettin

import Foundation

protocol MessageMapper: Sendable {
    func encodeData() -> Data?
    static func decodeData(of data: Data?) -> Self?
}
