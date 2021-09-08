//
//  AssetsIndex.swift
//  
//
//  Created by Ezekiel Elin on 10/11/20.
//

import Foundation
import Common

public struct AssetsIndex: Codable {
    public var objects: [String: Metadata]
    
    public struct Metadata: Codable, DownloadableModifiable, SizedDownloadable {
        public private(set) var hash: String
        public var size: UInt
        public var url: String
        
        public var sha1: String {
            get { self.hash }
            set { self.hash = newValue }
        }
        
        enum CodingKeys: CodingKey {
            case hash
            case size
            case url
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            self.hash = try container.decode(String.self, forKey: .hash)
            self.size = try container.decode(UInt.self, forKey: .size)
            
            if let url = try? container.decode(String.self, forKey: .url) {
                self.url = url
            } else {
                let prefix = self.hash.prefix(2)
                self.url = "https://resources.download.minecraft.net/\(prefix)/\(self.hash)"
            }
        }
    }
}
