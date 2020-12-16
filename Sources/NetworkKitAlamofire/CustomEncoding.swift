//
//  CustomEncoding.swift
//  Alamofire
//
//  Created by José Manuel Sánchez Peñarroja on 10/01/2019.
//

import Foundation
import Alamofire

public class CustomEncoding {
	public var encode: (URLRequest, Parameters) throws -> URLRequest
	
	public init(encode: @escaping (URLRequest, Parameters) throws -> URLRequest) {
		self.encode = encode
	}
}

extension CustomEncoding: ParameterEncoding {
	public func encode(_ urlRequest: URLRequestConvertible, with parameters: Parameters?) throws -> URLRequest {
		try self.encode(urlRequest.asURLRequest(), parameters ?? [:])
	}
}
