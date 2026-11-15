import Foundation

/// Central feature availability for shipping builds. UI and navigation must consult this
/// rather than scattering ad-hoc workspace flags.
public enum FeaturePolicy: Sendable {
    /// Studio editor UI is deferred to a future version. FFmpeg tooling/diagnostics remain available.
    public static let studioWorkspaceEnabled = false

    public static let studioComingSoonMessage = "Studio is coming in a future version."

    public static func isWorkspaceEnabled(_ workspace: String) -> Bool {
        switch workspace {
        case "studio":
            return studioWorkspaceEnabled
        default:
            return true
        }
    }
}
