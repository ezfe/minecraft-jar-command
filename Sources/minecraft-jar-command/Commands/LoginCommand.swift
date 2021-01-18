//
//  LoginCommand.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation
import MojangAuthentication
import ArgumentParser

struct LoginCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "login",
        abstract: "Login and fetch an authentication token"
    )
    
    @Argument(help: "Mojang Email Address")
    var username: String
    
    @Argument(help: "Mojang Password")
    var password: String
    
    @Option(name: [.long, .customShort("c")], help: "Client Token")
    var clientToken: String?

    @Flag(name: [.long, .customShort("s")])
    var saveCredentials: Bool = false
    
    func run() throws {
        let defaults = UserDefaults.standard
        
        let savedClientToken = defaults.string(forKey: "clientToken")
        if savedClientToken != nil && clientToken == nil {
            print("Client Token Loaded...")
        }
        
        let auth = try AuthenticationManager.authenticate(username: username, password: password, clientToken: clientToken ?? savedClientToken)
        
        if saveCredentials {
            defaults.set(auth.clientToken, forKey: "clientToken")
            defaults.set(auth.accessToken, forKey: "accessToken")
            print("Credentials Saved...")
        }
        
        print("Authentication Successful")
        print("=========================")
        print("Access Token: \(auth.accessToken)")
        print("Client Token: \(auth.clientToken)")
        print("=========================")
        print("Minecraft Username: \(auth.profile.name)")
        print("Minecraft User ID:  \(auth.profile.id)")
    }
}
