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
        // Resolve each existing prefix before moving through ..; the final directory may not exist yet.
        var resolved = URL(fileURLWithPath: "/", isDirectory: true)
        for component in directory.pathComponents.dropFirst() {
            switch component {
            case ".", "": continue
            case "..": if resolved.path != "/" { resolved.deleteLastPathComponent() }
            default:
                resolved.append(path: component)
                resolved = resolved.resolvingSymlinksInPath()
            }
        }
        return resolved.standardizedFileURL.path
    }
}
