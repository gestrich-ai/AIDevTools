import PRRadarModelsService
import SwiftUI

public struct GitDiffView: View {
    public let diff: GitDiff
    private let onSelectedFileChange: ((String?) -> Void)?

    @State private var selectedFile: String?

    public init(diff: GitDiff, onSelectedFileChange: ((String?) -> Void)? = nil) {
        self.diff = diff
        self.onSelectedFileChange = onSelectedFileChange
    }

    public var body: some View {
        HSplitView {
            fileSidebar
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 260)

            diffContent
        }
        .onAppear {
            if selectedFile == nil {
                selectedFile = diff.changedFiles.first
            }
            onSelectedFileChange?(selectedFile)
        }
        .onChange(of: diff.changedFiles) { _, changedFiles in
            if let selectedFile, changedFiles.contains(selectedFile) {
                return
            }
            self.selectedFile = changedFiles.first
            onSelectedFileChange?(self.selectedFile)
        }
        .onChange(of: selectedFile) { _, newValue in
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
            ForEach(displayedFiles, id: \.self) { filePath in
                let hunks = diff.getHunks(byFilePath: filePath)
                let renameFrom = hunks.first(where: { $0.renameFrom != nil })?.renameFrom

                if let renameFrom {
                    RenameFileHeaderView(oldPath: renameFrom, newPath: filePath)
                        .diffListRow()
                } else {
                    Text(filePath)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .diffListRow()
                }

                if hunks.contains(where: \.isPureRename) {
                    PureRenameContentView()
                        .diffListRow()
                }

                ForEach(hunks.filter { !$0.isPureRename }) { hunk in
                    HunkHeaderView(hunk: hunk)
                        .diffListRow()

                    ForEach(hunk.getDiffLines().filter { $0.lineType != .header }, id: \.rawLineWithNumbers) { line in
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
        guard let selectedFile else { return diff.changedFiles }
        return [selectedFile]
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
