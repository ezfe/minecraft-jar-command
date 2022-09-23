//
//  File.swift
//  File
//
//  Created by Ezekiel Elin on 10/17/21.
//

import Foundation
import Common

public struct JavaVersionInfo: Codable, DownloadableAllModifiable {
	let version: Int
	public var url: String
	public var size: UInt
	public var sha1: String
}
