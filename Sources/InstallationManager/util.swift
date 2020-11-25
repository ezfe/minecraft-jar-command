//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/22/20.
//

import Foundation
import Common
import MojangRules

func buildAssetRequest(name: String, hash: String, size: UInt, installationManager: InstallationManager) -> Result<DownloadManager.DownloadRequest, CError> {
    let prefix = hash.prefix(2)

    guard let downloadURL = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(hash)") else {
        return .failure(CError.encodingError("Failed to build URL for \(name)"))
    }

    let destinationURL = installationManager.assetsObjectsDirectory.appendingPathComponent("\(prefix)/\(hash)")

    let request = DownloadManager.DownloadRequest(taskName: "Asset \(name)",
                                                  remoteURL: downloadURL,
                                                  destinationURL: destinationURL,
                                                  size: size,
                                                  sha1: hash,
                                                  verbose: false)
    return .success(request)
}
