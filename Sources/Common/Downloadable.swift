//
//  File.swift
//  File
//
//  Created by Ezekiel Elin on 9/3/21.
//

import Foundation
import Crypto

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol Downloadable {
    var url: String { get }
    var sha1: String { get }
}

public protocol SizedDownloadable: Downloadable {
    var size: UInt { get }
}

public protocol DownloadableAllModifiable: SizedDownloadable {
    var url: String { get set }
    var size: UInt { get set }
    var sha1: String { get set }
}

public extension Downloadable {
    func download(checkSha1: Bool = true) async throws -> Data {
        guard let url = URL(string: self.url) else {
            throw CError.unknownError("Failed to create URL from \(self.url)")
        }
        
        let data = try await retrieveData(from: url).0
        
        if checkSha1 {
            let foundSha1 = data.sha1()
            
            if foundSha1 != sha1 {
                throw CError.sha1Error(sha1, foundSha1)
            }
        }
        
        return data
    }
    
    func download(to destinationUrl: URL) async throws {
        let fm = FileManager.default
        
        do {
            if let existingFileData = try? Data(contentsOf: destinationUrl) {
                let existingSha1 = Insecure.SHA1.hash(data: existingFileData)
                    .compactMap { String(format: "%02x", $0) }
                    .joined()
                
                if existingSha1.lowercased() == sha1 {
                    // File exists and SHA1 matches. Abort.
                    return
                }
            }
            
            // If the file exists, the SHA1 doesn't match
            // Try to delete the file
            if fm.fileExists(atPath: destinationUrl.path) {
                try fm.removeItem(at: destinationUrl)
            }
            
            // Ensure the directory exists to save the real file in
            try fm.createDirectory(at: destinationUrl.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
        } catch let err {
            throw CError.filesystemError(err.localizedDescription)
        }
        
        let data = try await self.download(checkSha1: true)
        
        do {
            try data.write(to: destinationUrl)
        } catch let err {
            throw CError.filesystemError(err.localizedDescription)
        }
        
    }
}
