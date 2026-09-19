//
//  AuthenticationSessionError.swift
//  swift-openapi-token-authentication
//
//  Created by Zaid Rahhawi on 9/18/26.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum AuthenticationSessionError: Error, Equatable {
    /// No session exists, or refresh credentials are missing, expired, or rejected.
    case userAuthenticationRequired
}
