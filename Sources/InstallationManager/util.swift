//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/22/20.
//

import Foundation
import Common
import MojangRules

func processArtifact(libraryInfo: VersionPackage.Library, installationManager: InstallationManager) throws -> LibraryMetadata? {
    let artifact = libraryInfo.downloads.artifact
    
    guard let remoteURL = URL(string: artifact.url) else {
        throw CError.decodingError("Failed to parse out artifact URL")
    }
    
    let destinationURL = installationManager.libraryDirectory.appendingPathComponent(artifact.path)

    let request = DownloadManager.DownloadRequest(taskName: "Library \(libraryInfo.name)",
                                                  remoteURL: remoteURL,
                                                  destinationURL: destinationURL,
                                                  size: artifact.size,
                                                  sha1: artifact.sha1,
                                                  verbose: false)
    return LibraryMetadata(localURL: destinationURL, isNative: false, downloadRequest: request)
}

func processClassifier(libraryInfo: VersionPackage.Library, installationManager: InstallationManager) throws -> LibraryMetadata? {

    guard let nativesMappingDictionary = libraryInfo.natives,
          let nativesMappingKey = nativesMappingDictionary.osx else {
        // Failures here are acceptable and need not be logged
        return nil
    }

    guard let macosNativeDict = libraryInfo.downloads.classifiers?.nativesMacOS ?? libraryInfo.downloads.classifiers?.nativesOSX else {
        // This is a failure point, however
        throw CError.decodingError("There's a natives entry for macOS = \(nativesMappingKey), but there's no corresponding download")
    }

    guard let remoteURL = URL(string: macosNativeDict.url) else {
        throw CError.decodingError("Failed to parse out native URL")
    }

    let destinationURL = installationManager.libraryDirectory.appendingPathComponent(macosNativeDict.path)

    let request = DownloadManager.DownloadRequest(taskName: "Library/Native \(libraryInfo.name)",
                                                  remoteURL: remoteURL,
                                                  destinationURL: destinationURL,
                                                  size: macosNativeDict.size,
                                                  sha1: macosNativeDict.sha1,
                                                  verbose: false)

    return LibraryMetadata(localURL: destinationURL, isNative: true, downloadRequest: request)
}

func downloadLibrary(libraryInfo: VersionPackage.Library, installationManager: InstallationManager) throws -> [LibraryMetadata] {
    if let rules = libraryInfo.rules {
        if !RuleProcessor.verifyRulesPass(rules, with: .none) {
            return []
        }
    }

    let libmetadata = try processArtifact(libraryInfo: libraryInfo, installationManager: installationManager)
    let nativemetadata = try processClassifier(libraryInfo: libraryInfo, installationManager: installationManager)

    return [libmetadata, nativemetadata].compactMap { $0 }
}

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
