import Foundation

struct ParsedGatewayRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}
