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
        self.totalSize = batch.map { $0.source.size }.reduce(0, +)
    }
    
    init(_ request: DownloadRequest) {
        self.batch = [request]
        self.batchName = nil
        self.totalSize = request.source.size
    }
    
    func download(progress: ((Double) -> Void)? = nil) async throws {
        if let batchName = batchName {
            print("==== Starting Download Batch : \(batchName) ====")
        }
        
        try await withThrowingTaskGroup(of: Result<UInt, CError>.self) { group in
            for request in batch {
                group.addTask {
                    do {
                        try await request.download()
                    } catch let error {
                        return .failure(.networkError(error.localizedDescription))
                    }
                    return .success(request.source.size)
                }
            }
            
            for try await sizeResult in group {
                switch sizeResult {
                    case .success(let sizeDone):
                        currentTotal += sizeDone
                        if let progress = progress {
                            progress(Double(currentTotal) / Double(totalSize))
                        }
                    case .failure(let error):
                        throw error
                }
            }
        }

        if let batchName = batchName {
            print("==== Finished Download Batch : \(batchName) ====")
        }
    }
}

extension DownloadManager {
    struct DownloadRequest {
        let taskName: String
        let source: SizedDownloadable
        let destinationURL: URL
        let verbose: Bool

        internal init(taskName: String,
                      source: SizedDownloadable,
                      destinationURL: URL,
                      verbose: Bool = true) {
            self.taskName = taskName
            self.source = source
            self.destinationURL = destinationURL
            self.verbose = verbose
        }
        
        internal func download() async throws {
            try await source.download(to: destinationURL)
        }
    }
}
