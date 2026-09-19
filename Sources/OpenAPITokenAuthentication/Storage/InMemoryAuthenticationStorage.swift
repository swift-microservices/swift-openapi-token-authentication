import Synchronization

/// Thread-safe storage that retains credentials only for the lifetime of this instance.
public final class InMemoryAuthenticationStorage<Response: AuthenticationResponse>: AuthenticationStorage {
    private let response: Mutex<Response?>

    public init(_ response: Response? = nil) {
        self.response = Mutex(response)
    }

    public func set(_ response: Response) {
        self.response.withLock { $0 = response }
    }

    public func get() -> Response? {
        response.withLock { $0 }
    }

    public func wipe() {
        response.withLock { $0 = nil }
    }
}
