//
//  File.swift
//  File
//
//  Created by Ezekiel Elin on 9/3/21.
//

import Foundation
import Backblaze
import Common

public struct MirrorRequest<Element: Downloadable> {
    public let source: Element
    public let targetName: String
    public let fileType: String
    
    public init(source: Element, targetName: String, fileType: String) {
        self.source = source
        self.targetName = targetName
        self.fileType = fileType
    }
    
    public func process(with authorization: AuthorizeAccount.Response,
                        to bucket: ListBuckets.Response.Bucket,
                        existingFiles: [UploadFile.Response]) async throws -> Element {
        
        let searchResult = existingFiles.first(where: { file in
            return file.fileName == self.targetName && file.contentSha1 == self.source.sha1
        })

        let fileInfo: UploadFile.Response
        if let searchResult = searchResult {
            print("Found existing file with correct name and sha1")
            fileInfo = searchResult
        } else {
            print("Downloading file to reupload to Backblaze")
            let data = try await self.source.download()
            print("Uploading file to Backblaze")
            fileInfo = try await UploadFile.exec(authorization: authorization,
                                                 bucket: bucket,
                                                 fileName: self.targetName,
                                                 contentType: "application/java-archive",
                                                 data: data)
        }

        if var modified = self.source as? URLModifiable {
            print("Record is mutable, assigning new URL")
            modified.url = "\(authorization.downloadUrl)/file/\(bucket.bucketName)/\(fileInfo.fileName)"
            return modified as! Element
        } else {
            print("Record is not mutable, not assigning new URL")
            return self.source
        }
    }
}
