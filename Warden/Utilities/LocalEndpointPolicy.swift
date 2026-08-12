import Foundation

/// Restricts local-provider traffic to loopback or RFC 1918/private LAN hosts.
/// Local providers can receive conversation content, so public endpoints are not valid here.
enum LocalEndpointPolicy {
    static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased()
        else { return false }

        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1" {
            return true
        }

        if let ipv4 = IPv4Address(host) {
            return ipv4.isLoopback || ipv4.isPrivate
        }

        if let ipv6 = IPv6Address(host) {
            return ipv6.isLoopback || ipv6.isUniqueLocal || ipv6.isLinkLocal
        }

        return false
    }

    static func validate(_ url: URL) throws {
        guard allows(url) else {
            throw APIError.noApiService("Local providers require a loopback or private-LAN endpoint.")
        }
    }
}

private struct IPv4Address {
    let octets: [UInt8]

    init?(_ host: String) {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let parsed = parts.compactMap { UInt8($0) }
        guard parsed.count == 4 else { return nil }
        octets = parsed
    }

    var isLoopback: Bool { octets[0] == 127 }

    var isPrivate: Bool {
        switch (octets[0], octets[1]) {
        case (10, _), (192, 168), (172, 16...31):
            return true
        default:
            return false
        }
    }
}

private struct IPv6Address {
    let host: String

    init?(_ host: String) {
        guard host.contains(":"), let address = IPv6Address.normalized(host) else { return nil }
        self.host = address
    }

    var isLoopback: Bool { host == "::1" }
    var isUniqueLocal: Bool { host.hasPrefix("fc") || host.hasPrefix("fd") }
    var isLinkLocal: Bool { host.hasPrefix("fe8") || host.hasPrefix("fe9") || host.hasPrefix("fea") || host.hasPrefix("feb") }

    private static func normalized(_ host: String) -> String? {
        let withoutZone = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        return withoutZone.lowercased()
    }
}
