//
//  File.swift
//  File
//
//  Created by Ezekiel Elin on 9/4/21.
//

import Foundation

public struct VersionPackageSupplemental: Codable {
    public let assetStoreBaseURL: String
    
    public init(assetStoreBaseURL: String) {
        self.assetStoreBaseURL = assetStoreBaseURL
    }
}
