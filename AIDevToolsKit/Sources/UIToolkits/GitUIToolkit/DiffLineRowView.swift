import PRRadarModelsService
import SwiftUI

public struct DiffLineRowView: View {
    public let lineContent: String
    public let oldLineNumber: Int?
    public let newLineNumber: Int?
    public let lineType: DiffLineType
    public let searchQuery: String
    public let isMoved: Bool
    public let onAddComment: (() -> Void)?
    public let onMoveTapped: (() -> Void)?
    public let onSelectRules: (() -> Void)?
    public let lineInfoContent: (() -> AnyView)?

    @State private var isHovering = false
    @State private var showLineInfo = false

    public init(
        lineContent: String,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        lineType: DiffLineType,
        searchQuery: String = "",
        isMoved: Bool = false,
        onAddComment: (() -> Void)? = nil,
        onMoveTapped: (() -> Void)? = nil,
        onSelectRules: (() -> Void)? = nil,
        lineInfoContent: (() -> AnyView)? = nil
    ) {
        self.lineContent = lineContent
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.lineType = lineType
        self.searchQuery = searchQuery
        self.isMoved = isMoved
        self.onAddComment = onAddComment
        self.onMoveTapped = onMoveTapped
        self.onSelectRules = onSelectRules
        self.lineInfoContent = lineInfoContent
    }

    private var matchesSearch: Bool {
        guard !searchQuery.isEmpty else { return false }
        return lineContent.lowercased().contains(searchQuery.lowercased())
    }

    public var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(oldLineNumber.map { String($0) } ?? "")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)

                Color.clear
                    .frame(width: 4, height: 16)
                    .overlay {
                        if isMoved, let onMoveTapped {
                            Button(action: onMoveTapped) {
                                Image(systemName: "arrow.right.arrow.left")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.orange)
                            }
                            .buttonStyle(.plain)
                            .help("View moved code")
                        }
                    }

                Text(newLineNumber.map { String($0) } ?? "")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
            .background(gutterBackground)
            .contextMenu {
                if lineInfoContent != nil {
                    Button("Line Info") {
                        showLineInfo = true
                    }
                }
                if let onSelectRules {
                    Button {
                        onSelectRules()
                    } label: {
                        Label("Select Rules & Analyze\u{2026}", systemImage: "sparkles")
                    }
                }
            }
            .popover(isPresented: $showLineInfo) {
                if let lineInfoContent {
                    lineInfoContent()
                }
            }
            .overlay(alignment: .trailing) {
                if isHovering, let onAddComment, newLineNumber != nil {
                    Button(action: onAddComment) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.accentColor.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 12)
                }
            }

            HStack(spacing: 0) {
                if matchesSearch {
                    Text(highlightedContent)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                } else {
                    Text(lineContent)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }
            }
        }
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.white.opacity(isHovering ? 0.15 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var textColor: Color {
        switch lineType {
        case .added, .removed:
            return Color.white
        case .context, .header:
            return Color.primary
        }
    }

    private var gutterBackground: Color {
        switch lineType {
        case .added:
            return Color.green.opacity(0.15)
        case .removed:
            return Color.red.opacity(0.15)
        case .context, .header:
            return Color.gray.opacity(0.1)
        }
    }

    private var backgroundColor: Color {
        switch lineType {
        case .added:
            return Color.green.opacity(0.08)
        case .removed:
            return Color.red.opacity(0.08)
        case .context, .header:
            return Color.clear
        }
    }

    private var highlightedContent: AttributedString {
        var attributedString = AttributedString(lineContent)
        if let range = attributedString.range(of: searchQuery, options: .caseInsensitive) {
            attributedString[range].backgroundColor = .yellow.opacity(0.5)
            attributedString[range].foregroundColor = .black
        }
        return attributedString
    }
}
