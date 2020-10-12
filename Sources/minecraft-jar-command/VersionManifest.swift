//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/9/20.
//

import Foundation

struct VersionManifest: Decodable {
    let latest: Latest
    let versions: [Version]

    struct Version: Decodable {
        let id: String
        let type: String
        let url: URL
        let time: Date
        let releaseTime: Date
    }

    struct Latest: Decodable {
        let release: String
        let snapshot: String
    }
}
