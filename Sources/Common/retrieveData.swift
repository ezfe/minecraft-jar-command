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

public func retrieveData(from url: URL) async throws -> (Data, URLResponse) {
    let request = URLRequest(url: url)
    return try await retrieveData(for: request)
}

public func retrieveData(for request: URLRequest) async throws -> (Data, URLResponse) {
    do {
        #if canImport(FoundationNetworking)
            return try await withCheckedThrowingContinuation { continuation in
                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let data = data,
                          let response = response else {
                        fatalError("Expected data/response when error is nil")
                    }
                    continuation.resume(returning: (data, response))
                }.resume()
            }
        #else
            return try await URLSession.shared.data(for: request)
        #endif
    } catch let err {
        throw CError.networkError(err.localizedDescription)
    }
}
