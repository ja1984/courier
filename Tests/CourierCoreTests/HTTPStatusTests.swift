import Testing
@testable import CourierCore

@Suite struct HTTPStatusTests {
    @Test(arguments: [
        (200, "OK"),
        (201, "Created"),
        (204, "No Content"),
        (304, "Not Modified"),
        (404, "Not Found"),
        (422, "Unprocessable Content"),
        (429, "Too Many Requests"),
        (503, "Service Unavailable"),
    ])
    func standardPhrases(code: Int, phrase: String) {
        #expect(HTTPStatus.reasonPhrase(for: code) == phrase)
    }

    @Test func unregisteredCodesFallBackToClass() {
        #expect(HTTPStatus.reasonPhrase(for: 299) == "Success")
        #expect(HTTPStatus.reasonPhrase(for: 499) == "Client Error")
        #expect(HTTPStatus.reasonPhrase(for: 599) == "Server Error")
        #expect(HTTPStatus.reasonPhrase(for: 999) == "Unknown")
    }
}
