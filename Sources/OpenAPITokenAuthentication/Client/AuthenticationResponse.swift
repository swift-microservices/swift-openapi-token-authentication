// Copyright (c) 2026 Zaid Rahhawi
// SPDX-License-Identifier: MIT
// See LICENSE for license information.

#if canImport(FoundationEssentials)
public import FoundationEssentials
#else
public import Foundation
#endif

public protocol AuthenticationResponse: Sendable {
    var accessToken: String { get }
    var accessTokenExpiration: Date { get }
    var refreshToken: String { get }
    var refreshTokenExpiration: Date { get }
}
