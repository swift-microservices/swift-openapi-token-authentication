/// The observable authentication phase, without credentials or internal tasks.
public enum AuthenticationState: Sendable, Equatable {
    case unauthenticated
    case authenticating
    case authenticated
    /// The existing session is refreshing its credentials, not signing out.
    case refreshing
}
