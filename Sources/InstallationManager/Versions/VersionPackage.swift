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
public struct VersionPackage: Decodable {
    public let id: String
    let complianceLevel: Int
    public let mainClass: String
    public let minimumLauncherVersion: UInt
    let releaseTime: Date
    let time: Date
    let type: ReleaseType

    public let arguments: Arguments
    let assetIndex: AssetIndex
    public let assets: String
    let downloads: Downloads
    let libraries: [Library]
    let logging: Logging
    
    static func decode(from data: Data) -> Result<VersionPackage, CError> {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        jsonDecoder.dateDecodingStrategy = .iso8601

        do {
            let versionInfo = try jsonDecoder.decode(VersionPackage.self, from: data)
            return .success(versionInfo)
        } catch let error {
            return .failure(.decodingError(error.localizedDescription))
        }
    }
}

// MARK:- Arguments

extension VersionPackage {
    public struct Arguments: Decodable {
        public let game: [Argument]
        public let jvm: [Argument]

        public struct Argument: Decodable {
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
        }
    }
}

// MARK:- Asset Index

extension VersionPackage {
    struct AssetIndex: Decodable {
        let id: String
        let sha1: String
        let size: UInt
        let totalSize: UInt
        let url: String
    }
}

// MARK:- Downloads

extension VersionPackage {
    struct Downloads: Decodable {
        let client: Download
        let clientMappings: Download
        let server: Download
        let serverMappings: Download
        
        struct Download: Decodable {
            let sha1: String
            let size: UInt
            let url: String
        }
    }
}

// MARK:- Library

extension VersionPackage {
    struct Library: Decodable {
        let name: String
        let downloads: Download
        let natives: Natives?
        let rules: [Rule]?
        
        struct Download: Decodable {
            let artifact: Artifact
            let classifiers: Classifiers?
            
            struct Artifact: Decodable {
                let path: String
                let sha1: String
                let size: UInt
                let url: String
            }
            
            struct Classifiers: Decodable {
                let javadoc: Artifact?
                let nativesLinux: Artifact?
                let nativesMacOS: Artifact?
                let nativesOSX: Artifact?
                let nativesWindows: Artifact?
                let sources: Artifact?

                enum CodingKeys: String, CodingKey {
                    case javadoc
                    case nativesLinux = "natives-linux"
                    case nativesMacOS = "natives-macos"
                    case nativesOSX = "natives-osx"
                    case nativesWindows = "natives-windows"
                    case sources
                }
            }
        }

        struct Natives: Decodable {
            let linux: String?
            let osx: String?
            let windows: String?
        }
    }
}

// MARK:- Logging

extension VersionPackage {
    struct Logging: Decodable {
        let client: Client
        
        struct Client: Decodable {
            let argument: String
            let file: File
            let type: String
            
            struct File: Decodable {
                let id: String
                let sha1: String
                let size: UInt
                let url: String
            }
        }
    }
}

// MARK:- Release Type

extension VersionPackage {
    enum ReleaseType: String, Decodable {
        case release, snapshot
    }
}
