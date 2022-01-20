//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/22/20.
//

import Foundation
import MojangRules
import Common

/**
 * A file that describes a specific Minecraft version, and includes information
 * like assets, libraries, and how to launch the game.
 */
public struct VersionPackage: Codable {
    public var id: String
    let complianceLevel: Int
    public let mainClass: String
    public let minimumLauncherVersion: UInt
    public var releaseTime: Date
    public var time: Date
    public let type: ReleaseType

    public let arguments: Arguments
    public var assetIndex: AssetIndex
    public let assets: String
    public var downloads: Downloads
    public var libraries: [Library]
    let logging: Logging
    
    public let javaVersion: JavaVersion?
    
    public static func decode(from data: Data) throws -> VersionPackage {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        jsonDecoder.dateDecodingStrategy = .iso8601

        do {
            let versionInfo = try jsonDecoder.decode(VersionPackage.self, from: data)
            return versionInfo
        } catch let error {
            print(error)
            throw CError.decodingError(error.localizedDescription)
        }
    }
    
    public func encode() throws -> Data {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
        jsonEncoder.dateEncodingStrategy = .iso8601
        
        do {
            return try jsonEncoder.encode(self)
        } catch let error {
            print(error)
            throw CError.encodingError(error.localizedDescription)
        }
    }
}

// MARK:- Arguments

extension VersionPackage {
    public struct Arguments: Codable {
        public let game: [Argument]
        public let jvm: [Argument]

        public struct Argument: Codable {
            public let values: [String]
            public let rules: [Rule]
            
            enum CodingKeys: String, CodingKey {
                case value, rules
            }
            
            public init(from decoder: Decoder) throws {
                var errors = [DecodingError]()
                do {
                    let svnt = try decoder.singleValueContainer()
                    let string = try svnt.decode(String.self)
                    self.values = [string]
                    self.rules = []
                    return
                } catch let error {
                    if let decodingError = error as? DecodingError {
                        errors.append(decodingError)
                    } else {
                        throw error
                    }
                }
                
                do {
                    let svc = try decoder.container(keyedBy: CodingKeys.self)
                    let string = try svc.decode(String.self, forKey: .value)
                    let rules = try svc.decode([Rule].self, forKey: .rules)
                    self.values = [string]
                    self.rules = rules
                    return
                } catch let error {
                    if let decodingError = error as? DecodingError {
                        errors.append(decodingError)
                    } else {
                        throw error
                    }
                }

                do {
                    let mvc = try decoder.container(keyedBy: CodingKeys.self)
                    self.values = try mvc.decode([String].self, forKey: .value)
                    self.rules = try mvc.decode([Rule].self, forKey: .rules)
                    return
                } catch let error {
                    if let decodingError = error as? DecodingError {
                        errors.append(decodingError)
                    } else {
                        throw error
                    }
                }
                
                guard errors.isEmpty else {
                    let sorted = errors.sorted { (e1, e2) -> Bool in
                        switch e1 {
                            case .typeMismatch(_, let c1), .keyNotFound(_, let c1):
                                switch e2 {
                                    case .typeMismatch(_, let c2), .keyNotFound(_, let c2):
                                        return c1.codingPath.count > c2.codingPath.count
                                    default:
                                        return true
                                }
                            default:
                                return false
                        }
                    }
                    
                    throw sorted.first!
                }
                
                throw CError.decodingError("An unknown error occurred decoding an argument - program state should never allow this line to run")
            }
            
            public func encode(to encoder: Encoder) throws {
                if rules.isEmpty && values.count == 1 {
                    var svnt = encoder.singleValueContainer()
                    try svnt.encode(values[0])
                } else if values.count == 1 {
                    var svc = encoder.container(keyedBy: CodingKeys.self)
                    try svc.encode(values[0], forKey: .value)
                    try svc.encode(rules, forKey: .rules)
                } else {
                    var mvc = encoder.container(keyedBy: CodingKeys.self)
                    try mvc.encode(values, forKey: .value)
                    try mvc.encode(rules, forKey: .rules)
                }
            }
        }
    }
}

// MARK:- Asset Index

extension VersionPackage {
    public struct AssetIndex: Codable, DownloadableAllModifiable {
        let id: String
        public var sha1: String
        public var size: UInt
        let totalSize: UInt
        public var url: String
    }
}

// MARK:- Downloads

extension VersionPackage {
    public struct Downloads: Codable {
        public var client: Download
        public var clientMappings: Download?
        public var server: Download
        public var serverMappings: Download?
        
        public struct Download: Codable, DownloadableAllModifiable {
            public var sha1: String
            public var size: UInt
            public var url: String
        }
    }
}

// MARK:- Library

extension VersionPackage {
    public struct Library: Codable {
        public var name: String
        public var downloads: Download
        public let natives: Natives?
        public let rules: [Rule]?
        
        public struct Download: Codable {
            public var artifact: Artifact
            public var classifiers: [String: Artifact]?
            
            public struct Artifact: Codable, DownloadableAllModifiable {
                public var path: String
                public var sha1: String
                public var size: UInt
                public var url: String
            }
        }

        public struct Natives: Codable {
            public let linux: String?
            public let osx: String?
            public let windows: String?
        }
    }
}

// MARK:- Logging

extension VersionPackage {
    struct Logging: Codable {
        let client: Client
        
        struct Client: Codable {
            let argument: String
            let file: File
            let type: String
            
            struct File: Codable, DownloadableAllModifiable {
                let id: String
                var sha1: String
                var size: UInt
                var url: String
            }
        }
    }
}

// MARK:- Release Type

extension VersionPackage {
    public enum ReleaseType: String, Codable {
        case release, snapshot
    }
}

// MARK:- Java Version

extension VersionPackage {
    public struct JavaVersion: Codable {
        let component: String
        public let majorVersion: Int
    }
}
