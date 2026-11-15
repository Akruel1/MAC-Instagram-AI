import Foundation

public enum PathSafety {
    /// Resolve and ensure `path` is within `root` after resolving symlinks.
    public static func resolveContainedPath(path: String, root: URL) throws -> URL {
        let rootResolved = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate: URL
        if path.hasPrefix("/") {
            candidate = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        } else {
            candidate = rootResolved.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        }
        let rootPath = rootResolved.path
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else {
            throw AppError.unsafeOperation("Path escapes allowed root: \(path)")
        }
        // Block obvious traversal tokens before resolution as defense-in-depth for relative inputs.
        if path.contains("..") && !FileManager.default.fileExists(atPath: candidatePath) {
            // Still allow legitimate filenames containing ".." only if resolved path is inside root
            // (already checked). Empty extra check for explicit patterns:
        }
        if path.split(separator: "/").contains("..") {
            // After standardization, if still outside we already threw; relative ".." that stay inside root are OK.
            // Reject unresolved traversal attempts that would leave root when joined without existing symlink targets.
            let naive = rootResolved.appendingPathComponent(path).standardizedFileURL.path
            if !(naive == rootPath || naive.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")) {
                throw AppError.unsafeOperation("Path traversal blocked: \(path)")
            }
        }
        return candidate
    }

    public static func assertNoShellMetacharacters(_ value: String, label: String) throws {
        let forbidden = CharacterSet(charactersIn: ";|&$`\n\r")
        if value.rangeOfCharacter(from: forbidden) != nil {
            throw AppError.unsafeOperation("\(label) contains forbidden shell metacharacters")
        }
    }
}
