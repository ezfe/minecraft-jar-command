//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public func retrieveData(url: URL) async throws -> Data {
    do {
        #if canImport(FoundationNetworking)
            return await withCheckedContinuation { continuation in
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    guard let data = data else {
                        fatalError()
                    }
                    continuation.resume(returning: data)
                }.resume()
            }
        #else
            return try await URLSession.shared.data(from: url).0
        #endif
    } catch let err {
        throw CError.networkError(err.localizedDescription)
    }
}
