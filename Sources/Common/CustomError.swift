//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

public enum CError: Error {
    case mojangErorr(YggdrasilError)
    case networkError(String)
    case encodingError(String)
    case decodingError(String)
    case filesystemError(String)
    case unknownError(String)
}

public struct YggdrasilError: Decodable {
    let error: String
    let errorMessage: String
}
