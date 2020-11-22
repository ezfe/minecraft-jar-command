//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/9/20.
//

import Foundation

public struct LibraryMetadata {
    public let localURL: URL
    public let isNative: Bool

    let downloadRequest: DownloadManager.DownloadRequest
}
