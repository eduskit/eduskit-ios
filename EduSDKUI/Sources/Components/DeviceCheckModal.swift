import EduSDK
import SwiftUI
#if os(iOS)
import UIKit
#endif

private enum DeviceCheckTokens {
    static let previewAspectRatio: CGFloat = 16 / 9
    static let panelMaxWidth: CGFloat = 640
    static let panelMaxHeight: CGFloat = 580
    static let wideThreshold: CGFloat = 560
    static let landscapePreviewWidth: CGFloat = 224
    static let stackPadding: CGFloat = 16
    static let meterHeight: CGFloat = 6
    static let heardThreshold = 8
}

struct DeviceCheckModalView: View {
    @ObservedObject var controller: ClassroomController
    @State private var cameras: [MediaDevice] = []
    @State private var microphones: [MediaDevice] = []
    @State private var speakers: [MediaDevice] = []
    @State private var cameraId = ""
    @State private var microphoneId = ""
    @State private var speakerId = ""
    @State private var micLevel = 0
    @State private var micHeard = false

    var body: some View {
        DeviceCheckPanelLayout(onClose: controller.deferDeviceCheck, onConfirm: {
            controller.confirmDeviceCheck(selection: DeviceCheckSelection(
                cameraId: cameraId.isEmpty ? nil : cameraId,
                microphoneId: microphoneId.isEmpty ? nil : microphoneId,
                speakerId: speakerId.isEmpty ? nil : speakerId))
        }, preview: {
            ZStack(alignment: .bottom) {
                #if os(iOS)
                DeviceCheckPreviewHost(cameraId: cameraId, controller: controller)
                #else
                Color.clear
                #endif
                if cameras.isEmpty {
                    Text(EduI18n.text("deviceCheckFaultEmptyCamera"))
                        .foregroundStyle(EduColors.onPrimary)
                        .padding(DeviceCheckTokens.stackPadding)
                }
                DeviceCheckMeter(level: micLevel)
                    .padding(DeviceCheckTokens.stackPadding)
            }
            .background(EduColors.surfaceLow)

        }, controls: {
            VStack(alignment: .leading, spacing: DeviceCheckTokens.stackPadding) {
                deviceSection(EduI18n.text("deviceCheckCamera"), devices: cameras, selected: cameraId) {
                    cameraId = $0
                }
                deviceSection(EduI18n.text("deviceCheckMicrophone"), devices: microphones, selected: microphoneId) {
                    microphoneId = $0
                }
                DeviceCheckMeter(level: micLevel)
                Text(micHint)
                    .foregroundStyle(micHeard ? EduColors.success : EduColors.onSurfaceVariant)
                deviceSection(EduI18n.text("deviceCheckSpeaker"), devices: speakers, selected: speakerId) {
                    speakerId = $0
                }
                Button(EduI18n.text("deviceCheckSpeakerTest")) {
                    controller.playTestTone()
                }
                .foregroundStyle(EduColors.onSurface)
                .frame(minHeight: 44)
                if cameras.isEmpty || microphones.isEmpty {
                    Text(EduI18n.text("deviceCheckWarningEnter"))
                        .foregroundStyle(EduColors.onSurface)
                }
            }
        })
        .onAppear {
            controller.loadMediaDevices { devices in
                cameras = devices.cameras
                microphones = devices.microphones
                speakers = devices.speakers
                if cameraId.isEmpty { cameraId = devices.cameras.first?.deviceId ?? "" }
                if microphoneId.isEmpty { microphoneId = devices.microphones.first?.deviceId ?? "" }
                if speakerId.isEmpty { speakerId = devices.speakers.first?.deviceId ?? "" }
            }
            controller.setLocalAudioLevelListener { level in
                micLevel = level
                if level >= DeviceCheckTokens.heardThreshold { micHeard = true }
            }
            controller.startLocalAudioPreview(microphoneId: microphoneId.isEmpty ? nil : microphoneId)
        }
        .onChange(of: microphoneId) { id in
            micHeard = false
            micLevel = 0
            controller.startLocalAudioPreview(microphoneId: id.isEmpty ? nil : id)
        }
        .onDisappear {
            controller.setLocalAudioLevelListener(nil)
            controller.stopLocalPreview()
            controller.stopLocalAudioPreview()
        }
    }

    private var micHint: String {
        if microphones.isEmpty { return EduI18n.text("deviceCheckFaultEmptyMic") }
        return EduI18n.text(micHeard ? "deviceCheckMicHeard" : "deviceCheckMicSilent")
    }

    private func deviceSection(
        _ title: String,
        devices: [MediaDevice],
        selected: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: DeviceCheckTokens.stackPadding / 2) {
            Text(title).foregroundStyle(EduColors.onSurfaceVariant)
            ForEach(devices, id: \.deviceId) { device in
                deviceRow(device.label, selected: device.deviceId == selected) {
                    onSelect(device.deviceId)
                }
            }
        }
    }

    private func deviceRow(_ label: String, selected: Bool, onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DeviceCheckTokens.stackPadding)
                .foregroundStyle(selected ? EduColors.onPrimary : EduColors.onSurface)
                .background(selected ? EduColors.primary : EduColors.surfaceLow)
                .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusLg))
        }
        .buttonStyle(EduPressButtonStyle())
    }
}

/// Keeps dismissal and confirmation reachable while the device list scrolls.
/// Preview constraints are explicit because the native video host has no intrinsic size.
struct DeviceCheckPanelLayout<Preview: View, Controls: View>: View {
    let onClose: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder var preview: () -> Preview
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        GeometryReader { outer in
            let safe = EduSafeArea.merge(with: outer)
            let width = min(DeviceCheckTokens.panelMaxWidth,
                max(0, outer.size.width - safe.leading - safe.trailing - MobileClassroomTokens.inset * 2))
            let height = min(DeviceCheckTokens.panelMaxHeight,
                max(0, outer.size.height - safe.top - safe.bottom - MobileClassroomTokens.inset * 2))
            let wide = width >= DeviceCheckTokens.wideThreshold && width > height
            let previewWidth = wide ? DeviceCheckTokens.landscapePreviewWidth : width - DeviceCheckTokens.stackPadding * 2
            VStack(spacing: 0) {
                HStack {
                    Text(EduI18n.text("deviceCheckTitle"))
                        .font(EduFont.sans(18, weight: .semibold))
                        .foregroundStyle(EduColors.onSurface)
                    Spacer(minLength: MobileClassroomTokens.gap)
                    Button(action: onClose) {
                        EduIcon(EduIcons.close, tint: EduColors.onSurfaceVariant)
                            .frame(width: MobileClassroomTokens.touch, height: MobileClassroomTokens.touch)
                    }
                    .accessibilityLabel(EduI18n.text("close"))
                    .accessibilityIdentifier("device-check-close")
                }.padding(.horizontal, DeviceCheckTokens.stackPadding)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: DeviceCheckTokens.stackPadding) {
                        Text(EduI18n.text("deviceCheckSubtitle"))
                            .font(EduFont.sans(14)).foregroundStyle(EduColors.onSurfaceVariant)
                        // Keep the media host at the same structural position on rotation.
                        HStack(alignment: .top, spacing: wide ? DeviceCheckTokens.stackPadding : 0) {
                            VStack(alignment: .leading, spacing: DeviceCheckTokens.stackPadding) {
                                preview()
                                    .frame(width: previewWidth, height: previewWidth / DeviceCheckTokens.previewAspectRatio)
                                    .clipped()
                                    .accessibilityIdentifier("device-check-preview")
                                if !wide { controls() }
                            }
                            if wide { controls().frame(maxWidth: .infinity) }
                        }
                    }.padding(DeviceCheckTokens.stackPadding)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                Divider()
                HStack {
                    Spacer()
                    Button(EduI18n.text("deviceCheckConfirm"), action: onConfirm)
                        .foregroundStyle(EduColors.onPrimary)
                        .frame(minHeight: MobileClassroomTokens.touch)
                        .padding(.horizontal, DeviceCheckTokens.stackPadding)
                        .background(EduColors.primary, in: RoundedRectangle(cornerRadius: MobileClassroomTokens.inset))
                        .accessibilityIdentifier("device-check-confirm")
                }.padding(MobileClassroomTokens.inset)
            }
            .frame(width: width, height: height)
            .background(EduColors.surfaceLowest)
            .clipShape(RoundedRectangle(cornerRadius: MobileClassroomTokens.sheetRadius, style: .continuous))
            .accessibilityIdentifier("device-check-panel")
            .position(x: safe.leading + (outer.size.width - safe.leading - safe.trailing) / 2,
                y: safe.top + (outer.size.height - safe.top - safe.bottom) / 2)
        }
    }
}

private struct DeviceCheckMeter: View {
    let level: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(EduColors.surfaceHigh)
                Capsule()
                    .fill(EduColors.primary)
                    .frame(width: geo.size.width * CGFloat(min(100, max(0, level))) / 100)
            }
        }
        .frame(height: DeviceCheckTokens.meterHeight)
    }
}

#if os(iOS)
private struct DeviceCheckPreviewHost: UIViewRepresentable {
    let cameraId: String
    let controller: ClassroomController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        controller.startLocalPreview(view: uiView, cameraId: cameraId.isEmpty ? nil : cameraId)
    }
}
#endif
