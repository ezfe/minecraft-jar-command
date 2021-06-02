//
//  InstallationManager.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation
import Common
import MojangRules
import MojangAuthentication
import Zip

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
    public private(set) var manifests: [URL: VersionManifest] = [:]
    public private(set) var version: VersionPackage? = nil
    public private(set) var jar: URL? = nil
    public private(set) var javaBundle: URL? = nil
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
        
        let defaultGameDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/minecraft")
            .absoluteURL
        self.gameDirectory = gameDirectory ?? defaultGameDirectory
        
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
    
    func getManifest(url: URL, callback: @escaping (Result<VersionManifest, CError>) -> Void) {
        if let manifest = self.manifests[url] {
            callback(.success(manifest))
        } else {
            VersionManifest.downloadManifest(url: url) { manifestResult in
                switch manifestResult {
                    case .success(let manifest):
                        self.manifests[url] = manifest
                    default:
                        break
                }
                callback(manifestResult)
            }
        }
    }
    
    public func availableVersions(url: URL, callback: @escaping (Result<[VersionManifest.VersionMetadata], CError>) -> Void) {
        self.getManifest(url: url) { manifestResult in
            switch manifestResult {
                case .success(let manifest):
                    callback(.success(manifest.versions))
                case .failure(let error):
                    callback(.failure(error))
            }
        }
    }

    public func use(version: VersionManifest.VersionType) {
        self.versionRequested = version
    }
    
    public func downloadVersionInfo(url: URL, callback: @escaping (Result<VersionPackage, CError>) -> Void) {
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
        self.getManifest(url: url) { manifestResult in
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

        guard let macosNativeDict = libraryInfo.downloads.classifiers?[nativesMappingKey] else {
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
    
    public func downloadLibraries(progress: @escaping (Double) -> Void = { _ in },
                                  callback: @escaping (Result<[LibraryMetadata], CError>) -> Void) {
        let libraryMetadataResult = createLibraryMetadata()
        switch libraryMetadataResult {
            case .success(let libraryMetadata):
                let requests = libraryMetadata.map { $0.downloadRequest }
                DownloadManager.shared.download(requests, named: "Libraries", progress: progress) { result in
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

// MARK:- Java Version Management
extension InstallationManager {
    func javaVersionDirectory() -> URL {
        return URL(fileURLWithPath: "runtimes", relativeTo: self.baseDirectory)
    }
    
    func javaVersionInfo(url: URL, callback: @escaping (Result<VersionManifest.JavaVersionInfo, CError>) -> Void) {
        guard let version = self.version else {
            callback(.failure(CError.stateError("\(#function) must not be called before `version` is set")))
            return
        }
        
        let javaVersion = version.javaVersion?.majorVersion ?? 8
        
        self.getManifest(url: url) { manifestResult in
            switch manifestResult {
                case .success(let manifest):
                    let info = manifest.javaVersions.first { $0.version == javaVersion }
                    if let info = info {
                        callback(.success(info))
                    } else {
                        callback(.failure(
                            .unknownError("Unable to find Java version \(javaVersion)")
                        ))
                    }
                case .failure(let error):
                    callback(.failure(error))
            }
        }
    }

    public func downloadJava(url: URL, callback: @escaping (Result<URL, CError>) -> Void) {
        guard let version = self.version else {
            callback(.failure(.stateError("\(#function) must not be called before `version` is set")))
            return
        }
        
        let javaVersion = version.javaVersion?.majorVersion ?? 8
        
        let temporaryDestinationURL = self.javaVersionDirectory()
            .appendingPathComponent("java-\(javaVersion).zip")

        let bundleDestinationURL = self.javaVersionDirectory()
            .appendingPathComponent("java-\(javaVersion).bundle")
        
        javaVersionInfo(url: url) { infoResult in
            switch infoResult {
                case .success(let javaVersionInfo):
                    guard let remoteURL = URL(string: javaVersionInfo.url) else {
                        callback(.failure(.decodingError("Failed to convert \(javaVersionInfo.url) to URL")))
                        break
                    }
                    let request = DownloadManager.DownloadRequest(taskName: "Java Runtime",
                                                                  remoteURL: remoteURL,
                                                                  destinationURL: temporaryDestinationURL,
                                                                  size: javaVersionInfo.size,
                                                                  sha1: javaVersionInfo.sha1)
                    
                    DownloadManager.shared.download(request) { result in
                        print("Finished downloading the java runtime")
                        do {
                            if FileManager.default.fileExists(atPath: bundleDestinationURL.path) {
                                try FileManager.default.removeItem(atPath: bundleDestinationURL.path)
                            }
                            
                            try Zip.unzipFile(temporaryDestinationURL,
                                              destination: bundleDestinationURL,
                                              overwrite: true,
                                              password: nil)
                            
                            self.javaBundle = bundleDestinationURL
                            callback(.success(bundleDestinationURL))
                        } catch (let error) {
                            callback(.failure(.filesystemError("Failed to unzip Java runtime bundle: \(error.localizedDescription)")))
                        }
                    }
                case .failure(let error):
                    callback(.failure(error))
            }
        }
    }
}

// MARK:- Command Compilation
extension InstallationManager {
    public func launchArguments(with auth: AuthResult) -> Result<[String], CError> {
        guard let clientJAR = self.jar else {
            return .failure(CError.stateError("\(#function) must not be called before `jar` is set"))
        }
        
        guard let version = self.version else {
            return .failure(CError.stateError("\(#function) must not be called before `version` is set"))
        }

        let librariesClassPath = self.libraryMetadata.map { $0.localURL.relativePath }.joined(separator: ":")
        let classPath = "\(librariesClassPath):\(clientJAR.relativePath)"

        let argumentProcessor = ArgumentProcessor(versionInfo: version,
                                                  installationManager: self,
                                                  classPath: classPath,
                                                  authResults: auth)
        
        let jvmArgsStr = argumentProcessor.jvmArguments(versionInfo: version)
        let gameArgsString = argumentProcessor.gameArguments(versionInfo: version)

        let args = ["-Xms1024M", "-Xmx1024M"] + jvmArgsStr + [version.mainClass] + gameArgsString
        return .success(args)
    }
}
