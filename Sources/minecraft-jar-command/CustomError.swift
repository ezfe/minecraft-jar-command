//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/11/20.
//

import Foundation

enum CustomError: Error {
    case filesystemError(String)
    case fileDownloadError(String)
}
