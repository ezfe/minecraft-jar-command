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

struct SyncCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Sync Supporting Materials"
    )
    
    @Option(help: "The Minecraft version to download")
    var version: String

    mutating func run() async throws {
        let mojangManifest = try await VersionManifest.downloadManifest(url: .mojang)
        guard let versionMetadata = mojangManifest.get(version: .custom(version)) else {
            throw CError.unknownVersion(version)
        }

        let versionPackageData = try await retrieveData(url: versionMetadata.url)
        let package = try VersionPackage.decode(from: versionPackageData)
        var modifiedPackage = package
        
        let bucketName = "minecraft-jar-command"
        let authorization = try await AuthorizeAccount.exec(
            applicationKeyId: "0011acffbd43dbe0000000004",
            applicationKey: "K0019Dwi4j/N57+rNLm5QVm7UUQsqtA"
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

        let downloadRequests = [
            MirrorRequest(
                source: package.downloads.client,
                targetName: "\(package.id)/downloads/client.jar",
                fileType: "application/java-archive"
            ),
            MirrorRequest(
                source: package.downloads.clientMappings,
                targetName: "\(package.id)/downloads/client.txt",
                fileType: "text/plain"
            ),
            MirrorRequest(
                source: package.downloads.server,
                targetName: "\(package.id)/downloads/server.jar",
                fileType: "application/java-archive"
            ),
            MirrorRequest(
                source: package.downloads.serverMappings,
                targetName: "\(package.id)/downloads/server.txt",
                fileType: "text/plain"
            )
        ];
        let processedDownloads = await withTaskGroup(of: VersionPackage.Downloads.Download.self,
                                                     returning: [VersionPackage.Downloads.Download].self,
                                                     body: { group in
            for req in downloadRequests {
                group.addTask {
                    return try! await req.process(with: authorization,
                                       to: bucket,
                                       existingFiles: existingFiles)
                }
            }
            
            var collected = [VersionPackage.Downloads.Download]()
            for await v in group {
                collected.append(v)
            }
            return collected
        })
        
        modifiedPackage.downloads.client = processedDownloads[0]
        modifiedPackage.downloads.clientMappings = processedDownloads[1]
        modifiedPackage.downloads.server = processedDownloads[2]
        modifiedPackage.downloads.serverMappings = processedDownloads[3]
        
        // MARK: Libraries
        await withTaskGroup(
            of: VersionPackage.Library.self,
            body: { group in
                print("Uploading \(package.libraries.count) libraries to Backblaze")
                for library in package.libraries {
                    print("Uploading library \(library.name) to Backblaze")
                    group.addTask {
                        var modifiedLibrary = library
                        
                        // Mirror primary artifact
                        let artifactPath = "common/libraries/\(library.downloads.artifact.path)"
                        let artifactRequest = MirrorRequest(source: library.downloads.artifact,
                                                            targetName: artifactPath,
                                                            fileType: "application/java-archive")
                        let modifiedArtifact = try! await artifactRequest.process(with: authorization,
                                                                                  to: bucket,
                                                                                  existingFiles: existingFiles)
                        modifiedLibrary.downloads.artifact = modifiedArtifact

                        // Mirror classifiers
                        if let classifiers = modifiedLibrary.downloads.classifiers {
                            var modifiedClassifiers = classifiers
                            for (classifierKey, classifierArtifact) in classifiers {
                                let classifierArtifactPath = "common/natives/\(classifierArtifact.path)"
                                let classifierArtifactRequest = MirrorRequest(
                                    source: classifierArtifact,
                                    targetName: classifierArtifactPath,
                                    fileType: "application/java-archive"
                                )
                                let modifiedClassifierArtifact = try! await classifierArtifactRequest.process(
                                    with: authorization,
                                    to: bucket,
                                    existingFiles: existingFiles
                                )
                                modifiedClassifiers[classifierKey] = modifiedClassifierArtifact
                            }
                            modifiedLibrary.downloads.classifiers = modifiedClassifiers
                        }

                        return modifiedLibrary
                    }
                }
                
                print("Waiting for uploads to finish")
                
                // Re-save libraries back to modified package
                modifiedPackage.libraries.removeAll()
                for await modifiedLibrary in group {
                    modifiedPackage.libraries.append(modifiedLibrary)
                }

                print("Assigned \(modifiedPackage.libraries.count) libraries to new package")
            }
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let packageData = try encoder.encode(modifiedPackage)
        
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
    }
}
