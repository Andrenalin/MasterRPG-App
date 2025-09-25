// @copyright André Trettin

import Foundation

protocol MessageMapper {
    func encodeData() -> Data?
    static func decodeData(of data: Data?) -> Self?
}
