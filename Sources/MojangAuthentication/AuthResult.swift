//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/23/20.
//

import Foundation

public struct AuthResult {
    public let accessToken: String
    public let clientToken: String
    
    public let profile: Profile
    
    public init(accessToken: String, clientToken: String, profile: Profile) {
        self.accessToken = accessToken
        self.clientToken = clientToken
        self.profile = profile
    }
    
    init(_ refreshResponse: RefreshResponse) {
        self.accessToken = refreshResponse.accessToken
        self.clientToken = refreshResponse.clientToken
        self.profile = refreshResponse.selectedProfile
    }
    
    init(_ authenticateResponse: AuthenticateResponse) {
        self.accessToken = authenticateResponse.accessToken
        self.clientToken = authenticateResponse.clientToken
        self.profile = authenticateResponse.selectedProfile
    }
}
