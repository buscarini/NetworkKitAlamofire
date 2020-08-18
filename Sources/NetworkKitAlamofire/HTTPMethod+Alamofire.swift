import Foundation

import NetworkKit
import Alamofire

extension NetworkKit.HTTPMethod {
	var alamofire: Alamofire.HTTPMethod {
		switch self {
		case .get:
			return .get
		case .post:
			return .post
		case .put:
			return .put
		case .delete:
			return .delete
		case .patch:
			return .patch
		case .head:
			return .head
		case .connect:
			return .connect
		case .options:
			return .options
		case .trace:
			return .trace
		}
	}
}
