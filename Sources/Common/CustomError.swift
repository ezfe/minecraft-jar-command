//
//  CustomError.swift
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
    case stateError(String)
    /// Expected, Found
    case sha1Error(String, String)
    case unknownVersion(String)
    case unknownError(String)
    
    public var errorText: String {
        switch self {
            case .mojangErorr(let e):
                return e.description
            case .decodingError(let s):
                return "Decoding Error: \(s)"
            case .encodingError(let s):
                return "Encoding Error: \(s)"
            case .networkError(let s):
                return "Network Error: \(s)"
            case .filesystemError(let s):
                return "Filesystem Error: \(s)"
            case .stateError(let s):
                return "State Error: \(s)"
            case .sha1Error(let e, let f):
                return "Sha1 Error: Expected \(e) but found \(f)"
            case .unknownVersion(let version):
                return "\(version) is not a valid Minecraft version"
            case .unknownError(let s):
                return "Unknown Error: \(s)"
        }
    }
}

public struct YggdrasilError: Decodable, CustomStringConvertible {
    let error: String
    let errorMessage: String
    
    public var description: String {
        return "\(error): \(errorMessage)"
    }
}
