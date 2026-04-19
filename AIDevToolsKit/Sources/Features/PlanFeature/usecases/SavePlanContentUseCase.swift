import Foundation
import UseCaseSDK

public struct SavePlanContentUseCase: UseCase {

    public init() {}

    public func run(content: String, planURL: URL) throws {
        try content.write(to: planURL, atomically: true, encoding: .utf8)
    }
}
