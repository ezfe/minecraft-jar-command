//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/13/20.
//

import Foundation

func applyVariableReplacement(source: String, parameters: [String: String]) -> String {
    var working = source
    for (key, value) in parameters {
        working = working.replacingOccurrences(of: "${\(key)}", with: value)
    }
    return working
}
