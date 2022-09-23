//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/22/20.
//

import Foundation
import Common
import MojangRules

func applyVariableReplacement(source: String, parameters: [String: String]) -> String {
	var working = source
	for (key, value) in parameters {
		working = working.replacingOccurrences(of: "${\(key)}", with: value)
	}
	return working
}
