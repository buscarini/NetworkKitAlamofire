//
//  NetworkKitAlamofireTests.swift
//  NetworkKitAlamofire
//
//  Created by José Manuel Sánchez on 11/12/2018.
//  Copyright © 2018 NetworkKitAlamofire. All rights reserved.
//

import Foundation
import XCTest
import NetworkKit
import NetworkKitAlamofire

class NetworkKitAlamofireTests: XCTestCase {
	func testExample() {
		let request = Request<Data>(method: .get, url: .full(URL(string: "https://www.google.es")!), type: .request(parameters: [:], parametersEncoding: .url))
		
		let service = NetworkService.alamofire(URL(string: "https://www.google.es")!)
		
		let finish = expectation(description: "Download google.es home page")
		
		_ = service.request(request, log: { _ in }, completion: { result in
			switch result {
			case let .success(.some(data), response):
				let string = String(data: data, encoding: .isoLatin1)!
				XCTAssert(string.count > 0)
				
				XCTAssert(response.responseCode == 200)
			default:
				XCTFail()
			}
			
			finish.fulfill()
		})
		
		waitForExpectations(timeout: 5, handler: nil)
	}
	
	func testPost() {
		let finish = expectation(description: "Make post request")
		
		let base = URL(string: "http://httpbin.org")!
		
		let params = [ "name" : "test" ]
		
		let request = Request<Data>.post(
			.endpoint("post"),
			params,
			encoding: .json
		)
		
		let alamofire = NetworkService.alamofire(base)
		alamofire.request(request, log: { _ in }) { response in
			switch response {
			case let .success(_, httpResponse):
				XCTAssert(httpResponse.responseCode == 200)
			case .encodingError, .networkError:
				XCTFail()
			}
			
			finish.fulfill()
		}
		
		waitForExpectations(timeout: 5, handler: nil)
	}
}
