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
		
		let expectation = XCTestExpectation(description: "Download google.es home page")
		
		_ = service.request(request, log: { _ in }, completion: { result in
			switch result {
			case let .success(.some(data), response):
				let string = String(data: data, encoding: .isoLatin1)!
				XCTAssert(string.count > 0)
				
				XCTAssert(response.responseCode == 200)
			default:
				XCTFail()
			}
			
			expectation.fulfill()
		})
		
		wait(for: [expectation], timeout: 10.0)
    }
    
    static var allTests = [
        ("testExample", testExample),
    ]
}
