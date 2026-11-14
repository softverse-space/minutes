import Testing
@testable import OMSCore

struct SystemPromptTests {
    let old = "Rules v1"
    let new = "Rules v2"

    @Test func writesDefaultWhenCopyIsMissingOrEmpty() {
        #expect(SystemPrompt.copyAction(userCopy: nil, bundledDefault: new, lastWrittenDefaultDigest: nil) == .writeDefault)
        #expect(SystemPrompt.copyAction(userCopy: " \n", bundledDefault: new, lastWrittenDefaultDigest: nil) == .writeDefault)
    }

    @Test func updatesCopyThatUserDidNotEdit() {
        let digest = SystemPrompt.digest(old)
        #expect(SystemPrompt.copyAction(userCopy: old, bundledDefault: new, lastWrittenDefaultDigest: digest) == .writeDefault)
    }

    @Test func keepsEditedCopy() {
        let digest = SystemPrompt.digest(old)
        #expect(SystemPrompt.copyAction(userCopy: "My rules", bundledDefault: new, lastWrittenDefaultDigest: digest) == .keep)
        #expect(SystemPrompt.copyAction(userCopy: "My rules", bundledDefault: new, lastWrittenDefaultDigest: nil) == .keep)
    }

    @Test func keepsCopyEqualToDefault() {
        #expect(SystemPrompt.copyAction(userCopy: new, bundledDefault: new, lastWrittenDefaultDigest: nil) == .keep)
    }

    @Test func effectiveTextFallsBackToDefault() {
        #expect(SystemPrompt.effective(userCopy: "My rules", bundledDefault: new) == "My rules")
        #expect(SystemPrompt.effective(userCopy: "", bundledDefault: new) == new)
        #expect(SystemPrompt.effective(userCopy: nil, bundledDefault: nil) == nil)
    }

    @Test func digestIsStableAndDetectsChanges() {
        #expect(SystemPrompt.digest(old) == SystemPrompt.digest("Rules v1"))
        #expect(SystemPrompt.digest(old) != SystemPrompt.digest(new))
    }
}
