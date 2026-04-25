import Foundation

#if canImport(Combine)
import Combine

public typealias FileSystemItemObservable = ObservableObject
#else
public protocol FileSystemItemObservable: AnyObject {}
#endif

public final class FileSystemItem: Codable, Equatable, Identifiable, FileSystemItemObservable, @unchecked Sendable {
    private static let ideExcludePatterns: [String] = [
        ".build",
        ".cache",
        ".DS_Store",
        ".dia",
        ".gradle",
        ".idea",
        ".scan",
        ".svn",
        ".vscode",
        "__pycache__",
        "*.class",
        "*.dia",
        "*.log",
        "*.o",
        "*.pyc",
        "*.swo",
        "*.swp",
        "*.tmp",
        "*.xcworkspace",
        "Build",
        "build",
        "DerivedData",
        "dist",
        "node_modules",
        "out",
        "Pods",
        "target",
        "xcuserdata",
    ]

    public static func == (lhs: FileSystemItem, rhs: FileSystemItem) -> Bool {
        lhs.id == rhs.id
    }

    public let id: UUID
    public let isDirectory: Bool
    public let name: String
    public let url: URL
    #if canImport(Combine)
    @Published public var children: [FileSystemItem]?
    @Published public var isExpanded: Bool = false
    #else
    public var children: [FileSystemItem]?
    public var isExpanded: Bool = false
    #endif

    public var path: String {
        url.path
    }

    enum CodingKeys: String, CodingKey {
        case children
        case id
        case isDirectory
        case name
        case url
    }

    public init(url: URL, isDirectory: Bool) {
        self.id = UUID()
        self.isDirectory = isDirectory
        self.name = url.lastPathComponent
        self.url = url
        self.children = isDirectory ? [] : nil
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.url = try container.decode(URL.self, forKey: .url)
        self.name = try container.decode(String.self, forKey: .name)
        self.isDirectory = try container.decode(Bool.self, forKey: .isDirectory)
        self.children = try container.decodeIfPresent([FileSystemItem].self, forKey: .children)
        self.isExpanded = false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(children, forKey: .children)
        try container.encode(id, forKey: .id)
        try container.encode(isDirectory, forKey: .isDirectory)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
    }

    public func loadChildren(ignorePatterns: [String]) -> [FileSystemItem] {
        guard isDirectory else {
            return []
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var items: [FileSystemItem] = []
            for itemURL in contents {
                let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues.isDirectory ?? false

                if shouldInclude(path: itemURL.path, ignorePatterns: ignorePatterns) {
                    items.append(FileSystemItem(url: itemURL, isDirectory: isDirectory))
                }
            }

            items.sort { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }

                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return items
        } catch {
            FileTreeLoggers.item.warning("Failed to load children for \(url.path): \(error)")
            return []
        }
    }

    public func setChildren(_ items: [FileSystemItem]) {
        children = items
    }

    private func matchesPattern(path _: String, fileName: String, pattern: String) -> Bool {
        let trimmedPattern = pattern.trimmingCharacters(in: .whitespaces)

        if trimmedPattern.isEmpty || trimmedPattern.hasPrefix("#") {
            return false
        }

        if trimmedPattern.hasSuffix("/") {
            let directoryPattern = String(trimmedPattern.dropLast())
            return fileName == directoryPattern
        }

        if trimmedPattern.hasPrefix("*") && trimmedPattern.hasSuffix("*") {
            let middle = String(trimmedPattern.dropFirst().dropLast())
            return fileName.contains(middle)
        }

        if trimmedPattern.hasPrefix("*") {
            let suffix = String(trimmedPattern.dropFirst())
            return fileName.hasSuffix(suffix)
        }

        if trimmedPattern.hasSuffix("*") {
            let prefix = String(trimmedPattern.dropLast())
            return fileName.hasPrefix(prefix)
        }

        return fileName == trimmedPattern
    }

    private func shouldInclude(path: String, ignorePatterns: [String]) -> Bool {
        let fileName = (path as NSString).lastPathComponent

        for pattern in Self.ideExcludePatterns where matchesPattern(path: path, fileName: fileName, pattern: pattern) {
            return false
        }

        for pattern in ignorePatterns where matchesPattern(path: path, fileName: fileName, pattern: pattern) {
            return false
        }

        return true
    }
}
