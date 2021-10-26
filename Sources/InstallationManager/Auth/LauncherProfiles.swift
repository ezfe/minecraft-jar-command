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

    public init(authenticationDatabase: [String : LauncherProfiles.AuthenticationDatabaseEntry],
                  clientToken: String,
                  selectedUser: LauncherProfiles.SelectedUser) {
        self.authenticationDatabase = authenticationDatabase
        self.clientToken = clientToken
        self.selectedUser = selectedUser
    }
    
    public struct AuthenticationDatabaseEntry: Decodable {
        let accessToken: String
        let profiles: [String: AuthProfile]
        let username: String
        
        public init(accessToken: String, profiles: [String : String], username: String) {
            self.accessToken = accessToken
            self.profiles = profiles.mapValues { AuthProfile(displayName: $0) }
            self.username = username
        }
        
        struct AuthProfile: Decodable {
            let displayName: String
            
            init(displayName: String) {
                self.displayName = displayName
            }
        }
    }
    
    public struct SelectedUser: Decodable {
        let account: String
        let profile: String
        
        public init(account: String, profile: String) {
            self.account = account
            self.profile = profile
        }
    }
}
