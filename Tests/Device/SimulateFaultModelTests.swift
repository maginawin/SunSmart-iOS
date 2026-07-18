import Foundation

@main
struct SimulateFaultModelTests {
    static func main() {
        let actions: Set<SimulateFaultAction> = [
            .motionSensor(.normal), .motionSensor(.fault),
            .photocellSensor(.normal), .photocellSensor(.fault),
            .lightStatus(.normal), .lightStatus(.dim), .lightStatus(.flicker),
            .lightStatus(.dimFlicker), .lightStatus(.off)
        ]
        precondition(actions.count == 9)

        let expectedAlerts: [SimulateFaultAction: SimulateFaultAlertPayload] = [
            .motionSensor(.normal): .init(type: "motion_sensor", status: "normal", level: "3"),
            .motionSensor(.fault): .init(type: "motion_sensor", status: "fault", level: "3"),
            .photocellSensor(.normal): .init(type: "photocell_sensor", status: "normal", level: "2"),
            .photocellSensor(.fault): .init(type: "photocell_sensor", status: "fault", level: "2"),
            .lightStatus(.normal): .init(type: "light_status", status: "normal", level: "1"),
            .lightStatus(.dim): .init(type: "light_status", status: "dim", level: "1"),
            .lightStatus(.flicker): .init(type: "light_status", status: "flicker", level: "1"),
            .lightStatus(.dimFlicker): .init(type: "light_status", status: "dim_flicker", level: "1"),
            .lightStatus(.off): .init(type: "light_status", status: "off", level: "1")
        ]
        precondition(expectedAlerts.count == 9)
        expectedAlerts.forEach { action, expected in
            precondition(action.alertPayload == expected)
        }

        let payload = SimulateFaultRequestPayload(
            siteId: "ST02",
            spaceId: "SP02",
            nodeId: "01AA8F81-16D3-4482-87A3-5799F3F05D98",
            alert: .init(type: "motion_sensor", status: "fault", level: "3"),
            nodeAddress: "00A1",
            date: Date(timeIntervalSince1970: 0)
        )
        let parameters = payload.parameters
        precondition(parameters.count == 9)
        precondition(parameters["siteId"] as? String == "ST02")
        precondition(parameters["spaceId"] as? String == "SP02")
        precondition(parameters["nodeId"] as? String == "01AA8F81-16D3-4482-87A3-5799F3F05D98")
        precondition(parameters["nodeAddress"] as? String == "00A1")
        precondition(parameters["source"] as? String == "ios")
        precondition(parameters["desc"] as? String == "")
        precondition(parameters["location"] as? String == "")
        precondition(parameters["datetime"] as? String == "1970-01-01 00:00:00")
        let alert = parameters["alert"] as? [String: String]
        precondition(alert == ["type": "motion_sensor", "status": "fault", "level": "3"])

        precondition(SimulateFaultGridMetrics.columns(availableWidth: 311, itemCount: 5) == 4)
        precondition(SimulateFaultGridMetrics.rows(availableWidth: 311, itemCount: 5) == 2)
        precondition(SimulateFaultGridMetrics.collectionHeight(availableWidth: 311, itemCount: 5) == 71)

        precondition(SimulateFaultGridMetrics.columns(availableWidth: 387, itemCount: 5) == 5)
        precondition(SimulateFaultGridMetrics.rows(availableWidth: 387, itemCount: 5) == 1)
        precondition(SimulateFaultGridMetrics.collectionHeight(availableWidth: 387, itemCount: 5) == 36)

        precondition(SimulateFaultGridMetrics.columns(availableWidth: 50, itemCount: 2) == 1)
        precondition(SimulateFaultGridMetrics.rows(availableWidth: 50, itemCount: 2) == 2)
        precondition(SimulateFaultGridMetrics.collectionHeight(availableWidth: 50, itemCount: 0) == 0)

        precondition(
            SimulateFaultPresentationMetrics.contentHeight(
                availableWidth: 375,
                safeAreaBottom: 34
            ) == 386
        )
        precondition(
            SimulateFaultPresentationMetrics.contentHeight(
                availableWidth: 768,
                safeAreaBottom: 20
            ) == 351
        )

        print("SimulateFaultModelTests passed")
    }
}
