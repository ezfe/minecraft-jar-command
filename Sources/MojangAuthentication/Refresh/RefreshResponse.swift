//
//  RefreshResponse.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

public struct RefreshResponse: Decodable {
    let user: User

    public let accessToken: String
    public let clientToken: String
    
    public let selectedProfile: Profile
}
