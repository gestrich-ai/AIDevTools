import PRRadarModelsService
import Testing
@testable import GitUIToolkit

@Suite("GitDiffView")
struct GitDiffViewTests {
    @Test("renderedFiles exposes renamed files, pure renames, and diff lines")
    func renderedFilesExposeStructuredDiffContent() throws {
        let pureRename = Hunk(
            filePath: "Sources/NewName.swift",
            content: """
            diff --git a/Sources/OldName.swift b/Sources/NewName.swift
            similarity index 100%
            rename from Sources/OldName.swift
            rename to Sources/NewName.swift
            """,
            rawHeader: [
                "diff --git a/Sources/OldName.swift b/Sources/NewName.swift",
                "similarity index 100%",
                "rename from Sources/OldName.swift",
                "rename to Sources/NewName.swift",
            ],
            renameFrom: "Sources/OldName.swift"
        )
        let changedFile = Hunk(
            filePath: "Sources/Feature.swift",
            content: """
            diff --git a/Sources/Feature.swift b/Sources/Feature.swift
            index 1111111..2222222 100644
            --- a/Sources/Feature.swift
            +++ b/Sources/Feature.swift
            @@ -1,2 +1,3 @@
             struct Feature {
            +    let enabled = true
             }
            """,
            rawHeader: [
                "diff --git a/Sources/Feature.swift b/Sources/Feature.swift",
                "index 1111111..2222222 100644",
                "--- a/Sources/Feature.swift",
                "+++ b/Sources/Feature.swift",
            ],
            oldStart: 1,
            oldLength: 2,
            newStart: 1,
            newLength: 3
        )
        let diff = GitDiff(rawContent: "diff", hunks: [pureRename, changedFile], commitHash: "abc123")
        let view = GitDiffView(diff: diff)

        #expect(view.renderedFiles.count == 2)

        let changedRenderedFile = try #require(view.renderedFiles.first(where: { $0.filePath == "Sources/Feature.swift" }))
        #expect(changedRenderedFile.renameFrom == nil)
        #expect(!changedRenderedFile.showsPureRename)
        #expect(changedRenderedFile.hunks.count == 1)
        #expect(changedRenderedFile.hunks[0].hunk.newStart == 1)
        #expect(changedRenderedFile.hunks[0].lines.map(\.rawLine) == [
            " struct Feature {",
            "+    let enabled = true",
            " }",
        ])

        let renamedRenderedFile = try #require(view.renderedFiles.first(where: { $0.filePath == "Sources/NewName.swift" }))
        #expect(renamedRenderedFile.renameFrom == "Sources/OldName.swift")
        #expect(renamedRenderedFile.showsPureRename)
        #expect(renamedRenderedFile.hunks.isEmpty)
    }
}
