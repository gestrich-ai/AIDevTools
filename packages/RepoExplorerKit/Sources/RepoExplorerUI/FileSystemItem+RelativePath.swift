import RepoExplorerFileTreeService

extension FileSystemItem {
    func relativePath(from rootPath: String) -> String {
        guard path.hasPrefix(rootPath) else { return path }
        let relative = String(path.dropFirst(rootPath.count))
        return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
    }
}
