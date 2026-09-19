#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Serializes credential access and shares authentication work between callers.
public actor AuthenticationSession<Credentials: Sendable, Response: AuthenticationResponse> {
    private let client: any AuthenticationClient<Credentials, Response>
    private let storage: any AuthenticationStorage<Response>
    private let refreshLeeway: TimeInterval

    private enum State: Sendable {
        case unauthenticated
        case authenticated(response: Response)
        case authenticating(task: Task<Response, any Error>)
        case refreshingAuthentication(task: Task<Response, any Error>)

        var observableState: AuthenticationState {
            switch self {
            case .unauthenticated: .unauthenticated
            case .authenticating: .authenticating
            case .authenticated: .authenticated
            case .refreshingAuthentication: .refreshing
            }
        }
    }

    private var observers: [UUID: AsyncStream<AuthenticationState>.Continuation] = [:]
    // Update storage before assigning state so observers see committed credentials.
    private var state: State {
        didSet {
            guard state.observableState != oldValue.observableState else { return }
            for observer in observers.values {
                observer.yield(state.observableState)
            }
        }
    }

    /// Restores saved credentials while the refresh token remains valid.
    public init(
        client: any AuthenticationClient<Credentials, Response>,
        storage: any AuthenticationStorage<Response>,
        refreshLeeway: TimeInterval = 30
    ) {
        precondition(refreshLeeway.isFinite && refreshLeeway >= 0)

        self.client = client
        self.storage = storage
        self.refreshLeeway = refreshLeeway

        guard let response = storage.get(), response.isRefreshable else {
            storage.wipe()
            self.state = .unauthenticated
            return
        }

        self.state = .authenticated(response: response)
    }

    deinit {
        for observer in observers.values {
            observer.finish()
        }
    }

    /// Creates an independent subscription, initially buffering the current state.
    /// Slow observers receive only the latest state. Cancelling observation does not
    /// cancel authentication work. The stream remains open across login and logout.
    public func states() -> AsyncStream<AuthenticationState> {
        let (stream, continuation) = AsyncStream<AuthenticationState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()

        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        observers[id] = continuation
        continuation.yield(state.observableState)
        return stream
    }

    /// Starts a new login, replacing any previous credentials or pending work.
    public func authenticate(credentials: Credentials) async throws {
        logout()

        let task = Task {
            do {
                let response = try await client.authenticate(credentials: credentials)
                try save(response)
                return response
            } catch  where Task.isCancelled {
                throw CancellationError()
            } catch {
                self.state = .unauthenticated
                throw error
            }
        }

        self.state = .authenticating(task: task)
        _ = try await task.value
    }

    /// Returns a cached token, refreshing it when it is near expiration.
    public func accessToken() async throws -> String {
        switch state {
        case .authenticated(let response):
            guard response.isRefreshable, !response.accessToken.isEmpty,
                response.accessTokenExpiration.timeIntervalSinceNow > refreshLeeway
            else {
                return try await newAccessToken()
            }
            return response.accessToken
        case .authenticating(let task), .refreshingAuthentication(let task):
            return try await task.value.accessToken
        case .unauthenticated:
            throw AuthenticationSessionError.userAuthenticationRequired
        }
    }

    /// Refreshes authentication, or joins work already in progress.
    public func newAccessToken() async throws -> String {
        switch state {
        case .authenticated(let response):
            guard response.isRefreshable else {
                logout()
                throw AuthenticationSessionError.userAuthenticationRequired
            }

            let task = Task {
                do {
                    let refreshedResponse = try await client.refreshAuthentication(refreshToken: response.refreshToken)
                    try save(refreshedResponse)
                    return refreshedResponse
                } catch  where Task.isCancelled {
                    throw CancellationError()
                } catch AuthenticationSessionError.userAuthenticationRequired {
                    self.storage.wipe()
                    self.state = .unauthenticated
                    throw AuthenticationSessionError.userAuthenticationRequired
                } catch let error as AuthenticationClientError where error.code == .invalidRefreshToken {
                    self.storage.wipe()
                    self.state = .unauthenticated
                    throw AuthenticationSessionError.userAuthenticationRequired
                } catch {
                    guard response.isRefreshable else {
                        self.storage.wipe()
                        self.state = .unauthenticated
                        throw AuthenticationSessionError.userAuthenticationRequired
                    }
                    self.state = .authenticated(response: response)
                    throw error
                }
            }

            self.state = .refreshingAuthentication(task: task)
            return try await task.value.accessToken
        case .authenticating(let task), .refreshingAuthentication(let task):
            return try await task.value.accessToken
        case .unauthenticated:
            throw AuthenticationSessionError.userAuthenticationRequired
        }
    }

    /// Cancels in-flight authentication and removes saved credentials.
    public func logout() {
        switch state {
        case .authenticating(let task), .refreshingAuthentication(let task):
            task.cancel()
        default:
            break
        }
        self.storage.wipe()
        self.state = .unauthenticated
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func save(_ response: Response) throws {
        // The client may return successfully even after logout cancelled its task.
        try Task.checkCancellation()
        guard response.isRefreshable else {
            throw AuthenticationSessionError.userAuthenticationRequired
        }
        self.storage.set(response)
        self.state = .authenticated(response: response)
    }
}

extension AuthenticationResponse {
    fileprivate var isRefreshable: Bool {
        return !refreshToken.isEmpty && refreshTokenExpiration > Date.now
    }
}
