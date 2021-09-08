//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/11/20.
//

import Foundation
import Crypto
import Common

actor DownloadManager {
    let batch: [DownloadRequest]
    let batchName: String?
    let totalSize: UInt
    var currentTotal: UInt = 0
    
    init(_ batch: [DownloadRequest], named batchName: String) {
        self.batch = batch
        self.batchName = batchName
        self.totalSize = batch.map { $0.size }.reduce(0, +)
    }
    
    init(_ request: DownloadRequest) {
        self.batch = [request]
        self.batchName = nil
        self.totalSize = request.size
    }
    
    func download(progress: ((Double) -> Void)? = nil) async throws {
        if let batchName = batchName {
            print("==== Starting Download Batch : \(batchName) ====")
        }
        
        for request in batch {
            try await self.download(request)
            
            currentTotal += request.size
            if let progress = progress {
                progress(Double(currentTotal) / Double(totalSize))
            }
        }

        if let batchName = batchName {
            print("==== Finished Download Batch : \(batchName) ====")
        }
    }

    func verifySha1(url: URL, sha1: String?, fm: FileManager) -> Bool {
        if fm.fileExists(atPath: url.path) {
            if let fileData = fm.contents(atPath: url.path) {
                let foundSha1 = Insecure.SHA1.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
                if foundSha1.lowercased() == sha1 {
                    return true
                }
            }
        }
        return false
    }
    
    private func download(_ request: DownloadRequest) async throws {
        let fm = FileManager.default

        do {
            if verifySha1(url: request.destinationURL, sha1: request.sha1, fm: fm) {
                return
            } else {
                if fm.fileExists(atPath: request.destinationURL.path) {
                    try fm.removeItem(at: request.destinationURL)
                }
                try fm.createDirectory(at: request.destinationURL.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                // continuing on to download file
            }
        } catch let err {
            throw CError.filesystemError(err.localizedDescription)
        }
        
        let temporaryURL: URL
        do {
            temporaryURL = try await URLSession.shared.download(from: request.remoteURL).0
        } catch let err {
            throw CError.networkError(err.localizedDescription)
        }
        
        do {
            if fm.fileExists(atPath: request.destinationURL.path) {
                try fm.removeItem(at: request.destinationURL)
            }
            try fm.moveItem(at: temporaryURL, to: request.destinationURL)
        } catch let err {
            throw CError.filesystemError(err.localizedDescription)
        }
    }
}

extension DownloadManager {
    struct DownloadRequest {
        let taskName: String
        let remoteURL: URL
        let destinationURL: URL
        let size: UInt
        let sha1: String
        let verbose: Bool

        internal init(taskName: String,
                      remoteURL: URL,
                      destinationURL: URL,
                      size: UInt,
                      sha1: String,
                      verbose: Bool = true) {
            self.taskName = taskName
            self.remoteURL = remoteURL
            self.destinationURL = destinationURL
            self.size = size
            self.sha1 = sha1
            self.verbose = verbose
        }
    }
}
