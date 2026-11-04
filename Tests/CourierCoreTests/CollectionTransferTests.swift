import Foundation
import Testing
@testable import CourierCore

@Suite struct CollectionTransferTests {
    private func sampleCollection() -> RequestCollection {
        var spec = RequestSpec(method: .post, url: "https://api.example.com/v1/users")
        spec.setParams([KeyValue("api_token", "s3cret"), KeyValue("limit", "5")])
        spec.headers = [KeyValue("Authorization", "Bearer abc"), KeyValue("Accept", "application/json")]
        spec.bodyKind = .json
        spec.bodyText = #"{"name":"Ada"}"#
        return RequestCollection(name: "Example", color: .purple, requests: [SavedRequest(name: "Create user", spec: spec)])
    }

    // MARK: Courier format

    @Test func roundTripsWithFreshIDs() throws {
        let original = sampleCollection()
        let data = try CollectionTransfer.export([original], includeSecrets: true)
        let result = try CollectionTransfer.importFile(data)

        let imported = try #require(result.collections.first)
        #expect(imported.name == "Example")
        #expect(imported.color == .purple)
        #expect(imported.id != original.id)
        #expect(imported.requests.first?.id != original.requests.first?.id)
        #expect(imported.requests.first?.name == "Create user")
        #expect(imported.requests.first?.spec == original.requests.first?.spec)
        #expect(result.notes.isEmpty)
    }

    @Test func leavesOutSecretValuesByDefaultButKeepsTheirNames() throws {
        let data = try CollectionTransfer.export([sampleCollection()], includeSecrets: false)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("s3cret"))
        #expect(!text.contains("Bearer abc"))

        let spec = try #require(CollectionTransfer.importFile(data).collections.first?.requests.first?.spec)
        #expect(spec.headers.map(\.key) == ["Authorization", "Accept"])
        #expect(spec.headers.first?.value == "")
        #expect(spec.headers.last?.value == "application/json")
        #expect(spec.url == "https://api.example.com/v1/users?api_token&limit=5")
        #expect(spec.params.first?.key == "api_token")
        #expect(spec.bodyText == #"{"name":"Ada"}"#)
    }

    @Test func stripsPasswordsInURLs() {
        let spec = CollectionTransfer.withoutSecrets(RequestSpec(url: "https://me:hunter2@example.com/x"))
        #expect(!spec.url.contains("hunter2"))
        #expect(spec.url == "https://example.com/x")
    }

    @Test func rejectsNewerFormatsAndUnknownFiles() {
        let newer = Data(#"{"format":"courier.collections","version":99,"exported":"2026-01-01T00:00:00Z","collections":[]}"#.utf8)
        #expect(throws: CollectionTransfer.TransferError.unsupportedVersion(99)) { try CollectionTransfer.importFile(newer) }
        #expect(throws: CollectionTransfer.TransferError.unrecognizedFile) { try CollectionTransfer.importFile(Data(#"{"hello":1}"#.utf8)) }
        #expect(throws: CollectionTransfer.TransferError.unrecognizedFile) { try CollectionTransfer.importFile(Data("not json".utf8)) }
    }

    // MARK: Postman

    private let postman = #"""
    {
      "info": { "name": "Shop API", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json" },
      "auth": { "type": "bearer", "bearer": [{ "key": "token", "value": "{{token}}", "type": "string" }] },
      "item": [
        {
          "name": "Users",
          "item": [
            {
              "name": "Get user",
              "request": {
                "method": "GET",
                "header": [
                  { "key": "Accept", "value": "application/json" },
                  { "key": "X-Debug", "value": "1", "disabled": true }
                ],
                "url": {
                  "raw": "https://shop.test/users/1?expand=orders",
                  "query": [
                    { "key": "expand", "value": "orders" },
                    { "key": "fields", "value": "id", "disabled": true }
                  ]
                }
              }
            },
            {
              "name": "Create user",
              "request": {
                "method": "POST",
                "auth": { "type": "basic", "basic": [{ "key": "username", "value": "ada" }, { "key": "password", "value": "pw" }] },
                "body": { "mode": "raw", "raw": "{\"name\":\"Ada\"}", "options": { "raw": { "language": "json" } } },
                "url": { "protocol": "https", "host": ["shop", "test"], "path": ["users"] }
              }
            }
          ]
        },
        {
          "name": "Login",
          "request": {
            "method": "POST",
            "auth": { "type": "noauth" },
            "body": {
              "mode": "formdata",
              "formdata": [
                { "key": "user", "value": "ada", "type": "text" },
                { "key": "avatar", "type": "file", "src": "/tmp/a.png" }
              ]
            },
            "url": "https://shop.test/login"
          }
        },
        {
          "name": "Search",
          "request": {
            "method": "POST",
            "auth": { "type": "apikey", "apikey": [{ "key": "key", "value": "api_key" }, { "key": "value", "value": "k1" }, { "key": "in", "value": "query" }] },
            "body": { "mode": "graphql", "graphql": { "query": "{ products { id } }", "variables": "{\"first\": 5}" } },
            "url": "https://shop.test/graphql"
          }
        },
        { "name": "Health", "request": "https://shop.test/health" }
      ]
    }
    """#

    @Test func importsPostmanCollections() throws {
        let result = try CollectionTransfer.importFile(Data(postman.utf8))
        let collection = try #require(result.collections.first)
        #expect(result.collections.count == 1)
        #expect(collection.name == "Shop API")
        #expect(collection.requests.map(\.name) == ["Users / Get user", "Users / Create user", "Login", "Search", "Health"])

        let get = collection.requests[0].spec
        #expect(get.method == .get)
        #expect(get.url == "https://shop.test/users/1?expand=orders")
        #expect(get.params.map(\.key) == ["expand", "fields"])
        #expect(get.params.last?.isEnabled == false)
        #expect(get.headers.map(\.key) == ["Accept", "X-Debug", "Authorization"])
        #expect(get.headers[1].isEnabled == false)
        // Inherited from the collection.
        #expect(get.headers[2].value == "Bearer {{token}}")

        let create = collection.requests[1].spec
        #expect(create.url == "https://shop.test/users")
        #expect(create.bodyKind == .json)
        #expect(create.bodyText == #"{"name":"Ada"}"#)
        #expect(create.headers.first { $0.key == "Authorization" }?.value == "Basic \(Data("ada:pw".utf8).base64EncodedString())")

        let login = collection.requests[2].spec
        #expect(login.headers.isEmpty) // noauth overrides the collection's bearer token
        #expect(login.bodyKind == .form)
        #expect(login.formFields.map(\.key) == ["user"])

        let search = collection.requests[3].spec
        #expect(search.url == "https://shop.test/graphql?api_key=k1")
        #expect(search.bodyKind == .json)
        #expect(search.bodyText.contains("products"))
        #expect(search.bodyText.contains("\"first\" : 5"))

        #expect(collection.requests[4].spec.url == "https://shop.test/health")

        #expect(result.notes.contains { $0.contains("{{variables}}") })
        #expect(result.notes.contains { $0.contains("File fields") })
    }

    @Test func postmanFileWithoutRequestsIsEmpty() {
        let data = Data(#"{"info":{"name":"Nothing"},"item":[{"name":"Folder","item":[]}]}"#.utf8)
        #expect(throws: CollectionTransfer.TransferError.empty) { try CollectionTransfer.importFile(data) }
    }

    @Test func importedNamesDontClashWithExistingCollections() {
        var library = CollectionLibrary()
        library.addCollection(named: "API")
        library.add([RequestCollection(name: "API"), RequestCollection(name: "API"), RequestCollection(name: "Other")])
        #expect(library.collections.map(\.name) == ["API", "API 2", "API 3", "Other"])
    }
}
