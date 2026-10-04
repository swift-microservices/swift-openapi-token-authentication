// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

public import HTTPTypes
public import OpenAPIRuntime

#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// Applies Bearer authentication and retries a replayable request once after an
/// authentication failure.
///
/// Share the session across clients to coordinate refreshes.
public struct AuthenticationMiddleware<Credentials: Sendable, Response: AuthenticationResponse>: ClientMiddleware {
    private let session: AuthenticationSession<Credentials, Response>
    private let policy: AuthenticationPolicy
    private let shouldRefresh: @Sendable (HTTPResponse, HTTPBody?) -> Bool

    /// A middleware that refreshes and retries when `shouldRefresh` accepts a response.
    ///
    /// - Parameters:
    ///   - session: The session that supplies and refreshes tokens.
    ///   - policy: Whether a request needs an authenticated session.
    ///   - shouldRefresh: Decides whether a response requires authentication refresh.
    public init(
        session: AuthenticationSession<Credentials, Response>,
        policy: AuthenticationPolicy = .required,
        shouldRefresh: @escaping @Sendable (HTTPResponse, HTTPBody?) -> Bool
    ) {
        self.session = session
        self.policy = policy
        self.shouldRefresh = shouldRefresh
    }

    /// A middleware that refreshes and retries on the given status codes.
    ///
    /// - Parameters:
    ///   - session: The session that supplies and refreshes tokens.
    ///   - policy: Whether a request needs an authenticated session.
    ///   - refreshableStatusCodes: The statuses that trigger one refresh and retry.
    public init(
        session: AuthenticationSession<Credentials, Response>,
        policy: AuthenticationPolicy = .required,
        refreshableStatusCodes: [HTTPResponse.Status] = [.unauthorized]
    ) {
        self.init(session: session, policy: policy) { response, _ in
            refreshableStatusCodes.contains(response.status)
        }
    }

    /// Attaches the session's access token, then refreshes and retries a replayable request once
    /// when the response asks for it.
    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @concurrent @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let token: String
        do {
            token = try await session.accessToken()
        } catch AuthenticationSessionError.userAuthenticationRequired where policy == .ifAvailable {
            return try await next(request, body, baseURL)
        }
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
