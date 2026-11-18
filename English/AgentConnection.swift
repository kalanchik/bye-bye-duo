import Foundation

nonisolated enum AgentConnection {
    private struct Registration: Decodable {
        struct Transport: Decodable {
            let type: String
            let command: String?
            let args: [String]?
        }

        let enabled: Bool
        let transport: Transport
    }

    enum Failure: LocalizedError {
        case missingCLI, notSignedIn, registration, server, timeout

        var errorDescription: String? {
            switch self {
            case .missingCLI: "Codex CLI не найден. Укажи путь к нему в настройках приложения."
            case .notSignedIn: "Войди в Codex CLI командой codex login и повтори проверку."
            case .registration: "Выполни команду из инструкции, чтобы подключить эту копию English Practice."
            case .server: "Сервер english-practice не ответил. Проверь, что приложение доступно по указанному пути."
            case .timeout: "Проверка заняла слишком много времени. Попробуй ещё раз."
            }
        }
    }

    static var command: String {
        let bundle = Bundle.main.bundleURL.path
        let executable = Bundle.main.executableURL?.lastPathComponent ?? "English Practice"
        let relativePath = "Contents/MacOS/\(executable)"
        return [
            "APP=\(quote(bundle))",
            "codex mcp add english-practice -- \\",
            "  \"$APP\"/\(quote(relativePath)) --mcp"
        ].joined(separator: "\n")
    }

    @concurrent
    static func verify(executablePath: String) async throws {
        guard executablePath.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw Failure.missingCLI
        }
        let cli = URL(fileURLWithPath: executablePath)
        let login = try await run(cli, arguments: ["login", "status"])
        guard login.status == 0 else { throw Failure.notSignedIn }

        let config = try await run(cli, arguments: ["mcp", "get", "english-practice", "--json"])
        guard config.status == 0,
              let registration = try? JSONDecoder().decode(Registration.self, from: config.output),
              registration.enabled, registration.transport.type == "stdio",
              registration.transport.args == ["--mcp"],
              let command = registration.transport.command, command.hasPrefix("/"),
              let executable = Bundle.main.executableURL,
              URL(fileURLWithPath: command).resolvingSymlinksInPath() == executable.resolvingSymlinksInPath() else {
            throw Failure.registration
        }

        let request = """
        {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"English Practice","version":"1.0"}}}
        {"jsonrpc":"2.0","method":"notifications/initialized"}
        {"jsonrpc":"2.0","id":2,"method":"tools/list"}

        """
        let server = try await run(executable, arguments: ["--mcp"], input: Data(request.utf8))
        let replies = String(decoding: server.output, as: UTF8.self).split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
        let initialized = replies.contains { reply in
            guard reply["id"] as? Int == 1, let result = reply["result"] as? [String: Any],
                  let info = result["serverInfo"] as? [String: Any] else { return false }
            return info["name"] as? String == "english-practice"
        }
        let listsCourse = replies.contains { reply in
            guard reply["id"] as? Int == 2, let result = reply["result"] as? [String: Any],
                  let tools = result["tools"] as? [[String: Any]] else { return false }
            return tools.contains { $0["name"] as? String == "list_course" }
        }
        guard server.status == 0, initialized, listsCourse else { throw Failure.server }
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func run(
        _ executable: URL, arguments: [String], input: Data? = nil
    ) async throws -> (status: Int32, output: Data) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "EnglishConnect-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appending(path: "stdout")
        try Data().write(to: outputURL)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        let process = Process()
        let stdin = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardInput = stdin
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let (statuses, continuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { process in
            continuation.yield(process.terminationStatus)
            continuation.finish()
        }
        try Task.checkCancellation()
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            try? stdin.fileHandleForWriting.close()
        }
        if let input {
            try stdin.fileHandleForWriting.write(contentsOf: input)
        }
        try stdin.fileHandleForWriting.close()

        let status = try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                for await status in statuses { return status }
                throw CancellationError()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw Failure.timeout
            }
            defer { group.cancelAll() }
            guard let status = try await group.next() else { throw CancellationError() }
            return status
        }
        let data = try FileHandle(forReadingFrom: outputURL)
        defer { try? data.close() }
        return (status, try data.read(upToCount: 128_000) ?? Data())
    }
}
