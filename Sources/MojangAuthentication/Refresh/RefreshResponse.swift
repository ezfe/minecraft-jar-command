//
//  RefreshResponse.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

struct RefreshResponse: Decodable {
    let user: User

    let accessToken: String
    let clientToken: String
    
    let selectedProfile: Profile
}
