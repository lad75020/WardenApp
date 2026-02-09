import Foundation

/// Configures Google Veo video generation parameters used by the UI.
/// This struct is serialized into a hidden tag for API payloads.
public struct VeoUserParameters: Codable, Equatable, Sendable {
    /// The aspect ratio of the generated video, e.g. "16:9".
    public var aspectRatio: String
    /// The duration of the generated video in seconds.
    public var durationSeconds: Int
    /// Negative prompt to influence video content generation.
    public var negativePrompt: String

    /// Default instance with standard video generation parameters.
    public static let `default` = VeoUserParameters()

    /// Initializes VeoUserParameters with optional custom values.
    /// - Parameters:
    ///   - aspectRatio: The desired aspect ratio. Default is "16:9".
    ///   - durationSeconds: The desired video duration in seconds. Default is 6.
    ///   - negativePrompt: Negative prompt to influence content. Default is "".
    public init(
        aspectRatio: String = "16:9",
        durationSeconds: Int = 6,
        negativePrompt: String = ""
    ) {
        self.aspectRatio = aspectRatio
        self.durationSeconds = durationSeconds
        self.negativePrompt = negativePrompt
    }
}
