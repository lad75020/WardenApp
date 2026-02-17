

import Foundation
import KeychainAccess

class TokenManager {
    private static let keychain = Keychain(service: "fr.dubertrand.WardenAI")
        .accessibility(.afterFirstUnlock)
    private static let tokenPrefix = "api_token_"
    private static let bundleKey = "api_tokens_bundle"
    private static var cachedTokens: [String: String]?
    
    enum TokenError: Error {
        case setFailed
        case getFailed
        case deleteFailed
    }
    
    static func setToken(_ token: String, for service: String, identifier: String? = nil) throws {
        let key = makeKey(for: service, identifier: identifier)
        do {
            var bundle = try loadBundle()
            bundle[key] = token
            try saveBundle(bundle)
            cachedTokens = bundle
            // Clean up legacy per-item storage if present.
            try? keychain.remove(key)
        } catch {
            throw TokenError.setFailed
        }
    }
    
    static func getToken(for service: String, identifier: String? = nil) throws -> String? {
        let key = makeKey(for: service, identifier: identifier)
        do {
            if let cachedTokens, let value = cachedTokens[key] {
                return value
            }
            var bundle = try loadBundle()
            if let value = bundle[key] {
                cachedTokens = bundle
                return value
            }
            // Fallback to legacy per-item key; migrate if found.
            if let legacy = try keychain.get(key) {
                bundle[key] = legacy
                try saveBundle(bundle)
                cachedTokens = bundle
                try? keychain.remove(key)
                return legacy
            }
            cachedTokens = bundle
            return nil
        } catch {
            throw TokenError.getFailed
        }
    }
    
    static func deleteToken(for service: String, identifier: String? = nil) throws {
        let key = makeKey(for: service, identifier: identifier)
        do {
            var bundle = try loadBundle()
            bundle.removeValue(forKey: key)
            try saveBundle(bundle)
            cachedTokens = bundle
            try? keychain.remove(key)
        } catch {
            throw TokenError.deleteFailed
        }
    }

    private static func loadBundle() throws -> [String: String] {
        if let cachedTokens {
            return cachedTokens
        }
        guard let data = try keychain.getData(bundleKey) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func saveBundle(_ bundle: [String: String]) throws {
        let data = try JSONEncoder().encode(bundle)
        try keychain.set(data, key: bundleKey)
    }
    
    private static func makeKey(for service: String, identifier: String?) -> String {
        if let identifier = identifier {
            return "\(tokenPrefix)\(service)_\(identifier)"
        } else {
            return "\(tokenPrefix)\(service)"
        }
    }
}
