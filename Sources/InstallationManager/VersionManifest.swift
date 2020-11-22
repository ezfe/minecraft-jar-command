//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/9/20.
//

import Foundation

public struct VersionManifest: Decodable {
    let latest: Latest
    let versions: [Version]

    public struct Version: Decodable {
        public let id: String
        let type: String
        public let url: URL
        let time: Date
        let releaseTime: Date
    }

    public struct Latest: Decodable {
        let release: String
        let snapshot: String
    }
}
