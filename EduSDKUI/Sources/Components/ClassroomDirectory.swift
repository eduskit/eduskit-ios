import SwiftUI
import EduSDK

private typealias T = MobileClassroomTokens

struct DirectoryMemberRow: View {
    let member: ClassroomDirectoryMember
    let rowHeight: CGFloat
    let onSelect: () -> Void
    let onAction: (String, String, @escaping () -> Void) -> Void
    @State private var pending = false
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: T.directoryGap) {
                    Group {
                        if let url = member.avatarUrl { RemoteAvatarImage(avatarUrl: url) }
                        else { Text(String(member.name.prefix(1))).font(EduFont.sans(T.directoryAvatarGlyph, weight: .semibold)).foregroundStyle(EduColors.primary) }
                    }.frame(width: T.directoryAvatar, height: T.directoryAvatar).background(EduColors.primarySoft).clipShape(Circle())
                    VStack(alignment: .leading, spacing: T.gap / 2) {
                        HStack(spacing: T.gap) {
                            Text(member.name).font(EduFont.sans(T.directoryName, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                            if member.isSelf { Text(EduI18n.text("directorySelf")).font(EduFont.sans(T.directoryPill)).foregroundStyle(EduColors.onSurfaceVariant) }
                        }
                        HStack(spacing: T.gap) {
                            Text(EduI18n.text(member.roleKey)).font(EduFont.sans(T.directoryMeta)).foregroundStyle(EduColors.onSurfaceVariant).lineLimit(1)
                            tag(EduI18n.text(member.onStage ? "directoryOnStage" : "directoryOffStage"), stage: member.onStage)
                            if member.handRaised { tag(EduI18n.text("directoryHandRaised"), hand: true) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if !member.canApproveHand && !member.canRejectHand {
                        HStack(spacing: T.gap) {
                            if member.microphoneStatus != nil { EduIcon(member.microphoneStatus == "on" ? "mic" : "mic_off", size: T.titleSize, tint: member.microphoneStatus == "on" ? EduColors.success : EduColors.onSurfaceVariant) }
                            if member.cameraStatus != nil { EduIcon(member.cameraStatus == "on" ? "videocam" : "videocam_off", size: T.titleSize, tint: member.cameraStatus == "on" ? EduColors.success : EduColors.onSurfaceVariant) }
                            EduIcon("more_horiz", size: T.titleSize, tint: EduColors.onSurfaceVariant)
                        }
                    }
                }.padding(.leading, T.directoryInset).padding(.trailing, member.canApproveHand || member.canRejectHand ? 0 : T.directoryInset).frame(maxHeight: .infinity)
            }.buttonStyle(.plain).foregroundStyle(EduColors.onSurface)
            if member.canApproveHand || member.canRejectHand {
                HStack(spacing: 0) {
                    if member.canRejectHand { action("close", "reject_raise_hand", "memberActionRejectRaiseHand", EduColors.onSurfaceVariant) }
                    if member.canApproveHand { action("check", "approve_raise_hand", "memberActionApproveRaiseHand", EduColors.primary) }
                }.padding(.trailing, T.gap)
            }
        }.frame(height: rowHeight).background(member.handRaised ? EduColors.panelRaisedSurface : EduColors.surfaceLowest)
            .overlay(alignment: .bottom) { Rectangle().fill(EduColors.outlineVariant).frame(height: 1) }
    }
    private func tag(_ text: String, stage: Bool = false, hand: Bool = false) -> some View {
        Text(text).font(EduFont.sans(T.directoryPill)).lineLimit(1).fixedSize()
            .foregroundStyle(hand ? EduColors.panelAmberInk : stage ? EduColors.primary : EduColors.onSurfaceVariant)
            .padding(.horizontal, T.gap / 2).background(hand ? EduColors.panelAmberSurface : stage ? EduColors.primarySoft : EduColors.surfaceLow, in: RoundedRectangle(cornerRadius: T.cardRadius / 2))
    }
    private func action(_ icon: String, _ action: String, _ key: String, _ tint: Color) -> some View {
        Button { pending = true; onAction(action, member.userId) { pending = false } } label: { Image("panel_" + icon, bundle: .module).resizable().renderingMode(.template).foregroundStyle(tint).frame(width: T.directoryActionIcon, height: T.directoryActionIcon).frame(width: T.directoryAction, height: T.directoryAction) }
            .buttonStyle(.plain).disabled(pending).accessibilityLabel(EduI18n.text(key)).help(EduI18n.text(key))
    }
}

struct ToolCatalogGrid: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var compact: Bool { verticalSizeClass == .compact }
    private var gap: CGFloat { compact ? T.toolGridCompactGap : T.toolGridGap }
    let catalog: [ClassroomToolCatalogItem]
    let onSelect: (ClassroomToolCatalogItem) -> Void
    var body: some View {
        GeometryReader { proxy in
            let count = proxy.size.width < T.toolGridNarrowWidth ? Int(T.toolGridNarrowColumns) : Int(T.toolGridColumns)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: count), spacing: gap) {
                    ForEach(catalog, id: \.kind) { item in
                        Button { onSelect(item) } label: {
                            VStack(spacing: gap) {
                                Image("panel_" + item.icon, bundle: .module).resizable().renderingMode(.template).foregroundStyle(tone(item.tone)).frame(width: compact ? T.toolGridCompactGlyph : T.toolGridGlyph, height: compact ? T.toolGridCompactGlyph : T.toolGridGlyph).frame(width: compact ? T.toolGridCompactIcon : T.toolGridIcon, height: compact ? T.toolGridCompactIcon : T.toolGridIcon).background(surface(item.tone), in: RoundedRectangle(cornerRadius: T.toolGridRadius))
                                Text(EduI18n.text(item.titleKey)).font(EduFont.sans(compact ? T.toolGridCompactLabel : T.toolGridLabel)).lineLimit(1).foregroundStyle(EduColors.onSurface)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: compact ? T.toolGridCompactCellMin : T.toolGridCellMin).aspectRatio(1, contentMode: .fit)
                                .background(EduColors.surfaceLowest, in: RoundedRectangle(cornerRadius: T.toolGridRadius)).overlay(RoundedRectangle(cornerRadius: T.toolGridRadius).stroke(EduColors.outlineVariant, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel(EduI18n.text(item.titleKey))
                    }
                }.padding(compact ? T.toolGridCompactInset : T.toolGridInset)
            }
        }
    }
    private func surface(_ value: String) -> Color {
        switch value { case "green": return EduColors.panelGreenSurface; case "amber": return EduColors.panelAmberSurface; case "slate": return EduColors.surfaceLow; default: return EduColors.primarySoft }
    }
    private func tone(_ value: String) -> Color {
        switch value { case "green": return EduColors.success; case "amber": return EduColors.panelAmberInk; case "slate": return EduColors.onSurfaceVariant; default: return EduColors.primary }
    }
}
