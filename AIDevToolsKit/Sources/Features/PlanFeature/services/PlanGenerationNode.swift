import AIOutputSDK
import Foundation
import PipelineSDK
import RepositorySDK

struct PlanGenerationNode: PipelineNode {
    static let inputKey = PipelineContextKey<PlanService.GenerateOptions>("PlanGenerationNode.input")
    static let outputKey = PipelineContextKey<PlanService.GenerateResult>("PlanGenerationNode.output")

    let id: String
    let displayName: String

    private let client: any AIClient
    private let generateProgressHandler: @Sendable (PlanService.GenerateProgress) -> Void
    private let resolveProposedDirectory: @Sendable (RepositoryConfiguration) throws -> URL

    init(
        id: String = "planGeneration",
        displayName: String = "Generate Plan",
        client: any AIClient,
        generateProgressHandler: @escaping @Sendable (PlanService.GenerateProgress) -> Void = { _ in },
        resolveProposedDirectory: @escaping @Sendable (RepositoryConfiguration) throws -> URL
    ) {
        self.id = id
        self.displayName = displayName
        self.client = client
        self.generateProgressHandler = generateProgressHandler
        self.resolveProposedDirectory = resolveProposedDirectory
    }

    func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        guard let options = context[Self.inputKey] else {
            throw PipelineError.missingContextValue(key: Self.inputKey.name)
        }

        let repo: RepositoryConfiguration
        let repoMatch: RepoMatch

        if let selected = options.selectedRepository {
            repo = selected
            repoMatch = RepoMatch(repoId: selected.id.uuidString, interpretedRequest: options.prompt)
            generateProgressHandler(.matchedRepo(repoId: repoMatch.repoId, interpretedRequest: repoMatch.interpretedRequest))
        } else {
            generateProgressHandler(.matchingRepo)
            repoMatch = try await matchRepo(prompt: options.prompt, repositories: options.repositories)
            generateProgressHandler(.matchedRepo(repoId: repoMatch.repoId, interpretedRequest: repoMatch.interpretedRequest))

            guard let repoUUID = UUID(uuidString: repoMatch.repoId),
                  let matched = options.repositories.first(where: { $0.id == repoUUID }) else {
                throw PlanService.GenerateError.repoNotFound(repoMatch.repoId)
            }
            repo = matched
        }

        generateProgressHandler(.generatingPlan)
        let plan = try await generatePlan(interpretedRequest: repoMatch.interpretedRequest, repo: repo)
        generateProgressHandler(.generatedPlan(filename: plan.filename))

        generateProgressHandler(.writingPlan)
        let proposedDir = try resolveProposedDirectory(repo)
        let planURL = try writePlan(plan, to: proposedDir)
        generateProgressHandler(.completed(planURL: planURL, repository: repo))

        let result = PlanService.GenerateResult(
            planURL: planURL,
            repository: repo,
            repoMatch: repoMatch,
            plan: plan
        )

        var updated = context
        updated[Self.outputKey] = result
        return updated
    }

    // MARK: - Private: repo matching

    private func matchRepo(prompt: String, repositories: [RepositoryConfiguration]) async throws -> RepoMatch {
        let repoList = repositories.map { repo in
            var entry = "- id: \(repo.id.uuidString) | description: \(repo.description ?? repo.name)"
            if let focus = repo.recentFocus {
                entry += " | recent focus: \(focus)"
            }
            return entry
        }.joined(separator: "\n")

        let matchPrompt = """
        You are helping match a development request to the correct repository.

        Use the repository descriptions and recent focus areas to infer the best match.

        Request: "\(prompt)"

        Available repositories:
        \(repoList)

        You MUST select one of the listed repositories. Do not reference or suggest any repository not in this list.

        Return the best matching repository ID and your interpretation of what the request is asking for.
        """

        let schema = """
        {"type":"object","properties":{"repoId":{"type":"string","description":"The id of the matched repository"},"interpretedRequest":{"type":"string","description":"The interpreted version of the request"}},"required":["repoId","interpretedRequest"]}
        """

        let output = try await client.runStructured(
            RepoMatch.self,
            prompt: matchPrompt,
            jsonSchema: schema,
            options: AIClientOptions(),
            onOutput: nil
        )
        return output.value
    }

    // MARK: - Private: plan generation

    private func generatePlan(interpretedRequest: String, repo: RepositoryConfiguration) async throws -> GeneratedPlan {
        let skills = repo.skills ?? []
        let verificationCommands = repo.verification?.commands ?? []

        var repoContextLines = [
            "Repository: \(repo.id.uuidString)",
            "Path: \(repo.path.path())",
            "Description: \(repo.description ?? repo.name)",
            "Skills: \(skills.joined(separator: ", "))",
            "Verification commands: \(verificationCommands.joined(separator: ", "))",
        ]
        if let pr = repo.pullRequest {
            repoContextLines.append("PR base branch: \(pr.baseBranch)")
            repoContextLines.append("Branch naming: \(pr.branchNamingConvention)")
        }
        if let githubCredentialProfileId = repo.githubCredentialProfileId {
            repoContextLines.append("GitHub profile: \(githubCredentialProfileId) (GH_TOKEN injected automatically)")
        }
        let repoContext = repoContextLines.joined(separator: "\n")

        let projectInstructions = readProjectInstructions(at: repo.path)

        let prompt = """
        You are generating a complete, detailed phased implementation plan. You are ONLY generating the plan — do NOT execute, explore, or implement anything.

        Request: "\(interpretedRequest)"

        Repository context:
        \(repoContext)
        \(projectInstructions.map { "\nCLAUDE.md contents:\n\($0)" } ?? "")

        Generate a markdown plan document with this structure:

        1. **Relevant Skills** table at the top — only skills relevant to the task, discovered from the CLAUDE.md content above. Format:
           ```
           ## Relevant Skills

           | Skill | Description |
           |-------|-------------|
           | `skill-name` | Brief description of why it's relevant |
           ```

        2. **Background** section — why we're making changes, user requirements, context

        3. **All implementation phases** (Phase 1 through N, ≤10 total), each as:
           ```
           ## - [ ] Phase N: Short Description

           **Skills to read**: `skill-a`, `skill-b`

           Detailed description of what to implement. Include:
           - Specific tasks and files to modify
           - Technical considerations
           - Expected outcome
           ```
           The "Skills to read" line tells the executor which skills to read before implementing that phase. Only include skills genuinely relevant to that phase. Omit the line if no skills apply.

        4. **Final phase is always Validation** — prefer automated testing (running test suites, build verification) over manual verification. Include specific commands to run.

        CRITICAL scope and sizing rules:
        - Stay focused on exactly what was requested. Do not expand scope, refactor surrounding code, or make unrelated improvements.
        - Follow a "do no harm" principle: do not restructure or rewrite existing code that already works.
        - Scale the number of phases to match the size of the request. A small change may need only 1-2 phases. A large feature may need up to 10. Never exceed 10 phases total.
        - Every phase must be actionable and concrete — no "explore" or "gather context" phases.

        All phases must be unchecked (## - [ ]). None are completed at this stage.

        Also generate a short kebab-case description for the filename (e.g., "add-voice-commands", "fix-auth-timeout"). Do not include dates or extensions.

        Return the full markdown content as planContent and the description as filename.
        """

        let schema = """
        {"type":"object","properties":{"planContent":{"type":"string","description":"The full markdown plan document content"},"filename":{"type":"string","description":"Short kebab-case description without date prefix or extension"}},"required":["planContent","filename"]}
        """

        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: repo.path.path()
        )

        let output = try await client.runStructured(
            GeneratedPlan.self,
            prompt: prompt,
            jsonSchema: schema,
            options: options,
            onOutput: nil
        )
        return output.value
    }

    private func readProjectInstructions(at repoPath: URL) -> String? {
        let instructionsURL = repoPath.appendingPathComponent("CLAUDE.md")
        return try? String(contentsOf: instructionsURL, encoding: .utf8)
    }

    private func writePlan(_ plan: GeneratedPlan, to proposedDirectory: URL) throws -> URL {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: proposedDirectory.path) {
                try fm.createDirectory(at: proposedDirectory, withIntermediateDirectories: true)
            }
        } catch {
            throw PlanService.GenerateError.writeError("Could not create directory: \(error.localizedDescription)")
        }

        let filename = buildFilename(description: plan.filename, in: proposedDirectory)
        let planURL = proposedDirectory.appendingPathComponent(filename)
        do {
            try plan.planContent.write(to: planURL, atomically: true, encoding: .utf8)
        } catch {
            throw PlanService.GenerateError.writeError("Could not write plan file: \(error.localizedDescription)")
        }

        return planURL
    }

    private func buildFilename(description: String, in directory: URL) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let datePrefix = formatter.string(from: Date())

        let cleanDescription = description
            .replacingOccurrences(of: ".md", with: "")
            .trimmingCharacters(in: .whitespaces)

        let existingFiles = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let todayFiles = existingFiles.filter { $0.hasPrefix(datePrefix) }

        let alphaIndex: String
        if todayFiles.isEmpty {
            alphaIndex = "a"
        } else {
            let usedLetters = todayFiles.compactMap { filename -> Character? in
                let afterDate = filename.dropFirst(datePrefix.count)
                guard afterDate.hasPrefix("-"), afterDate.count > 1 else { return nil }
                let letter = afterDate[afterDate.index(after: afterDate.startIndex)]
                guard letter.isLetter, afterDate.count > 2,
                      afterDate[afterDate.index(afterDate.startIndex, offsetBy: 2)] == "-" else { return nil }
                return letter
            }
            let maxLetter = usedLetters.max() ?? Character("a")
            let nextScalar = Unicode.Scalar(maxLetter.asciiValue! + 1)
            alphaIndex = String(nextScalar)
        }

        return "\(datePrefix)-\(alphaIndex)-\(cleanDescription).md"
    }
}
