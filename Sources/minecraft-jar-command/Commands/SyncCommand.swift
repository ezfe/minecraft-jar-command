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
                
        // MARK: Downloads
        async let modifiedClient = try await reuploadDownload(
            package.downloads.client,
            to: bucket,
            using: authorization,
            versionId: package.id,
            path: "downloads/client.jar")

        async let modifiedServer = try await reuploadDownload(
            package.downloads.server,
            to: bucket,
            using: authorization,
            versionId: package.id,
            path: "downloads/server.jar")
        
        modifiedPackage.downloads.client = try await modifiedClient
        modifiedPackage.downloads.server = try await modifiedServer
        
        // MARK: Libraries
        modifiedPackage.libraries.removeAll()
        for library in package.libraries {
            var modifiedLibrary = library

            let artifactPath = "libraries/\(library.downloads.artifact.path)"
            let modifiedArtifact = try await reuploadDownload(library.downloads.artifact,
                                                              to: bucket,
                                                              using: authorization,
                                                              versionId: "common",
                                                              path: artifactPath)
            modifiedLibrary.downloads.artifact = modifiedArtifact

            if let classifiers = modifiedLibrary.downloads.classifiers {
                var modifiedClassifiers = classifiers
                for (classifierKey, classifierArtifact) in classifiers {
                    let classifierArtifactPath = "natives/\(classifierArtifact.path)"
                    let modifiedArtifact = try await reuploadDownload(classifierArtifact,
                                                                      to: bucket,
                                                                      using: authorization,
                                                                      versionId: "common",
                                                                      path: classifierArtifactPath)

                    modifiedClassifiers[classifierKey] = modifiedArtifact
                }
                modifiedLibrary.downloads.classifiers = modifiedClassifiers
            }

            modifiedPackage.libraries.append(modifiedLibrary)
        }
        
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

func reuploadDownload<Obj: Downloadable>(_ obj: Obj,
                                         to bucket: ListBuckets.Response.Bucket,
                                         using authorization: AuthorizeAccount.Response,
                                         versionId: String,
                                         path: String) async throws -> Obj {
    
    let data = try await obj.download()
    let sha1 = data.sha1()

    let fileName = "\(versionId)/\(path)"
    
    // TODO: Class C TXN
    let searchResult = try await ListFileNames
        .exec(authorization: authorization,
              bucket: bucket,
              prefix: fileName)
        .files
        .filter({ $0.fileName == fileName })
        .filter({ $0.contentSha1 == sha1 })
        .filter({ $0.contentLength == data.count })
        .first
    
    let fileInfo: UploadFile.Response
    if let searchResult = searchResult {
        print("Found existing file with correct name and sha1")
        fileInfo = searchResult
    } else {
        print("Uploading file to Backblaze")
        fileInfo = try await UploadFile.exec(authorization: authorization,
                                                   bucket: bucket,
                                                   fileName: fileName,
                                                   contentType: "application/java-archive",
                                                   data: data)
    }

    let newUrl = "\(authorization.downloadUrl)/file/\(bucket.bucketName)/\(fileInfo.fileName)"

    var modified = obj
    modified.url = newUrl

    return modified
}
