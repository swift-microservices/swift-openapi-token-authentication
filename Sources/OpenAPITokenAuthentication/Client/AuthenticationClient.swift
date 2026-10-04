// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

/// The API calls a session makes to sign in and to refresh, without the authentication middleware.
///
/// Implement it over the generated client's login and refresh operations. Use a client that does
/// not carry ``AuthenticationMiddleware``, so these calls never wait on the session they serve.
public protocol AuthenticationClient<Credentials, Response>: Sendable {
    /// What a person signs in with, such as a username and password or a pairing code.
    associatedtype Credentials: Sendable
    /// The tokens and expirations the API returns.
    associatedtype Response: AuthenticationResponse

    /// Signs in with `credentials` and returns the issued tokens.
    ///
    /// Classify rejected credentials with `AuthenticationClientError`; propagate other errors unchanged.
    func authenticate(credentials: Credentials) async throws -> Response

    /// Exchanges `refreshToken` for new tokens.
    ///
    /// Classify rejected refresh tokens with `AuthenticationClientError`; propagate other errors unchanged.
    func refreshAuthentication(refreshToken: String) async throws -> Response
}
