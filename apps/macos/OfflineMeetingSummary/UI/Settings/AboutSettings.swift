import AppKit
import OMSCore
import SwiftUI

struct AboutSettings: View {
    @Environment(UpdateController.self) private var updates

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    private var version: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(shortVersion) (\(build))"
    }

    private var problemReportURL: URL {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "Apple silicon"
        #else
        let architecture = "Intel"
        #endif
        return ProjectLinks.problemReport(
            appVersion: version,
            macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            architecture: architecture
        )
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "Minutes").font(.title.weight(.semibold))
                        Text("Version \(version)").foregroundStyle(.secondary).monospacedDigit()
                        Text("Meeting minutes that stay on your local machine.").foregroundStyle(.secondary)
                        Link("Free and open source", destination: ProjectLinks.repository)
                            .help(ProjectLinks.repository.absoluteString)
                    }
                    Spacer()
                    Button("Check for Updates…") { updates.checkForUpdates() }
                        .disabled((!updates.isEnabled || !updates.canCheckForUpdates) && !ScreenshotMode.isOn)
                        .help(updates.isEnabled ? "" : String(localized: "This build does not check for updates. Only the released app from GitHub updates itself."))
                }
                .padding(.vertical, 4)
            }

            Section {
                AboutStep(number: 1, icon: "record.circle", title: "Record",
                          text: "Record the screen, system audio and your microphone during a meeting.")
                AboutStep(number: 2, icon: "text.bubble", title: "Transcribe",
                          text: "A local model turns the speech into a transcript with time stamps. The audio stays on the Mac.")
                AboutStep(number: 3, icon: "sparkles", title: "Summarize",
                          text: "A model writes the summary from the transcript and a template. It can look at screen frames.")
                AboutStep(number: 4, icon: "doc.text", title: "Use",
                          text: "Open the summary as Markdown. All files of a session are in one folder.")
            } header: {
                Text("How it works")
            }

            Section {
                Text("Minutes is free and open source under the Apache License 2.0.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LinkRow(title: "Source code", label: "GitHub", url: ProjectLinks.repository)
                LinkRow(title: "What's new", label: "Release notes for version \(shortVersion)",
                        url: ProjectLinks.release(version: shortVersion))
                LinkRow(title: "User guide", label: "Open the guide", url: ProjectLinks.site)
                LinkRow(title: "Report a problem", label: "Report a problem on GitHub", url: problemReportURL)
            } header: {
                Text("Open source")
            } footer: {
                Text("Do not attach recordings, transcripts, summaries or screenshots of real meetings to a report.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("App data") {
                    Button("Open in Finder") { NSWorkspace.shared.open(AppPaths.applicationSupport) }
                        .buttonStyle(.link)
                        .help(AppPaths.applicationSupport.path)
                }
                LabeledContent("Sessions") {
                    Button("Open in Finder") { NSWorkspace.shared.open(AppSettings.current.sessionsFolder) }
                        .buttonStyle(.link)
                        .help(AppSettings.current.sessionsFolder.path)
                }
                if let acknowledgements = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt") {
                    LabeledContent("Licenses") {
                        Button("Show") { NSWorkspace.shared.open(acknowledgements) }
                            .buttonStyle(.link)
                            .help("Licenses of Minutes and of the third-party software in it")
                    }
                }
            } footer: {
                Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
    }
}

/// A label on the left and a link on the right. The tooltip shows the address.
private struct LinkRow: View {
    let title: LocalizedStringKey
    let label: LocalizedStringKey
    let url: URL

    var body: some View {
        LabeledContent(title) {
            Link(label, destination: url).help(url.absoluteString)
        }
    }
}

private struct AboutStep: View {
    let number: Int
    let icon: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(number). \(Text(title))"))
    }
}
