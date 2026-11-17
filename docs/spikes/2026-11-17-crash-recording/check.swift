// Crash spike checker. Usage: check <file> [expectedSeconds]
// Reports what each reader can read: AVURLAsset, AVAssetReader (real decoded seconds), AVAudioFile.
import AVFoundation
import Foundation

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
var parts = ["size=\(size / 1024)KB"]

let asset = AVURLAsset(url: url)
let sem = DispatchSemaphore(value: 0)
Task {
    do {
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        parts.append(String(format: "asset=%.1fs/%dtr", duration.seconds, tracks.count))
        if let track = tracks.first {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            reader.startReading()
            var last = 0.0, count = 0
            while let sb = output.copyNextSampleBuffer() {
                let end = CMTimeAdd(sb.presentationTimeStamp, sb.duration).seconds
                if end.isFinite { last = max(last, end) }
                count += 1
            }
            parts.append(String(format: "reader=%.1fs(%d bufs,status %d)", last, count, reader.status.rawValue))
        }
    } catch {
        parts.append("asset=ERR(\((error as NSError).code))")
    }
    sem.signal()
}
sem.wait()

do {
    let file = try AVAudioFile(forReading: url)
    parts.append(String(format: "avaudiofile=%.1fs", Double(file.length) / file.processingFormat.sampleRate))
} catch {
    parts.append("avaudiofile=ERR(\((error as NSError).code))")
}
print(parts.joined(separator: "  "))
