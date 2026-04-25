import ArgumentParser
import FileTreeService
import Foundation

func absoluteURL(for path: String) -> URL {
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(path)
        .standardizedFileURL
}

func resolvedDestinationURL(from sourceURL: URL, input: String) -> URL {
    let inputURL = URL(filePath: input)
    if inputURL.pathComponents.count > 1 || input.hasPrefix("/") || input.hasPrefix(".") {
        return absoluteURL(for: input)
    }
    return sourceURL.deletingLastPathComponent().appendingPathComponent(input)
}

func displayPath(for file: FileSystemItem, rootPath: String, fullPaths: Bool) -> String {
    guard !fullPaths else {
        return file.url.standardizedFileURL.path
    }

    let rootURL = URL(filePath: rootPath).standardizedFileURL
    let fileURL = file.url.standardizedFileURL
    let rootPathPrefix = rootURL.path + "/"
    return fileURL.path.replacingOccurrences(of: rootPathPrefix, with: "")
}

func filteredFiles(from files: [FileSystemItem], rootPath: String, filter: String?) throws -> [FileSystemItem] {
    let sortedFiles = files.sorted { lhs, rhs in
        lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
    }

    guard let filter, !filter.isEmpty else {
        return sortedFiles
    }

    return sortedFiles.filter { file in
        let relativePath = displayPath(for: file, rootPath: rootPath, fullPaths: false)
        return wildcardPatternMatches(relativePath, pattern: filter) || wildcardPatternMatches(file.name, pattern: filter)
    }
}

private func wildcardPatternMatches(_ value: String, pattern: String) -> Bool {
    var regexPattern = "^"

    for character in pattern {
        switch character {
        case "*":
            regexPattern += ".*"
        case "?":
            regexPattern += "."
        default:
            regexPattern += NSRegularExpression.escapedPattern(for: String(character))
        }
    }

    regexPattern += "$"
    return value.range(of: regexPattern, options: .regularExpression) != nil
}

func makeFileTreeService() throws -> FileTreeService {
    let root = try CLICompositionRoot.create()
    return root.fileTreeService
}

func validatedDirectoryURL(for path: String) throws -> URL {
    let directoryURL = absoluteURL(for: path)
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)

    guard exists else {
        throw ValidationError("Path does not exist: \(directoryURL.path)")
    }

    guard isDirectory.boolValue else {
        throw ValidationError("Path is not a directory: \(directoryURL.path)")
    }

    return directoryURL
}
