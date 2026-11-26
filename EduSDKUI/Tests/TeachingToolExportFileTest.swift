#if os(macOS)
import XCTest
import CryptoKit
@testable import EduSDKUI

final class TeachingToolExportFileTest:XCTestCase {
    private func withServer(_ run:(String,Data)throws->Void)throws {
        let python="""
import http.server,time
body=('\\ufefftitle,name\\r\\n'+'中文"quoted"\\r\\n'*10000).encode('utf-8')
class Handler(http.server.BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_GET(self):
  if self.path.startswith('/redirect'):
   self.send_response(302);self.send_header('Location','/artifact');self.send_header('Content-Length','0');self.end_headers();return
  if self.path.startswith('/reject'):
   self.send_response(403);self.send_header('Content-Length','0');self.end_headers();return
  data=body if not self.path.startswith('/corrupt') else body[:-1]+b'x'
  self.send_response(200);self.send_header('Content-Type','text/csv; charset=utf-8');self.send_header('Content-Length',str(len(data)));self.end_headers()
  try:
   for offset in range(0,len(data),4096):
    self.wfile.write(data[offset:offset+4096]);self.wfile.flush()
    if self.path.startswith('/slow'):time.sleep(.01)
  except (BrokenPipeError,ConnectionResetError):pass
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
print(server.server_port,flush=True)
server.serve_forever()
"""
        let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/env");process.arguments=["python3","-u","-c",python]
        let output=Pipe();process.standardOutput=output;process.standardError=FileHandle.nullDevice
        try process.run();defer {process.terminate();process.waitUntilExit()}
        var line=Data();while true {let byte=output.fileHandleForReading.readData(ofLength:1);guard !byte.isEmpty else {throw NSError(domain:"ExportTestServer",code:1)};if byte==Data([10]){break};line.append(byte)}
        let port=String(decoding:line,as:UTF8.self)
        let bytes=Data(("\u{FEFF}title,name\r\n"+String(repeating:"中文\"quoted\"\r\n",count:10000)).utf8)
        try run("http://127.0.0.1:"+port,bytes)
    }
    private func entry(_ url:String,_ bytes:Data)throws->TeachingToolExport {
        let hash=SHA256.hash(data:bytes).map {String(format:"%02x",$0)}.joined()
        let job:[String:Any]=["exportId":"export_1","classroomId":"cls_1","viewerUserId":"teacher_1","sessionId":"tool_1","sourceRevision":"9007199254740993","status":"ready","filename":"teaching-tools-export_1.csv","contentType":"text/csv; charset=utf-8","byteLength":bytes.count,"sha256":hash,"rowCount":10001]
        return try JSONDecoder().decode(TeachingToolExport.self,from:JSONSerialization.data(withJSONObject:["job":job,"canDownload":true,"downloadUrl":url]))
    }
    func testActualHTTPStreamsUnicodeArtifactAndVerifiesCompleteHash()throws {
        try withServer {base,bytes in
            let ready=expectation(description:"file ready")
            let download=TeachingToolExportFile(entry:try entry(base+"/artifact?token=private-capability",bytes),isCurrent:{true}) {result in
                switch result {case let .success(file):XCTAssertEqual(try? Data(contentsOf:file),bytes);TeachingToolExportFile.remove(file);XCTAssertFalse(FileManager.default.fileExists(atPath:file.path));case .failure:XCTFail("Expected verified file")};ready.fulfill()
            }
            download.start();wait(for:[ready],timeout:10)
        }
    }
    func testRejectsRedirectsCorruptContentAndExpiredPermissionWithoutPublishingFile()throws {
        try withServer {base,bytes in
            for path in ["redirect","reject","corrupt","slow"] {
                let before=try FileManager.default.contentsOfDirectory(atPath:FileManager.default.temporaryDirectory.path).filter {$0.hasPrefix("edusdk-export-")}.sorted()
                let failed=expectation(description:path)
                let lock=NSLock();var checks=0
                let current={lock.lock();defer {lock.unlock()};checks+=1;return path != "slow" || checks<4}
                let download=TeachingToolExportFile(entry:try entry(base+"/"+path+"?token=private-capability",bytes),isCurrent:current) {result in
                    if case let .success(file)=result {TeachingToolExportFile.remove(file);XCTFail("Must not publish an invalid artifact")};failed.fulfill()
                }
                download.start();wait(for:[failed],timeout:10)
                let after=try FileManager.default.contentsOfDirectory(atPath:FileManager.default.temporaryDirectory.path).filter {$0.hasPrefix("edusdk-export-")}.sorted()
                XCTAssertEqual(after,before,"Failed downloads must clean their private temporary directory")
            }
        }
    }
    func testGateFencesRenewedCapabilitiesAndLifecycleReset()throws {
        let bytes=Data("abc".utf8);let original=try entry("https://api.example.com/private?token=one",bytes),renewed=try entry("https://api.example.com/private?token=two",bytes)
        let gate=TeachingToolExportGate();gate.replace([original]);let ticket=gate.ticket();XCTAssertTrue(gate.permits(original,ticket));gate.replace([renewed]);XCTAssertFalse(gate.permits(original,ticket));XCTAssertTrue(gate.permits(renewed,ticket));gate.reset();XCTAssertFalse(gate.permits(renewed,ticket));gate.replace([renewed]);XCTAssertFalse(gate.permits(renewed,ticket))
    }
}
#endif
