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
}

// MARK: Download Manifest

public extension VersionManifest {
//    static let url = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest_v2.json")!
    static let url = URL(string: "https://f001.backblazeb2.com/file/com-ezekielelin-publicFiles/lwjgl-arm/version_manifest_v2.json")!
    
    static func downloadManifest(callback: @escaping (Result<VersionManifest, CError>) -> Void) {
        retrieveData(url: url, callback: { (result) in
            switch result {
            case .success(let manifestData):
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                
                guard let manifest = try? decoder.decode(VersionManifest.self, from: manifestData) else {
                    callback(.failure(CError.decodingError("Failed to decode Version Manifest")))
                    return
                }
            
                callback(.success(manifest))
            case .failure(let error):
                callback(.failure(.unknownError(error.localizedDescription)))
            }
        })
    }
    
    static func downloadManifest() throws -> VersionManifest {
        var result: Result<VersionManifest, CError> = .failure(CError.unknownError("Missing Result Object"))
        
        let group = DispatchGroup()
        group.enter()
        downloadManifest { (_result) in
            result = _result
            group.leave()
        }
        group.wait()
        
        switch result {
        case .success(let manifest):
            return manifest
        case .failure(let error):
            throw error
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
    
    func get(version: VersionType) -> Result<VersionManifest.VersionMetadata, CError> {
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
            return .success(versionManifestEntry)
        } else {
            return .failure(CError.unknownVersion(versionString))
        }
    }

}
