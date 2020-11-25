//
//  InstallationManager.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation
import Common

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
    public private(set) var version: VersionPackage
    public private(set) var jar: URL? = nil
    
    public convenience init(requestedDirectory: URL, gameDirectory: URL? = nil, versionInfo: VersionPackage) throws {
        try self.init(baseDirectory: requestedDirectory, gameDirectory: gameDirectory, versionInfo: versionInfo)
    }
    
    public convenience init(gameDirectory: URL? = nil, versionInfo: VersionPackage) throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let baseDirectory = temporaryDirectory.appendingPathComponent("minecraft-jar-command", isDirectory: true)
        
        try self.init(baseDirectory: baseDirectory, gameDirectory: gameDirectory, versionInfo: versionInfo)
    }
    
    init(baseDirectory: URL, gameDirectory: URL?, versionInfo: VersionPackage) throws {
        let absoluteBase = baseDirectory.absoluteURL
        
        self.baseDirectory = absoluteBase
        self.libraryDirectory = URL(fileURLWithPath: "libraries", isDirectory: true, relativeTo: absoluteBase)
        self.nativesDirectory = URL(fileURLWithPath: "natives", isDirectory: true, relativeTo: absoluteBase)
        self.assetsDirectory = URL(fileURLWithPath: "assets", isDirectory: true, relativeTo: absoluteBase)
        self.assetsObjectsDirectory = self.assetsDirectory.appendingPathComponent("objects", isDirectory: true)
        self.assetsIndexesDirectory = self.assetsDirectory.appendingPathComponent("indexes", isDirectory: true)
        self.gameDirectory = gameDirectory ?? absoluteBase
        
        self.version = versionInfo
        
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

// MARK:- JAR Management

extension InstallationManager {
    public func downloadJar(callback: @escaping (Result<URL, CError>) -> Void) {
        // TODO: This will need to be uncommented
//        guard let version = self.version else {
//            callback(.failure(CError.stateError("\(#function) must not be called before `version` is set")))
//            return
//        }
        let version = self.version
        
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
    public func downloadLibraries(callback: @escaping (Result<[LibraryMetadata], CError>) -> Void) {
        let libraryMetadata: FlattenSequence<[[LibraryMetadata]]>
        do {
            libraryMetadata = try self.version.libraries.compactMap {
                try downloadLibrary(libraryInfo: $0, installationManager: self)
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
