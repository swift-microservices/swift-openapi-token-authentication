import HTTPTypes
import OpenAPIRuntime

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Applies Bearer authentication and retries a replayable request once after an
/// authentication failure. Share the session across clients to coordinate refreshes.
public struct AuthenticationMiddleware<Credentials: Sendable, Response: AuthenticationResponse>: ClientMiddleware {
    private let session: AuthenticationSession<Credentials, Response>
    private let shouldRefresh: @Sendable (HTTPResponse, HTTPBody?) -> Bool

    /// Decides whether a response requires authentication refresh.
    public init(
        session: AuthenticationSession<Credentials, Response>,
        shouldRefresh: @escaping @Sendable (HTTPResponse, HTTPBody?) -> Bool
    ) {
        self.session = session
        self.shouldRefresh = shouldRefresh
    }

    public init(
        session: AuthenticationSession<Credentials, Response>,
        refreshableStatusCodes: [HTTPResponse.Status] = [.unauthorized]
    ) {
        self.init(session: session) { response, _ in
            refreshableStatusCodes.contains(response.status)
        }
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let token = try await session.accessToken()
        var request = request
        request.headerFields[.authorization] = "Bearer \(token)"

        let (response, responseBody) = try await next(request, body, baseURL)

        guard shouldRefresh(response, responseBody) else {
            return (response, responseBody)
        }

        guard body == nil || body?.iterationBehavior == .multiple else {
            return (response, responseBody)
        }

        let refreshed = try await session.newAccessToken()
        request.headerFields[.authorization] = "Bearer \(refreshed)"

        return try await next(request, body, baseURL)
    }
}
