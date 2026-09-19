import HTTPTypes
import OpenAPIRuntime
import OpenAPITokenAuthentication
import Synchronization
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite(.timeLimit(.minutes(1)))
struct AuthenticationMiddlewareTests {
    private let baseURL = URL(string: "https://example.com")!

    @Test(arguments: [HTTPResponse.Status.ok, .unauthorized])
    func retriesOnceWithFreshTokenAndOriginalBody(finalStatus: HTTPResponse.Status) async throws {
        let storage = InMemoryAuthenticationStorage(TestResponse())
        let client = TestClient(refresh: { _ in TestResponse(accessToken: "fresh") })
        let session = AuthenticationSession(client: client, storage: storage)
        let middleware = AuthenticationMiddleware(session: session)
        let headers = Mutex<[String?]>([])
        var request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/resource")
        request.headerFields[.authorization] = "Bearer unrelated"

        let (response, body) = try await middleware.intercept(
            request, body: HTTPBody("payload"), baseURL: baseURL, operationID: "example"
        ) { request, body, _ in
            let body = try #require(body)
            #expect(try await String(collecting: body, upTo: 100) == "payload")
            let attempt = headers.withLock {
                $0.append(request.headerFields[.authorization])
                return $0.count
            }
            return attempt == 1
                ? (HTTPResponse(status: .unauthorized), HTTPBody("rejection"))
                : (HTTPResponse(status: finalStatus), HTTPBody("final"))
        }

        #expect(response.status == finalStatus)
        #expect(headers.withLock { $0 } == ["Bearer access", "Bearer fresh"])
        let finalBody = try #require(body)
        #expect(try await String(collecting: finalBody, upTo: 100) == "final")
    }

    @Test(arguments: [HTTPResponse.Status.ok, .unauthorized])
    func singleUseBodyIsNotRetried(status: HTTPResponse.Status) async throws {
        let session = AuthenticationSession(client: TestClient(), storage: InMemoryAuthenticationStorage(TestResponse()))
        let middleware = AuthenticationMiddleware(session: session)
        let calls = Mutex(0)
        let body = HTTPBody(Array("payload".utf8), length: .known(7), iterationBehavior: .single)

        let (response, _) = try await middleware.intercept(
            HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/resource"),
            body: body, baseURL: baseURL, operationID: "example"
        ) { _, body, _ in
            calls.withLock { $0 += 1 }
            let body = try #require(body)
            #expect(try await String(collecting: body, upTo: 100) == "payload")
            return (HTTPResponse(status: status), nil)
        }

        #expect(response.status == status)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test
    func customPredicateCanRequestRefresh() async throws {
        let client = TestClient(refresh: { _ in TestResponse(accessToken: "fresh") })
        let session = AuthenticationSession(client: client, storage: InMemoryAuthenticationStorage(TestResponse()))
        let middleware = AuthenticationMiddleware(session: session) { response, _ in response.status == .forbidden }
        let (response, _) = try await middleware.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/resource"),
            body: nil, baseURL: baseURL, operationID: "example"
        ) { request, _, _ in
            (HTTPResponse(status: request.headerFields[.authorization] == "Bearer fresh" ? .ok : .forbidden), nil)
        }
        #expect(response.status == .ok)
    }

    @Test
    func cancellingEndpointDoesNotCancelSharedRefresh() async throws {
        let started = TestSignal()
        let release = TestSignal()
        let fresh = TestResponse(accessToken: "fresh", refreshToken: "rotated")
        let storage = InMemoryAuthenticationStorage(TestResponse())
        let client = TestClient(refresh: { _ in
            started.signal()
            await release.wait()
            #expect(!Task.isCancelled)
            return fresh
        })
        let session = AuthenticationSession(client: client, storage: storage)
        let middleware = AuthenticationMiddleware(session: session)
        let endpoint = Task {
            try await middleware.intercept(
                HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/resource"),
                body: nil, baseURL: baseURL, operationID: "example"
            ) { _, _, _ in
                // Model a transport that cooperates with endpoint cancellation.
                try Task.checkCancellation()
                return (HTTPResponse(status: .unauthorized), nil)
            }
        }
        await started.wait()

        endpoint.cancel()
        release.signal()

        await #expect(throws: CancellationError.self) { try await endpoint.value }
        #expect(storage.get() == fresh)
        #expect(try await session.accessToken() == fresh.accessToken)
    }
}
