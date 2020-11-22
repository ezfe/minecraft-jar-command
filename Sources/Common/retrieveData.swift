//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

public func retrieveData(url: URL) throws -> Data {
    var foundData: Data? = nil
    let semaphore = DispatchSemaphore(value: 0)

    var error: Error? = nil
    
    let task = URLSession.shared.dataTask(with: url) { (data, response, _error) in
        guard let data = data else {
            error = _error ?? CError.networkError("No data found and no error provided")
            return
        }

        foundData = data

        semaphore.signal()
    }

    task.resume()
    semaphore.wait()
    
    if let error = error {
        throw error
    }
    
    return foundData!
}
