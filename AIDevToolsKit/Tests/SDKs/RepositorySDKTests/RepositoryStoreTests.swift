import Foundation
import Testing
@testable import RepositorySDK

@Suite("RepositoryStore")
struct RepositoryStoreTests {
    private func makeTempStore() throws -> (RepositoryStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return (RepositoryStore(repositoriesFile: tempDir.appending(path: "repositories.json")), tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("loadAll returns empty array when no file exists")
    func loadAllReturnsEmptyWhenNoFile() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }

        // Act
        let result = try store.loadAll()

        // Assert
        #expect(result.isEmpty)
    }

    @Test("save and load preserves all repository fields")
    func saveAndLoadRoundTrip() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let repos = [
            RepositoryConfiguration(path: URL(filePath: "/tmp/repo1")),
            RepositoryConfiguration(
                path: URL(filePath: "/tmp/repo2"),
                name: "Custom Name",
                description: "A test repo",
                pullRequest: PullRequestConfig(baseBranch: "main", branchNamingConvention: "feature/<name>"),
                verification: Verification(commands: ["swift build"])
            ),
        ]

        // Act
        try store.save(repos)
        let loaded = try store.loadAll()

        // Assert
        #expect(loaded.count == 2)
        #expect(loaded[0].id == repos[0].id)
        #expect(loaded[0].name == "repo1")
        #expect(loaded[1].name == "Custom Name")
        #expect(loaded[1].description == "A test repo")
        #expect(loaded[1].verification?.commands == ["swift build"])
    }

    @Test("add appends a repository to the existing list")
    func addAppendsRepository() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let first = RepositoryConfiguration(path: URL(filePath: "/tmp/repo1"))
        let second = RepositoryConfiguration(path: URL(filePath: "/tmp/repo2"))

        // Act
        try store.add(first)
        try store.add(second)
        let loaded = try store.loadAll()

        // Assert
        #expect(loaded.count == 2)
        #expect(loaded[0].id == first.id)
        #expect(loaded[1].id == second.id)
    }

    @Test("update modifies an existing repository by ID")
    func updateModifiesExistingRepository() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let original = RepositoryConfiguration(path: URL(filePath: "/tmp/repo1"), name: "Original")
        try store.add(original)

        var updated = original
        updated.description = "Updated description"

        // Act
        try store.update(updated)
        let loaded = try store.loadAll()

        // Assert
        #expect(loaded.count == 1)
        #expect(loaded[0].id == original.id)
        #expect(loaded[0].description == "Updated description")
    }

    @Test("remove deletes a repository by ID")
    func removeDeletesById() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let first = RepositoryConfiguration(path: URL(filePath: "/tmp/repo1"))
        let second = RepositoryConfiguration(path: URL(filePath: "/tmp/repo2"))
        try store.save([first, second])

        // Act
        try store.remove(id: first.id)
        let loaded = try store.loadAll()

        // Assert
        #expect(loaded.count == 1)
        #expect(loaded[0].id == second.id)
    }

    @Test("find(byID:) returns the matching repository or nil")
    func findByID() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let repo = RepositoryConfiguration(path: URL(filePath: "/tmp/repo1"), name: "Target")
        let other = RepositoryConfiguration(path: URL(filePath: "/tmp/repo2"))
        try store.save([repo, other])

        // Act
        let found = try store.find(byID: repo.id)
        let notFound = try store.find(byID: UUID())

        // Assert
        #expect(found?.name == "Target")
        #expect(notFound == nil)
    }

    @Test("find(byPath:) returns the matching repository or nil")
    func findByPath() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let targetPath = URL(filePath: "/tmp/repo1")
        let repo = RepositoryConfiguration(path: targetPath, name: "Target")
        try store.save([repo])

        // Act
        let found = try store.find(byPath: targetPath)
        let notFound = try store.find(byPath: URL(filePath: "/nonexistent"))

        // Assert
        #expect(found?.name == "Target")
        #expect(notFound == nil)
    }
}
