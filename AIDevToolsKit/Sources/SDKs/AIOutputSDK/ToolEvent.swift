public struct ToolEvent: Sendable, Equatable {
    public let name: String
    public var command: String?
    public var exitCode: Int?
    public var filePath: String?
    public var inputKeys: [String]
    public var output: String?
    public var skillName: String?

    public init(
        name: String,
        inputKeys: [String] = [],
        command: String? = nil,
        output: String? = nil,
        exitCode: Int? = nil,
        skillName: String? = nil,
        filePath: String? = nil
    ) {
        self.name = name
        self.command = command
        self.exitCode = exitCode
        self.filePath = filePath
        self.inputKeys = inputKeys
        self.output = output
        self.skillName = skillName
    }
}
