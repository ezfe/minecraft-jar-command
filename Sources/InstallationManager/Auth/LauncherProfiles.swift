//
//  File.swift
//  File
//
//  Created by Ezekiel Elin on 10/17/21.
//

import Foundation

public struct SignInResult: Codable {
    public let id: String
    public let name: String
    public let token: String
    public let refresh: String
    
    public init(id: String, name: String, token: String, refresh: String) {
        self.id = id
        self.name = name
        self.token = token
        self.refresh = refresh
    }
}
