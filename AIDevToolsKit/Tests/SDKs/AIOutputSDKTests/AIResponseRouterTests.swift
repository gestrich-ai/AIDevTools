import Foundation
import Testing
@testable import AIOutputSDK

@Suite struct AIResponseRouterTests {

    private struct Action: Decodable, Sendable {
        let name: String
    }

    private struct Query: Decodable, Sendable {
        let id: Int
    }

    private func makeDescriptor(name: String, kind: AIResponseDescriptor.Kind) -> AIResponseDescriptor {
        AIResponseDescriptor(name: name, description: "test", jsonSchema: "{}", kind: kind)
    }

    // MARK: - Route registration and dispatch

    @Test func routesActionToHandler() async throws {
        let router = AIResponseRouter()
        let descriptor = makeDescriptor(name: "doThing", kind: .action)
        let received = ValueCapture<String>()

        router.addRoute(descriptor, type: Action.self) { action in
            received.value = action.name
            return nil
        }

        let json = #"{"name":"hello"}"#.data(using: .utf8)!
        let reply = try await router.handleResponse(name: "doThing", json: json)

        #expect(received.value == "hello")
        #expect(reply == nil)
    }

    @Test func routesQueryAndReturnsReply() async throws {
        let router = AIResponseRouter()
        let descriptor = makeDescriptor(name: "getCount", kind: .query)

        router.addRoute(descriptor, type: Query.self) { query in
            return "id is \(query.id)"
        }

        let json = #"{"id":42}"#.data(using: .utf8)!
        let reply = try await router.handleResponse(name: "getCount", json: json)

        #expect(reply == "id is 42")
    }

    @Test func returnsNilForUnknownRoute() async throws {
        let router = AIResponseRouter()
        let json = "{}".data(using: .utf8)!
        let reply = try await router.handleResponse(name: "unknown", json: json)
        #expect(reply == nil)
    }

    @Test func throwsOnMalformedJSON() async {
        let router = AIResponseRouter()
        let descriptor = makeDescriptor(name: "doThing", kind: .action)
        router.addRoute(descriptor, type: Action.self) { _ in nil }

        let badJSON = "not json".data(using: .utf8)!
        do {
            _ = try await router.handleResponse(name: "doThing", json: badJSON)
            Issue.record("Expected an error to be thrown")
        } catch {
            // expected
        }
    }

    // MARK: - responseDescriptors

    @Test func responseDescriptorsReflectsRegisteredRoutes() {
        let router = AIResponseRouter()
        let a = makeDescriptor(name: "alpha", kind: .action)
        let b = makeDescriptor(name: "beta", kind: .query)
        router.addRoute(a, type: Action.self) { _ in nil }
        router.addRoute(b, type: Query.self) { _ in nil }

        let names = router.responseDescriptors.map(\.name)
        #expect(names == ["alpha", "beta"])
    }

    @Test func responseDescriptorsAreSortedAlphabetically() {
        let router = AIResponseRouter()
        let z = makeDescriptor(name: "zulu", kind: .action)
        let a = makeDescriptor(name: "alpha", kind: .action)
        let m = makeDescriptor(name: "mike", kind: .action)
        router.addRoute(z, type: Action.self) { _ in nil }
        router.addRoute(a, type: Action.self) { _ in nil }
        router.addRoute(m, type: Action.self) { _ in nil }

        let names = router.responseDescriptors.map(\.name)
        #expect(names == ["alpha", "mike", "zulu"])
    }

    @Test func overwritingRouteKeepsLatestHandler() async throws {
        let router = AIResponseRouter()
        let descriptor = makeDescriptor(name: "action", kind: .action)
        let captured = ValueCapture<String>()

        router.addRoute(descriptor, type: Action.self) { _ in
            captured.value = "first"
            return nil
        }
        router.addRoute(descriptor, type: Action.self) { _ in
            captured.value = "second"
            return nil
        }

        let json = #"{"name":"x"}"#.data(using: .utf8)!
        _ = try await router.handleResponse(name: "action", json: json)

        #expect(captured.value == "second")
    }
}

private final class ValueCapture<T: Sendable>: @unchecked Sendable {
    var value: T?
}
