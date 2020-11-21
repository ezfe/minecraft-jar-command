//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

public struct AuthenticateResponse: Decodable {
    let user: User
    public let accessToken: String
    public let clientToken: String
    
    let availableProfiles: [Profile]
    public let selectedProfile: Profile
    
    struct User: Decodable {
        let username: String
        let id: String
    }
    
    public struct Profile: Decodable {
        public let name: String
        public let id: String
    }
}
