// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

public protocol AuthenticationStorage<Response>: Sendable {
    associatedtype Response: AuthenticationResponse

    func set(_ response: Response)
    func get() -> Response?
    func wipe()
}
