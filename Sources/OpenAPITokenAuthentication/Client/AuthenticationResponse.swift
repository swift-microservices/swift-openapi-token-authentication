// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

/// The tokens an ``AuthenticationClient`` returns, with their expirations.
///
/// Conform the generated response type, or a small wrapper over it.
public protocol AuthenticationResponse: Sendable {
    /// The bearer token presented on API requests.
    var accessToken: String { get }
    /// When the access token expires; the session refreshes ahead of it by its refresh leeway.
    var accessTokenExpiration: Date { get }
    /// The token exchanged for new tokens when the access token expires or is rejected.
    var refreshToken: String { get }
    /// When the refresh token expires; after it, the person must sign in again.
    var refreshTokenExpiration: Date { get }
}
