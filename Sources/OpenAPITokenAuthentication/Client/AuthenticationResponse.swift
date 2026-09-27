//
//  AuthenticationResponse.swift
//  swift-openapi-token-authentication
//
//  Created by Zaid Rahhawi on 9/18/26.
//

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
