import OpenAPITokenAuthentication
import Synchronization

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct TestResponse: AuthenticationResponse, Equatable {
    var accessToken = "access"
    var accessTokenExpiration = Date.distantFuture
    var refreshToken = "refresh"
    var refreshTokenExpiration = Date.distantFuture
}

enum TestFailure: Error, Equatable {
    case transport
    case unexpectedCall
}

struct TestClient: AuthenticationClient {
    var login: @Sendable (String) async throws -> TestResponse = { _ in throw TestFailure.unexpectedCall }
    var refresh: @Sendable (String) async throws -> TestResponse = { _ in throw TestFailure.unexpectedCall }

    func authenticate(credentials: String) async throws -> TestResponse {
        try await login(credentials)
    }

    func refreshAuthentication(refreshToken: String) async throws -> TestResponse {
        try await refresh(refreshToken)
    }
}

/// A single-waiter signal that deliberately ignores cancellation, like an uncooperative client.
final class TestSignal: Sendable {
    private struct State {
        var signalled = false
        var continuation: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())

    func wait() async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock {
                if $0.signalled { return true }
                precondition($0.continuation == nil)
                $0.continuation = continuation
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func signal() {
        let continuation = state.withLock {
            $0.signalled = true
            let continuation = $0.continuation
            $0.continuation = nil
            return continuation
        }
        continuation?.resume()
    }
}
