//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/9/20.
//

import Foundation
import Common

public struct VersionManifest: Decodable {
    public let latest: Latest
    public let versions: [VersionMetadata]
    let javaVersions: [JavaVersionInfo]?
    
    public struct VersionMetadata: Decodable {
        public let id: String
        let type: String
        public let url: URL
        let time: Date
        let releaseTime: Date
    }
    
    public struct Latest: Decodable {
        let release: String
        let snapshot: String
    }
    
    public struct JavaVersionInfo: Decodable {
        let version: Int
        let url: String
        let size: UInt
        let sha1: String
    }
}

// MARK: Download Manifest

public extension VersionManifest {
    enum ManifestUrls: String {
        case mojang = "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json"
        case legacyCustom = "https://f001.backblazeb2.com/file/com-ezekielelin-publicFiles/lwjgl-arm/version_manifest_v2.json"
    }
    
    static func downloadManifest(url: ManifestUrls) async throws -> VersionManifest {
        let url = URL(string: url.rawValue)!
        let manifestData = try await retrieveData(url: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let manifest = try decoder.decode(VersionManifest.self, from: manifestData)
            return manifest
            
        } catch let error {
            print(error)
            throw CError.decodingError("Failed to decode Version Manifest")
        }
    }
}

// MARK: Get Version

public extension VersionManifest {
    enum VersionType {
        case release
        case snapshot
        case custom(String)
    }
    
    func get(version: VersionType) -> VersionManifest.VersionMetadata? {
        let versionString: String
        switch version {
            case .release:
                versionString = self.latest.release
            case .snapshot:
                versionString = self.latest.snapshot
            case .custom(let customString):
                versionString = customString
        }
        
        return self.versions.first(where: { (versionEntry) in
            return versionEntry.id == versionString
        })
    }
    
}
