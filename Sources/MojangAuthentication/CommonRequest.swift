//
//  CommonRequest.swift
//  
//
//  Created by Ezekiel Elin on 11/21/20.
//

import Foundation

enum CError: Error {
    case mojangErorr(YggdrasilError)
    case networkError(String)
    case encodingError(String)
    case decodingError(String)
}

struct YggdrasilError: Decodable {
    let error: String
    let errorMessage: String
}

func yggdrasilPostSync<BodyType: Encodable, ResponseType: Decodable>(url: URL, body: BodyType) -> Result<ResponseType, CError> {
    var result: Result<ResponseType, CError>? = nil
    
    let group = DispatchGroup()
    group.enter()
    yggdrasilPost(url: url, body: body) { (_result: Result<ResponseType, CError>) in
        result = _result
        group.leave()
    }
    group.wait()
    
    return result!
}


func yggdrasilPost<BodyType: Encodable,
                   ResponseType: Decodable>(url: URL,
                                            body: BodyType,
                                            callback: @escaping (Result<ResponseType, CError>) -> Void) {
    
    let encoder = JSONEncoder()
    
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpMethod = "POST"
    
    do {
        request.httpBody = try encoder.encode(body)
    } catch let error {
        callback(.failure(CError.encodingError(error.localizedDescription)))
    }
    
    let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
        let decoder = JSONDecoder()
        
        // Verify existence of response Data, or throw an appropriate Error
        guard let data = data,
              let response = response,
              let httpResponse = response as? HTTPURLResponse else {
            
            guard let error = error else {
                callback(.failure(CError.networkError("No response was received, but no error was reported")))
                return
            }
            
            let newError = CError.networkError(error.localizedDescription)
            callback(.failure(newError))
            return
        }
        
        // Decode the Data
        do {
            if httpResponse.statusCode == 200 {
                let decoded = try decoder.decode(ResponseType.self, from: data)
                callback(.success(decoded))
                return
            } else {
                let decoded = try decoder.decode(YggdrasilError.self, from: data)
                callback(.failure(CError.mojangErorr(decoded)))
                return
            }
        } catch let error {
            callback(.failure(CError.decodingError(error.localizedDescription)))
            return
        }
    }
    
    task.resume()
}
