//
//  File.swift
//  File
//
//  Created by Ezekiel Elin on 9/3/21.
//

import Foundation

public protocol Downloadable {
    var url: String { get }
    var sha1: String { get }
}

public protocol URLModifiable {
    var url: String { get set }
}

public extension Downloadable {
    func download() async throws -> Data {
        guard let url = URL(string: self.url) else {
            throw CError.unknownError("Failed to create URL from \(self.url)")
        }
        
        let data: Data
        do {
            data = try await URLSession.shared.data(from: url).0
        } catch let err {
            throw CError.networkError(err.localizedDescription)
        }
        let foundSha1 = data.sha1()

        if foundSha1 != sha1 {
            throw CError.sha1Error(sha1, foundSha1)
        }
        
        return data
    }
}
