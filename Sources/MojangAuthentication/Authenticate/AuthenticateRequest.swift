//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

public struct AuthenticateRequest: Encodable {
    private let agent = Agent()
    
    let username: String
    let password: String
    
    let clientToken: String?
    let requestUser: Bool
    
    public init(username: String, password: String, clientToken: String? = nil, requestUser: Bool = false) {
        self.username = username
        self.password = password
        
        self.clientToken = clientToken
        self.requestUser = requestUser
    }
    
    private struct Agent: Encodable {
        let name = "Minecraft"
        let version = 1
    }
}
