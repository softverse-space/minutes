import Foundation

/// Public addresses of the Minutes project: source code, releases, user guide, problem reports and
/// the update feed (ADR-0031). The app opens them only when the user clicks.
public enum ProjectLinks {
    public static let repository = URL(string: "https://github.com/softverse-space/minutes")!
    public static let releases = repository.appending(path: "releases")
    public static let site = URL(string: "https://softverse-space.github.io/minutes/")!
    public static let appcast = site.appending(path: "appcast.xml")

    /// The GitHub release page of one version, for example `…/releases/tag/v1.1.0`.
    public static func release(version: String) -> URL {
        releases.appending(path: "tag").appending(path: "v\(version)")
    }

    /// A new problem report from the template `.github/ISSUE_TEMPLATE/bug_report.yml`.
    /// The URL fills in only the versions and the Mac type. The user sends the report in the browser.
    public static func problemReport(appVersion: String, macOSVersion: String, architecture: String) -> URL {
        var components = URLComponents(url: repository.appending(path: "issues/new"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "app-version", value: appVersion),
            URLQueryItem(name: "macos-version", value: macOSVersion),
            URLQueryItem(name: "mac", value: architecture),
        ]
        // `+` in a value would become a space in the form. Encode it.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}
