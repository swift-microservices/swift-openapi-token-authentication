//
//  AuthenticationStorage.swift
//  swift-openapi-token-authentication
//
//  Created by Zaid Rahhawi on 9/18/26.
//

public protocol AuthenticationStorage<Response>: Sendable {
    associatedtype Response: AuthenticationResponse

    func set(_ response: Response)
    func get() -> Response?
    func wipe()
}
