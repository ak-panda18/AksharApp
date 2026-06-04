import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "BundleDataLoader")

final class BundleDataLoader {

    init() {}
    func load<T: Decodable>(_ filename: String, as type: T.Type) -> T {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            logger.fault("BundleDataLoader: \(filename).json not found in bundle")
            fatalError("BundleDataLoader: \(filename).json not found in bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.fault("BundleDataLoader: failed to decode \(filename).json – \(error)")
            fatalError("BundleDataLoader: failed to decode \(filename).json – \(error)")
        }
    }

    func tryLoad<T: Decodable>(_ filename: String, as type: T.Type) -> T? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            logger.warning("BundleDataLoader: \(filename).json not found in bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("BundleDataLoader: failed to decode \(filename).json – \(error)")
            return nil
        }
    }
}
