//
//  Dispatcher.swift
//  Trooper
//
//  Created by David Jangdal on 2021-03-25.
//

import Foundation
import Combine

public enum APIError: Error {
    case urlRequestUnavailable
}

public struct ResponseError: Error, Decodable {
    public let error: String
    public let errorCode: String
}

public protocol APIDispatcherProtocol {
    func dispatch<Request: APIRequest>(_ request: Request) -> AnyPublisher<Request.ResponseBodyType, Error>
}

public struct APIDispatcher: APIDispatcherProtocol {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    public init(urlSession: URLSession = .shared, decoder: JSONDecoder = JSONDecoder()) {
        self.urlSession = urlSession
        self.decoder = decoder
    }

    public func dispatch<Request: APIRequest>(_ request: Request) -> AnyPublisher<Request.ResponseBodyType, Error> {
        guard let urlRequest = request.urlRequest else {
            return Fail(outputType: Request.ResponseBodyType.self, failure: APIError.urlRequestUnavailable).eraseToAnyPublisher()
        }
        return urlSession
            .dataTaskPublisher(for: urlRequest)
            .tryMap{ data, response in
                guard let httpResponse = response as? HTTPURLResponse else {
                    return data
                }

                if httpResponse.statusCode == 400 {
                    throw try self.decoder.decode(ResponseError.self, from: data)
                }

                if httpResponse.statusCode == 503 {
                    throw ResponseError(error: "Service unavailable", errorCode: "SERVICE_UNAVAILABLE")
                }

                return data
            }
            .decode(type: Request.ResponseBodyType.self, decoder: decoder)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

public class APIAuthenticatedDispatcher: APIDispatcherProtocol {
    private let urlSession: URLSession
    private var token: String
    private let authHeaderName: String
    private let decoder: JSONDecoder
    
    public init(urlSession: URLSession = .shared, token: String, authHeaderName: String, decoder: JSONDecoder = JSONDecoder()) {
        self.urlSession = urlSession
        self.token = token
        self.authHeaderName = authHeaderName
        self.decoder = decoder
    }
    
    public func dispatch<Request: APIRequest>(_ request: Request) -> AnyPublisher<Request.ResponseBodyType, Error> {
        guard var urlRequest = request.urlRequest else {
            return Fail(outputType: Request.ResponseBodyType.self, failure: APIError.urlRequestUnavailable).eraseToAnyPublisher()
        }
        urlRequest.addValue(token, forHTTPHeaderField: authHeaderName)
        return urlSession
            .dataTaskPublisher(for: urlRequest)
            .tryMap{ [weak self] data, response in
                guard let self = self, let httpResponse = response as? HTTPURLResponse else {
                    return data
                }
                if let token = httpResponse.value(forHTTPHeaderField: self.authHeaderName) {
                    self.token = token
                }

                if httpResponse.statusCode == 400 {
                    throw try self.decoder.decode(ResponseError.self, from: data)
                }

                if httpResponse.statusCode == 503 {
                    throw ResponseError(error: "Service unavailable", errorCode: "SERVICE_UNAVAILABLE")
                }

                return data
            }
            .decode(type: Request.ResponseBodyType.self, decoder: decoder)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
