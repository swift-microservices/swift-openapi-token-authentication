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

    @Test(
        arguments: [HTTPResponse.Status.ok, .unauthorized],
        [AuthenticationPolicy.required, .ifAvailable])
    func retriesOnceWithFreshTokenAndOriginalBody(
        finalStatus: HTTPResponse.Status, policy: AuthenticationPolicy
    ) async throws {
        let storage = InMemoryAuthenticationStorage(TestResponse())
        let client = TestClient(refresh: { _ in TestResponse(accessToken: "fresh") })
        let session = AuthenticationSession(client: client, storage: storage)
        let middleware = AuthenticationMiddleware(session: session, policy: policy)
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

    @Test(arguments: [AuthenticationPolicy.required, .ifAvailable])
    func customPredicateCanRequestRefresh(policy: AuthenticationPolicy) async throws {
        let client = TestClient(refresh: { _ in TestResponse(accessToken: "fresh") })
        let session = AuthenticationSession(client: client, storage: InMemoryAuthenticationStorage(TestResponse()))
        let middleware = AuthenticationMiddleware(session: session, policy: policy) { response, _ in
            response.status == .forbidden
        }
        let (response, _) = try await middleware.intercept(
            HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/resource"),
            body: nil, baseURL: baseURL, operationID: "example"
        ) { request, _, _ in
            (HTTPResponse(status: request.headerFields[.authorization] == "Bearer fresh" ? .ok : .forbidden), nil)
        }
        #expect(response.status == .ok)
    }

    @Test(arguments: [AuthenticationPolicy.required, .ifAvailable])
    func cancellingEndpointDoesNotCancelSharedRefresh(policy: AuthenticationPolicy) async throws {
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
        let middleware = AuthenticationMiddleware(session: session, policy: policy)
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

    @Test
    func defaultPolicyRequiresAuthenticationBeforeTransport() async {
        let session = AuthenticationSession(client: TestClient(), storage: InMemoryAuthenticationStorage<TestResponse>())
        let middleware = AuthenticationMiddleware(session: session)
        await #expect(throws: AuthenticationSessionError.userAuthenticationRequired) {
            try await middleware.intercept(
                HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/resource"),
                body: nil, baseURL: baseURL, operationID: "example"
            ) { _, _, _ in
                Issue.record("An unauthenticated request must not reach transport under the default policy")
                return (HTTPResponse(status: .ok), nil)
            }
        }
    }

    @Test(arguments: [HTTPResponse.Status.ok, .unauthorized], [nil, "Basic existing"] as [String?])
    func anonymousRequestsPassThroughUnchanged(status: HTTPResponse.Status, authorization: String?) async throws {
        let session = AuthenticationSession(client: TestClient(), storage: InMemoryAuthenticationStorage<TestResponse>())
        let middleware = AuthenticationMiddleware(session: session, policy: .ifAvailable) { _, _ in
            Issue.record("Anonymous responses must not enter refresh handling")
            return true
        }
        var request = HTTPRequest(method: .post, scheme: "https", authority: "example.com", path: "/resource")
        request.headerFields[.authorization] = authorization
        let calls = Mutex(0)
        let expectedURL = baseURL
        let (response, responseBody) = try await middleware.intercept(
            request, body: HTTPBody("payload"), baseURL: baseURL, operationID: "example"
        ) { request, body, url in
            calls.withLock { $0 += 1 }
            #expect(request.headerFields[.authorization] == authorization)
            #expect(request.method == .post)
            #expect(request.path == "/resource")
            #expect(url == expectedURL)
            let body = try #require(body)
            #expect(try await String(collecting: body, upTo: 100) == "payload")
            return (HTTPResponse(status: status), HTTPBody("response"))
        }
        #expect(response.status == status)
        let finalBody = try #require(responseBody)
        #expect(try await String(collecting: finalBody, upTo: 100) == "response")
        #expect(calls.withLock { $0 } == 1)
    }

    @Test
    func optionalAuthenticationUsesCompletedLogin() async throws {
        let started = TestSignal()
        let release = TestSignal()
        let storage = InMemoryAuthenticationStorage<TestResponse>()
        let client = TestClient(login: { _ in
            started.signal()
            await release.wait()
            #expect(!Task.isCancelled)
            return TestResponse()
        })
        let session = AuthenticationSession(client: client, storage: storage)
        let login = Task { try await session.authenticate(credentials: "pairing") }
        defer { release.signal() }
        await started.wait()

        let middleware = AuthenticationMiddleware(session: session, policy: .ifAvailable)
        let endpoint = Task {
            try await middleware.intercept(
                HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/resource"),
                body: nil, baseURL: baseURL, operationID: "example"
            ) { request, _, _ in
                #expect(request.headerFields[.authorization] == "Bearer access")
                #expect(storage.get() == TestResponse())
                return (HTTPResponse(status: .ok), nil)
            }
        }
        release.signal()
        try await login.value
        let (response, _) = try await endpoint.value
        #expect(response.status == .ok)
        #expect(storage.get() == TestResponse())
    }

    @Test(arguments: [false, true])
    func optionalAuthenticationPropagatesRefreshFailures(cancelled: Bool) async {
        let old = TestResponse(accessTokenExpiration: .distantPast)
        let storage = InMemoryAuthenticationStorage(old)
        let client = TestClient(refresh: { _ in
            if cancelled { throw CancellationError() }
            throw TestFailure.transport
        })
        let session = AuthenticationSession(client: client, storage: storage)
        let middleware = AuthenticationMiddleware(session: session, policy: .ifAvailable)
        do {
            _ = try await middleware.intercept(
                HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/resource"),
                body: nil, baseURL: baseURL, operationID: "example"
            ) { _, _, _ in
                Issue.record("A refresh failure must not fall back to anonymous transport")
                return (HTTPResponse(status: .ok), nil)
            }
            Issue.record("Expected refresh failure")
        } catch {
            if cancelled {
                #expect(error is CancellationError)
            } else {
                #expect(error as? TestFailure == .transport)
            }
        }
        #expect(storage.get() == old)
    }

    @Test(arguments: [AuthenticationPolicy.required, .ifAvailable])
    func rejectedRefreshDuringTokenLookupUsesPolicy(policy: AuthenticationPolicy) async throws {
        let storage = InMemoryAuthenticationStorage(TestResponse(accessTokenExpiration: .distantPast))
        let client = TestClient(refresh: { _ in throw AuthenticationClientError(.invalidRefreshToken) })
        let session = AuthenticationSession(client: client, storage: storage)
        let middleware = AuthenticationMiddleware(session: session, policy: policy)
        let calls = Mutex(0)
        do {
            let (response, _) = try await middleware.intercept(
                HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/resource"),
                body: nil, baseURL: baseURL, operationID: "example"
            ) { request, _, _ in
                calls.withLock { $0 += 1 }
                #expect(request.headerFields[.authorization] == nil)
                return (HTTPResponse(status: .unauthorized), nil)
            }
            #expect(policy == .ifAvailable)
            #expect(response.status == .unauthorized)
        } catch {
            #expect(policy == .required)
            #expect(error as? AuthenticationSessionError == .userAuthenticationRequired)
        }
        #expect(calls.withLock { $0 } == (policy == .ifAvailable ? 1 : 0))
        #expect(storage.get() == nil)
    }

    @Test
    func transportAuthenticationErrorIsNotCaughtAsTokenLookupFailure() async {
        let session = AuthenticationSession(client: TestClient(), storage: InMemoryAuthenticationStorage(TestResponse()))
        let middleware = AuthenticationMiddleware(session: session, policy: .ifAvailable)
        let calls = Mutex(0)
        await #expect(throws: AuthenticationSessionError.userAuthenticationRequired) {
            try await middleware.intercept(
                HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/resource"),
                body: nil, baseURL: baseURL, operationID: "example"
            ) { _, _, _ in
                calls.withLock { $0 += 1 }
                throw AuthenticationSessionError.userAuthenticationRequired
            }
        }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test
    func rejectedAuthenticatedRequestDoesNotRetryAnonymously() async {
        let storage = InMemoryAuthenticationStorage(TestResponse())
        let client = TestClient(refresh: { _ in throw AuthenticationClientError(.invalidRefreshToken) })
        let session = AuthenticationSession(client: client, storage: storage)
        let middleware = AuthenticationMiddleware(session: session, policy: .ifAvailable)
        let calls = Mutex(0)
        await #expect(throws: AuthenticationSessionError.userAuthenticationRequired) {
            try await middleware.intercept(
                HTTPRequest(method: .get, scheme: "https", authority: "example.com", path: "/resource"),
                body: nil, baseURL: baseURL, operationID: "example"
            ) { request, _, _ in
                calls.withLock { $0 += 1 }
                #expect(request.headerFields[.authorization] == "Bearer access")
                return (HTTPResponse(status: .unauthorized), nil)
            }
        }
        #expect(calls.withLock { $0 } == 1)
        #expect(storage.get() == nil)
    }
}
