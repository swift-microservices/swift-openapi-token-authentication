// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

/// A client-classified authentication rejection, optionally retaining its original cause.
public struct AuthenticationClientError: Error {
    public enum Code: Sendable {
        /// The credentials supplied for login were rejected.
        case invalidCredentials
        /// The refresh token was rejected or is no longer usable.
        case invalidRefreshToken
    }

    public let code: Code
    public let underlyingError: (any Error)?

    public init(_ code: Code, underlyingError: (any Error)? = nil) {
        self.code = code
        self.underlyingError = underlyingError
    }
}
