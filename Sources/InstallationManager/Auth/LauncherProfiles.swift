//
//  File.swift
//  File
//
//  Created by Ezekiel Elin on 10/17/21.
//

import Foundation

public struct LauncherProfiles: Decodable {
    let authenticationDatabase: [String: AuthenticationDatabaseEntry]
    let clientToken: String
    let selectedUser: SelectedUser
    
    var selectedAccount: AuthenticationDatabaseEntry? {
        return self.authenticationDatabase[self.selectedUser.account]
    }
    
    var selectedProfile: AuthenticationDatabaseEntry.AuthProfile? {
        return self.selectedAccount?.profiles[self.selectedUser.profile]
    }
    
    struct AuthenticationDatabaseEntry: Decodable {
        let accessToken: String
        let profiles: [String: AuthProfile]
        let username: String
        
        struct AuthProfile: Decodable {
            let displayName: String
        }
    }
    
    struct SelectedUser: Decodable {
        let account: String
        let profile: String
    }
}
