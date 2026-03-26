import ClaudeCLISDK

extension ExecuteImplementationUseCase {
    public init() {
        self.init(client: ClaudeCLIClient())
    }
}
