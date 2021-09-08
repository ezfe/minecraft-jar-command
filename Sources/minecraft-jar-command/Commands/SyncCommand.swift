//
//  RunCommand.swift
//
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation
import ArgumentParser
import Common
import InstallationManager
import Backblaze
import MojangRules

struct SyncCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync Supporting Materials"
    )
    
    @Option(help: "The Minecraft version to download")
    var version: String
    
    @Option(help: "Backblaze Application Key ID")
    var applicationKeyId: String
    
    @Option(help: "Backblaze Application Key")
    var applicationKey: String
    
    @Option(help: "Backblaze Bucket Name")
    var bucketName: String = "minecraft-jar-command"

    mutating func run() async throws {
        let mojangManifest = try await VersionManifest.downloadManifest(.mojang)
        guard let versionMetadata = mojangManifest.get(version: .custom(version)) else {
            throw CError.unknownVersion(version)
        }
        
        var backblazeManifest = try await VersionManifest.downloadManifest(.backblaze)
        let alreadyExists = backblazeManifest.get(version: .custom(version)) != nil
        if alreadyExists {
            print("\(version) already exists, please delete first.")
            return
        }

        let versionPackageData = try await versionMetadata.download()
        let package = try VersionPackage.decode(from: versionPackageData)
        var modifiedPackage = package
        
        let authorization = try await AuthorizeAccount.exec(
            applicationKeyId: applicationKeyId,
            applicationKey: applicationKey
        )
        let bucket = try await ListBuckets
            .exec(authorization: authorization)
            .first(where: { $0.bucketName == bucketName })!

        let existingFiles = try await ListFileNames
            .exec(authorization: authorization,
                  bucket: bucket,
                  maxFileCount: 10_000)
            .files

        // MARK: Downloads

        let newClientURL = "https://f001.backblazeb2.com/file/com-ezekielelin-publicFiles/lwjgl-arm/1.17.1-arm64.jar"
        modifiedPackage.downloads.client.url = newClientURL
        let newClientData = try! await modifiedPackage.downloads.client.download(checkSha1: false)
        modifiedPackage.downloads.client.sha1 = newClientData.sha1()
        modifiedPackage.downloads.client.size = UInt(newClientData.count)
        
        modifiedPackage.downloads.client = try await MirrorRequest(
            source: modifiedPackage.downloads.client,
            targetName: "\(modifiedPackage.id)/downloads/client.jar",
            fileType: "application/java-archive"
        ).process(with: authorization, to: bucket, existingFiles: existingFiles)
        
        modifiedPackage.downloads.clientMappings = try await MirrorRequest(
            source: modifiedPackage.downloads.clientMappings,
            targetName: "\(modifiedPackage.id)/downloads/client.txt",
            fileType: "text/plain"
        ).process(with: authorization, to: bucket, existingFiles: existingFiles)
        
        modifiedPackage.downloads.server = try await MirrorRequest(
            source: modifiedPackage.downloads.server,
            targetName: "\(modifiedPackage.id)/downloads/server.jar",
            fileType: "application/java-archive"
        ).process(with: authorization, to: bucket, existingFiles: existingFiles)
        
        modifiedPackage.downloads.serverMappings = try await MirrorRequest(
            source: modifiedPackage.downloads.serverMappings,
            targetName: "\(modifiedPackage.id)/downloads/server.txt",
            fileType: "text/plain"
        ).process(with: authorization, to: bucket, existingFiles: existingFiles)
        
        // MARK: Libraries and Assets
        modifiedPackage.libraries = await mirrorLibraries(authorization: authorization,
                                                          bucket: bucket,
                                                          existingFiles: existingFiles,
                                                          package: package)
        
        modifiedPackage.assetIndex = try await mirrorAssets(authorization: authorization,
                                                            bucket: bucket,
                                                            existingFiles: existingFiles,
                                                            package: package)
        
        modifiedPackage.time = Date()
        
        // MARK: Version JSON
        let packageData = try modifiedPackage.encode()
        
        let packageFileName = "\(package.id)/\(package.id).json"
        let uploadResult = try await UploadFile.exec(authorization: authorization,
                                                     bucket: bucket,
                                                     fileName: packageFileName,
                                                     contentType: "application/json",
                                                     data: packageData)
        
        print("Finished uploading version data")
        print("Filename: \(uploadResult.fileName)")
        print("SHA1: \(uploadResult.contentSha1)")
        print("Size: \(uploadResult.contentLength)")
        
        let versionPackageUrl = "\(authorization.downloadUrl)/file/\(bucket.bucketName)/\(uploadResult.fileName)"
        
        // MARK: Manifest
        
        backblazeManifest.versions.append(
            VersionManifest.VersionMetadata(id: modifiedPackage.id,
                                            type: modifiedPackage.type.rawValue,
                                            time: modifiedPackage.time,
                                            releaseTime: modifiedPackage.releaseTime,
                                            url: versionPackageUrl,
                                            sha1: uploadResult.contentSha1)
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let backblazeManifestData = try encoder.encode(backblazeManifest)
        
        let _ = try await UploadFile.exec(authorization: authorization,
                                                     bucket: bucket,
                                                     fileName: "version_manifest.json",
                                                     contentType: "application/json",
                                                     data: backblazeManifestData)
        print("Uploaded new manifest")
    }
}

func mirrorLibraries(authorization: AuthorizeAccount.Response,
                     bucket: ListBuckets.Response.Bucket,
                     existingFiles: [UploadFile.Response],
                     package: VersionPackage) async -> [VersionPackage.Library] {
    
    let applicableLibraries = package.libraries
        .filter { RuleProcessor.verifyRulesPass($0.rules, with: .none) }
    
    return await withTaskGroup(
        of: VersionPackage.Library.self,
        returning: [VersionPackage.Library].self,
        body: { group in
            print("Uploading \(package.libraries.count) libraries to Backblaze")
            for library in applicableLibraries {
                print("Uploading library \(library.name) to Backblaze")
                group.addTask {
                    var modifiedLibrary = library
                    
                    // MARK: Patch LWJGL
                    let lwjglVersion = "nightly-2021-06-02"
                    let lwjglUrlPrefix = "https://f001.backblazeb2.com/file/com-ezekielelin-publicFiles/lwjgl-arm/lwjgl-nightly-2021-06-02-custom/"
                    let lwjglUrls = [
                        "lwjgl": "lwjgl.jar",
                        "lwjgl-opengl": "lwjgl-opengl.jar",
                        "lwjgl-openal": "lwjgl-openal.jar",
                        "lwjgl-jemalloc": "lwjgl-jemalloc.jar",
                        "lwjgl-stb": "lwjgl-stb.jar",
                        "lwjgl-tinyfd": "lwjgl-tinyfd.jar",
                        "lwjgl-glfw": "lwjgl-glfw.jar"
                    ]
                    let lwjglNativeurls = [
                        "lwjgl": "lwjgl-natives-macos-arm64.jar",
                        "lwjgl-opengl": "lwjgl-opengl-natives-macos-arm64.jar",
                        "lwjgl-openal": "lwjgl-openal-natives-macos-arm64.jar",
                        "lwjgl-jemalloc": "lwjgl-jemalloc-natives-macos-arm64.jar",
                        "lwjgl-stb": "lwjgl-stb-natives-macos-arm64.jar",
                        "lwjgl-tinyfd": "lwjgl-tinyfd-natives-macos-arm64.jar",
                        "lwjgl-glfw": "lwjgl-glfw-natives-macos-arm64.jar"
                    ]
                    let libNameComponents = library.name.split(separator: ":")
                    let libOrg = libNameComponents[0]
                    let libName = libNameComponents[1]
                    let libVersion = libNameComponents[2]
                    
                    let isPatching = libName.contains("lwjgl")
                    
                    if isPatching {
                        if let urlSuffix = lwjglUrls[String(libName)] {
                            let url = "\(lwjglUrlPrefix)\(urlSuffix)"
                            modifiedLibrary.name = "\(libOrg):\(libName):\(lwjglVersion)"
                            modifiedLibrary.downloads.artifact.url = url
                            modifiedLibrary.downloads.artifact.path = library.downloads.artifact.path
                                .replacingOccurrences(of: libVersion, with: lwjglVersion)
                            
                            let newData = try! await modifiedLibrary.downloads.artifact.download(checkSha1: false)
                            modifiedLibrary.downloads.artifact.sha1 = newData.sha1()
                            modifiedLibrary.downloads.artifact.size = UInt(newData.count)
                        } else {
                            print("Cannot find mapping for \(libOrg):\(libName):\(libVersion)")
                            exit(2)
                        }
                    }
                    
                    // MARK: Mirror primary artifact
                    let artifactPath = "common/libraries/\(modifiedLibrary.downloads.artifact.path)"
                    let artifactRequest = MirrorRequest(source: modifiedLibrary.downloads.artifact,
                                                        targetName: artifactPath,
                                                        fileType: "application/java-archive")
                    let modifiedArtifact = try! await artifactRequest.process(with: authorization,
                                                                              to: bucket,
                                                                              existingFiles: existingFiles)
                    modifiedLibrary.downloads.artifact = modifiedArtifact

                    
                    //MARK: - Mirror classifiers
                    if let osxKey = library.natives?.osx,
                       var osxClassifier = library.downloads.classifiers?[osxKey] {
                                                
                        // Patch LWJGL Natives
                        if isPatching {
                            if let urlSuffix = lwjglNativeurls[String(libName)] {
                                let url = "\(lwjglUrlPrefix)\(urlSuffix)"
                                osxClassifier.url = url
                                osxClassifier.path = osxClassifier.path
                                    .replacingOccurrences(of: libVersion, with: lwjglVersion)
                                
                                let newData = try! await osxClassifier.download(checkSha1: false)
                                osxClassifier.sha1 = newData.sha1()
                                osxClassifier.size = UInt(newData.count)
                            } else {
                                print("Cannot find NATIVE mapping for \(libOrg):\(libName):\(libVersion) -- \(osxKey) classifier")
                                exit(2)
                            }
                        }
                        
                        // Upload to Backblaze
                        let classifierArtifactPath = "common/libraries/\(osxClassifier.path)"
                        let classifierArtifactRequest = MirrorRequest(
                            source: osxClassifier,
                            targetName: classifierArtifactPath,
                            fileType: "application/java-archive"
                        )
                        let modifiedClassifierArtifact = try! await classifierArtifactRequest.process(
                            with: authorization,
                            to: bucket,
                            existingFiles: existingFiles
                        )
                        
                        modifiedLibrary.downloads.classifiers = [
                            osxKey: modifiedClassifierArtifact
                        ]
                    }

                    return modifiedLibrary
                }
            }
            
            print("Waiting for uploads to finish")
            
            // Re-save libraries back to modified package
            var collected = [VersionPackage.Library]()
            for await modifiedLibrary in group {
                collected.append(modifiedLibrary)
            }

            return collected
        }
    )
}

func mirrorAssets(authorization: AuthorizeAccount.Response,
                  bucket: ListBuckets.Response.Bucket,
                  existingFiles: [UploadFile.Response],
                  package: VersionPackage) async throws -> VersionPackage.AssetIndex {

    let indexData = try await package.assetIndex.download()

    let jsonDecoder = JSONDecoder()
    jsonDecoder.dateDecodingStrategy = .iso8601
    let jsonEncoder = JSONEncoder()
    jsonEncoder.dateEncodingStrategy = .iso8601

    let index = try jsonDecoder.decode(AssetsIndex.self, from: indexData)
    var modifiedIndex = index

    print("Uploading assets to Backblaze")
    modifiedIndex.objects = await withTaskGroup(
        of: (String, AssetsIndex.Metadata).self,
        returning: [String: AssetsIndex.Metadata].self
    ) { group in
        for (key, record) in index.objects {
            group.addTask {
                let hashPrefix = record.hash.prefix(2)
                let fileName = "common/assets/\(hashPrefix)/\(record.hash)"
                let request = MirrorRequest(
                    source: record,
                    targetName: fileName,
                    fileType: "application/octet-stream"
                )
                return try! (
                    key,
                    await request.process(with: authorization, to: bucket, existingFiles: existingFiles)
                )
            }
        }
        
        var collected = [String: AssetsIndex.Metadata]()
        for await result in group {
            collected[result.0] = result.1
        }
        return collected
    }
    print("Finished uploading assets to Backblaze")
    
    print("Uploading asset manifest to Backblaze")
    let modifiedIndexData = try jsonEncoder.encode(modifiedIndex)
    let uploadedIndexInfo = try await UploadFile.exec(authorization: authorization,
                                                      bucket: bucket,
                                                      fileName: "\(package.id)/assets.json",
                                                      contentType: "application/json",
                                                      data: modifiedIndexData)
    
    print("Saving URL of new manifest")
    
    var modifiedIndexInfo = package.assetIndex
    modifiedIndexInfo.sha1 = uploadedIndexInfo.contentSha1
    modifiedIndexInfo.size = uploadedIndexInfo.contentLength
    modifiedIndexInfo.url = "\(authorization.downloadUrl)/file/\(bucket.bucketName)/\(uploadedIndexInfo.fileName)"
    
    return modifiedIndexInfo
}
