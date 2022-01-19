//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/9/20.
//

import Foundation
import Common

public struct VersionManifest: Codable {
    public let latest: Latest
    public var versions: [VersionMetadata]
    
    public struct VersionMetadata: Codable, Downloadable {
        public let id: String
        let type: String
        let time: Date
        let releaseTime: Date
        public let url: String
        public let sha1: String
        
        public init(id: String, type: String, time: Date, releaseTime: Date, url: String, sha1: String) {
            self.id = id
            self.type = type
            self.time = time
            self.releaseTime = releaseTime
            self.url = url
            self.sha1 = sha1
        }

        public func package(patched: Bool) async throws -> VersionPackage {
            let packageData = try await self.download()
            
            let package = try VersionPackage.decode(from: packageData)
            let patchInfo: VersionPatch?
            
            if patched {
                patchInfo = try await VersionPatch.download(for: self.id)
            } else {
                patchInfo = nil
            }

            if let patchInfo = patchInfo {
                return try await patchInfo.patch(package: package)
            } else {
                return package
            }
        }
    }
    
    public struct Latest: Codable {
        let release: String
        let snapshot: String
    }
}

// MARK: Download Manifest

public extension VersionManifest {
    static func download() async throws -> VersionManifest {
        let url = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json")!
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
    enum VersionType: Hashable {
        case release
        case snapshot
        case custom(String)
        
        public func hash(into hasher: inout Hasher) {
            switch self {
                case .release:
                    hasher.combine("release_unspecified")
                case .snapshot:
                    hasher.combine("snapshot_unspecified")
                case .custom(let version):
                    hasher.combine("custom_\(version)")
            }
        }
    }
    
    func metadata(for version: VersionType) throws -> VersionManifest.VersionMetadata {
        let versionString: String
        switch version {
            case .release:
                versionString = self.latest.release
            case .snapshot:
                versionString = self.latest.snapshot
            case .custom(let customString):
                versionString = customString
        }
        
        let metadata = self.versions.first(where: { (versionEntry) in
            return versionEntry.id == versionString
        })
        
        guard let metadata = metadata else {
            throw CError.unknownError("\(version)")
        }

        return metadata
    }
}
