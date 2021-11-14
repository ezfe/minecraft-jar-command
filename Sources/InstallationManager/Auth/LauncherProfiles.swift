//
//  File.swift
//  File
//
//  Created by Ezekiel Elin on 10/17/21.
//

import Foundation

public struct SignInResult {
    let id: String
    let name: String
    let token: String
    
    public init(id: String, name: String, token: String) {
        self.id = id
        self.name = name
        self.token = token
    }
}
