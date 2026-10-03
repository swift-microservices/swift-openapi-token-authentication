// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

public protocol AuthenticationClient<Credentials, Response>: Sendable {
    associatedtype Credentials: Sendable
    associatedtype Response: AuthenticationResponse

    /// Classify rejected credentials with `AuthenticationClientError`; propagate other errors unchanged.
    func authenticate(credentials: Credentials) async throws -> Response

    /// Classify rejected refresh tokens with `AuthenticationClientError`; propagate other errors unchanged.
    func refreshAuthentication(refreshToken: String) async throws -> Response
}
