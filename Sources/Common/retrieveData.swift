//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

public func retrieveData(url: URL) async throws -> Data {
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    } catch let err {
        throw CError.networkError(err.localizedDescription)
    }
}
