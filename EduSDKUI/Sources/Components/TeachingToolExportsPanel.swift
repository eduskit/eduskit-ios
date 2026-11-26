import SwiftUI
import UIKit

@MainActor
struct TeachingToolExportsPanel: View {
    let card:TeachingToolCard
    @ObservedObject var controller:ClassroomController
    @State private var downloading=false
    @State private var saved=false
    @State private var file:ExportFile?
    @State private var pendingURL:URL?
    @State private var active=true
    private struct ExportFile:Identifiable {let id=UUID();let url:URL}
    var body:some View {
        VStack(alignment:.leading) {
            Button(EduI18n.text("tool_exportAll")){controller.createToolExport(card,currentRound:false)}.disabled(controller.toolMutationPending(card.sessionId))
            if card.roundId != nil {Button(EduI18n.text("tool_exportRound")){controller.createToolExport(card,currentRound:true)}.disabled(controller.toolMutationPending(card.sessionId))}
            ForEach(controller.toolsView?.exports.filter {$0.job.sessionId==card.sessionId} ?? []) {entry in
                Text(EduI18n.text("tool_export_"+entry.job.status)+" · "+EduI18n.text("tool_exportRevision")+" "+entry.job.sourceRevision)
                if let count=entry.job.rowCount {Text(EduI18n.text("tool_exportRows")+" \(count)")}
                if ["queued","processing","ready"].contains(entry.job.status) {Button(EduI18n.text(entry.job.status=="ready" && !entry.canDownload ? "tool_exportRenew":"tool_exportRefresh")){controller.refreshToolExport(entry)}}
                if entry.canDownload {Button(EduI18n.text("tool_exportDownload")){downloading=true;saved=false;controller.downloadToolExport(entry){url in downloading=false;if let url {if active {pendingURL=url;file=ExportFile(url:url)}else{release(url)}}}}.disabled(downloading)}
            }
            if downloading {Text(EduI18n.text("tool_exportSaving"))}
            if saved {Text(EduI18n.text("tool_exportSaved"))}
        }.onAppear{active=true}.onDisappear{active=false;if let pendingURL {release(pendingURL)};pendingURL=nil;file=nil}
        .sheet(item:$file,onDismiss:{if let pendingURL {release(pendingURL)};pendingURL=nil;file=nil}) {selected in
            ToolExportDocumentPicker(file:selected.url) {success in saved=success;release(selected.url);pendingURL=nil;file=nil}
        }
    }
    private func release(_ url:URL){DispatchQueue.global(qos:.utility).async {TeachingToolExportFile.remove(url)}}
}

@MainActor
private struct ToolExportDocumentPicker:UIViewControllerRepresentable {
    let file:URL
    let complete:(Bool)->Void
    func makeCoordinator()->Coordinator {Coordinator(complete)}
    func makeUIViewController(context:Context)->UIDocumentPickerViewController {
        let picker=UIDocumentPickerViewController(forExporting:[file],asCopy:true);picker.delegate=context.coordinator;return picker
    }
    func updateUIViewController(_ controller:UIDocumentPickerViewController,context:Context) {}
    final class Coordinator:NSObject,UIDocumentPickerDelegate {
        let complete:(Bool)->Void
        init(_ complete:@escaping (Bool)->Void){self.complete=complete}
        func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]){complete(!urls.isEmpty)}
        func documentPickerWasCancelled(_ controller:UIDocumentPickerViewController){complete(false)}
    }
}
