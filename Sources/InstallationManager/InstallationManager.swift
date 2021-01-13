//
//  InstallationManager.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation
import Common
import MojangRules

public class InstallationManager {
    // MARK: Directories
    public let baseDirectory: URL
    
    public let libraryDirectory: URL
    public let nativesDirectory: URL
    
    public let assetsDirectory: URL
    public let assetsObjectsDirectory: URL
    public let assetsIndexesDirectory: URL
    
    public let gameDirectory: URL
    
    // MARK: Installation State
    public private(set) var versionRequested: VersionManifest.VersionType = .release
    public private(set) var manifest: VersionManifest? = nil
    public private(set) var version: VersionPackage? = nil
    public private(set) var jar: URL? = nil
    public private(set) var libraryMetadata: [LibraryMetadata] = []
    
    public convenience init(requestedDirectory: URL, gameDirectory: URL? = nil) throws {
        try self.init(baseDirectory: requestedDirectory, gameDirectory: gameDirectory)
    }
    
    public convenience init(gameDirectory: URL? = nil) throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let baseDirectory = temporaryDirectory.appendingPathComponent("minecraft-jar-command", isDirectory: true)
        
        try self.init(baseDirectory: baseDirectory, gameDirectory: gameDirectory)
    }
    
    init(baseDirectory: URL, gameDirectory: URL?) throws {
        let absoluteBase = baseDirectory.absoluteURL
        
        self.baseDirectory = absoluteBase
        self.libraryDirectory = URL(fileURLWithPath: "libraries", isDirectory: true, relativeTo: absoluteBase)
        self.nativesDirectory = URL(fileURLWithPath: "natives", isDirectory: true, relativeTo: absoluteBase)
        self.assetsDirectory = URL(fileURLWithPath: "assets", isDirectory: true, relativeTo: absoluteBase)
        self.assetsObjectsDirectory = self.assetsDirectory.appendingPathComponent("objects", isDirectory: true)
        self.assetsIndexesDirectory = self.assetsDirectory.appendingPathComponent("indexes", isDirectory: true)
        self.gameDirectory = gameDirectory ?? absoluteBase
        
        print(self.baseDirectory)
        
        try createDirectories()
    }
    
    func createDirectories() throws {
        try FileManager.default.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.libraryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.nativesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.assetsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.assetsIndexesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.assetsObjectsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: self.gameDirectory, withIntermediateDirectories: true)
    }
}

// MARK:- Version Management
extension InstallationManager {
    func destinationDirectory(for version: String) -> URL {
        return URL(fileURLWithPath: "versions/\(version)", relativeTo: self.baseDirectory)
    }
    
    func getManifest(callback: @escaping (Result<VersionManifest, CError>) -> Void) {
        if let manifest = self.manifest {
            callback(.success(manifest))
        } else {
            VersionManifest.downloadManifest(callback: callback)
        }
    }

    public func use(version versionString: String) {
        self.versionRequested = .custom(versionString)
    }
    
    public func useLatest() {
        self.versionRequested = .release
    }
    
    public func downloadVersionInfo(callback: @escaping (Result<VersionPackage, CError>) -> Void) {
        let fm = FileManager.default

        // Check if the file exists on the local file system, and if it does
        // try to decode it as a version package. Lastly, verify that the
        // version package matches the requested version.
        switch versionRequested {
            case .custom(let versionString):
                let targetFileLocation = self.destinationDirectory(for: versionString).appendingPathComponent("\(versionString).json")
                
                do {
                    try fm.createDirectory(at: targetFileLocation.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                } catch let err {
                    callback(.failure(.filesystemError(err.localizedDescription)))
                    return
                }
                if fm.fileExists(atPath: targetFileLocation.path) {
                    if let versionData = fm.contents(atPath: targetFileLocation.path) {
                        let result = VersionPackage.decode(from: versionData)
                        switch result {
                            case .success(let versionPackage):
                                if versionPackage.id == versionString {
                                    self.version = versionPackage
                                    callback(.success(versionPackage))
                                    return
                                } else {
                                    // else continue on as if the versionData didn't
                                    // decode properly
                                }
                            default:
                                break
                        }
                    }
                }
            default:
                break
        }

        // If we haven't aborted at this point, then no file already exists, or one
        // did and has been removed in the meantime.
        self.getManifest { manifestResult in
            switch manifestResult {
                case .success(let manifest):
                    let entryResult = manifest.get(version: self.versionRequested)
                    
                    switch entryResult {
                        case .success(let entry):
                            retrieveData(url: entry.url) { versionDataResult in
                                switch versionDataResult {
                                    case .success(let versionData):
                                        let packageResult = VersionPackage.decode(from: versionData)
                                        switch packageResult {
                                            case .success(let package):
                                                let targetFileLocation = self.destinationDirectory(for: package.id).appendingPathComponent("\(package.id).json")

                                                do {
                                                    if fm.fileExists(atPath: targetFileLocation.path) {
                                                        try fm.removeItem(at: targetFileLocation)
                                                    }
                                                } catch let err {
                                                    callback(.failure(.filesystemError(err.localizedDescription)))
                                                    return
                                                }

                                                fm.createFile(atPath: targetFileLocation.path,
                                                              contents: versionData)
                                                
                                                self.version = package
                                                callback(VersionPackage.decode(from: versionData))
                                                return
                                            case .failure(let error):
                                                callback(.failure(error))
                                                return
                                        }
                                    case .failure(let error):
                                        callback(.failure(error))
                                        return
                                }
                            }
                        case .failure(let error):
                            callback(.failure(error))
                            return
                    }
                case .failure(let error):
                    callback(.failure(error))
                    return
            }
        }
    }
}

// MARK:- JAR Management

extension InstallationManager {
    public func downloadJar(callback: @escaping (Result<URL, CError>) -> Void) {
        guard let version = self.version else {
            callback(.failure(CError.stateError("\(#function) must not be called before `version` is set")))
            return
        }
        
        let destinationURL = self.destinationDirectory(for: version.id).appendingPathComponent("\(version.id).jar")
        
        guard let remoteURL = URL(string: version.downloads.client.url) else {
            callback(.failure(CError.decodingError("Failed to parse out client JAR download URL")))
            return
        }
        
        let request = DownloadManager.DownloadRequest(taskName: "Client JAR File",
                                                      remoteURL: remoteURL,
                                                      destinationURL: destinationURL,
                                                      size: version.downloads.client.size,
                                                      sha1: version.downloads.client.sha1)
        
        DownloadManager.shared.download(request) { result in
            self.jar = destinationURL
            callback(.success(destinationURL))
        }
    }
}

// MARK:- Library management

extension InstallationManager {
    func processArtifact(libraryInfo: VersionPackage.Library) throws -> LibraryMetadata? {
        let artifact = libraryInfo.downloads.artifact
        
        guard let remoteURL = URL(string: artifact.url) else {
            throw CError.decodingError("Failed to parse out artifact URL")
        }
        
        let destinationURL = self.libraryDirectory.appendingPathComponent(artifact.path)

        let request = DownloadManager.DownloadRequest(taskName: "Library \(libraryInfo.name)",
                                                      remoteURL: remoteURL,
                                                      destinationURL: destinationURL,
                                                      size: artifact.size,
                                                      sha1: artifact.sha1,
                                                      verbose: false)
        return LibraryMetadata(localURL: destinationURL, isNative: false, downloadRequest: request)
    }

    func processClassifier(libraryInfo: VersionPackage.Library) throws -> LibraryMetadata? {

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

        let destinationURL = self.libraryDirectory.appendingPathComponent(macosNativeDict.path)

        let request = DownloadManager.DownloadRequest(taskName: "Library/Native \(libraryInfo.name)",
                                                      remoteURL: remoteURL,
                                                      destinationURL: destinationURL,
                                                      size: macosNativeDict.size,
                                                      sha1: macosNativeDict.sha1,
                                                      verbose: false)

        return LibraryMetadata(localURL: destinationURL, isNative: true, downloadRequest: request)
    }

    func downloadLibrary(libraryInfo: VersionPackage.Library) throws -> [LibraryMetadata] {
        if let rules = libraryInfo.rules {
            if !RuleProcessor.verifyRulesPass(rules, with: .none) {
                return []
            }
        }

        let libmetadata = try processArtifact(libraryInfo: libraryInfo)
        let nativemetadata = try processClassifier(libraryInfo: libraryInfo)

        return [libmetadata, nativemetadata].compactMap { $0 }
    }
    
    func createLibraryMetadata() -> Result<[LibraryMetadata], CError> {
        guard let version = self.version else {
            return .failure(CError.stateError("\(#function) must not be called before `version` is set"))
        }

        do {
            let libraryMetadata = try version.libraries.compactMap {
                try downloadLibrary(libraryInfo: $0)
            }.joined()
            let arr = Array(libraryMetadata)
            self.libraryMetadata = arr
            return .success(arr)
        } catch let error {
            if let error = error as? CError {
                return .failure(error)
            } else {
                return .failure(.unknownError(error.localizedDescription))
            }
        }
    }
    
    public func downloadLibraries(callback: @escaping (Result<[LibraryMetadata], CError>) -> Void) {
        let libraryMetadataResult = createLibraryMetadata()
        switch libraryMetadataResult {
            case .success(let libraryMetadata):
                let requests = libraryMetadata.map { $0.downloadRequest }
                DownloadManager.shared.download(requests, named: "Libraries") { progress in
                    print("Library%: \(progress)")
                } callback: { result in
                    // Map will transform the success case, leave the error case
                    callback(result.map { libraryMetadata })
                }
            case .failure(let error):
                callback(.failure(error))
                
        }
    }
}

// MARK: Native Management

extension InstallationManager {
    public func copyNatives() throws {
        if FileManager.default.fileExists(atPath: self.nativesDirectory.path) {
            try FileManager.default.removeItem(at: self.nativesDirectory)
            try FileManager.default.createDirectory(at: self.nativesDirectory, withIntermediateDirectories: true)
        }
        try self.libraryMetadata.filter { $0.isNative }.forEach { libMetadata in
            let target = self.nativesDirectory.appendingPathComponent(libMetadata.localURL.lastPathComponent)
            try FileManager.default.copyItem(at: libMetadata.localURL, to: target)
        }
    }
}

// MARK:- Asset Management

extension InstallationManager {
    public func downloadAssets(progress: @escaping (Double) -> Void = { _ in },
                               callback: @escaping (Result<Void, CError>) -> Void) {

        guard let version = self.version else {
            callback(.failure(CError.stateError("\(#function) must not be called before `version` is set")))
            return
        }
        
        let assetIndex = version.assetIndex
        guard let assetIndexURL = URL(string: assetIndex.url) else {
            callback(.failure(.decodingError("Failed to retrieve asset index URL")))
            return
        }

        retrieveData(url: assetIndexURL) { indexDataResult in
            switch indexDataResult {
                case .success(let indexData):
                    let indexJSONFileURL = self.assetsIndexesDirectory.appendingPathComponent("\(assetIndex.id).json")
                    do {
                        try indexData.write(to: indexJSONFileURL)
                    } catch let error {
                        callback(.failure(.filesystemError(error.localizedDescription)))
                        return
                    }
                    
                    let index: AssetsIndex
                    do {
                        let decoder = JSONDecoder()
                        index = try decoder.decode(AssetsIndex.self, from: indexData)
                    } catch let error {
                        callback(.failure(.decodingError(error.localizedDescription)))
                        return
                    }
                    
                    let downloadRequests: [DownloadManager.DownloadRequest]
                    do {
                        downloadRequests = try index.objects.map { (name, metadata) -> DownloadManager.DownloadRequest in
                            let res = buildAssetRequest(name: name, hash: metadata.hash, size: metadata.size, installationManager: self)
                            switch res {
                            case .success(let request):
                                return request
                            case .failure(let error):
                                throw error
                            }
                        }
                    } catch let error {
                        if let error = error as? CError {
                            callback(.failure(error))
                        } else {
                            callback(.failure(.unknownError(error.localizedDescription)))
                        }
                        return
                    }
                    
                    DownloadManager.shared.download(downloadRequests,
                                                    named: "Asset Collection",
                                                    progress: progress,
                                                    callback: callback)

                case .failure(let error):
                    callback(.failure(error))
                    return
            }
        }
    }
}
