//
//  getManifest.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation
import Common

public func getManifest(version: String?) throws -> VersionManifest.Version {
    let url = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest.json")!

    print("Downloading version manifest...")
    let manifestData = try retrieveData(url: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    guard let manifest = try? decoder.decode(VersionManifest.self, from: manifestData) else {
        throw CError.decodingError("Failed to decode Version Manifest")
    }

    let targetVersion = version ?? manifest.latest.release
    guard let versionManifestEntry = manifest.versions.first(where: {
        $0.id == targetVersion
    }) else {
        throw CError.unknownError("\(targetVersion) is not a valid Minecraft version")
    }

    return versionManifestEntry
}
