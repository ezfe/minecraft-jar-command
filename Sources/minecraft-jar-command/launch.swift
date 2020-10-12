//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 10/10/20.
//

import Foundation

func launch(shell: String) {
    let script = """
        tell application "Terminal"
            do script "\(shell)"
        end tell
        """
    print(script)
    var error: NSDictionary?
    if let scriptObject = NSAppleScript(source: script) {
        if let outputString = scriptObject.executeAndReturnError(&error).stringValue {
            print(outputString)
        } else {
            print("error: \(error?.description ?? "unknown error")")
        }
    }
}
