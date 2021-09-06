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
    public private(set) var manifests: [VersionManifest.ManifestUrls: VersionManifest] = [:]
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
    
    func getManifest(_ type: VersionManifest.ManifestUrls) async throws -> VersionManifest {
        if let manifest = self.manifests[type] {
            return manifest
        } else {
            let manifest = try await VersionManifest.downloadManifest(type)
            self.manifests[type] = manifest
            return manifest
        }
    }
    
    public func availableVersions(_ type: VersionManifest.ManifestUrls) async throws -> [VersionManifest.VersionMetadata] {
        return try await self.getManifest(type).versions
    }

    public func use(version: VersionManifest.VersionType) {
        self.versionRequested = version
    }
    
    public func downloadVersionInfo(_ type: VersionManifest.ManifestUrls) async throws -> VersionPackage {
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
                    throw CError.filesystemError(err.localizedDescription)
                }
                if fm.fileExists(atPath: targetFileLocation.path) {
                    if let versionData = fm.contents(atPath: targetFileLocation.path) {
                        let versionPackage = try? VersionPackage.decode(from: versionData)
                        
                        if let versionPackage = versionPackage {
                            if versionPackage.id == versionString {
                                self.version = versionPackage
                                return versionPackage
                            } else {
                                // else continue on as if the versionData didn't
                                // decode properly
                            }
                        }
                    }
                }
            default:
                break
        }

        // If we haven't aborted at this point, then no file already exists, or one
        // did and has been removed in the meantime.
        let manifest = try await self.getManifest(type)
        guard let entry = manifest.get(version: self.versionRequested) else {
            throw CError.unknownVersion("\(self.versionRequested)")
        }
        
        let versionData = try await entry.download()
        
        let package = try VersionPackage.decode(from: versionData)

        let targetFileLocation = self.destinationDirectory(for: package.id).appendingPathComponent("\(package.id).json")
        
        do {
            if fm.fileExists(atPath: targetFileLocation.path) {
                try fm.removeItem(at: targetFileLocation)
            }
        } catch let err {
            throw CError.filesystemError(err.localizedDescription)
        }
        
        fm.createFile(atPath: targetFileLocation.path,
                      contents: versionData)
        
        self.version = package
        return try VersionPackage.decode(from: versionData)
    }
}

// MARK:- JAR Management

extension InstallationManager {
    public func downloadJar() async throws {
        guard let version = self.version else {
            throw CError.stateError("\(#function) must not be called before `version` is set")
        }
        
        let destinationURL = self.destinationDirectory(for: version.id).appendingPathComponent("\(version.id).jar")
        
        guard let remoteURL = URL(string: version.downloads.client.url) else {
            throw CError.decodingError("Failed to parse out client JAR download URL")
        }
        
        let request = DownloadManager.DownloadRequest(taskName: "Client JAR File",
                                                      remoteURL: remoteURL,
                                                      destinationURL: destinationURL,
                                                      size: version.downloads.client.size,
                                                      sha1: version.downloads.client.sha1)
        
        let downloader = DownloadManager(request)
        try await downloader.download()
        self.jar = destinationURL
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
    
    public func downloadLibraries(progress: @escaping (Double) -> Void = { _ in }) async throws -> [LibraryMetadata] {
        let libraryMetadataResult = createLibraryMetadata()
        switch libraryMetadataResult {
            case .success(let libraryMetadata):
                let requests = libraryMetadata.map { $0.downloadRequest }
                let downloader = DownloadManager(requests, named: "Libraries")
                try await downloader.download(progress: progress)
                return libraryMetadata
            case .failure(let error):
                throw error
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
    public func downloadAssets(progress: @escaping (Double) -> Void = { _ in }) async throws {
        guard let version = self.version else {
            throw CError.stateError("\(#function) must not be called before `version` is set")
        }
        
        let assetIndex = version.assetIndex
        guard let assetIndexURL = URL(string: assetIndex.url) else {
            throw CError.decodingError("Failed to retrieve asset index URL")
        }

        let indexData = try await retrieveData(url: assetIndexURL)
         
        let indexJSONFileURL = self.assetsIndexesDirectory.appendingPathComponent("\(assetIndex.id).json")
        do {
            try indexData.write(to: indexJSONFileURL)
        } catch let error {
            throw CError.filesystemError(error.localizedDescription)
        }
        
        let index: AssetsIndex
        do {
            let decoder = JSONDecoder()
            index = try decoder.decode(AssetsIndex.self, from: indexData)
        } catch let error {
            throw CError.decodingError(error.localizedDescription)
        }
        
        let downloadRequests: [DownloadManager.DownloadRequest]
        downloadRequests = index.objects.map { (name, metadata) in
            let destinationURL = self.assetsObjectsDirectory
                .appendingPathComponent("\(metadata.sha1.prefix(2))/\(metadata.sha1)")

            let request = DownloadManager.DownloadRequest(taskName: "Asset \(name)",
                                                          remoteURL: URL(string: metadata.url)!,
                                                          destinationURL: destinationURL,
                                                          size: metadata.size,
                                                          sha1: metadata.sha1,
                                                          verbose: false)

            return request
        }
        
        let downloader = DownloadManager(downloadRequests, named: "Asset Collection")
        try await downloader.download(progress: progress)
    }
}

// MARK:- Java Version Management
extension InstallationManager {
    func javaVersionDirectory() -> URL {
        return URL(fileURLWithPath: "runtimes", relativeTo: self.baseDirectory)
    }
    
    func javaVersionInfo(_ type: VersionManifest.ManifestUrls) async throws -> VersionManifest.JavaVersionInfo {
        guard let version = self.version else {
            throw CError.stateError("\(#function) must not be called before `version` is set")
        }
        
        let javaVersion = version.javaVersion?.majorVersion ?? 8
        
        let versions = try await self.getManifest(type).javaVersions ?? []
        let info = versions.first { $0.version == javaVersion }
        
        if let info = info {
            return info
        } else {
            throw CError.unknownError("Unable to find Java version \(javaVersion)")
        }
    }

    public func downloadJava(_ type: VersionManifest.ManifestUrls) async throws -> URL {
        guard let version = self.version else {
            throw CError.stateError("\(#function) must not be called before `version` is set")
        }
        
        let javaVersion = version.javaVersion?.majorVersion ?? 8
        
        let temporaryDestinationURL = self.javaVersionDirectory()
            .appendingPathComponent("java-\(javaVersion).zip")

        let bundleDestinationURL = self.javaVersionDirectory()
            .appendingPathComponent("java-\(javaVersion).bundle")
        
        let javaVersionInfo = try await javaVersionInfo(type)

        guard let remoteURL = URL(string: javaVersionInfo.url) else {
            throw CError.decodingError("Failed to convert \(javaVersionInfo.url) to URL")
        }
        let request = DownloadManager.DownloadRequest(taskName: "Java Runtime",
                                                      remoteURL: remoteURL,
                                                      destinationURL: temporaryDestinationURL,
                                                      size: javaVersionInfo.size,
                                                      sha1: javaVersionInfo.sha1)
        
        let downloader = DownloadManager(request)
        try await downloader.download()
        
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
            return bundleDestinationURL
        } catch (let error) {
            throw CError.filesystemError("Failed to unzip Java runtime bundle: \(error.localizedDescription)")
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
