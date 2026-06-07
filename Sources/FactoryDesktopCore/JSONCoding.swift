import Foundation

public enum JSONCoding {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    public static func decode<T: Decodable>(_ value: String?, as type: T.Type) -> T? {
        guard let value, let data = value.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    public static func encodeArray(_ value: [String]) -> String {
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    public static func decodeArray(_ value: String?) -> [String] {
        guard let value, let data = value.data(using: .utf8) else { return [] }
        return (try? decoder.decode([String].self, from: data)) ?? []
    }

    public static func encodeDictionary(_ value: [String: String]) -> String {
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    public static func decodeDictionary(_ value: String?) -> [String: String] {
        guard let value, let data = value.data(using: .utf8) else { return [:] }
        return (try? decoder.decode([String: String].self, from: data)) ?? [:]
    }
}
