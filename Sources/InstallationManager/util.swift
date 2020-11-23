//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/22/20.
//

import Foundation
import Common
import Rules

public func downloadClientJAR(versionInfo: VersionPackage, version: String, temporaryDirectoryURL: URL) throws -> URL {
    guard let remoteURL = URL(string: versionInfo.downloads.client.url) else {
        throw CError.decodingError("Failed to parse out client JAR download URL")
    }
    
    let downloadedClientJAR = URL(fileURLWithPath: "versions/\(version)/\(version).jar", relativeTo: temporaryDirectoryURL)

    let request = DownloadManager.DownloadRequest(taskName: "Client JAR File",
                                                  remoteURL: remoteURL,
                                                  destinationURL: downloadedClientJAR,
                                                  size: versionInfo.downloads.client.size,
                                                  sha1: versionInfo.downloads.client.sha1)
    try DownloadManager.shared.download(request)

    return downloadedClientJAR
}

func processArtifact(libraryInfo: VersionPackage.Library, librariesURL: URL) throws -> LibraryMetadata? {
    let artifact = libraryInfo.downloads.artifact
    
    guard let remoteURL = URL(string: artifact.url) else {
        throw CError.decodingError("Failed to parse out artifact URL")
    }
    
    let destinationURL = librariesURL.appendingPathComponent(artifact.path)

    let request = DownloadManager.DownloadRequest(taskName: "Library \(libraryInfo.name)",
                                                  remoteURL: remoteURL,
                                                  destinationURL: destinationURL,
                                                  size: artifact.size,
                                                  sha1: artifact.sha1,
                                                  verbose: false)
    return LibraryMetadata(localURL: destinationURL, isNative: false, downloadRequest: request)
}

func processClassifier(libraryInfo: VersionPackage.Library, librariesURL: URL) throws -> LibraryMetadata? {

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

    let destinationURL = librariesURL.appendingPathComponent(macosNativeDict.path)

    let request = DownloadManager.DownloadRequest(taskName: "Library/Native \(libraryInfo.name)",
                                                  remoteURL: remoteURL,
                                                  destinationURL: destinationURL,
                                                  size: macosNativeDict.size,
                                                  sha1: macosNativeDict.sha1,
                                                  verbose: false)

    return LibraryMetadata(localURL: destinationURL, isNative: true, downloadRequest: request)
}

func downloadLibrary(libraryInfo: VersionPackage.Library, librariesURL: URL) throws -> [LibraryMetadata] {
    

    if let rules = libraryInfo.rules {
        if !RuleProcessor.verifyRulesPass(rules) {
            return []
        }
    }

    let libmetadata = try processArtifact(libraryInfo: libraryInfo, librariesURL: librariesURL)
    let nativemetadata = try processClassifier(libraryInfo: libraryInfo, librariesURL: librariesURL)

    return [libmetadata, nativemetadata].compactMap { $0 }
}

public func downloadLibraries(versionInfo: VersionPackage, temporaryDirectoryURL: URL) throws -> [LibraryMetadata] {

    let libraryURL = URL(fileURLWithPath: "libraries",
                         relativeTo: temporaryDirectoryURL)

    let libraryMetadata = try versionInfo.libraries.compactMap {
        try downloadLibrary(libraryInfo: $0, librariesURL: libraryURL)
    }.joined()

    let requests = libraryMetadata.map { $0.downloadRequest }
    try DownloadManager.shared.download(requests, named: "Libraries")

    return Array(libraryMetadata)
}

func buildAssetRequest(name: String, hash: String, size: UInt, assetsObjsDirectoryURL: URL) -> Result<DownloadManager.DownloadRequest, CError> {
    let prefix = hash.prefix(2)

    guard let downloadURL = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(hash)") else {
        return .failure(CError.encodingError("Failed to build URL for \(name)"))
    }

    let destinationURL = assetsObjsDirectoryURL.appendingPathComponent("\(prefix)/\(hash)")

    let request = DownloadManager.DownloadRequest(taskName: "Asset \(name)",
                                                  remoteURL: downloadURL,
                                                  destinationURL: destinationURL,
                                                  size: size,
                                                  sha1: hash,
                                                  verbose: false)
    return .success(request)
}

public func downloadAssets(versionInfo: VersionPackage, temporaryDirectoryURL: URL) throws -> (assetsDirectory: URL, assetsVersion: String) {
    let assetsDirectoryURL = URL(fileURLWithPath: "assets", isDirectory: true, relativeTo: temporaryDirectoryURL)
    let assetsObjsDirectoryURL = assetsDirectoryURL.appendingPathComponent("objects", isDirectory: true)
    let assetsIndxsDirectoryURL = assetsDirectoryURL.appendingPathComponent("indexes", isDirectory: true)

    let assetIndex = versionInfo.assetIndex
    guard let assetIndexURL = URL(string: assetIndex.url) else {
        throw CError.decodingError("Failed to retrieve asset index URL")
    }

    let decoder = JSONDecoder()
    let indexData = try retrieveData(url: assetIndexURL)

    let indexJSONFileURL = assetsIndxsDirectoryURL.appendingPathComponent("\(assetIndex.id).json")
    try FileManager.default.createDirectory(at: assetsIndxsDirectoryURL, withIntermediateDirectories: true)
    try indexData.write(to: indexJSONFileURL)

    let index = try decoder.decode(AssetsIndex.self, from: indexData)
    let downloadRequests = try index.objects.map { (name, metadata) -> DownloadManager.DownloadRequest in
        let res = buildAssetRequest(name: name, hash: metadata.hash, size: metadata.size, assetsObjsDirectoryURL: assetsObjsDirectoryURL)
        switch res {
        case .success(let request):
            return request
        case .failure(let error):
            throw error
        }
    }

    try DownloadManager.shared.download(downloadRequests, named: "Asset Collection")

    return (assetsObjsDirectoryURL.deletingLastPathComponent(), assetIndex.id)
}
