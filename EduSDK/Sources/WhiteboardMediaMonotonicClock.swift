import Foundation
import Darwin

/// Same suspend-aware boot clock as edusdk-providers/native_clock.rs on Apple.
/// No Date/systemUptime/arrival-time fallback or origin estimation.
enum WhiteboardMediaMonotonicClock {
    private static let scale: Result<(UInt32, UInt32), SdkError> = {
        var value = mach_timebase_info_data_t()
        guard mach_timebase_info(&value) == KERN_SUCCESS else {
            return .failure(SdkError(code:.internal,message:"Native media clock timebase unavailable"))
        }
        return .success((value.numer,value.denom))
    }()
    static func milliseconds() throws -> UInt64 {
        let (numer,denom) = try scale.get()
        return try convert(mach_continuous_time(),numer:numer,denom:denom)
    }
    static func convert(_ ticks: UInt64, numer: UInt32, denom: UInt32) throws -> UInt64 {
        guard numer > 0, denom > 0 else { throw SdkError(code:.internal,message:"Invalid native media clock scale") }
        let product = ticks.multipliedFullWidth(by:UInt64(numer))
        let divisor = UInt64(denom) * 1_000_000
        guard product.high < divisor else { throw SdkError(code:.internal,message:"Native media clock overflow") }
        return divisor.dividingFullWidth(product).quotient
    }
}
