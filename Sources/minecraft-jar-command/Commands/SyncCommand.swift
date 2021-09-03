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
            jarName: "client.jar")

        async let modifiedServer = try await reuploadDownload(
            package.downloads.server,
            to: bucket,
            using: authorization,
            versionId: package.id,
            jarName: "server.jar")
        
        modifiedPackage.downloads.client = try await modifiedClient
        modifiedPackage.downloads.server = try await modifiedServer
        
        // MARK: Libraries
        for lib in package.libraries {
            lib
        }
    }
}

func reuploadDownload(_ download: VersionPackage.Downloads.Download,
                      to bucket: ListBuckets.Response.Bucket,
                      using authorization: AuthorizeAccount.Response,
                      versionId: String,
                      jarName: String) async throws -> VersionPackage.Downloads.Download {
    
    let originalUrl = download.url
    let (data, _) = try await URLSession.shared.data(from: URL(string: originalUrl)!)
    let fileName = "\(versionId)/downloads/\(jarName)"
    let uploadInfo = try await UploadFile.exec(authorization: authorization,
                                               bucket: bucket,
                                               fileName: fileName,
                                               contentType: "application/java-archive",
                                               data: data)
    
    let newUrl = "\(authorization.downloadUrl)/file/\(bucket.bucketName)/\(uploadInfo.fileName)"

    var modifiedDownload = download
    modifiedDownload.url = newUrl
    modifiedDownload.sha1 = uploadInfo.contentSha1
    modifiedDownload.size = uploadInfo.contentLength

    return modifiedDownload
}
