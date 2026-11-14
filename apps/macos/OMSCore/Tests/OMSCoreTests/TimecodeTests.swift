import Testing
@testable import OMSCore

struct TimecodeTests {
    @Test(arguments: [
        (0.0, ".", "00:00:00"),
        (3723.456, ",", "01:02:03,456"),
        (-2.0, ".", "00:00:00"),
    ])
    func formats(seconds: Double, separator: String, expected: String) {
        let text = separator == "." ? Timecode.format(seconds) : Timecode.format(seconds, millisecondSeparator: separator)
        #expect(text == expected)
    }
}
