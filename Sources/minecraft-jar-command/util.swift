//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/13/20.
//

import Foundation

func retrieveData(url: URL) -> Data {
    var foundData: Data? = nil
    let semaphore = DispatchSemaphore(value: 0)

    let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
        guard let data = data else {
            print(error?.localizedDescription ?? "Unknown error downloading data")
            Main.exit()
        }

        foundData = data

        semaphore.signal()
    }

    task.resume()
    semaphore.wait()
    return foundData!
}

func getManifest(version: String?) -> VersionManifest.Version {
    let url = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest.json")!

    print("Downloading version manifest...")
    let manifestData = retrieveData(url: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    guard let manifest = try? decoder.decode(VersionManifest.self, from: manifestData) else {
        print("Failed to retrieve manifest")
        Main.exit()
    }

    let targetVersion = version ?? manifest.latest.release
    guard let versionManifestEntry = manifest.versions.first(where: {
        $0.id == targetVersion
    }) else {
        print("\(targetVersion) is not a valid Minecraft version")
        Main.exit()
    }

    return versionManifestEntry
}

func downloadClientJAR(versionDict: NSDictionary, version: String, temporaryDirectoryURL: URL) throws -> URL {
    guard let _remoteURL = versionDict.value(forKeyPath: "downloads.client.url") as? String,
          let remoteURL = URL(string: _remoteURL),
          let sha1 = versionDict.value(forKeyPath: "downloads.client.sha1") as? String,
          let size = versionDict.value(forKeyPath: "downloads.client.size") as? Int else {

        print("Failed to parse out client JAR download URL")
        Main.exit()
    }

    let downloadedClientJAR = URL(fileURLWithPath: "versions/\(version)/\(version).jar", relativeTo: temporaryDirectoryURL)

    let request = DownloadManager.DownloadRequest(taskName: "Client JAR File",
                                                  remoteURL: remoteURL,
                                                  destinationURL: downloadedClientJAR,
                                                  size: size,
                                                  sha1: sha1)
    try DownloadManager.shared.download(request)

    return downloadedClientJAR
}

func processArtifact(name: String, libraryDict: NSDictionary, librariesURL: URL) throws -> LibraryMetadata {
    guard let artifactDict = libraryDict.value(forKeyPath: "downloads.artifact") as? NSDictionary else {
        print("Artifact dictionary missing")
        print(libraryDict)
        Main.exit()
    }

    guard let pathComponent = artifactDict.value(forKey: "path") as? String,
          let _remoteURL = artifactDict.value(forKey: "url") as? String,
          let remoteURL = URL(string: _remoteURL),
          let sha1 = artifactDict.value(forKey: "sha1") as? String,
          let size = artifactDict.value(forKey: "size") as? Int else {

        print("Failed to parse out parameters from artifact dictionary")
        print(artifactDict)
        Main.exit()
    }

    let destinationURL = librariesURL.appendingPathComponent(pathComponent)

    let request = DownloadManager.DownloadRequest(taskName: "Library \(name)",
                                                  remoteURL: remoteURL,
                                                  destinationURL: destinationURL,
                                                  size: size,
                                                  sha1: sha1,
                                                  verbose: false)
    return LibraryMetadata(localURL: destinationURL, isNative: false, downloadRequest: request)
}

func processClassifier(name: String, libraryDict: NSDictionary, librariesURL: URL) throws -> LibraryMetadata? {

    guard let nativesMappingDictionary = libraryDict.value(forKey: "natives") as? NSDictionary,
          let nativesMappingKey = nativesMappingDictionary.value(forKey: "osx") as? String else {
        // Failures here are acceptable and need not be logged
        return nil
    }

    guard let classifiersDict = libraryDict.value(forKeyPath: "downloads.classifiers") as? NSDictionary,
          let macosNativeDict = classifiersDict.value(forKey: nativesMappingKey) as? NSDictionary else {
        // This is a failure point, however
        print("There's a natives entry for macOS = \(nativesMappingKey), but there's no corresponding download")
        print(libraryDict)
        Main.exit()
    }

    guard let pathComponent = macosNativeDict.value(forKey: "path") as? String,
          let _remoteURL = macosNativeDict.value(forKey: "url") as? String,
          let remoteURL = URL(string: _remoteURL),
          let sha1 = macosNativeDict.value(forKey: "sha1") as? String,
          let size = macosNativeDict.value(forKey: "size") as? Int else {

        print("Failed to parse out parameters from native dictionary")
        print(macosNativeDict)
        Main.exit()
    }

    let destinationURL = librariesURL.appendingPathComponent(pathComponent)

    let request = DownloadManager.DownloadRequest(taskName: "Library/Native \(name)",
                                                  remoteURL: remoteURL,
                                                  destinationURL: destinationURL,
                                                  size: size,
                                                  sha1: sha1,
                                                  verbose: false)

    return LibraryMetadata(localURL: destinationURL, isNative: true, downloadRequest: request)
}

func downloadLibrary(libraryDict: NSDictionary, librariesURL: URL) throws -> [LibraryMetadata] {
    guard let name = libraryDict.value(forKey: "name") as? String else {
        print("Library name missing")
        Main.exit()
    }

    if let rules = libraryDict.value(forKey: "rules") as? [NSDictionary] {
        if !RuleProcessor.verifyRulePasses(rules) {
            return []
        }
    }

    let libmetadata = try processArtifact(name: name, libraryDict: libraryDict, librariesURL: librariesURL)
    let nativemetadata = try processClassifier(name: name, libraryDict: libraryDict, librariesURL: librariesURL)

    return [libmetadata, nativemetadata].compactMap { $0 }
}

func downloadLibraries(versionDict: NSDictionary, temporaryDirectoryURL: URL) throws -> [LibraryMetadata] {
    guard let libraryArr = versionDict.value(forKey: "libraries") as? [NSDictionary] else {
        print("Failed to parse out library array")
        Main.exit()
    }

    let libraryURL = URL(fileURLWithPath: "libraries",
                         relativeTo: temporaryDirectoryURL)

    let libraryMetadata = try libraryArr.compactMap { try downloadLibrary(libraryDict: $0, librariesURL: libraryURL) }.joined()

    let requests = libraryMetadata.map { $0.downloadRequest }
    try DownloadManager.shared.download(requests, named: "Libraries")

    return Array(libraryMetadata)
}

func buildAssetRequest(name: String, hash: String, size: Int, assetsObjsDirectoryURL: URL) -> Result<DownloadManager.DownloadRequest, CustomError> {
    let prefix = hash.prefix(2)

    guard let downloadURL = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(hash)") else {
        print("Failed to build URL for \(name)")
        return .failure(CustomError.urlConstructionError)
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

func downloadAssets(versionDict: NSDictionary, temporaryDirectoryURL: URL) throws -> (assetsDirectory: URL, assetsVersion: String) {
    let assetsDirectoryURL = URL(fileURLWithPath: "assets", isDirectory: true, relativeTo: temporaryDirectoryURL)
    let assetsObjsDirectoryURL = assetsDirectoryURL.appendingPathComponent("objects", isDirectory: true)
    let assetsIndxsDirectoryURL = assetsDirectoryURL.appendingPathComponent("indexes", isDirectory: true)

    guard let assetIndexDict = versionDict.value(forKey: "assetIndex") as? NSDictionary else {
        print("Failed to retrieve asset index")
        print(versionDict)
        Main.exit()
    }
    guard let assetIndexId = assetIndexDict.value(forKey: "id") as? String else {
        print("Failed to retrieve asset index ID")
        print(assetIndexDict)
        Main.exit()
    }
    guard let _assetIndexURL = assetIndexDict.value(forKey: "url") as? String,
          let assetIndexURL = URL(string: _assetIndexURL) else {
        print("Failed to retrieve asset index URL")
        print(assetIndexDict)
        Main.exit()
    }

    let decoder = JSONDecoder()
    let indexData = retrieveData(url: assetIndexURL)

    let indexJSONFileURL = assetsIndxsDirectoryURL.appendingPathComponent("\(assetIndexId).json")
    try FileManager.default.createDirectory(at: assetsIndxsDirectoryURL, withIntermediateDirectories: true)
    try indexData.write(to: indexJSONFileURL)

    let index = try decoder.decode(AssetsIndex.self, from: indexData)
    let downloadRequests = index.objects.map { (name, metadata) -> DownloadManager.DownloadRequest in
        let res = buildAssetRequest(name: name, hash: metadata.hash, size: metadata.size, assetsObjsDirectoryURL: assetsObjsDirectoryURL)
        switch res {
        case .success(let request):
            return request
        case .failure(let error):
            print(error)
            Main.exit()
        }
    }

    try DownloadManager.shared.download(downloadRequests, named: "Asset Collection")

    return (assetsObjsDirectoryURL.deletingLastPathComponent(), assetIndexId)
}

func applyVariableReplacement(source: String, parameters: [String: String]) -> String {
    var working = source
    for (key, value) in parameters {
        working = working.replacingOccurrences(of: "${\(key)}", with: value)
    }
    return working
}
