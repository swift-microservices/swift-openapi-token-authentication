// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

/// The observable authentication phase, without credentials or internal tasks.
public enum AuthenticationState: Sendable, Equatable {
    /// No credentials; the person must sign in.
    case unauthenticated
    /// A login is in flight.
    case authenticating
    /// Credentials are available.
    case authenticated
    /// The existing session is refreshing its credentials, not signing out.
    case refreshing
}
