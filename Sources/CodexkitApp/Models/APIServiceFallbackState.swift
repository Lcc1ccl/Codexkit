import Foundation

enum APIServicePoolServiceability: Equatable {
    case apiServiceDisabled
    case apiServiceDegraded
    case apiServiceRunning
    case observedPoolUnserviceable
}
