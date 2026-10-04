// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

/// A client-classified authentication rejection, optionally retaining its original cause.
public struct AuthenticationClientError: Error {
    /// What the API rejected.
    public enum Code: Sendable {
        /// The credentials supplied for login were rejected.
        case invalidCredentials
        /// The refresh token was rejected or is no longer usable.
        case invalidRefreshToken
    }

    /// What the API rejected.
    public let code: Code
    /// The API's own error, if the client kept it.
    public let underlyingError: (any Error)?

    /// A rejection of `code`, optionally keeping the API's error.
    public init(_ code: Code, underlyingError: (any Error)? = nil) {
        self.code = code
        self.underlyingError = underlyingError
    }
}
