import EduSDK
import SwiftUI
#if os(iOS)
import UIKit
#endif

private enum DeviceCheckTokens {
    static let previewAspectRatio: CGFloat = 16 / 9
    static let panelMaxWidth: CGFloat = 640
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DeviceCheckTokens.stackPadding / 2) {
                Text(EduI18n.text("deviceCheckTitle"))
                    .font(EduFont.sans(18, weight: .semibold))
                    .foregroundStyle(EduColors.onSurface)
                Text(EduI18n.text("deviceCheckSubtitle"))
                    .foregroundStyle(EduColors.onSurfaceVariant)
            }
            .padding(DeviceCheckTokens.stackPadding)

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
            .aspectRatio(DeviceCheckTokens.previewAspectRatio, contentMode: .fit)
            .background(EduColors.surfaceLow)

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
                if cameras.isEmpty || microphones.isEmpty {
                    Text(EduI18n.text("deviceCheckWarningEnter"))
                        .foregroundStyle(EduColors.onSurface)
                }
                HStack {
                    Spacer()
                    Button(EduI18n.text("deviceCheckLater")) {
                        controller.deferDeviceCheck()
                    }
                    .foregroundStyle(EduColors.onSurfaceVariant)
                    Button(EduI18n.text("deviceCheckConfirm")) {
                        controller.confirmDeviceCheck(
                            selection: DeviceCheckSelection(
                                cameraId: cameraId.isEmpty ? nil : cameraId,
                                microphoneId: microphoneId.isEmpty ? nil : microphoneId,
                                speakerId: speakerId.isEmpty ? nil : speakerId
                            )
                        )
                    }
                    .foregroundStyle(EduColors.onPrimary)
                }
            }
            .padding(DeviceCheckTokens.stackPadding)
        }
        .frame(maxWidth: DeviceCheckTokens.panelMaxWidth)
        .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusXl))
        .eduGlass(cornerRadius: EduDimens.radiusXl, tier: .soft)
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
