import Foundation

public struct FeatureAvailability: Sendable, Equatable, Codable {
    public var claudeConfigured: Bool
    public var instagramAuthenticated: Bool
    public var ffmpegAvailable: Bool
    public var nodeAvailable: Bool
    public var pythonAvailable: Bool
    public var hermesAvailable: Bool
    public var mcpEnabled: Bool

    public init(
        claudeConfigured: Bool = false,
        instagramAuthenticated: Bool = false,
        ffmpegAvailable: Bool = false,
        nodeAvailable: Bool = false,
        pythonAvailable: Bool = false,
        hermesAvailable: Bool = false,
        mcpEnabled: Bool = true
    ) {
        self.claudeConfigured = claudeConfigured
        self.instagramAuthenticated = instagramAuthenticated
        self.ffmpegAvailable = ffmpegAvailable
        self.nodeAvailable = nodeAvailable
        self.pythonAvailable = pythonAvailable
        self.hermesAvailable = hermesAvailable
        self.mcpEnabled = mcpEnabled
    }
}
