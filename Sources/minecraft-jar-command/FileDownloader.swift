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

    func download(taskName: String, from remoteURL: URL, to destinationURL: URL, sha1: String? = nil) throws {
        print("==== Starting Download Task : \(taskName) ====")
        defer {
            print("==== Completed Download Task : \(taskName) ====")
        }

        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: destinationURL.path) {
                print("Local file already exists...")
                print(destinationURL.path)

                if let sha1 = sha1 {
                    print("Verifying against provided hash...")
                    if let fileData = fm.contents(atPath: destinationURL.path) {
                        let foundSha1 = Insecure.SHA1.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()

                        if foundSha1.lowercased() == sha1 {
                            print("Verified local file hash, task completed...")
                            return
                        } else {
                            print("Local file hash does not match, ...")
                        }
                    } else {
                        print("Unknown file system state, erasing and downloading...")
                    }

                } else {
                    print("No hash provided, erasing and downloading...")
                }

                try fm.removeItem(at: destinationURL)
            } else {
                print("File doesn't exist, so ensuring target directory exists...")
                try fm.createDirectory(at: destinationURL.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
            }
        } catch let err {
            throw CustomError.filesystemError(err.localizedDescription)
        }

        var receivedError: CustomError? = nil
        let group = DispatchGroup()
        group.enter()
        print("Starting download...")
        let task = URLSession.shared.downloadTask(with: remoteURL) { (temporaryURL, response, error) in
            defer {
                group.leave()
            }

            print("Download completed...")
            guard let temporaryURL = temporaryURL, error != nil else {
                receivedError = .fileDownloadError(error?.localizedDescription ?? "Unknown error download error")
                return
            }

            do {
                try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            } catch let err {
                receivedError = .filesystemError(err.localizedDescription)
            }
        }

        if let error = receivedError {
            throw error
        }

        task.resume()
        group.wait()
    }
}
