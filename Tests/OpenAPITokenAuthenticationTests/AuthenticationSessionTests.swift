import OpenAPITokenAuthentication
import Synchronization
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite(.timeLimit(.minutes(1)))
struct AuthenticationSessionTests {
    @Test
    func loginPersistsCredentialsAndCachesAccessToken() async throws {
        let response = TestResponse()
        let storage = InMemoryAuthenticationStorage<TestResponse>()
        let client = TestClient(login: { credentials in
            #expect(credentials == "credentials")
            return response
        })
        let session = AuthenticationSession(client: client, storage: storage)

        try await session.authenticate(credentials: "credentials")

        #expect(storage.get() == response)
        #expect(try await session.accessToken() == response.accessToken)
    }

    @Test(
        arguments: [
            nil,
            TestResponse(refreshToken: ""),
            TestResponse(refreshTokenExpiration: .distantPast),
        ] as [TestResponse?])
    func unusableStoredCredentialsRequireAuthentication(_ response: TestResponse?) async {
        let storage = InMemoryAuthenticationStorage(response)
        let session = AuthenticationSession(client: TestClient(), storage: storage)

        await #expect(throws: AuthenticationSessionError.userAuthenticationRequired) {
            try await session.accessToken()
        }
        #expect(storage.get() == nil)
    }

    @Test(arguments: [Date.distantPast, Date.now.addingTimeInterval(60)])
    func expiredOrNearExpiryAccessTokenRefreshes(_ expiration: Date) async throws {
        let old = TestResponse(accessTokenExpiration: expiration)
        let fresh = TestResponse(accessToken: "new-access", refreshToken: "rotated-refresh")
        let storage = InMemoryAuthenticationStorage(old)
        let client = TestClient(refresh: { token in
            #expect(token == old.refreshToken)
            return fresh
        })
        let session = AuthenticationSession(client: client, storage: storage, refreshLeeway: 3600)

        #expect(try await session.accessToken() == fresh.accessToken)
        #expect(storage.get() == fresh)
    }

    @Test
    func rejectedLoginPreservesClientError() async throws {
        let storage = InMemoryAuthenticationStorage(TestResponse())
        let client = TestClient(login: { _ in
            throw AuthenticationClientError(.invalidCredentials, underlyingError: TestFailure.transport)
        })
        let session = AuthenticationSession(client: client, storage: storage)

        do {
            try await session.authenticate(credentials: "rejected")
            Issue.record("Expected rejected credentials")
        } catch let error as AuthenticationClientError {
            #expect(error.code == .invalidCredentials)
            #expect(error.underlyingError as? TestFailure == .transport)
        }
        #expect(storage.get() == nil)
    }

    @Test
    func rejectedRefreshClearsCredentials() async {
        let storage = InMemoryAuthenticationStorage(TestResponse())
        let client = TestClient(refresh: { _ in throw AuthenticationClientError(.invalidRefreshToken) })
        let session = AuthenticationSession(client: client, storage: storage)

        await #expect(throws: AuthenticationSessionError.userAuthenticationRequired) {
            try await session.newAccessToken()
        }
        #expect(storage.get() == nil)
        await #expect(throws: AuthenticationSessionError.userAuthenticationRequired) {
            try await session.accessToken()
        }
    }

    @Test(arguments: [TestResponse(refreshToken: ""), TestResponse(refreshTokenExpiration: .distantPast)])
    func unusableRefreshResponseRequiresAuthentication(_ response: TestResponse) async {
        let storage = InMemoryAuthenticationStorage(TestResponse())
        let client = TestClient(refresh: { _ in response })
        let session = AuthenticationSession(client: client, storage: storage)

        await #expect(throws: AuthenticationSessionError.userAuthenticationRequired) {
            try await session.newAccessToken()
        }
        #expect(storage.get() == nil)
    }

    @Test
    func temporaryRefreshFailurePreservesCredentialsAndAllowsRetry() async throws {
        let calls = Mutex(0)
        let old = TestResponse()
        let fresh = TestResponse(accessToken: "fresh")
        let storage = InMemoryAuthenticationStorage(old)
        let client = TestClient(refresh: { _ in
            let attempt = calls.withLock {
                $0 += 1
                return $0
            }
            if attempt == 1 { throw TestFailure.transport }
            return fresh
        })
        let session = AuthenticationSession(client: client, storage: storage)

        await #expect(throws: TestFailure.transport) { try await session.newAccessToken() }
        #expect(storage.get() == old)
        #expect(try await session.accessToken() == old.accessToken)
        #expect(try await session.newAccessToken() == fresh.accessToken)
        #expect(storage.get() == fresh)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test
    func concurrentAccessSharesRefresh() async throws {
        let started = TestSignal()
        let release = TestSignal()
        let calls = Mutex(0)
        let fresh = TestResponse(accessToken: "fresh", refreshToken: "rotated")
        let storage = InMemoryAuthenticationStorage(TestResponse(accessTokenExpiration: .distantPast))
        let client = TestClient(refresh: { _ in
            calls.withLock { $0 += 1 }
            started.signal()
            await release.wait()
            return fresh
        })
        let session = AuthenticationSession(client: client, storage: storage)

        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let token = try await session.accessToken()
                    #expect(storage.get() == fresh)
                    return token
                }
            }
            await started.wait()
            release.signal()
            for try await token in group { #expect(token == fresh.accessToken) }
        }
        #expect(calls.withLock { $0 } == 1)
    }

    @Test(arguments: [false, true])
    func logoutPreventsLateRefreshFromChangingState(clientThrows: Bool) async {
        let started = TestSignal()
        let release = TestSignal()
        let storage = InMemoryAuthenticationStorage(TestResponse())
        let client = TestClient(refresh: { _ in
            started.signal()
            await release.wait()
            if clientThrows { throw TestFailure.transport }
            return TestResponse(accessToken: "late")
        })
        let session = AuthenticationSession(client: client, storage: storage)
        let refresh = Task { try await session.newAccessToken() }
        await started.wait()

        await session.logout()
        release.signal()

        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(storage.get() == nil)
        await #expect(throws: AuthenticationSessionError.userAuthenticationRequired) {
            try await session.accessToken()
        }
    }

    @Test
    func newerLoginCannotBeOverwrittenByOldRefresh() async throws {
        let started = TestSignal()
        let release = TestSignal()
        let fresh = TestResponse(accessToken: "new-account")
        let storage = InMemoryAuthenticationStorage(TestResponse())
        let client = TestClient(
            login: { _ in fresh },
            refresh: { _ in
                started.signal()
                await release.wait()
                return TestResponse(accessToken: "old-account")
            })
        let session = AuthenticationSession(client: client, storage: storage)
        let refresh = Task { try await session.newAccessToken() }
        await started.wait()

        // Always release the old request, even if login unexpectedly fails.
        defer { release.signal() }
        try await session.authenticate(credentials: "new-account")
        release.signal()

        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(storage.get() == fresh)
        #expect(try await session.accessToken() == fresh.accessToken)
    }
}
