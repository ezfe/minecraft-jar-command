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
    
    public var versionTypes: [VersionTypeMetadataPair] {
        var types = [VersionTypeMetadataPair]()
        
        if let releaseMetadata = try? self.metadata(for: .release) {
            types.append(VersionTypeMetadataPair(version: .release, metadata: releaseMetadata))
        }
        if let snapshotMetadata = try? self.metadata(for: .snapshot) {
            types.append(VersionTypeMetadataPair(version: .snapshot, metadata: snapshotMetadata))
        }
        
        for metadata in self.versions {
            if metadata.id == self.latest.snapshot || metadata.id == self.latest.release {
                continue
            }
            types.append(VersionTypeMetadataPair(version: .custom(metadata.id), metadata: metadata))
        }
        
        return types
    }
    
    public init(versions: [VersionMetadata], latest: Latest) {
        self.versions = versions
        self.latest = latest
    }
    
    public struct VersionTypeMetadataPair: Identifiable {
        public var id: VersionType { version }
        public let version: VersionType
        public let metadata: VersionMetadata
    }
    
    public struct VersionMetadata: Codable, Downloadable, Identifiable {
        public let id: String
        public let type: String
        public let time: Date
        public let releaseTime: Date
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
        public let release: String
        public let snapshot: String
        
        public init(release: String, snapshot: String) {
            self.release = release
            self.snapshot = snapshot
        }
    }
}

// MARK: Download Manifest

public let MOJANG_MANIFEST_URL = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json")!
public extension VersionManifest {
    static func download(url: URL = MOJANG_MANIFEST_URL) async throws -> VersionManifest {
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
    enum VersionType: Codable, Hashable, Equatable {
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
