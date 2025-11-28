// @copyright André Trettin

import AndrenalinKit
import Foundation
import os.log

struct ValueResultModel: Equatable, Hashable, Codable {
    let valueModels: [ValueModel]
    let valueEntryModels: [ValueEntryModel]
}

extension ValueResultModel {
    func encodeData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }

    static func decodeData(of data: Data?) -> Self? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Self.self, from: data)
        } catch {
            Logger.codable.error("ValueResultModel error \(error, privacy: .public)")
        }
        return nil
    }
}
