/// Whether a request needs an authenticated session before it can be sent.
public enum AuthenticationPolicy: Sendable, Equatable {
    /// Require a token, waiting for an in-flight login or refresh if necessary.
    case required
    /// Attempt token lookup, waiting for in-flight login or refresh work.
    /// Send unchanged if lookup requires user authentication; other errors propagate.
    case ifAvailable
}
