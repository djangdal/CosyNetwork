//
//  Request.swift
//
//  Created by David Jangdal on 2021-03-25.
//

import Foundation
import Combine

public enum HTTPMethod: String {
    case get
    case post
    case put
    case patch
    case delete
}

enum APIRequestError: Error {
    case unableToGetUrlComponents
    case unableToCreateUrl
}

public protocol APIRequest {
    associatedtype ErrorBodyType: Decodable & Error

    // Required
    var baseURLPath: String { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var failingStatusCodes: [HTTPStatusCode] { get }

    //Optional
    var queryParameters: [String: String]? { get }
    var requestHeaders: [String: String]? { get set }
    var cachingPolicy: URLRequest.CachePolicy { get }
    var encoder: JSONEncoder { get }

    var urlRequest: URLRequest { get throws }
}

public protocol APIDecodableRequest: APIRequest {
    associatedtype ResponseBodyType: Decodable
    var successStatusCodes: [HTTPStatusCode] { get }
}

public protocol APIEncodableRequest: APIRequest {
    associatedtype RequestBodyType: Encodable
    var body: RequestBodyType { get }
}

public typealias APICodableRequest = APIEncodableRequest & APIDecodableRequest

// Default values
public extension APIRequest {
    var queryParameters: [String: String]? { return nil }
    var cachingPolicy: URLRequest.CachePolicy { return .reloadIgnoringLocalAndRemoteCacheData }
    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

fileprivate extension APIRequest {
    var baseRequest: URLRequest {
        get throws {
            guard var urlComponents = URLComponents(string: baseURLPath + path) else {
                throw APIRequestError.unableToGetUrlComponents
            }

            if urlComponents.queryItems == nil || urlComponents.queryItems?.isEmpty == true {
                urlComponents.queryItems = queryParameters?.map { URLQueryItem(name: $0, value: $1) }
            } else if let queryParams = queryParameters, var queryItems = urlComponents.queryItems {
                queryItems.append(contentsOf: queryParams.map { URLQueryItem(name: $0, value: $1) })
                urlComponents.queryItems = queryItems
            }

            guard let url = urlComponents.url else {
                throw APIRequestError.unableToCreateUrl
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = method.rawValue.uppercased()
            urlRequest.cachePolicy = cachingPolicy
            requestHeaders?.forEach { (key: String, value: String) in
                urlRequest.addValue(value, forHTTPHeaderField: key)
            }
            return urlRequest
        }
    }
}

public extension APIRequest {
    var urlRequest: URLRequest {
        get throws {
            try baseRequest
        }
    }
}

public extension APIEncodableRequest {
    var urlRequest: URLRequest {
        get throws {
            var urlRequest = try baseRequest
            if urlRequest.allHTTPHeaderFields?["Content-Type"] == nil {
                urlRequest.allHTTPHeaderFields?["Content-Type"] = "application/json"
            }
            let data = try encoder.encode(body)
            urlRequest.httpBody = data
            return urlRequest
        }
    }
}
