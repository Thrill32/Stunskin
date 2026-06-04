import Foundation

let state = State.shared

let listener = XPCListener()

if state.currentData.running == true {
    listener.endConnection() { _ in }
}

func ensureAppDirectories() throws {
    let fm = FileManager.default
    let base = URL(fileURLWithPath: "/Library/Application Support/Stunskin")
    let subdirs = ["Data", "tmp"]

    for subdir in subdirs {
        let url = base.appendingPathComponent(subdir)
        try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }
}

do {
    try ensureAppDirectories()
} catch {
    print("StunskinHelper Failed to create app directories: \(error)")
}

listener.start()
