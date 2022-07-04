//
//  File.swift
//  File
//
//  Created by Ezekiel Elin on 9/7/21.
//

import Foundation
import Common
import MojangRules

public struct VersionPatch: Codable {
    public let id: String
    public let clientJarURL: String?
    public var libraries: [String: LibraryPatch]
    
    public init(id: String, clientJarURL: String?, libraries: [String : LibraryPatch]) {
        self.id = id
        self.clientJarURL = clientJarURL
        self.libraries = libraries
    }
    
    public struct LibraryPatch: Codable {
        public let newLibraryVersion: String
        public let artifactURL: String
        public let macOSNativeURL: String?
        
        public init(newLibraryVersion: String, artifactURL: String, macOSNativeURL: String?) {
            self.newLibraryVersion = newLibraryVersion
            self.artifactURL = artifactURL
            self.macOSNativeURL = macOSNativeURL
        }
    }
    
    public static func download(for version: String) async throws -> Self? {
        guard let url = URL(string: "https://m1craft-server.ezekiel.workers.dev/patch/\(version).json") else {
            throw CError.encodingError("Failed to create patch URL for version \(version)")
        }
        
        let (data, response) = try await retrieveData(from: url)
        let httpResponse = response as! HTTPURLResponse
        
        if httpResponse.statusCode == 200 {
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(Self.self, from: data)
            } catch let err {
                throw CError.decodingError(err.localizedDescription)
            }
        } else if httpResponse.statusCode == 404 {
            return nil
        } else {
            throw CError.networkError("HTTP Status Code: \(httpResponse.statusCode)")
        }
    }
    
    public func patch(package: VersionPackage) async throws -> VersionPackage {
        var writablePackage = package
        writablePackage.time = Date()
        if let newClientURL = self.clientJarURL {
            try await VersionPatch.editURL(resource: &writablePackage.downloads.client, newURL: newClientURL)
        }
        
        writablePackage.libraries = []
        for library in package.libraries {
            if let rules = library.rules {
                if !RuleProcessor.verifyRulesPass(rules, with: .none) {
                    continue
                }
            }
            
            let libNameComponents = library.name.split(separator: ":")
            let libOrg = libNameComponents[0]
            let libName = String(libNameComponents[1])
            let libVersion = libNameComponents[2]
            
            let libraryPatch = self.libraries[libName]
            if let libraryPatch = libraryPatch {
                var writableLibrary = library

                writableLibrary.name = "\(libOrg):\(libName):\(libraryPatch.newLibraryVersion)"
                
                if var artifact = writableLibrary.downloads.artifact {
                    try await VersionPatch.editURL(resource: &artifact, newURL: libraryPatch.artifactURL)
                    artifact.path = artifact.path.replacingOccurrences(of: libVersion,
                                                                       with: libraryPatch.newLibraryVersion)
                    writableLibrary.downloads.artifact = artifact
                }
                
                if let nativePatchUrl = libraryPatch.macOSNativeURL,
                   let osxKey = library.natives?.osx,
                   let osxClassifier = library.downloads.classifiers?[osxKey] {
                    var writableClassifier = osxClassifier
                    
                    try await VersionPatch.editURL(resource: &writableClassifier, newURL: nativePatchUrl)
                    writableClassifier.path = osxClassifier.path
                        .replacingOccurrences(of: libVersion, with: libraryPatch.newLibraryVersion)
                    
                    writableLibrary.downloads.classifiers?[osxKey] = writableClassifier
                }
                
                writablePackage.libraries.append(writableLibrary)
            } else {
                writablePackage.libraries.append(library)
            }
        }
        
        return writablePackage
    }
    
    static func editURL<R: DownloadableAllModifiable>(resource: inout R, newURL: String) async throws {
        resource.url = newURL
        let newData = try await resource.download(checkSha1: false)
        resource.sha1 = newData.sha1()
        resource.size = UInt(newData.count)
    }
}
