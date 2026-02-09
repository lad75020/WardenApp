import Foundation

struct VeoUserParameters: Codable, Equatable {
    /// Raw aspect ratio string as expected by the Veo REST API (e.g. "16:9").
    /// Kept as `String` (not an enum) so we can support additional ratios without code changes.
    var aspectRatio: String
    var durationSeconds: Int
    var negativePrompt: String

    static let supportedAspectRatios: [String] = [
        "16:9",
        "9:16",
        "1:1",
        "4:3"
    ]

    static let `default` = VeoUserParameters(
        aspectRatio: "16:9",
        durationSeconds: 8,
        negativePrompt: "blurry, low quality, distorted, flickering"
    )
}
