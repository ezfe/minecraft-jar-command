//
//  InstallationManager.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation
import Common
import MojangRules
import Zip

public class InstallationManager {
	// MARK: Directories
	public let baseDirectory: URL
	public let gameDirectory: URL
	
	// MARK: Installation State
	public private(set) var javaBundle: URL? = nil
	public private(set) var libraryMetadata: [LibraryMetadata] = []
	
	public convenience init(baseDirectory: URL? = nil, gameDirectory: URL? = nil) throws {        
		let applicationSupportDirectory = FileManager
			.default
			.urls(for: .applicationSupportDirectory, in: .userDomainMask)
			.first
		guard let applicationSupportDirectory = applicationSupportDirectory else {
			throw CError.filesystemError("No Application Support directory found for current user")
		}
		
		let defaultGameDirectory = applicationSupportDirectory
			.appendingPathComponent("minecraft")
			.absoluteURL
		let defaultBaseDirectory = applicationSupportDirectory
			.appendingPathComponent("minecraft-jar-command")
			.absoluteURL
		
		try self.init(
			baseDirectory: baseDirectory ?? defaultBaseDirectory,
			gameDirectory: gameDirectory ?? defaultGameDirectory
		)
	}
	
	init(baseDirectory: URL, gameDirectory: URL) throws {
		let absoluteBase = baseDirectory.absoluteURL
		
		self.baseDirectory = absoluteBase
		self.gameDirectory = gameDirectory
		
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

// MARK: - Computed Directories
extension InstallationManager {
	public var libraryDirectory: URL {
		URL(fileURLWithPath: "libraries", isDirectory: true, relativeTo: self.baseDirectory.absoluteURL)
	}
	public var nativesDirectory: URL {
		URL(fileURLWithPath: "natives", isDirectory: true, relativeTo: self.baseDirectory.absoluteURL)
	}
	
	public var assetsDirectory: URL {
		URL(fileURLWithPath: "assets", isDirectory: true, relativeTo: self.baseDirectory.absoluteURL)
	}
	public var assetsObjectsDirectory: URL {
		self.assetsDirectory.appendingPathComponent("objects", isDirectory: true)
	}
	public var assetsIndexesDirectory: URL {
		self.assetsDirectory.appendingPathComponent("indexes", isDirectory: true)
	}
}

// MARK: - Version Management
extension InstallationManager {
	func directory(for version: String) -> URL {
		return URL(fileURLWithPath: "versions/\(version)", relativeTo: self.baseDirectory)
	}
	
	//    public func package(for version: VersionManifest.VersionType) async throws -> VersionPackage {
	//        let manifest = try await VersionManifest.download()
	//        let metadata = try manifest.metadata(for: version)
	//
	//        let package = try await metadata.package(patched: true)
	//
	//        let targetFileLocation = self.directory(for: package.id).appendingPathComponent("\(package.id).json")
	//
	//        let encoder = JSONEncoder()
	//        encoder.dateEncodingStrategy = .iso8601
	//
	//        let data: Data
	//        do {
	//            data = try encoder.encode(package)
	//        } catch let err {
	//            throw CError.encodingError(err.localizedDescription)
	//        }
	//
	//        do {
	//            try data.write(to: targetFileLocation)
	//        } catch let err {
	//            throw CError.filesystemError(err.localizedDescription)
	//        }
	//
	//        return package
	//    }
}

// MARK: - JAR Management

extension InstallationManager {
	public func downloadJar(for version: VersionPackage) async throws -> URL {
		let destinationURL = self.directory(for: version.id).appendingPathComponent("\(version.id).jar")
		try await version.downloads.client.download(to: destinationURL)
		return destinationURL
	}
}

// MARK: - Library management

extension InstallationManager {
	func processArtifact(libraryInfo: VersionPackage.Library) throws -> LibraryMetadata? {
		guard let artifact = libraryInfo.downloads.artifact else {
			return nil
		}
		
		let destinationURL = self.libraryDirectory.appendingPathComponent(artifact.path)
		
		let request = DownloadManager.DownloadRequest(taskName: "Library \(libraryInfo.name)",
																	 source: artifact,
																	 destinationURL: destinationURL,
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
		
		let destinationURL = self.libraryDirectory.appendingPathComponent(macosNativeDict.path)
		
		let request = DownloadManager.DownloadRequest(taskName: "Library/Native \(libraryInfo.name)",
																	 source: macosNativeDict,
																	 destinationURL: destinationURL,
																	 verbose: false)
		
		return LibraryMetadata(localURL: destinationURL, isNative: true, downloadRequest: request)
	}
	
	func createLibraryMetadata(for version: VersionPackage) async throws -> Result<[LibraryMetadata], CError> {
		do {
			let libraryMetadata = try version.libraries.compactMap { libraryInfo -> [LibraryMetadata] in
				if let rules = libraryInfo.rules {
					if !RuleProcessor.verifyRulesPass(rules, with: .none) {
						return []
					}
				}
				
				let libmetadata = try processArtifact(libraryInfo: libraryInfo)
				let nativemetadata = try processClassifier(libraryInfo: libraryInfo)
				
				return [libmetadata, nativemetadata].compactMap { $0 }
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
	
	public func downloadLibraries(for version: VersionPackage,
											progress: @escaping (Double) -> Void = { _ in }) async throws -> [LibraryMetadata] {
		
		let libraryMetadataResult = try await createLibraryMetadata(for: version)
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

// MARK: - Native Management

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

// MARK: - Asset Management

extension InstallationManager {
	public func downloadAssets(for version: VersionPackage,
										with patch: VersionPatch?,
										progress: @escaping (Double) -> Void = { _ in }) async throws {
		
		let assetIndex = version.assetIndex
		let indexData = try await assetIndex.download()
		
		let indexJSONFileURL = self.assetsIndexesDirectory.appendingPathComponent("\(assetIndex.id).json")
		do {
			try indexData.write(to: indexJSONFileURL)
		} catch let error {
			throw CError.filesystemError(error.localizedDescription)
		}
		
		let index: AssetsIndex
		do {
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			index = try decoder.decode(AssetsIndex.self, from: indexData)
		} catch let error {
			throw CError.decodingError(error.localizedDescription)
		}
		
		let downloadRequests: [DownloadManager.DownloadRequest]
		downloadRequests = index.objects.filter { (name, metadata) in
			if let patch, patch.removeIcon {
				return !name.contains("icon")
			} else {
				return true
			}
		}.map { (name, metadata) in
			let destinationURL = self.assetsObjectsDirectory
				.appendingPathComponent("\(metadata.sha1.prefix(2))/\(metadata.sha1)")
			
			let request = DownloadManager.DownloadRequest(taskName: "Asset \(name)",
																		 source: metadata,
																		 destinationURL: destinationURL,
																		 verbose: false)
			
			return request
		}
		
		let downloader = DownloadManager(downloadRequests, named: "Asset Collection")
		try await downloader.download(progress: progress)
	}
}

// MARK: - Java Version Management
extension InstallationManager {
	func javaVersionDirectory() -> URL {
		return URL(fileURLWithPath: "runtimes", relativeTo: self.baseDirectory)
	}
	
	func javaVersionInfo(for version: VersionPackage) async throws -> JavaVersionInfo {
		let javaVersion = version.javaVersion?.majorVersion ?? 8
		
		guard let javaInfoUrl = URL(string: "https://m1craft.ezekiel.dev/api/java/\(javaVersion).json") else {
			throw CError.unknownError("Unable to find build URL for Java version \(javaVersion)")
		}
		let javaInfoData = try await retrieveData(from: javaInfoUrl).0
		
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let info = try? decoder.decode(JavaVersionInfo.self, from: javaInfoData)
		
		if let info = info {
			return info
		} else {
			throw CError.unknownError("Unable to find Java version \(javaVersion)")
		}
	}
	
	public func downloadJava(for version: VersionPackage) async throws -> URL {
		let javaVersionInfo = try await javaVersionInfo(for: version)
		
		let temporaryDestinationURL = self.javaVersionDirectory()
			.appendingPathComponent("java-\(javaVersionInfo.version).zip")
		
		let bundleDestinationURL = self.javaVersionDirectory()
			.appendingPathComponent("java-\(javaVersionInfo.version).bundle")
		
		try await javaVersionInfo.download(to: temporaryDestinationURL)
		
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

// MARK: - Command Compilation
extension InstallationManager {
	public func launchArguments(for version: VersionPackage,
										 with credentials: SignInResult,
										 clientJar: URL,
										 memory: UInt8 = 2) async throws -> Result<[String], CError> {
		
		let librariesClassPath = self.libraryMetadata.map { $0.localURL.relativePath }.joined(separator: ":")
		let classPath = "\(librariesClassPath):\(clientJar.relativePath)"
		
		let argumentProcessor = ArgumentProcessor(versionInfo: version,
																installationManager: self,
																classPath: classPath,
																credentials: credentials)
		
		let jvmArgsStr = argumentProcessor.jvmArguments(versionInfo: version) + ["-Xmx\(memory)G"] // 4 GB max
		let gameArgsString = argumentProcessor.gameArguments(versionInfo: version)
		
		let args = ["-Xms1024M", "-Xmx1024M"] + jvmArgsStr + [version.mainClass] + gameArgsString
		return .success(args)
	}
}
