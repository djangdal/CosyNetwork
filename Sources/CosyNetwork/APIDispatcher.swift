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

public protocol APIDispatcherProtocol {
    func dispatch<Request: APIRequest>(_ request: Request) -> AnyPublisher<Request.ResponseBodyType, Error>
}

public struct APIDispatcher: APIDispatcherProtocol {
    private let urlSession: URLSession
    private let decoder = JSONDecoder()

    public init(urlSession: URLSession = .shared, dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .iso8601) {
        self.urlSession = urlSession
        decoder.dateDecodingStrategy = dateDecodingStrategy
    }

    public func dispatch<Request: APIRequest>(_ request: Request) -> AnyPublisher<Request.ResponseBodyType, Error> {
        guard let urlRequest = request.urlRequest else {
            return Fail(outputType: Request.ResponseBodyType.self, failure: APIError.urlRequestUnavailable).eraseToAnyPublisher()
        }
        return urlSession
            .dataTaskPublisher(for: urlRequest)
            .tryMap({ data, response in
                return data
            })
            .decode(type: Request.ResponseBodyType.self, decoder: decoder)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

public class APIAuthenticatedDispatcher: APIDispatcherProtocol {
    private let urlSession: URLSession
    private var token: String
    private let authHeaderName: String
    private let decoder = JSONDecoder()
    
    public init(urlSession: URLSession = .shared, token: String, authHeaderName: String) {
        self.urlSession = urlSession
        self.token = token
        self.authHeaderName = authHeaderName
        decoder.dateDecodingStrategy = .iso8601
    }
    
    public func dispatch<Request: APIRequest>(_ request: Request) -> AnyPublisher<Request.ResponseBodyType, Error> {
        guard var urlRequest = request.urlRequest else {
            return Fail(outputType: Request.ResponseBodyType.self, failure: APIError.urlRequestUnavailable).eraseToAnyPublisher()
        }
        urlRequest.addValue(token, forHTTPHeaderField: authHeaderName)
        return urlSession
            .dataTaskPublisher(for: urlRequest)
            .map({ data, response in
                if let httpResponse = response as? HTTPURLResponse, let token = httpResponse.value(forHTTPHeaderField: self.authHeaderName) {
                    self.token = token
                }
                return data
            })
            .decode(type: Request.ResponseBodyType.self, decoder: decoder)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
