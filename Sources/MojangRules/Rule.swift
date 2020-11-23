//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/22/20.
//

import Foundation

public struct Rule: Decodable {
    let action: Action
    
    /// Filter this rule based on the current operating system
    let os: OperatingSystem?
    
    /// Filter this rule based on a feature being enabled or disabled
    let features: Feature?
    
    struct OperatingSystem: Decodable {
        let name: String?
        let version: String?
        let arch: String?
    }
    
    struct Feature: Decodable {
        let isDemoUser: Bool?
        let hasCustomResolution: Bool?
    }
    
    enum Action: String, Decodable {
        case allow, disallow
    }
}
