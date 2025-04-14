// @copyright André Trettin

import Foundation

public enum JSONString {
    public static func decode<Value: Codable, Other: StringProtocol>(text: Other?) -> Value? {
        guard let text else { return nil }
        let decoder = JSONDecoder()
        guard let data = text.data(using: .utf8) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    public static func encode<Value: Codable>(value: Value) -> String? {
        let encoder = JSONEncoder()
        guard let encodedData = try? encoder.encode(value) else {
            return nil
        }
        let text = String(data: encodedData, encoding: String.Encoding.utf8)
        return text
    }
}
