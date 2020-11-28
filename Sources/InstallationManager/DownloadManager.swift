//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/11/20.
//

import Foundation
import Crypto
import Common

struct DownloadManager {
    static let shared = DownloadManager()

    fileprivate init() { }

    func download(_ batch: [DownloadRequest],
                  named batchName: String,
                  progress: @escaping (Double) -> Void,
                  callback: @escaping (Result<Void, CError>) -> Void) {
        
        DispatchQueue.global(qos: .utility).async {
            print("==== Starting Download Batch : \(batchName) ====")
            
            // Remove duplicates by sha1
            let sha1Dictionary = Dictionary(grouping: batch) { $0.sha1 }
            let uniqued = sha1Dictionary.values.compactMap { $0.first }
            
            let reportingQueue = DispatchQueue(label: "reporting-queue")
            let totalSize = batch.map { $0.size }.reduce(0, +)
            var currentTotal: UInt = 0
            
            var foundError: CError? = nil
            
            let group = DispatchGroup()
            for request in uniqued {
                group.enter()
                self.download(request) { result in
                    group.leave()
                    switch result {
                        case .success(_):
                            break
                        case .failure(let error):
                            foundError = error
                            return
                    }

                    reportingQueue.sync {
                        currentTotal += request.size
                        progress(Double(currentTotal) / Double(totalSize))
                    }
                }
            }

            group.wait()
            if let error = foundError {
                callback(.failure(error))
            } else {
                callback(.success(()))
            }
        }
    }

    func verifySha1orDelete(url: URL, sha1: String?, fm: FileManager) throws -> Bool {
        if fm.fileExists(atPath: url.path) {
            if let fileData = fm.contents(atPath: url.path) {
                let foundSha1 = Insecure.SHA1.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
                if foundSha1.lowercased() == sha1 {
                    return true
                }
            }
            try fm.removeItem(at: url)
        }
        return false
    }
    
    func download(_ request: DownloadRequest, callback: @escaping (Result<Void, CError>) -> Void) {
        let fm = FileManager.default

        do {
            if try verifySha1orDelete(url: request.destinationURL, sha1: request.sha1, fm: fm) {
                callback(.success((/* void */)))
            } else {
                try fm.createDirectory(at: request.destinationURL.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
            }
        } catch let err {
            callback(.failure(CError.filesystemError(err.localizedDescription)))
            return
        }

        let task = URLSession.shared.downloadTask(with: request.remoteURL) { (temporaryURL, response, error) in
            guard let temporaryURL = temporaryURL, error == nil else {
                callback(.failure(.networkError(error?.localizedDescription ?? "Unknown error download error")))
                return
            }

            do {
                try fm.moveItem(at: temporaryURL, to: request.destinationURL)
            } catch let err {
                callback(.failure(.filesystemError(err.localizedDescription)))
                return
            }
            
            callback(.success((/* void */)))
        }
        task.resume()
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
