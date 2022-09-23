//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/11/20.
//

import Foundation

enum CustomError: Error, CustomStringConvertible {
	case filesystemError(String)
	case fileDownloadError(String)
	case urlConstructionError
	case authenticationFailed
	
	var description: String {
		switch self {
			case .authenticationFailed:
				return "Authentication failed. Please verify your access token and client token, and try again."
			case .filesystemError(let message):
				return "A filesystem error occurred: \(message)"
			case .fileDownloadError(let message):
				return "A downloading error occurred: \(message)"
			case .urlConstructionError:
				return "An error occurred building the request URL"
		}
	}
}
