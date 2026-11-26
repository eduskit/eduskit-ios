import Foundation
import CryptoKit

/// Streaming file capability. Delegate work runs off MainActor and the Core/query owner.
final class TeachingToolExportFile: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum Failure: Error { case unavailable, downloadFailed }
    private let entry: TeachingToolExport
    private let isCurrent: () -> Bool
    private let completion: (Result<URL, Error>) -> Void
    private let queue: OperationQueue = { let q=OperationQueue();q.name="edusdk.tool-export-file";q.maxConcurrentOperationCount=1;q.qualityOfService = .userInitiated;return q }()
    private var session: URLSession?
    private var handle: FileHandle?
    private var file: URL?
    private var directory: URL?
    private var length: Int64=0
    private var digest=SHA256()
    private var failed=false
    init(entry: TeachingToolExport, isCurrent: @escaping () -> Bool, completion: @escaping (Result<URL, Error>) -> Void) {
        self.entry=entry;self.isCurrent=isCurrent;self.completion=completion
    }
    func start() {
        queue.addOperation { [self] in
            do {
                guard entry.canDownload, isCurrent(), let address=entry.downloadUrl, let url=URL(string:address), entry.job.byteLength != nil, entry.job.sha256 != nil else {throw Failure.unavailable}
                let root=FileManager.default.temporaryDirectory.appendingPathComponent("edusdk-export-"+UUID().uuidString,isDirectory:true)
                try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
                directory=root
                let target=root.appendingPathComponent(entry.job.filename)
                guard FileManager.default.createFile(atPath:target.path,contents:nil) else {throw Failure.downloadFailed}
                file=target;handle=try FileHandle(forWritingTo:target)
                let config=URLSessionConfiguration.ephemeral;config.httpCookieStorage=nil;config.urlCache=nil;config.timeoutIntervalForRequest=15
                let transport=URLSession(configuration:config,delegate:self,delegateQueue:queue);session=transport
                var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData);request.setValue(entry.job.contentType,forHTTPHeaderField:"Accept")
                transport.dataTask(with:request).resume()
            } catch {finish(success:false)}
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {completionHandler(nil)}
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard isCurrent(), let http=response as? HTTPURLResponse, http.statusCode==200,
            response.expectedContentLength==entry.job.byteLength, http.value(forHTTPHeaderField:"Content-Type")==entry.job.contentType else {failed=true;completionHandler(.cancel);return}
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !failed,isCurrent(),let expected=entry.job.byteLength,length+Int64(data.count)<=expected else {failed=true;dataTask.cancel();return}
        do {try handle?.write(contentsOf:data);length+=Int64(data.count);digest.update(data:data)} catch {failed=true;dataTask.cancel()}
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let hash=digest.finalize().map {String(format:"%02x",$0)}.joined()
        finish(success:error==nil && !failed && isCurrent() && length==entry.job.byteLength && hash==entry.job.sha256)
    }
    private func finish(success: Bool) {
        do {try handle?.close()} catch {failed=true};handle=nil
        session?.finishTasksAndInvalidate();session=nil
        if success && !failed,let file {completion(.success(file))}
        else {if let directory {try? FileManager.default.removeItem(at:directory)};completion(.failure(Failure.downloadFailed))}
    }
    /// Call on a background queue after the system picker has copied/cancelled the file.
    static func remove(_ file: URL) {try? FileManager.default.removeItem(at:file.deletingLastPathComponent())}
}

/// Lifecycle/capability mirror for I/O only; Core remains the authorization authority.
final class TeachingToolExportGate: @unchecked Sendable {
    private let lock=NSLock()
    private var generation: UInt64=0
    private var capabilities: [String:String]=[:]
    func replace(_ entries:[TeachingToolExport]) {lock.lock();defer {lock.unlock()};capabilities=Dictionary(uniqueKeysWithValues:entries.compactMap {entry in guard entry.canDownload,let url=entry.downloadUrl else {return nil};return(entry.id,url)})}
    func reset() {lock.lock();defer {lock.unlock()};generation &+= 1;capabilities=[:]}
    func ticket()->UInt64 {lock.lock();defer {lock.unlock()};return generation}
    func permits(_ entry:TeachingToolExport,_ ticket:UInt64)->Bool {lock.lock();defer {lock.unlock()};return generation==ticket && capabilities[entry.id]==entry.downloadUrl && entry.canDownload}
}
