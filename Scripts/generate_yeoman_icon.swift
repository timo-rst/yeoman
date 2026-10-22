import Foundation

let dir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let pyScript = dir.appendingPathComponent("generate_yeoman_icon.py").path

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
proc.arguments = ["python3", pyScript]
try? proc.run()
proc.waitUntilExit()

if proc.terminationStatus == 0 {
    print("Icon generation finished successfully.")
} else {
    print("Icon generation failed with exit code: \(proc.terminationStatus)")
}
