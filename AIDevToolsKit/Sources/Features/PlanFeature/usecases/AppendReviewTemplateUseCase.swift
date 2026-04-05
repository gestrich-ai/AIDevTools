import Foundation
import PlanService
import PipelineSDK
import UseCaseSDK

public struct AppendReviewTemplateUseCase: UseCase {

    public struct Options: Sendable {
        public let planURL: URL
        public let template: ReviewTemplate

        public init(planURL: URL, template: ReviewTemplate) {
            self.planURL = planURL
            self.template = template
        }
    }

    public init() {}

    public func run(_ options: Options) async throws {
        let service = ReviewTemplateService(reviewsDirectory: options.template.url.deletingLastPathComponent())
        let descriptions = try service.loadSteps(from: options.template)
        let steps: [CodeChangeStep] = descriptions.map { description in
            CodeChangeStep(
                id: UUID().uuidString,
                description: description,
                isCompleted: false,
                prompt: description,
                skills: [],
                context: .empty
            )
        }
        try await MarkdownPipelineSource(fileURL: options.planURL, format: .phase).appendSteps(steps)
    }
}
