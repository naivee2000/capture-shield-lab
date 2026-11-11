import Testing
@testable import CaptureCore

struct CaptureConfigurationTests {
    @Test func cursorRecordingIncludesTheRealPointerAndKeepsAudioOff() {
        let cursor = IndependentCaptureConfiguration.make(width: 1920, height: 1080, includesCursor: true)
        #expect(cursor.showsCursor)
        #expect(!cursor.capturesAudio && !cursor.captureMicrophone && !cursor.showMouseClicks)
        let original = IndependentCaptureConfiguration.make(width: 1920, height: 1080)
        #expect(!original.showsCursor)
    }
}
