import ClaudeChainFeature
import Foundation

@MainActor @Observable
final class ClaudeChainModel {

    enum State {
        case idle
        case loadingChains
        case loaded([ChainProject])
        case executing(projectName: String, status: String)
        case error(Error)
    }

    private(set) var state: State = .idle

    private let executeChainUseCase: ExecuteChainUseCase
    private let listChainsUseCase: ListChainsUseCase

    init(
        executeChainUseCase: ExecuteChainUseCase = ExecuteChainUseCase(),
        listChainsUseCase: ListChainsUseCase = ListChainsUseCase()
    ) {
        self.executeChainUseCase = executeChainUseCase
        self.listChainsUseCase = listChainsUseCase
    }

    func loadChains(for repoPath: URL) {
        state = .loadingChains
        Task {
            do {
                let projects = try listChainsUseCase.run(options: .init(repoPath: repoPath))
                state = .loaded(projects)
            } catch {
                state = .error(error)
            }
        }
    }

    func executeChain(projectName: String, repoPath: URL) {
        state = .executing(projectName: projectName, status: "Starting...")
        Task {
            do {
                state = .executing(projectName: projectName, status: "Running claude-code...")
                let result = try await executeChainUseCase.run(
                    options: .init(repoPath: repoPath, projectName: projectName)
                )
                if result.success {
                    let status = result.prURL.map { "PR created: \($0)" } ?? result.message
                    state = .executing(projectName: projectName, status: status)
                    loadChains(for: repoPath)
                } else {
                    state = .error(
                        NSError(
                            domain: "ClaudeChainModel",
                            code: 0,
                            userInfo: [NSLocalizedDescriptionKey: result.message]
                        )
                    )
                }
            } catch {
                state = .error(error)
            }
        }
    }
}
