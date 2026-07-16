import Foundation

struct SimulateFaultAlertPayload: Equatable {
    let type: String
    let status: String
    let level: String

    var parameters: [String: String] {
        ["type": type, "status": status, "level": level]
    }
}

struct SimulateFaultRequestPayload {
    let siteId: String
    let spaceId: String
    let nodeId: String
    let alert: SimulateFaultAlertPayload
    let nodeAddress: String
    let source = "ios"
    let desc = ""
    let location = ""
    let datetime: String

    init(
        siteId: String,
        spaceId: String,
        nodeId: String,
        alert: SimulateFaultAlertPayload,
        nodeAddress: String,
        date: Date
    ) {
        self.siteId = siteId
        self.spaceId = spaceId
        self.nodeId = nodeId
        self.alert = alert
        self.nodeAddress = nodeAddress
        self.datetime = Self.utcDateTimeString(from: date)
    }

    var parameters: [String: Any] {
        [
            "siteId": siteId,
            "spaceId": spaceId,
            "nodeId": nodeId,
            "alert": alert.parameters,
            "nodeAddress": nodeAddress,
            "source": source,
            "desc": desc,
            "location": location,
            "datetime": datetime
        ]
    }

    private static func utcDateTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
