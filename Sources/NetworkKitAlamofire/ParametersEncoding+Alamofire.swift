import Foundation

import NetworkKit
import Alamofire

extension ParametersEncoding {
    var alamofire: Alamofire.ParameterEncoding {
        switch self {
        case .json:
            return JSONEncoding.default
        case .url:
            return URLEncoding.default
		case let .other(encode):
			return CustomEncoding(encode: encode)
        }
    }
}
