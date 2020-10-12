//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/11/20.
//

import Foundation

struct AssetsIndex: Decodable {
    let objects: [String: Metadata]
    
    struct Metadata: Decodable {
        let hash: String
    }
}
