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

public func downloadAssets(versionInfo: VersionPackage, installationManager: InstallationManager) throws -> String {
    
    let assetIndex = versionInfo.assetIndex
    guard let assetIndexURL = URL(string: assetIndex.url) else {
        throw CError.decodingError("Failed to retrieve asset index URL")
    }

    let decoder = JSONDecoder()
    let indexData = try retrieveData(url: assetIndexURL)

    let indexJSONFileURL = installationManager.assetsIndexesDirectory.appendingPathComponent("\(assetIndex.id).json")
    try indexData.write(to: indexJSONFileURL)

    let index = try decoder.decode(AssetsIndex.self, from: indexData)
    let downloadRequests = try index.objects.map { (name, metadata) -> DownloadManager.DownloadRequest in
        let res = buildAssetRequest(name: name, hash: metadata.hash, size: metadata.size, installationManager: installationManager)
        switch res {
        case .success(let request):
            return request
        case .failure(let error):
            throw error
        }
    }

//    try DownloadManager.shared.download(downloadRequests, named: "Asset Collection")
    var result: Result<Void, CError>? = nil
    let group = DispatchGroup()
    group.enter()
    DownloadManager.shared.download(downloadRequests, named: "Asset Collection") { progress in
        print("Asset%: \(progress)")
    } callback: { _result in
        result = _result
        group.leave()
    }
    group.wait()

    switch result! {
        case .failure(let error):
            throw error
        case .success(_):
            return assetIndex.id
    }
}
