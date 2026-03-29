import Foundation
import Testing
@testable import AIOutputSDK

@Suite struct StructuredOutputParserTests {

    private let parser = StructuredOutputParser()

    // MARK: - parse

    @Test func parsesSingleResponse() {
        let text = #"Hello! <app-response name="doThing">{"key":"value"}</app-response> Bye."#
        let results = parser.parse(text)

        #expect(results.count == 1)
        #expect(results[0].name == "doThing")
        let decoded = try? JSONDecoder().decode([String: String].self, from: results[0].json)
        #expect(decoded == ["key": "value"])
    }

    @Test func parsesMultipleResponses() {
        let text = """
        <app-response name="action1">{"x":1}</app-response>
        Some text.
        <app-response name="action2">{"y":2}</app-response>
        """
        let results = parser.parse(text)

        #expect(results.count == 2)
        #expect(results[0].name == "action1")
        #expect(results[1].name == "action2")
    }

    @Test func returnsEmptyForNoMatches() {
        let text = "Just some plain text with no tags."
        let results = parser.parse(text)
        #expect(results.isEmpty)
    }

    @Test func handlesMultilineJSON() {
        let text = """
        <app-response name="query">
        {
          "id": 42,
          "label": "hello"
        }
        </app-response>
        """
        let results = parser.parse(text)
        #expect(results.count == 1)
        #expect(results[0].name == "query")
    }

    @Test func ignoresMalformedTag() {
        let text = #"<app-response name="broken"> not valid json </app-response>"#
        let results = parser.parse(text)
        #expect(results.count == 1)
        #expect(results[0].name == "broken")
    }

    // MARK: - stripResponses

    @Test func stripsTagsAndTrims() {
        let text = #"Before. <app-response name="x">{"a":1}</app-response> After."#
        let stripped = parser.stripResponses(from: text)
        #expect(stripped == "Before.  After.")
    }

    @Test func stripsMultipleTags() {
        let text = #"A <app-response name="x">{}</app-response> B <app-response name="y">{}</app-response> C"#
        let stripped = parser.stripResponses(from: text)
        #expect(stripped == "A  B  C")
    }

    @Test func stripsNothingWhenNoTags() {
        let text = "No tags here."
        let stripped = parser.stripResponses(from: text)
        #expect(stripped == "No tags here.")
    }

    @Test func stripsMultilineTagAndTrimsResult() {
        let text = """
        Hello world.
        <app-response name="act">
        {"value": 1}
        </app-response>
        """
        let stripped = parser.stripResponses(from: text)
        #expect(stripped == "Hello world.")
    }
}
