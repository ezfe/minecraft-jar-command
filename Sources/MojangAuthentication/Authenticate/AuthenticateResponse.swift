//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

struct AuthenticateResponse: Decodable {
    let user: User

    let accessToken: String
    let clientToken: String
    
    let availableProfiles: [Profile]
    let selectedProfile: Profile
}
