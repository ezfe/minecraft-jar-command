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
        self.getManifest { manifestResult in
            switch manifestResult {
                case .success(let manifest):
                    let entryResult = manifest.get(version: self.versionRequested)
                    
                    switch entryResult {
                        case .success(let entry):
                            retrieveData(url: entry.url) { versionDataResult in
                                switch versionDataResult {
                                    case .success(let versionData):
                                        let jsonDecoder = JSONDecoder()
                                        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
                                        jsonDecoder.dateDecodingStrategy = .iso8601

                                        do {
                                            let versionInfo = try jsonDecoder.decode(VersionPackage.self, from: versionData)
                                            self.version = versionInfo
                                            callback(.success(versionInfo))
                                        } catch let error {
                                            callback(.failure(.decodingError(error.localizedDescription)))
                                        }
                                    case .failure(let error):
                                        callback(.failure(error))
                                }
                            }
                        case .failure(let error):
                            callback(.failure(error))
                    }
                case .failure(let error):
                    callback(.failure(error))
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
        
        let destinationURL = URL(fileURLWithPath: "versions/\(version.id)/\(version.id).jar", relativeTo: self.baseDirectory)
        
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
    
    public func downloadLibraries(callback: @escaping (Result<[LibraryMetadata], CError>) -> Void) {
        guard let version = self.version else {
            callback(.failure(CError.stateError("\(#function) must not be called before `version` is set")))
            return
        }

        let libraryMetadata: FlattenSequence<[[LibraryMetadata]]>
        do {
            libraryMetadata = try version.libraries.compactMap {
                try downloadLibrary(libraryInfo: $0)
            }.joined()
        } catch let error {
            if let error = error as? CError {
                callback(.failure(error))
            } else {
                callback(.failure(.unknownError(error.localizedDescription)))
            }
            return
        }

        let requests = libraryMetadata.map { $0.downloadRequest }
        DownloadManager.shared.download(requests, named: "Libraries") { progress in
            print("Library%: \(progress)")
        } callback: { result in
            // Map will transform the success case, leave the error case
            callback(result.map { Array(libraryMetadata) })
        }
    }
}
