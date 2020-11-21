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
    
    @Argument
    var username: String
    
    @Argument
    var password: String
    
    @Option(name: [.long, .customShort("c")], help: "hi")
    var clientToken: String?

    func run() throws {
        let auth = try AuthenticationManager.authenticate(username: username, password: password, clientToken: clientToken)
        
        print("Authentication Successful")
        print("=========================")
        print("Access Token: \(auth.accessToken)")
        print("Client Token: \(auth.clientToken)")
        print("=========================")
        print("Minecraft Username: \(auth.selectedProfile.name)")
        print("Minecraft User ID:  \(auth.selectedProfile.id)")
    }
}
