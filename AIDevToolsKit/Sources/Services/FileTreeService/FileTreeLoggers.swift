import Logging

enum FileTreeLoggers {
    static let cache = Logger(label: "FileTreeService.DirectoryCache")
    static let item = Logger(label: "FileTreeService.FileSystemItem")
    static let monitor = Logger(label: "FileTreeService.FileSystemMonitor")
    static let service = Logger(label: "FileTreeService")
}
