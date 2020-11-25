//
//  File.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

public func retrieveData(url: URL, callback: @escaping (Result<Data, CError>) -> Void) {
    let task = URLSession.shared.dataTask(with: url) { (data, response, _error) in
        guard let data = data else {
            callback(.failure(.networkError(_error?.localizedDescription ?? "No data found and no error provided")))
            return
        }

        callback(.success(data))
    }
    task.resume()
}

public func retrieveData(url: URL) throws -> Data {
    var result: Result<Data, CError> = .failure(CError.unknownError("Missing Result Object"))

    let group = DispatchGroup()
    group.enter()
    retrieveData(url: url) { (_result) in
        result = _result
        group.leave()
    }
    group.wait()
    
    switch result {
    case .success(let data):
        return data
    case .failure(let error):
        throw error
    }
}
