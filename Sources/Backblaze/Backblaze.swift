//
//  File.swift
//  File
//
//  Created by Ezekiel Elin on 9/2/21.
//

import Foundation
import Crypto

public struct AuthorizeAccount {
    public static func exec(applicationKeyId: String, applicationKey: String) async throws -> Response {
        let url = URL(string: "https://api.backblazeb2.com/b2api/v2/b2_authorize_account")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue(
            AuthorizeAccount.buildAuthHeader(username: applicationKeyId, password: applicationKey),
            forHTTPHeaderField: "Authorization"
        )
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Response.self, from: data)
        
        return decoded
    }

    public struct Response: Decodable {
        let accountId: String
        let authorizationToken: String
        
        let apiUrl: String
        public let downloadUrl: String
        
        let s3ApiUrl: String
    }

    static func buildAuthHeader(username: String, password: String) -> String {
        let encoded = "\(username):\(password)".data(using: .utf8)!.base64EncodedString()
        return "Basic \(encoded)"
    }
}

public struct ListBuckets {
    public static func exec(authorization: AuthorizeAccount.Response) async throws -> [Response.Bucket] {
        let url = URL(string: "\(authorization.apiUrl)/b2api/v2/b2_list_buckets")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(
            authorization.authorizationToken,
            forHTTPHeaderField: "Authorization"
        )

        let encoder = JSONEncoder()
        let body = Request(accountId: authorization.accountId)
        request.httpBody = try encoder.encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Response.self, from: data)
        
        return decoded.buckets
    }

    public struct Request: Encodable {
        let accountId: String
    }

    public struct Response: Decodable {
        public struct Bucket: Decodable {
            public let accountId: String
            public let bucketId: String
            public let bucketName: String
        }
        
        let buckets: [Bucket]
    }
}

struct GetUploadUrl {
    static func exec(authorization: AuthorizeAccount.Response,
                            bucket: ListBuckets.Response.Bucket) async throws -> Response {

        let url = URL(string: "\(authorization.apiUrl)/b2api/v2/b2_get_upload_url")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(
            authorization.authorizationToken,
            forHTTPHeaderField: "Authorization"
        )

        let encoder = JSONEncoder()
        let body = Request(bucketId: bucket.bucketId)
        request.httpBody = try encoder.encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Response.self, from: data)
        
        return decoded
    }

    struct Request: Encodable {
        let bucketId: String
    }

    struct Response: Decodable {
        public let bucketId: String
        public let uploadUrl: String
        public let authorizationToken: String
    }
}

public struct UploadFile {
    public static func exec(authorization: AuthorizeAccount.Response,
                            bucket: ListBuckets.Response.Bucket,
                            fileName: String,
                            contentType: String,
                            data: Data) async throws -> Response {

        let uploadInfo = try await GetUploadUrl.exec(authorization: authorization, bucket: bucket)
        
        let url = URL(string: uploadInfo.uploadUrl)!
        
        let shaDigest = Insecure.SHA1.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(
            uploadInfo.authorizationToken,
            forHTTPHeaderField: "Authorization"
        )
        request.addValue(fileName, forHTTPHeaderField: "X-Bz-File-Name")
        request.addValue(contentType, forHTTPHeaderField: "Content-Type")
        request.addValue(data.count.description, forHTTPHeaderField: "Content-Length")
        request.addValue(shaDigest, forHTTPHeaderField: "X-Bz-Content-Sha1")

        request.httpBody = data
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Response.self, from: responseData)
        
        return decoded
    }

    public struct Response: Decodable {
        public let accountId: String
        public let bucketId: String
        public let contentLength: UInt
        public let contentSha1: String
        public let contentType: String
        public let fileId: String
        public let fileName: String
    }
}
