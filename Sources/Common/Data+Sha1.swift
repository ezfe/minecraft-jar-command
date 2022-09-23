//
//  File.swift
//  File
//
//  Created by Ezekiel Elin on 9/3/21.
//

import Foundation
import Crypto

public extension Data {
	func sha1() -> String {
		return Insecure.SHA1.hash(data: self).compactMap { String(format: "%02x", $0) }.joined()
	}
}
