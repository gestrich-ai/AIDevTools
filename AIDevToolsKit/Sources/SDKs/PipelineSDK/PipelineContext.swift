public struct PipelineContextKey<Value: Sendable>: Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }
}

public struct PipelineContext: Sendable {
    public static let injectedTaskSourceKey = PipelineContextKey<any TaskSource>("PipelineContext.injectedTaskSource")
    public static let workingDirectoryKey = PipelineContextKey<String>("PipelineContext.workingDirectory")

    private var storage: [String: any Sendable]

    public init() {
        self.storage = [:]
    }

    public subscript<Value: Sendable>(_ key: PipelineContextKey<Value>) -> Value? {
        get { storage[key.name] as? Value }
        set {
            if let newValue {
                storage[key.name] = newValue
            } else {
                storage.removeValue(forKey: key.name)
            }
        }
    }


}
