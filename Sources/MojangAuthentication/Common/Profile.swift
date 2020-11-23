//
//  Profile.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

public struct Profile: Decodable {
    public let name: String
    public let id: String
    
    public init(name: String, id: String) {
        self.name = name
        self.id = id
    }
}
