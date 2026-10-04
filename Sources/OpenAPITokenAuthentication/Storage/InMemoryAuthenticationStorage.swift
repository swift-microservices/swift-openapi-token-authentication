// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

import Synchronization

/// Thread-safe storage that retains credentials only for the lifetime of this instance.
public final class InMemoryAuthenticationStorage<Response: AuthenticationResponse>: AuthenticationStorage {
    private let response: Mutex<Response?>

    /// Storage holding `response`, or empty.
    public init(_ response: Response? = nil) {
        self.response = Mutex(response)
    }

    /// Replaces the stored credentials with `response`.
    public func set(_ response: Response) {
        self.response.withLock { $0 = response }
    }

    /// The stored credentials, or `nil` when there are none.
    public func get() -> Response? {
        response.withLock { $0 }
    }

    /// Removes the stored credentials.
    public func wipe() {
        response.withLock { $0 = nil }
    }
}
