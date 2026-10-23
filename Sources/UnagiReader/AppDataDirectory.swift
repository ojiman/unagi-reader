import Foundation

/// Resolve the launch directory before creating a store or any of its supporting files.
enum AppDataDirectory {
    private enum Failure: LocalizedError {
        case unsafeSyntheticDirectory
        var errorDescription: String? {
            "A synthetic app requires --data-directory pointing outside the normal library."
        }
    }

    static func resolve(arguments: [String], bundleIdentifier: String?, normalDirectory: URL) throws -> URL {
        let index = arguments.firstIndex(of: "--data-directory")
        let path = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let prefix = "xyz.ojima.UnagiReader.Synthetic"
        let synthetic = bundleIdentifier == prefix || bundleIdentifier?.hasPrefix(prefix + ".") == true
        if synthetic {
            guard let path, !path.isEmpty, !path.hasPrefix("--"),
                  arguments.filter({ $0 == "--data-directory" }).count == 1 else {
                throw Failure.unsafeSyntheticDirectory
            }
        }
        let directory = path.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? normalDirectory
        if synthetic {
            let target = resolvedPath(directory).lowercased()
            let library = resolvedPath(normalDirectory).lowercased()
            guard target != library, !target.hasPrefix(library + "/") else {
                throw Failure.unsafeSyntheticDirectory
            }
        }
        return directory
    }

    private static func resolvedPath(_ directory: URL) -> String {
        // Foundation can leave ancestor aliases unresolved when the final directory does not exist yet.
        var ancestor = directory
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            missing.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var resolved = ancestor.resolvingSymlinksInPath().standardizedFileURL
        for component in missing.reversed() { resolved.append(path: component) }
        return resolved.path
    }
}
