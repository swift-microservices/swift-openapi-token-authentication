// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

/// Why a session cannot supply a token.
public enum AuthenticationSessionError: Error, Equatable {
    /// No session exists, or refresh credentials are missing, expired, or rejected.
    case userAuthenticationRequired
}
