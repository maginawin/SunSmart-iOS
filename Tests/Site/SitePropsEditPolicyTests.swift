import Foundation

@main
struct SitePropsEditPolicyTests {

    static func main() {
        testChangedFieldsDetectsEachPropertyAndIanaChanges()
        testTimestampIsStrictlyMonotonic()
        testNoChangesAndNoPendingProducesNoUpdate()
        testNewChangesUnionWithPendingAndAdvanceTimestamp()
        testPureRetryReusesPendingTimestamp()
        testMissingPendingTimestampIsRepaired()
        testNewerRemoteWinsWithoutPending()
        testNewerLocalWinsWithoutPending()
        testEqualTimestampUsesRemoteButAvoidsRedundantPersistence()
        testMatchingRemoteClearsPendingAndContinuesMerge()
        testPendingMismatchKeepsAllLocalProperties()
        testMissingRemoteTimezoneNeverClearsLocalTimezone()
        testUpdateResponseRequiresExactTimestampAndSentFields()
        testUpdateResponseIgnoresUnsentFields()
        testSuccessfulSnapshotClearsOnlyUnchangedPendingVersion()
        testInitialSiteUploadClearsOnlyMatchingTimezonePending()
        testInitialSiteUploadPreservesNewerTimezonePending()
        testInitialSiteUploadPreservesDifferentTimezonePending()
        print("SitePropsEditPolicyTests passed")
    }

    private static let singapore = SiteTimeZoneValue(
        ianaId: "Asia/Singapore",
        rawUTCOffset: "+08:00"
    )!
    private static let shanghai = SiteTimeZoneValue(
        ianaId: "Asia/Shanghai",
        rawUTCOffset: "+08:00"
    )!
    private static let utc = SiteTimeZoneValue(
        ianaId: "Etc/UTC",
        rawUTCOffset: "+00:00"
    )!

    private static func testChangedFieldsDetectsEachPropertyAndIanaChanges() {
        let original = values(name: "Site", imageId: 1, timezone: singapore)

        require(
            SitePropsEditPolicy.changedFields(
                from: original,
                to: values(name: "Renamed", imageId: 1, timezone: singapore)
            ) == [.siteName],
            "Expected a name-only change"
        )
        require(
            SitePropsEditPolicy.changedFields(
                from: original,
                to: values(name: "Site", imageId: 2, timezone: singapore)
            ) == [.imageId],
            "Expected an image-only change"
        )
        require(
            SitePropsEditPolicy.changedFields(
                from: original,
                to: values(name: "Site", imageId: 1, timezone: shanghai)
            ) == [.timezone],
            "Same offset with a different IANA identifier must be a timezone change"
        )
    }

    private static func testTimestampIsStrictlyMonotonic() {
        require(
            SitePropsEditPolicy.nextTimestamp(now: 200, current: 100) == 200,
            "Expected current phone seconds when newer"
        )
        require(
            SitePropsEditPolicy.nextTimestamp(now: 100, current: 100) == 101,
            "Expected same-second edits to advance"
        )
        require(
            SitePropsEditPolicy.nextTimestamp(now: 50, current: 100) == 101,
            "Expected clock rollback to remain monotonic"
        )
    }

    private static func testNoChangesAndNoPendingProducesNoUpdate() {
        let currentValues = values(name: "Site", imageId: 1, timezone: singapore)
        let local = localState(values: currentValues, lastUpdate: 100)

        let snapshot = SitePropsEditPolicy.makeUpdateSnapshot(
            siteId: "site-id",
            local: local,
            original: currentValues,
            draft: currentValues,
            now: 200
        )

        require(snapshot == nil, "No changes and no pending fields must not request update")
    }

    private static func testNewChangesUnionWithPendingAndAdvanceTimestamp() {
        let original = values(name: "Site", imageId: 1, timezone: singapore)
        let local = localState(
            values: original,
            lastUpdate: 100,
            pending: SitePropsPendingState(fields: [.imageId], timestamp: 90)
        )
        let draft = values(name: "Renamed", imageId: 1, timezone: shanghai)

        let snapshot = SitePropsEditPolicy.makeUpdateSnapshot(
            siteId: "site-id",
            local: local,
            original: original,
            draft: draft,
            now: 100
        )

        require(snapshot?.fields == [.siteName, .imageId, .timezone], "Expected field union")
        require(snapshot?.timestamp == 101, "Expected a new monotonic version")
        require(snapshot?.values == draft, "Expected the complete target values")
    }

    private static func testPureRetryReusesPendingTimestamp() {
        let currentValues = values(name: "Site", imageId: 3, timezone: singapore)
        let local = localState(
            values: currentValues,
            lastUpdate: 120,
            pending: SitePropsPendingState(fields: [.imageId], timestamp: 120)
        )

        let snapshot = SitePropsEditPolicy.makeUpdateSnapshot(
            siteId: "site-id",
            local: local,
            original: currentValues,
            draft: currentValues,
            now: 500
        )

        require(snapshot?.fields == [.imageId], "Expected only historical pending field")
        require(snapshot?.timestamp == 120, "Pure retry must reuse pending timestamp")
    }

    private static func testMissingPendingTimestampIsRepaired() {
        let currentValues = values(name: "Site", imageId: 3, timezone: singapore)
        let local = localState(
            values: currentValues,
            lastUpdate: 120,
            pending: SitePropsPendingState(fields: [.imageId], timestamp: nil)
        )

        let snapshot = SitePropsEditPolicy.makeUpdateSnapshot(
            siteId: "site-id",
            local: local,
            original: currentValues,
            draft: currentValues,
            now: 100
        )

        require(snapshot?.timestamp == 121, "Missing pending timestamp must be repaired")
    }

    private static func testNewerRemoteWinsWithoutPending() {
        let local = localState(
            values: values(name: "Local", imageId: 1, timezone: singapore),
            lastUpdate: 100,
            lastUpload: 80
        )
        let remote = remoteSnapshot(
            name: "Cloud",
            imageId: 2,
            timezone: utc,
            timestamp: 101
        )

        let result = SitePropsEditPolicy.mergeRetrieve(local: local, remote: remote)

        require(result.state.values == values(name: "Cloud", imageId: 2, timezone: utc), "Remote should win")
        require(result.state.lastUpdate == 101, "Expected cloud update timestamp")
        require(result.state.lastUploadCloudTimestamp == 101, "Expected cloud upload marker")
        require(result.shouldPersist, "Changed remote values must persist")
    }

    private static func testNewerLocalWinsWithoutPending() {
        let local = localState(
            values: values(name: "Local", imageId: 1, timezone: singapore),
            lastUpdate: 102,
            lastUpload: 80
        )
        let remote = remoteSnapshot(
            name: "Cloud",
            imageId: 2,
            timezone: utc,
            timestamp: 101
        )

        let result = SitePropsEditPolicy.mergeRetrieve(local: local, remote: remote)

        require(result.state == local, "Newer local data must remain unchanged")
        require(!result.shouldPersist, "Unchanged local state must not be rewritten")
    }

    private static func testEqualTimestampUsesRemoteButAvoidsRedundantPersistence() {
        let values = values(name: "Same", imageId: 1, timezone: singapore)
        let local = localState(values: values, lastUpdate: 100, lastUpload: 100)
        let sameRemote = remoteSnapshot(
            name: "Same",
            imageId: 1,
            timezone: singapore,
            timestamp: 100
        )
        let changedRemote = remoteSnapshot(
            name: "Cloud",
            imageId: 2,
            timezone: utc,
            timestamp: 100
        )

        let sameResult = SitePropsEditPolicy.mergeRetrieve(local: local, remote: sameRemote)
        let changedResult = SitePropsEditPolicy.mergeRetrieve(local: local, remote: changedRemote)

        require(!sameResult.shouldPersist, "Equal identical cloud data must not rewrite storage")
        require(changedResult.state.values.siteName == "Cloud", "Equal timestamp must prefer cloud")
        require(changedResult.shouldPersist, "Equal but different cloud data must persist")
    }

    private static func testMatchingRemoteClearsPendingAndContinuesMerge() {
        let local = localState(
            values: values(name: "Local Name", imageId: 3, timezone: singapore),
            lastUpdate: 120,
            lastUpload: 90,
            pending: SitePropsPendingState(fields: [.imageId, .timezone], timestamp: 120)
        )
        let remote = remoteSnapshot(
            name: "Cloud Name",
            imageId: 3,
            timezone: singapore,
            timestamp: 121
        )

        let result = SitePropsEditPolicy.mergeRetrieve(local: local, remote: remote)

        require(result.state.pending.fields.isEmpty, "Matching cloud fields must clear pending")
        require(result.state.pending.timestamp == nil, "Cleared pending must clear timestamp")
        require(result.state.values.siteName == "Cloud Name", "Merge must continue after reconciliation")
        require(result.state.lastUpdate == 121, "Expected newer cloud timestamp")
        require(result.shouldPersist, "Reconciliation must persist")
    }

    private static func testPendingMismatchKeepsAllLocalProperties() {
        let local = localState(
            values: values(name: "Local Name", imageId: 3, timezone: singapore),
            lastUpdate: 120,
            pending: SitePropsPendingState(fields: [.timezone], timestamp: 120)
        )
        let remote = remoteSnapshot(
            name: "Cloud Name",
            imageId: 9,
            timezone: shanghai,
            timestamp: 130
        )

        let result = SitePropsEditPolicy.mergeRetrieve(local: local, remote: remote)

        require(result.state == local, "Any pending mismatch must keep the complete local props")
        require(!result.shouldPersist, "Pending local intent must not be rewritten")
    }

    private static func testMissingRemoteTimezoneNeverClearsLocalTimezone() {
        let local = localState(
            values: values(name: "Local", imageId: 1, timezone: singapore),
            lastUpdate: 100
        )
        let remote = SitePropsRemoteSnapshot(
            siteName: "Cloud",
            imageId: 2,
            timezone: nil,
            providedFields: [.siteName, .imageId],
            timestamp: 101
        )

        let result = SitePropsEditPolicy.mergeRetrieve(local: local, remote: remote)

        require(result.state.values.siteName == "Cloud", "Expected valid remote name")
        require(result.state.values.imageId == 2, "Expected valid remote image")
        require(result.state.values.timezone == singapore, "Missing timezone must preserve local value")
    }

    private static func testUpdateResponseRequiresExactTimestampAndSentFields() {
        let request = SitePropsUpdateSnapshot(
            siteId: "site-id",
            fields: [.siteName, .timezone],
            values: values(name: "Target", imageId: 1, timezone: singapore),
            timestamp: 200
        )
        let exact = remoteSnapshot(
            name: "Target",
            imageId: 9,
            timezone: singapore,
            timestamp: 200
        )
        let wrongTimestamp = remoteSnapshot(
            name: "Target",
            imageId: 9,
            timezone: singapore,
            timestamp: 201
        )
        let missingTimezone = SitePropsRemoteSnapshot(
            siteName: "Target",
            imageId: 9,
            timezone: nil,
            providedFields: [.siteName, .imageId],
            timestamp: 200
        )
        let wrongName = remoteSnapshot(
            name: "Different",
            imageId: 9,
            timezone: singapore,
            timestamp: 200
        )

        require(SitePropsEditPolicy.updateResponseMatches(request: request, response: exact), "Expected exact response")
        require(!SitePropsEditPolicy.updateResponseMatches(request: request, response: wrongTimestamp), "Timestamp mismatch must fail")
        require(!SitePropsEditPolicy.updateResponseMatches(request: request, response: missingTimezone), "Missing sent timezone must fail")
        require(!SitePropsEditPolicy.updateResponseMatches(request: request, response: wrongName), "Sent name mismatch must fail")
    }

    private static func testUpdateResponseIgnoresUnsentFields() {
        let request = SitePropsUpdateSnapshot(
            siteId: "site-id",
            fields: [.siteName],
            values: values(name: "Target", imageId: 1, timezone: singapore),
            timestamp: 200
        )
        let response = remoteSnapshot(
            name: "Target",
            imageId: 999,
            timezone: utc,
            timestamp: 200
        )

        require(
            SitePropsEditPolicy.updateResponseMatches(request: request, response: response),
            "Unsent image and timezone fields must be ignored"
        )
    }

    private static func testSuccessfulSnapshotClearsOnlyUnchangedPendingVersion() {
        let request = SitePropsUpdateSnapshot(
            siteId: "site-id",
            fields: [.siteName, .timezone],
            values: values(name: "Target", imageId: 1, timezone: singapore),
            timestamp: 200
        )
        let unchanged = localState(
            values: request.values,
            lastUpdate: 200,
            pending: SitePropsPendingState(fields: request.fields, timestamp: 200)
        )
        let newerVersion = localState(
            values: values(name: "Newer", imageId: 1, timezone: shanghai),
            lastUpdate: 201,
            pending: SitePropsPendingState(fields: request.fields, timestamp: 201)
        )

        let cleared = SitePropsEditPolicy.localStateAfterSuccessfulUpdate(
            current: unchanged,
            request: request
        )
        let preserved = SitePropsEditPolicy.localStateAfterSuccessfulUpdate(
            current: newerVersion,
            request: request
        )

        require(cleared.pending.fields.isEmpty, "Unchanged snapshot must clear pending")
        require(cleared.pending.timestamp == nil, "Cleared snapshot must clear pending timestamp")
        require(cleared.lastUploadCloudTimestamp == 200, "Expected upload timestamp to advance")
        require(preserved == newerVersion, "A newer pending version must remain untouched")
    }

    private static func testInitialSiteUploadClearsOnlyMatchingTimezonePending() {
        let current = localState(
            values: values(name: "Site", imageId: 1, timezone: singapore),
            lastUpdate: 200,
            pending: SitePropsPendingState(
                fields: [.imageId, .timezone],
                timestamp: 200
            )
        )
        let submission = SiteInitialTimeZoneSubmission(
            timezone: singapore,
            timestamp: 200
        )

        let result = SitePropsEditPolicy.localStateAfterSuccessfulInitialSiteUpload(
            current: current,
            submission: submission
        )

        require(result.pending.fields == [.imageId], "Initial Site Add must clear only timezone pending")
        require(result.pending.timestamp == 200, "Remaining pending fields must retain their timestamp")
        require(result.lastUploadCloudTimestamp == 200, "Initial Site Add must confirm its submitted generation")
    }

    private static func testInitialSiteUploadPreservesNewerTimezonePending() {
        let current = localState(
            values: values(name: "Site", imageId: 1, timezone: shanghai),
            lastUpdate: 201,
            pending: SitePropsPendingState(fields: [.timezone], timestamp: 201)
        )
        let submission = SiteInitialTimeZoneSubmission(
            timezone: singapore,
            timestamp: 200
        )

        let result = SitePropsEditPolicy.localStateAfterSuccessfulInitialSiteUpload(
            current: current,
            submission: submission
        )

        require(result.pending == current.pending, "A newer timezone pending version must survive an older Site Add")
        require(result.lastUploadCloudTimestamp == 200, "Only the submitted Site Add generation may be confirmed")
        require(result.lastUpdate == 201, "A newer local generation must remain dirty")
    }

    private static func testInitialSiteUploadPreservesDifferentTimezonePending() {
        let current = localState(
            values: values(name: "Site", imageId: 1, timezone: shanghai),
            lastUpdate: 200,
            pending: SitePropsPendingState(fields: [.timezone], timestamp: 200)
        )
        let submission = SiteInitialTimeZoneSubmission(
            timezone: singapore,
            timestamp: 200
        )

        let result = SitePropsEditPolicy.localStateAfterSuccessfulInitialSiteUpload(
            current: current,
            submission: submission
        )

        require(result.pending == current.pending, "A different local timezone must keep its pending intent")
        require(result.lastUploadCloudTimestamp == 200, "The submitted generation must still be recorded")
    }

    private static func values(
        name: String,
        imageId: Int,
        timezone: SiteTimeZoneValue?
    ) -> SitePropsValues {
        return SitePropsValues(siteName: name, imageId: imageId, timezone: timezone)
    }

    private static func localState(
        values: SitePropsValues,
        lastUpdate: Int64,
        lastUpload: Int64? = nil,
        pending: SitePropsPendingState = .init(fields: [], timestamp: nil)
    ) -> SitePropsLocalState {
        return SitePropsLocalState(
            values: values,
            lastUpdate: lastUpdate,
            lastUploadCloudTimestamp: lastUpload,
            pending: pending
        )
    }

    private static func remoteSnapshot(
        name: String,
        imageId: Int,
        timezone: SiteTimeZoneValue,
        timestamp: Int64
    ) -> SitePropsRemoteSnapshot {
        return SitePropsRemoteSnapshot(
            siteName: name,
            imageId: imageId,
            timezone: timezone,
            providedFields: [.siteName, .imageId, .timezone],
            timestamp: timestamp
        )
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError(message)
        }
    }
}
