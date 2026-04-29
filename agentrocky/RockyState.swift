//
//  RockyState.swift
//  agentrocky
//

import Foundation
import Darwin

class RockyState: ObservableObject {
    @Published var isChatOpen: Bool = false

    lazy var session: ClaudeSession = ClaudeSession(workingDirectory: realHome)

    private var realHome: String {
        getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir, encoding: .utf8) }
            ?? NSHomeDirectory()
    }
}
