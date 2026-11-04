import Foundation
import Testing
@testable import CourierCore

@Suite struct URLQueryTests {
    @Test func editingParamsRebuildsURL() {
        var spec = RequestSpec()
        spec.setURL("https://example.com/path?a=1#frag")
        var params = spec.params
        params.append(KeyValue("q", "a&b c"))
        spec.setParams(params)
        #expect(spec.url == "https://example.com/path?a=1&q=a%26b%20c#frag")
    }

    @Test func disabledParamsSurviveURLEdits() {
        var spec = RequestSpec()
        spec.setURL("https://example.com?a=1&b=2")
        var params = spec.params
        params[1].isEnabled = false
        spec.setParams(params)
        #expect(spec.url == "https://example.com?a=1")

        spec.setURL("https://example.com?a=5")
        #expect(spec.params.map(\.key) == ["a", "b"])
        #expect(spec.params.map(\.isEnabled) == [true, false])
    }

    @Test func emptyRowsDoNotChangeURL() {
        var spec = RequestSpec()
        spec.setURL("https://example.com")
        spec.setParams([KeyValue()])
        #expect(spec.url == "https://example.com")
        #expect(spec.params.count == 1)
    }
}

@Suite struct JSONFormatterTests {
    @Test func preservesKeyOrderAndStrings() throws {
        let pretty = try #require(JSONFormatter.prettyPrinted(#"{"z":1,"a":{"s":"{not, a: brace}"},"e":[],"o":{}}"#))
        #expect(pretty == """
        {
          "z": 1,
          "a": {
            "s": "{not, a: brace}"
          },
          "e": [],
          "o": {}
        }
        """)
    }

    @Test func escapedQuotesInStrings() throws {
        let pretty = try #require(JSONFormatter.prettyPrinted(#"["a\"b",2]"#))
        #expect(pretty == "[\n  \"a\\\"b\",\n  2\n]")
    }

    @Test func invalidReturnsNil() {
        #expect(JSONFormatter.prettyPrinted("{nope}") == nil)
    }

    @Test func highlighterDistinguishesKeysFromValues() {
        let tokens = JSONHighlighter.tokens(in: #"{"k": "v", "n": -1.5e3, "b": true}"#)
        let kinds = tokens.filter { $0.kind != .punctuation }.map(\.kind)
        #expect(kinds == [.key, .string, .key, .number, .key, .literal])
    }
}

@Suite struct HTTPClientTests {
    @Test func buildsRequestWithDefaults() throws {
        var spec = RequestSpec(method: .post, headers: [KeyValue("X-A", "1"), KeyValue("X-Off", "1", isEnabled: false)])
        spec.setURL("localhost:3000/api")
        spec.bodyKind = .form
        spec.formFields = [KeyValue("name", "Jo Doe"), KeyValue("x", "y", isEnabled: false)]

        let request = try HTTPClient.makeURLRequest(from: spec)
        #expect(request.url?.absoluteString == "http://localhost:3000/api")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-A") == "1")
        #expect(request.value(forHTTPHeaderField: "X-Off") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(request.httpBody.map { String(decoding: $0, as: UTF8.self) } == "name=Jo%20Doe")
    }

    @Test func explicitContentTypeWins() throws {
        let spec = RequestSpec(
            method: .post,
            url: "https://example.com",
            headers: [KeyValue("content-type", "application/vnd.api+json")],
            bodyKind: .json,
            bodyText: "{}"
        )
        let request = try HTTPClient.makeURLRequest(from: spec)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/vnd.api+json")
    }

    @Test func rejectsEmptyAndInvalidURLs() {
        #expect(throws: RequestBuildError.emptyURL) { try HTTPClient.makeURLRequest(from: RequestSpec(url: "  ")) }
        #expect(throws: RequestBuildError.invalidURL("http://")) { try HTTPClient.makeURLRequest(from: RequestSpec(url: "http://")) }
    }
}
