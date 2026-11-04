import Foundation
import Testing
@testable import CourierCore

@Suite struct RedirectChainTests {
    private func hop(_ status: Int, _ url: String, location: String? = nil) -> RedirectHop {
        RedirectHop(method: "GET", url: URL(string: url)!, statusCode: status, location: location)
    }

    @Test func keepsRedirectsBeforeTheFinalResponse() {
        let chain = RedirectHop.chain(from: [
            hop(301, "https://fasttrack-solutions.com/", location: "https://www.fasttrack.ai/"),
            hop(302, "https://www.fasttrack.ai/", location: "/en"),
            hop(200, "https://www.fasttrack.ai/en"),
        ])
        #expect(chain.map(\.statusCode) == [301, 302])
        #expect(chain.last?.location == "/en")
    }

    @Test func noRedirectsForASingleResponse() {
        #expect(RedirectHop.chain(from: [hop(200, "https://example.com/")]).isEmpty)
        #expect(RedirectHop.chain(from: []).isEmpty)
    }

    @Test func ignoresNonRedirectRetries() {
        // A 401 answered automatically with credentials is a retry, not a redirect.
        let chain = RedirectHop.chain(from: [
            hop(401, "https://example.com/private"),
            hop(200, "https://example.com/private"),
        ])
        #expect(chain.isEmpty)
    }

    @Test func finalResponseIsNeverPartOfTheChainEvenIfItIsA3xx() {
        // e.g. 304, or a redirect without a Location that URLSession didn't follow.
        let chain = RedirectHop.chain(from: [hop(301, "http://a.test/", location: "https://a.test/"), hop(304, "https://a.test/")])
        #expect(chain.map(\.statusCode) == [301])
    }
}
