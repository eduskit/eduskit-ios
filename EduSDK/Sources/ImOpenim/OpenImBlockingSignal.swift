import Darwin
import Foundation

/// `DispatchSemaphore` 不会把等待线程的 QoS 让给发信号的线程。
/// OpenIM 在自己的 Default QoS 线程上回调，而进课、销毁走 User-initiated。
/// 若直接 `signal`，Thread Performance Checker 会报优先级反转。
/// 发信号时当前线程必须不低于等待方；抬不上去时改由新线程发信号，避免占用同一 GCD 线程池。
enum OpenImBlockingSignal {
    private static let relativePriority: Int32 = 0
    private static let fallbackThreadName = "edusdk.openim.qos-signal"

    static func signal(
        _ semaphore: DispatchSemaphore,
        waiterQoS: qos_class_t,
        beforeSignal: (() -> Void)? = nil
    ) {
        guard outranks(waiterQoS, qos_class_self()) else {
            beforeSignal?()
            semaphore.signal()
            return
        }
        let previous = qos_class_self()
        if pthread_set_qos_class_self_np(waiterQoS, relativePriority) == 0 {
            beforeSignal?()
            semaphore.signal()
            if previous != QOS_CLASS_UNSPECIFIED {
                pthread_set_qos_class_self_np(previous, relativePriority)
            }
            return
        }
        signalOnFreshThread(semaphore, waiterQoS: waiterQoS, beforeSignal: beforeSignal)
    }

    static func outranks(_ needed: qos_class_t, _ current: qos_class_t) -> Bool {
        switch needed {
        case QOS_CLASS_USER_INTERACTIVE:
            return current != QOS_CLASS_USER_INTERACTIVE
        case QOS_CLASS_USER_INITIATED:
            return current != QOS_CLASS_USER_INTERACTIVE && current != QOS_CLASS_USER_INITIATED
        default:
            return false
        }
    }

    private static func signalOnFreshThread(
        _ semaphore: DispatchSemaphore,
        waiterQoS: qos_class_t,
        beforeSignal: (() -> Void)?
    ) {
        let thread = Thread {
            _ = pthread_set_qos_class_self_np(waiterQoS, relativePriority)
            beforeSignal?()
            semaphore.signal()
        }
        thread.qualityOfService = waiterQoS == QOS_CLASS_USER_INTERACTIVE
            ? .userInteractive
            : .userInitiated
        thread.name = fallbackThreadName
        thread.start()
    }
}
