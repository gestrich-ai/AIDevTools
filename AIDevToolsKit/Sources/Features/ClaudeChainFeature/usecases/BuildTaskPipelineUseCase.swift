import AIOutputSDK
import ClaudeChainService
import Foundation
import PipelineSDK

public struct BuildTaskPipelineUseCase {
    private let client: any AIClient

    public init(client: any AIClient) {
        self.client = client
    }

    public func run(task: ChainTask, options: ChainRunOptions) async throws -> PipelineBlueprint {
        let service = ClaudeChainService(client: client)
        return try await service.buildPipeline(for: task, options: options)
    }
}
