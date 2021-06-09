//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/9/20.
//

import Foundation
import Common

public struct VersionManifest: Decodable {
    let latest: Latest
    let versions: [VersionMetadata]
    let javaVersions: [JavaVersionInfo]

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
    static func downloadManifest(url: URL) async throws -> VersionManifest {
        let manifestData = try await retrieveData(url: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let manifest = try? decoder.decode(VersionManifest.self, from: manifestData) else {
            throw CError.decodingError("Failed to decode Version Manifest")
        }
    
        return manifest
    }
}

// MARK: Get Version

public extension VersionManifest {
    enum VersionType {
        case release
        case snapshot
        case custom(String)
    }
    
    func get(version: VersionType) throws -> VersionManifest.VersionMetadata {
        let versionString: String
        switch version {
            case .release:
                versionString = self.latest.release
            case .snapshot:
                versionString = self.latest.snapshot
            case .custom(let customString):
                versionString = customString
        }
        
        let versionManifestEntry = self.versions.first(where: { (versionEntry) in
            return versionEntry.id == versionString
        })
        
        if let versionManifestEntry = versionManifestEntry {
            return versionManifestEntry
        } else {
            throw CError.unknownVersion(versionString)
        }
    }

}
