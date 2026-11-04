import Foundation
import Testing
@testable import CourierCore

@Suite struct CollectionLibraryTests {
    private let users = RequestSpec(method: .get, url: "https://api.example.com/v1/users?limit=5")

    @Test func savesUpdatesAndFindsRequests() throws {
        var library = CollectionLibrary()
        let collection = library.addCollection(named: "  Example API ")
        let idResult = library.saveRequest(users, named: "List users", in: collection)
        let id = try #require(idResult)

        #expect(library.collection(collection)?.name == "Example API")
        #expect(library.request(id)?.request.name == "List users")
        #expect(library.request(id)?.collection.id == collection)

        var edited = users
        edited.method = .post
        let updated = library.updateRequest(id, spec: edited)
        #expect(updated)
        #expect(library.request(id)?.request.spec.method == .post)
        #expect(library.requestCount == 1)
    }

    @Test func savingIntoMissingCollectionFails() {
        var library = CollectionLibrary()
        let saved = library.saveRequest(users, named: "x", in: UUID())
        let updated = library.updateRequest(UUID(), spec: users)
        #expect(saved == nil)
        #expect(!updated)
    }

    @Test func blankNamesFallBackToSensibleDefaults() throws {
        var library = CollectionLibrary()
        let collection = library.addCollection(named: "   ")
        #expect(library.collection(collection)?.name == "Untitled Collection")

        let idResult = library.saveRequest(users, named: "", in: collection)
        let id = try #require(idResult)
        #expect(library.request(id)?.request.name == "v1/users")

        library.renameRequest(id, to: "  ")
        #expect(library.request(id)?.request.name == "v1/users")
        library.renameCollection(collection, to: "Renamed")
        #expect(library.collection(collection)?.name == "Renamed")
    }

    @Test func duplicateGoesRightBelowTheOriginal() throws {
        var library = CollectionLibrary()
        let collection = library.addCollection(named: "API")
        let firstResult = library.saveRequest(users, named: "Users", in: collection)
        let first = try #require(firstResult)
        library.saveRequest(users, named: "Other", in: collection)

        let copyResult = library.duplicateRequest(first)
        let copy = try #require(copyResult)
        #expect(library.collection(collection)?.requests.map(\.name) == ["Users", "Users copy", "Other"])
        #expect(library.request(copy)?.request.spec == users)
    }

    @Test func deletesRequestsAndCollections() throws {
        var library = CollectionLibrary()
        let collection = library.addCollection(named: "API")
        let idResult = library.saveRequest(users, named: "Users", in: collection)
        let id = try #require(idResult)
        library.deleteRequest(id)
        #expect(library.request(id) == nil)
        #expect(library.collection(collection) != nil)
        library.deleteCollection(collection)
        #expect(library.isEmpty)
    }

    @Test func filtersByRequestOrCollectionName() {
        var library = CollectionLibrary()
        let api = library.addCollection(named: "Example API")
        let other = library.addCollection(named: "Pipedrive")
        library.saveRequest(users, named: "List users", in: api)
        library.saveRequest(RequestSpec(method: .delete, url: "https://api.example.com/v1/users/1"), named: "Remove", in: api)
        library.saveRequest(RequestSpec(url: "https://api.pipedrive.com/v1/leads"), named: "Leads", in: other)

        #expect(library.filtered(by: "").count == 2)
        #expect(library.filtered(by: "leads").map(\.name) == ["Pipedrive"])
        #expect(library.filtered(by: "DELETE").first?.requests.map(\.name) == ["Remove"])
        // A matching collection name keeps all of its requests.
        #expect(library.filtered(by: "example api").first?.requests.count == 2)
        #expect(library.filtered(by: "nothing").isEmpty)
    }

    @Test func suggestsNames() {
        #expect(CollectionLibrary.suggestedName(for: users) == "v1/users")
        #expect(CollectionLibrary.suggestedName(for: RequestSpec(url: "https://www.fasttrack.ai/")) == "www.fasttrack.ai")
        #expect(CollectionLibrary.suggestedName(for: RequestSpec()) == "New Request")
        #expect(CollectionLibrary.suggestedCollectionName(for: RequestSpec(url: "https://www.fasttrack.ai/en")) == "fasttrack.ai")
        #expect(CollectionLibrary.suggestedCollectionName(for: RequestSpec(url: "localhost:3000/api")) == "localhost:3000")
        #expect(CollectionLibrary.suggestedCollectionName(for: RequestSpec()) == "My Requests")
    }

    @Test func roundTripsThroughCodable() throws {
        var library = CollectionLibrary()
        let collection = library.addCollection(named: "API")
        library.saveRequest(users, named: "Users", in: collection, at: Date(timeIntervalSince1970: 1_800_000_000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CollectionLibrary.self, from: encoder.encode(library))
        #expect(decoded == library)
    }

    @Test func setsAndClearsColors() {
        var library = CollectionLibrary()
        let id = library.addCollection(named: "API")
        #expect(library.collection(id)?.color == nil)
        library.setColor(.purple, for: id)
        #expect(library.collection(id)?.color == .purple)
        library.setColor(nil, for: id)
        #expect(library.collection(id)?.color == nil)
    }

    @Test func decodesCollectionsSavedBeforeColorsExisted() throws {
        let json = #"{"collections":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","requests":[]}]}"#
        let library = try JSONDecoder().decode(CollectionLibrary.self, from: Data(json.utf8))
        #expect(library.collections.first?.name == "Old")
        #expect(library.collections.first?.color == nil)
    }
}
