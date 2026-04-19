import PRRadarModelsService
import SwiftUI

public struct GitDiffView: View {
    struct RenderedFile {
        let filePath: String
        let hunks: [RenderedHunk]
        let renameFrom: String?
        let showsPureRename: Bool
    }

    struct RenderedHunk {
        let hunk: Hunk
        let lines: [DiffLine]
    }

    public let diff: GitDiff
    private let selectedFileOverride: String?
    private let showsFileSidebar: Bool
    private let onSelectedFileChange: ((String?) -> Void)?

    @State private var selectedFile: String?

    public init(
        diff: GitDiff,
        selectedFile: String? = nil,
        showsFileSidebar: Bool = true,
        onSelectedFileChange: ((String?) -> Void)? = nil
    ) {
        self.diff = diff
        self.selectedFileOverride = selectedFile
        self.showsFileSidebar = showsFileSidebar
        self.onSelectedFileChange = onSelectedFileChange
    }

    public var body: some View {
        Group {
            if showsFileSidebar {
                HSplitView {
                    fileSidebar
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)

                    diffContent
                }
            } else {
                diffContent
            }
        }
        .onAppear {
            if selectedFile == nil {
                selectedFile = selectedFileOverride ?? diff.changedFiles.first
            }
            if selectedFileOverride == nil {
                onSelectedFileChange?(effectiveSelectedFile)
            }
        }
        .onChange(of: diff.changedFiles) { _, changedFiles in
            let currentSelection = effectiveSelectedFile
            if let currentSelection, changedFiles.contains(currentSelection) {
                return
            }
            self.selectedFile = changedFiles.first
            onSelectedFileChange?(effectiveSelectedFile)
        }
        .onChange(of: selectedFile) { _, newValue in
            guard showsFileSidebar else { return }
            onSelectedFileChange?(newValue)
        }
    }

    @ViewBuilder
    private var fileSidebar: some View {
        List(selection: $selectedFile) {
            Section("Changed Files") {
                ForEach(diff.changedFiles, id: \.self) { filePath in
                    HStack {
                        Text(URL(fileURLWithPath: filePath).lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        Text("\(diff.getHunks(byFilePath: filePath).count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(filePath)
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var diffContent: some View {
        List {
            ForEach(renderedFiles, id: \.filePath) { file in
                if let renameFrom = file.renameFrom {
                    RenameFileHeaderView(oldPath: renameFrom, newPath: file.filePath)
                        .diffListRow()
                } else {
                    Text(file.filePath)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .diffListRow()
                }

                if file.showsPureRename {
                    PureRenameContentView()
                        .diffListRow()
                }

                ForEach(file.hunks, id: \.hunk.id) { renderedHunk in
                    HunkHeaderView(hunk: renderedHunk.hunk)
                        .diffListRow()

                    ForEach(renderedHunk.lines, id: \.rawLineWithNumbers) { line in
                        DiffLineRowView(
                            lineContent: line.rawLine,
                            oldLineNumber: line.oldLineNumber,
                            newLineNumber: line.newLineNumber,
                            lineType: line.lineType
                        )
                        .diffListRow()
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color(nsColor: .textBackgroundColor))
        .scrollContentBackground(.hidden)
    }

    private var displayedFiles: [String] {
        guard let selectedFile = effectiveSelectedFile else { return diff.changedFiles }
        return [selectedFile]
    }

    var renderedFiles: [RenderedFile] {
        displayedFiles.map { filePath in
            let hunks = diff.getHunks(byFilePath: filePath)
            return RenderedFile(
                filePath: filePath,
                hunks: hunks
                    .filter { !$0.isPureRename }
                    .map { hunk in
                        RenderedHunk(
                            hunk: hunk,
                            lines: hunk.getDiffLines().filter { $0.lineType != .header }
                        )
                    },
                renameFrom: hunks.first(where: { $0.renameFrom != nil })?.renameFrom,
                showsPureRename: hunks.contains(where: \.isPureRename)
            )
        }
    }

    private var effectiveSelectedFile: String? {
        if showsFileSidebar {
            return selectedFile
        }
        return selectedFileOverride ?? selectedFile
    }
}

private extension Hunk {
    var isPureRename: Bool {
        renameFrom != nil && getDiffLines().allSatisfy { $0.lineType == .header }
    }
}

private extension DiffLine {
    var rawLineWithNumbers: String {
        "\(oldLineNumber.map(String.init) ?? "-"):\(newLineNumber.map(String.init) ?? "-"):\(rawLine)"
    }
}
