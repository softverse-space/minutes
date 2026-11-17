import Foundation
import Testing
@testable import OMSCore

struct ProjectLinksTests {
    @Test func fixedAddresses() {
        #expect(ProjectLinks.repository.absoluteString == "https://github.com/softverse-space/minutes")
        #expect(ProjectLinks.releases.absoluteString == "https://github.com/softverse-space/minutes/releases")
        #expect(ProjectLinks.appcast.absoluteString == "https://softverse-space.github.io/minutes/appcast.xml")
    }

    @Test func releaseOfVersion() {
        #expect(ProjectLinks.release(version: "1.1.0").absoluteString
            == "https://github.com/softverse-space/minutes/releases/tag/v1.1.0")
    }

    @Test func problemReportFillsInOnlyVersions() throws {
        let url = ProjectLinks.problemReport(appVersion: "1.1.0 (2)", macOSVersion: "15.4.1", architecture: "Apple silicon")
        #expect(url.absoluteString.hasPrefix("https://github.com/softverse-space/minutes/issues/new?"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(values == [
            "template": "bug_report.yml",
            "app-version": "1.1.0 (2)",
            "macos-version": "15.4.1",
            "mac": "Apple silicon",
        ])
    }

    @Test func problemReportEncodesPlus() {
        let url = ProjectLinks.problemReport(appVersion: "1.1.0+beta", macOSVersion: "15.0", architecture: "Intel")
        #expect(url.absoluteString.contains("app-version=1.1.0%2Bbeta"))
        #expect(!url.absoluteString.contains(" "))
    }
}
