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

        // MARK: Download and Patch
        let versionPackageData = try await versionMetadata.download()
        let _package = try VersionPackage.decode(from: versionPackageData)
        let patchInfo = try await VersionPatch.download(for: _package.id)
        
        var package = try await patchInfo?.patch(package: _package) ?? _package
        
        // MARK: Downloads
//        package.downloads.client = try await MirrorRequest(
//            source: package.downloads.client,
//            targetName: "\(package.id)/downloads/client.jar",
//            fileType: "application/java-archive"
//        ).process(with: authorization, to: bucket, existingFiles: existingFiles)
//
//        package.downloads.clientMappings = try await MirrorRequest(
//            source: package.downloads.clientMappings,
//            targetName: "\(package.id)/downloads/client.txt",
//            fileType: "text/plain"
//        ).process(with: authorization, to: bucket, existingFiles: existingFiles)
//
//        package.downloads.server = try await MirrorRequest(
//            source: package.downloads.server,
//            targetName: "\(package.id)/downloads/server.jar",
//            fileType: "application/java-archive"
//        ).process(with: authorization, to: bucket, existingFiles: existingFiles)
//
//        package.downloads.serverMappings = try await MirrorRequest(
//            source: package.downloads.serverMappings,
//            targetName: "\(package.id)/downloads/server.txt",
//            fileType: "text/plain"
//        ).process(with: authorization, to: bucket, existingFiles: existingFiles)
        
        // MARK: Libraries and Assets
//        package.libraries = await mirrorLibraries(authorization: authorization,
//                                                  bucket: bucket,
//                                                  existingFiles: existingFiles,
//                                                  package: package,
//                                                  patchInfo: patchInfo)
        
//        package.assetIndex = try await mirrorAssets(authorization: authorization,
//                                                    bucket: bucket,
//                                                    existingFiles: existingFiles,
//                                                    package: package)
        
        package.time = Date()
        
        // MARK: Version JSON
        let packageData = try package.encode()
        
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
            VersionManifest.VersionMetadata(id: package.id,
                                            type: package.type.rawValue,
                                            time: package.time,
                                            releaseTime: package.releaseTime,
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
                     package: VersionPackage,
                     patchInfo: VersionPatch?) async -> [VersionPackage.Library] {
    
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
                       let osxClassifier = library.downloads.classifiers?[osxKey] {
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
