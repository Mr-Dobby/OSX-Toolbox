import Foundation

struct LANTransferPeer: Identifiable, Equatable {
    let hostName: String
    let ipAddress: String
    let port: UInt16

    var id: String { "\(ipAddress):\(port)" }
}

struct IncomingLANTransfer: Identifiable, Equatable {
    enum Status: String {
        case pending = "Pending approval"
        case approved = "Approved — waiting for upload"
        case receiving = "Receiving"
        case extracting = "Extracting"
        case completed = "Completed"
        case declined = "Declined"
        case failed = "Failed"
    }

    let id: String
    let senderName: String
    let senderIP: String
    let itemNames: [String]
    let archiveName: String
    let byteCount: Int64
    var status: Status
    var message: String?
}

struct OutgoingLANTransfer: Identifiable, Equatable {
    enum Status: String {
        case awaitingApproval = "Waiting for approval"
        case uploading = "Uploading"
        case completed = "Completed"
        case declined = "Declined"
        case failed = "Failed"
    }

    let id: String
    let recipientName: String
    let recipientIP: String
    let itemNames: [String]
    var status: Status
    var message: String?
}

struct TransferCapabilityResponse: Codable {
    let receivingEnabled: Bool
    let hostName: String
    let port: UInt16
}

struct TransferRequestPayload: Codable {
    let senderName: String
    let senderIP: String
    let itemNames: [String]
    let archiveName: String
    let byteCount: Int64
}

struct TransferRequestResponse: Codable {
    let requestID: String
}

struct TransferRequestStatusResponse: Codable {
    let status: String
}
