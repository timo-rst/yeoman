import Foundation

let dir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let pyScript = dir.appendingPathComponent("generate_yeoman_icon.py").path

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
proc.arguments = [pyScript]
proc.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
do {
    try proc.run()
    proc.waitUntilExit()
} catch {
    FileHandle.standardError.write(Data("Icon generation could not start: \(error.localizedDescription)\n".utf8))
    exit(1)
}

if proc.terminationStatus == 0 {
    print("Icon generation finished successfully.")
} else {
    print("Icon generation failed with exit code: \(proc.terminationStatus)")
}
