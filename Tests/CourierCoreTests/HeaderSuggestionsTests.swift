import Testing
@testable import CourierCore

@Suite struct HeaderSuggestionsTests {
    private let builtIn = HeaderSuggestions()

    @Test func prefixMatchesComeFirst() {
        let names = builtIn.names(matching: "con")
        #expect(names == ["Connection", "Content-Encoding", "Content-Language", "Content-Type", "Cache-Control"])
    }

    @Test func matchesInsideNamesAfterPrefixes() {
        let names = builtIn.names(matching: "type")
        #expect(names == ["Content-Type"])
        let auth = builtIn.names(matching: "auth")
        #expect(auth.first == "Authorization")
    }

    @Test func isCaseInsensitive() {
        #expect(builtIn.names(matching: "USER").contains("User-Agent"))
        #expect(builtIn.values(for: "CONTENT-TYPE", matching: "APPLICATION/J").contains("application/json"))
    }

    @Test func noSuggestionsForEmptyInputOrExactMatch() {
        #expect(builtIn.names(matching: "").isEmpty)
        #expect(builtIn.names(matching: "  ").isEmpty)
        #expect(builtIn.names(matching: "accept").isEmpty)
        #expect(builtIn.values(for: "Content-Type", matching: "application/json").isEmpty)
    }

    @Test func leavesOutNamesUsedInOtherRows() {
        let names = builtIn.names(matching: "accept-", excluding: ["accept-encoding"])
        #expect(names == ["Accept-Language"])
    }

    @Test func valuesDependOnTheName() {
        #expect(builtIn.values(for: "Content-Type", matching: "").first == "application/json")
        #expect(builtIn.values(for: "Authorization", matching: "") == ["Bearer ", "Basic "])
        #expect(builtIn.values(for: "Cache-Control", matching: "no").contains("no-cache"))
        #expect(builtIn.values(for: "X-Unknown", matching: "").isEmpty)
        #expect(builtIn.values(for: "", matching: "").isEmpty)
    }

    @Test func capsTheNumberOfResults() {
        #expect(builtIn.names(matching: "e").count == HeaderSuggestions.maxResults)
    }

    @Test func learnsNamesAndValuesFromPreviousRequests() {
        let spec = RequestSpec(headers: [
            KeyValue("X-Tenant", "acme"),
            KeyValue("x-tenant", "globex"),
            KeyValue("Content-Type", "application/vnd.api+json"),
        ])
        let learned = HeaderSuggestions(learnedFrom: [spec])
        #expect(learned.names(matching: "x-ten") == ["X-Tenant"])
        #expect(learned.values(for: "X-TENANT", matching: "") == ["acme", "globex"])
        #expect(learned.values(for: "Content-Type", matching: "vnd").contains("application/vnd.api+json"))
    }

    @Test func neverLearnsSecretValues() {
        let spec = RequestSpec(headers: [
            KeyValue("Authorization", "Bearer abc123"),
            KeyValue("X-API-Key", "sk_live_123"),
            KeyValue("X-Session", "s3cr3t"),
        ])
        let learned = HeaderSuggestions(learnedFrom: [spec])
        #expect(learned.values(for: "Authorization", matching: "") == ["Bearer ", "Basic "])
        #expect(learned.values(for: "X-API-Key", matching: "").isEmpty)
        #expect(learned.values(for: "X-Session", matching: "").isEmpty)
        // The names themselves are fine to suggest.
        #expect(learned.names(matching: "x-sess") == ["X-Session"])
    }

    @Test func doesNotDuplicateBuiltInsOrIgnoreBlankRows() {
        let spec = RequestSpec(headers: [KeyValue("accept", "*/*"), KeyValue("  ", "x"), KeyValue("Accept", "")])
        let learned = HeaderSuggestions(learnedFrom: [spec])
        #expect(learned.names.count == HeaderSuggestions.commonNames.count)
        #expect(learned.values(for: "Accept", matching: "").filter { $0 == "*/*" }.count == 1)
    }
}
