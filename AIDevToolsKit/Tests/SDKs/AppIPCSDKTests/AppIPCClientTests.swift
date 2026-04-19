import AppIPCSDK
import Foundation
import Testing

@Suite("AppIPCClient")
struct AppIPCClientTests {

    // MARK: - IPCRequest Codable

    @Test("IPCRequest encodes and decodes query field")
    func ipcRequestRoundtrip() throws {
        let request = IPCRequest(query: "getUIState")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(IPCRequest.self, from: data)
        #expect(decoded.query == "getUIState")
    }

    @Test("IPCRequest encodes to expected JSON keys")
    func ipcRequestJSONKeys() throws {
        let request = IPCRequest(query: "getUIState")
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(json?["query"] == "getUIState")
    }

    // MARK: - IPCUIState Codable

    @Test("IPCUIState decodes plan name and tab from JSON")
    func ipcUIStateWithValues() throws {
        let json = #"{"selectedPlanName":"MyPlan","currentTab":"plans"}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(IPCUIState.self, from: json)
        #expect(state.selectedPlanName == "MyPlan")
        #expect(state.currentTab == "plans")
    }

    @Test("IPCUIState decodes null fields as nil")
    func ipcUIStateNilFields() throws {
        let json = #"{"selectedPlanName":null,"currentTab":null}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(IPCUIState.self, from: json)
        #expect(state.selectedPlanName == nil)
        #expect(state.currentTab == nil)
    }

    @Test("IPCUIState encodes optional fields correctly")
    func ipcUIStateRoundtrip() throws {
        let state = IPCUIState(currentTab: "evals", selectedChainName: nil, selectedPlanName: "TestPlan")
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(IPCUIState.self, from: data)
        #expect(decoded.selectedPlanName == "TestPlan")
        #expect(decoded.currentTab == "evals")
    }

    @Test("uiStateText includes only selected tab details")
    func uiStateTextUsesSelectedTabDetails() {
        let state = IPCUIState(
            activePlanContext: IPCPlanContext(
                completedPhases: ["Phase 1"],
                planFilePath: "/tmp/TestPlan.md",
                planName: "TestPlan"
            ),
            currentTab: "claudeChain",
            selectedChainName: "chain-a",
            selectedPlanName: "TestPlan"
        )

        let text = state.uiStateText()

        #expect(text.contains("Selected tab: Chains"))
        #expect(text.contains("Selected chain: chain-a"))
        #expect(!text.contains("Selected plan:"))
        #expect(!text.contains("Plan file path:"))
    }

    @Test("chatContextText includes plan and diff details only for plans tab")
    func chatContextTextForPlansTab() {
        let state = IPCUIState(
            activeDiffContext: IPCDiffContext(
                selectedCommits: [IPCDiffCommit(hash: "abc123", message: "Commit message")],
                selectedFilePath: "Sources/App.swift",
                selectedSources: ["commit"]
            ),
            activePlanContext: IPCPlanContext(
                completedPhases: ["Phase 1", "Phase 2"],
                planFilePath: "/tmp/TestPlan.md",
                planName: "TestPlan"
            ),
            currentTab: "plans",
            selectedChainName: "chain-a",
            selectedPlanName: "TestPlan"
        )

        let text = state.chatContextText()

        #expect(text.contains("Selected tab: Plans"))
        #expect(text.contains("Selected plan: TestPlan"))
        #expect(text.contains("Plan file path: /tmp/TestPlan.md"))
        #expect(text.contains("Selected commits:"))
        #expect(text.contains("Selected file: Sources/App.swift"))
        #expect(text.contains("Selected diff sources: commit"))
        #expect(text.contains("requesting code modifications"))
        #expect(!text.contains("Selected chain:"))
    }

    // MARK: - AppIPCClient behavior

    @Test("getUIState throws appNotRunning when socket file is absent")
    func getUIStateThrowsWhenSocketAbsent() async throws {
        let socketPath = AppIPCClient.socketFilePath
        guard !FileManager.default.fileExists(atPath: socketPath) else {
            return  // App is running — skip this case
        }
        let client = AppIPCClient()
        await #expect {
            _ = try await client.getUIState()
        } throws: { error in
            guard let ipcError = error as? IPCError else { return false }
            if case .appNotRunning = ipcError { return true }
            return false
        }
    }

    // MARK: - IPCError descriptions

    @Test("appNotRunning error description mentions AIDevTools app")
    func appNotRunningErrorDescription() {
        #expect(IPCError.appNotRunning.errorDescription?.contains("AIDevTools") == true)
    }

    @Test("connectionFailed error description includes the message")
    func connectionFailedErrorDescription() {
        let message = "socket closed"
        let error = IPCError.connectionFailed(message)
        #expect(error.errorDescription?.contains(message) == true)
    }

    @Test("noResponse error has non-nil description")
    func noResponseErrorDescription() {
        #expect(IPCError.noResponse.errorDescription != nil)
    }
}
