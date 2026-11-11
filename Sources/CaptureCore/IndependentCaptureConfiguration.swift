import ScreenCaptureKit
import CoreMedia

public enum IndependentCaptureConfiguration {
    public static func make(width: Int, height: Int, includesCursor: Bool = false) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = width; config.height = height
        config.showsCursor = includesCursor; config.capturesAudio = false; config.captureMicrophone = false
        config.showMouseClicks = false
        return config
    }
}
