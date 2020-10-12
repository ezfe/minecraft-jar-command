//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/11/20.
//

import Foundation
import Crypto

struct DownloadManager {
    static let shared = DownloadManager()

    fileprivate init() { }

    func download(_ batch: [DownloadRequest], named batchName: String) throws {
        print("==== Starting Download Batch : \(batchName) ====")

        let totalSize = batch.map { $0.size }.reduce(0, +)
        var currentTotal = 0
        var lastPercentPrinted = 0

        for request in batch {
            try self.download(request)

            currentTotal += request.size
            let currentPercent = (100 * currentTotal) / totalSize

            func intervalCheck(target: Int) {
                if currentPercent >= target && lastPercentPrinted < target {
                    // Bring up to target - 1
                    print(String(repeating: "=", count: target - 1 - lastPercentPrinted), terminator: "")
                    print(target, terminator: "")
                    lastPercentPrinted = target + 1
                }
            }

            intervalCheck(target: 10)
            intervalCheck(target: 25)
            intervalCheck(target: 50)
            intervalCheck(target: 75)
            intervalCheck(target: 90)

            if currentPercent > lastPercentPrinted {
                let deficit = currentPercent - lastPercentPrinted
                lastPercentPrinted = currentPercent
                print(String(repeating: "=", count: deficit), terminator: "")
            }
        }

        print("==== Completed Download Batch : \(batchName) ====")
    }

    func download(_ request: DownloadRequest) throws {
        if request.verbose {
            print("==== Starting Download Task : \(request.taskName) ====")
        }

        defer {
            if request.verbose {
                print("==== Completed Download Task : \(request.taskName) ====")
            }
        }

        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: request.destinationURL.path) {
                if request.verbose {
                    print("Local file already exists...")
                    print(request.destinationURL.path)
                }

                if let sha1 = request.sha1 {
                    if request.verbose {
                        print("Verifying against provided hash...")
                    }
                    if let fileData = fm.contents(atPath: request.destinationURL.path) {
                        let foundSha1 = Insecure.SHA1.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()

                        if foundSha1.lowercased() == sha1 {
                            if request.verbose {
                                print("Verified local file hash, task completed...")
                            }
                            return
                        } else if request.verbose {
                            print("Local file hash does not match, ...")
                        }
                    } else if request.verbose {
                        print("Unknown file system state, erasing and downloading...")
                    }

                } else if request.verbose {
                    print("No hash provided, erasing and downloading...")
                }

                try fm.removeItem(at: request.destinationURL)
            } else {
                if request.verbose {
                    print("File doesn't exist, so ensuring target directory exists...")
                }
                try fm.createDirectory(at: request.destinationURL.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
            }
        } catch let err {
            throw CustomError.filesystemError(err.localizedDescription)
        }

        var receivedError: CustomError? = nil
        let group = DispatchGroup()
        group.enter()
        if request.verbose {
            print("Starting download...")
        }
        let task = URLSession.shared.downloadTask(with: request.remoteURL) { (temporaryURL, response, error) in
            defer {
                group.leave()
            }

            if request.verbose {
                print("Download completed...")
            }
            guard let temporaryURL = temporaryURL, error == nil else {
                receivedError = .fileDownloadError(error?.localizedDescription ?? "Unknown error download error")
                return
            }

            do {
                try FileManager.default.moveItem(at: temporaryURL, to: request.destinationURL)
            } catch let err {
                receivedError = .filesystemError(err.localizedDescription)
            }
        }

        task.resume()
        group.wait()

        if let error = receivedError {
            throw error
        }
    }
}

extension DownloadManager {
    struct DownloadRequest {
        let taskName: String
        let remoteURL: URL
        let destinationURL: URL
        let size: Int
        let sha1: String?
        let verbose: Bool

        internal init(taskName: String,
                      remoteURL: URL,
                      destinationURL: URL,
                      size: Int,
                      sha1: String? = nil,
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
