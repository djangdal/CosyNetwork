//
//  Request.swift
//  Trooper
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

public protocol APIRequest {
    associatedtype ResponseBodyType: Decodable

    // Required
    var baseURLPath: String { get }
    var path: String { get }
    var method: HTTPMethod { get }

    //Optional
    var queryParameters: [String: String]? { get }
    var requestHeaders: [String: String]? { get }
    var cachingPolicy: URLRequest.CachePolicy { get }

    var urlRequest: URLRequest? { get }
}

// Default values
public extension APIRequest {
    var requestHeaders: [String: String]? { return nil }
    var queryParameters: [String: String]? { return nil }
    var cachingPolicy: URLRequest.CachePolicy { return .reloadIgnoringLocalAndRemoteCacheData }
}

// Create URLRequest from the values
public extension APIRequest {
    var urlRequest: URLRequest? {
        baseRequest
    }
}

private extension APIRequest {
    var baseRequest: URLRequest? {
        guard var urlComponents = URLComponents(string: baseURLPath + path) else { return nil }

        if urlComponents.queryItems == nil || urlComponents.queryItems?.isEmpty == true {
            urlComponents.queryItems = queryParameters?.map { URLQueryItem(name: $0, value: $1) }
        } else if let queryParams = queryParameters, var queryItems = urlComponents.queryItems {
            queryItems.append(contentsOf: queryParams.map { URLQueryItem(name: $0, value: $1) })
            urlComponents.queryItems = queryItems
        }

        guard let url = urlComponents.url else { return nil }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue.uppercased()
        urlRequest.cachePolicy = cachingPolicy
        requestHeaders?.forEach { (key: String, value: String) in
            urlRequest.addValue(value, forHTTPHeaderField: key)
        }
        return urlRequest
    }
}

public protocol APIBodyRequest: APIRequest {
    associatedtype RequestBodyType: Encodable
    var body: RequestBodyType { get }
}

public extension APIBodyRequest {
    var urlRequest: URLRequest? {
        guard var urlRequest = baseRequest, let data = try? JSONEncoder().encode(body) else { return nil }
        urlRequest.allHTTPHeaderFields?["Content-Type"] = "application/json"
        urlRequest.httpBody = data
        return urlRequest
    }
}
