import XCTest
import EduSDK
#if canImport(TXLiteAVSDK_TRTC)
import TXLiteAVSDK_TRTC

final class LiveVendorCallbackContractTest: XCTestCase {
    func testNativeObserverExportsTheActualVendorSelectors() {
        let adapter = TencentLiveIosAdapter(onEvent: { _ in }, resolveView: { _ in nil })
        for name in ["onVideoPlaying:firstPlay:extraInfo:", "onAudioPlaying:firstPlay:extraInfo:",
                     "onVideoLoading:extraInfo:", "onAudioLoading:extraInfo:", "onConnected:extraInfo:", "onWarning:code:message:extraInfo:", "onError:code:message:extraInfo:",
                     "onReceiveSeiMessage:payloadType:data:", "onStatisticsUpdate:statistics:"] {
            XCTAssertTrue(adapter.responds(to: NSSelectorFromString(name)), name)
        }
    }
}
#endif
