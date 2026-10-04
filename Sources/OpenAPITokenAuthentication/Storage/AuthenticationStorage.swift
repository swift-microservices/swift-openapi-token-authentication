// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

/// Where a session keeps its credentials.
///
/// Implement it over the platform's secure store, such as the Keychain, when credentials must
/// survive a restart.
public protocol AuthenticationStorage<Response>: Sendable {
    /// The credentials it stores.
    associatedtype Response: AuthenticationResponse

    /// Replaces the stored credentials with `response`.
    func set(_ response: Response)
    /// The stored credentials, or `nil` when there are none.
    func get() -> Response?
    /// Removes the stored credentials.
    func wipe()
}
