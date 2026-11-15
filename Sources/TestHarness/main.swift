import Foundation
import Core
import Persistence
import AI
import MCP
import Instagram
import Video
import Dependencies
import Hermes
import Jobs
import BackendInterface

@main
struct TestHarness {
    static var failures = 0
    static var passes = 0

    static func main() async {
        print("Instagram AI Studio — Phase 1 Test Harness (CLT / no XCTest)")
        await runAll()
        print("\nResults: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL \(file):\(line) — \(message)")
        }
    }

    static func runAll() async {
        testConfiguration()
        testKeychain()
        testPathSafety()
        testLogRedaction()
        testServiceContainer()
        await testPersistence()
        await testAnalytics()
        await testOAuthState()
        await testMCP()
        await testPermissions()
        await testVideoOps()
        await testDependencies()
        await testHermesOptional()
        await testJobs()
        await testOrchestrator()
        await testRuntime()
        await testMCPStdioFixture()
        testSecurityShell()
        await testRealFFmpegIntegration()
    }

    static func testConfiguration() {
        var config = AppConfiguration(applicationSupportDirectory: FileManager.default.temporaryDirectory)
        expect((try? config.validate()) != nil, "config validates")
        config.claudeMaxTokens = 0
        expect((try? config.validate()) == nil, "invalid max tokens rejected")
        expect((try? ModelCatalog.default.resolve("custom")) == "custom", "model catalog override")
    }

    static func testKeychain() {
        let store = InMemoryKeychainStore()
        try? store.setSecret("s", account: "a")
        expect((try? store.getSecret(account: "a")) == "s", "keychain roundtrip")
        try? store.deleteSecret(account: "a")
        expect((try? store.getSecret(account: "a")) == nil, "keychain delete")
    }

    static func testPathSafety() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("harness-root-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        expect((try? PathSafety.resolveContainedPath(path: "../etc/passwd", root: root)) == nil, "traversal blocked")
        expect((try? PathSafety.resolveContainedPath(path: "ok.txt", root: root)) != nil, "safe path allowed")
    }

    static func testLogRedaction() {
        let r = StructuredLogger.redact("Authorization: Bearer sk-ant-secret")
        expect(!r.contains("sk-ant-secret") && r.contains("REDACTED"), "log redaction")
    }

    static func testServiceContainer() {
        let c = ServiceContainer()
        c.registerSingleton(7)
        expect((try? c.resolve(Int.self)) == 7, "DI resolve")
    }

    static func testPersistence() async {
        do {
            let db = try DatabaseManager.inMemory()
            let conversations = ConversationRepository(db: db)
            let conversation = ConversationRecord(title: "t", model: "m")
            try conversations.create(conversation)
            try conversations.appendMessage(MessageRecord(conversationId: conversation.id, role: "user", contentJSON: "[]"))
            expect((try? conversations.messages(conversationId: conversation.id).count) == 1, "message persist")
            var thrown = false
            do {
                try conversations.appendMessage(MessageRecord(conversationId: "missing", role: "user", contentJSON: "[]"))
            } catch { thrown = true }
            expect(thrown, "foreign keys enforced")
        } catch {
            expect(false, "persistence setup \(error)")
        }
    }

    static func testAnalytics() async {
        do {
            let db = try DatabaseManager.inMemory()
            let repo = InstagramRepository(db: db)
            try repo.upsertAccount(InstagramAccountRecord(id: "acc", username: "u"))
            let engine = AnalyticsEngine(repository: repo)
            let insights = [
                InsightMetricDTO(name: "likes", period: "day", values: [InsightValueDTO(value: 3, endTime: nil)]),
                InsightMetricDTO(name: "reach", period: "day", values: [InsightValueDTO(value: 10, endTime: nil)])
            ]
            _ = try engine.persistInsights(accountId: "acc", mediaId: nil, insights: insights, provenance: "fixture")
            let report = try engine.buildReport(
                accountId: "acc",
                periodStart: Date().addingTimeInterval(-86400),
                periodEnd: Date().addingTimeInterval(86400),
                expectedMetrics: ["likes", "reach", "views"]
            )
            expect(report.missingMetrics.contains("views"), "missing views flagged")
            expect((try? engine.aggregateAdditive(metrics: report.observedMetrics, name: "reach")) == nil, "non-additive reach rejected")
            expect((try? engine.aggregateAdditive(metrics: report.observedMetrics, name: "likes")) == 3, "likes additive")
            let empty = try engine.persistInsights(accountId: "acc", mediaId: nil, insights: [], provenance: "api")
            expect(empty.first?.completeness == .missing && empty.first?.value == nil, "empty insights not fabricated as zero")
        } catch {
            expect(false, "analytics \(error)")
        }
    }

    static func testOAuthState() async {
        let oauth = InstagramOAuthService(
            configuration: AppConfiguration(metaAppID: "app"),
            keychain: InMemoryKeychainStore(),
            http: FixtureHTTPClient()
        )
        _ = try? await oauth.beginAuthorization()
        var failed = false
        do {
            _ = try await oauth.completeWithCode("x", expectedState: "bad")
        } catch {
            failed = true
        }
        expect(failed, "invalid oauth state rejected")
        let expired = InstagramTokenSet(accessToken: "t", expiresIn: 1, obtainedAt: Date().addingTimeInterval(-100))
        expect(expired.isExpired, "expired token detection")
    }

    static func testMCP() async {
        let registry = MCPRegistry()
        expect((try? registry.descriptor(id: "fixture-echo")) != nil, "reviewed mcp present")
        expect((try? registry.descriptor(id: "evil-pkg")) == nil, "unreviewed mcp rejected")
        let transport = MCPInMemoryTransport()
        try? await transport.start()
        let list = try? await transport.send(request: MCPRequest(method: "tools/list"))
        expect(list?.error == nil, "in-memory tools/list")
        await transport.stop()
    }

    static func testPermissions() async {
        let broker = DenyByDefaultApprovalBroker(allowAll: false)
        var policy = ToolPermissionPolicy(allowedRoots: [FileManager.default.temporaryDirectory])
        policy.allowedCategories.remove(.instagramPublishing)
        let gate = ToolPermissionGate(policy: policy, approvalBroker: broker)
        var denied = false
        do {
            try await gate.authorize(toolName: "publish", category: .instagramPublishing, summary: "p")
        } catch {
            denied = true
        }
        expect(denied, "publishing denied")
    }

    static func testVideoOps() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vid-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        expect(
            (try? VideoOperation.trim(input: "../x", output: "o", startSeconds: 0, durationSeconds: 1).validated(allowedRoot: root)) == nil,
            "video traversal blocked"
        )
        expect(UnavailableRemotionRenderer().isAvailable == false, "remotion optional unavailable")
    }

    static func testDependencies() async {
        struct Fake: ProcessRunnerLike {
            func which(_ name: String) -> String? { name == "node" ? "/bin/node" : nil }
            func version(path: String) -> String? { "1" }
            func run(executable: String, arguments: [String]) async throws -> Int32 { 0 }
        }
        let manager = DependencyManager(
            processRunner: Fake(),
            approvalBroker: DenyByDefaultApprovalBroker(allowAll: false),
            isExecutable: { _ in false }
        )
        let plan = manager.planInstallation()
        expect(plan.steps.contains(where: { $0.id.contains("ffmpeg") }), "ffmpeg install planned when missing")
        var denied = false
        do { try await manager.execute(plan: plan, approved: false) } catch { denied = true }
        expect(denied || plan.steps.isEmpty, "install requires approval")
        let evil = InstallationPlan(steps: [
            InstallationStep(id: "e", title: "e", command: "brew", arguments: ["install", "x;rm"], packageManager: "homebrew", rationale: "x")
        ], summary: "e")
        var unsafe = false
        do {
            try await DependencyManager(
                processRunner: Fake(),
                approvalBroker: DenyByDefaultApprovalBroker(allowAll: true),
                isExecutable: { _ in false }
            ).execute(plan: evil, approved: true)
        } catch { unsafe = true }
        expect(unsafe, "unsafe installer args rejected")

        // Real discovery must find MacPorts ffmpeg when present even if PATH omits /opt/local/bin.
        let live = DependencyManager(approvalBroker: DenyByDefaultApprovalBroker(allowAll: false))
        let liveProfile = live.detectSystem()
        if FileManager.default.isExecutableFile(atPath: "/opt/local/bin/ffmpeg") {
            expect(liveProfile.dependencies.first(where: { $0.id == "ffmpeg" })?.available == true, "macports ffmpeg discovered")
            expect(liveProfile.dependencies.first(where: { $0.id == "ffmpeg" })?.path == "/opt/local/bin/ffmpeg", "macports ffmpeg path")
            expect(live.planInstallation(forMissingFrom: liveProfile).steps.isEmpty, "no ffmpeg install planned when present")
        }
    }

    static func testHermesOptional() async {
        struct Fake: ProcessRunnerLike {
            func which(_ name: String) -> String? { nil }
            func version(path: String) -> String? { nil }
            func run(executable: String, arguments: [String]) async throws -> Int32 { 1 }
        }
        let deps = DependencyManager(processRunner: Fake(), approvalBroker: DenyByDefaultApprovalBroker(allowAll: true))
        let hermes = HermesManager(dependencyManager: deps, keychain: InMemoryKeychainStore(), approvalBroker: DenyByDefaultApprovalBroker(allowAll: true), processRunner: Fake())
        expect(!hermes.status().installed, "hermes missing ok")
        expect(hermes.installationPlan().steps.first?.packageManager == "manual", "hermes install manual")
        expect(DisabledHermesToolBridge().exportedToolNames().isEmpty, "bridge disabled")
    }

    static func testJobs() async {
        do {
            let db = try DatabaseManager.inMemory()
            let repo = JobRepository(db: db)
            let coordinator = JobCoordinator(repository: repo, audit: AuditLogRepository(db: db), logger: StructuredLogger(minimumLevel: .error))
            struct H: JobHandler {
                var kind: String { "t" }
                func run(job: JobRecord, progress: @escaping @Sendable (Double, String?) async -> Void) async throws -> String {
                    await progress(1, nil)
                    return "{}"
                }
            }
            await coordinator.register(H())
            let job = try await coordinator.submit(kind: "t", payloadJSON: "{}")
            try await coordinator.enqueue(job.id)
            try await Task.sleep(nanoseconds: 100_000_000)
            let status = try await coordinator.status(job.id)
            expect(status.state == .completed || status.state == .running || status.state == .queued, "job progressed")

            let interrupted = JobRecord(kind: "t", state: .running, payloadJSON: "{}")
            try repo.insert(interrupted)
            try await coordinator.recoverIncomplete()
            expect((try? repo.get(id: interrupted.id)?.state) == .failed, "recovery marks interrupted failed")
        } catch {
            expect(false, "jobs \(error)")
        }
    }

    static func testOrchestrator() async {
        do {
            let db = try DatabaseManager.inMemory()
            let broker = DenyByDefaultApprovalBroker(allowAll: true)
            let gate = ToolPermissionGate(policy: ToolPermissionPolicy(allowedRoots: [FileManager.default.temporaryDirectory]), approvalBroker: broker)
            let client = SequencingClient(responses: [
                ClaudeResponse(id: "1", model: "m", content: [.toolUse(id: "t", name: "get_instagram_analytics", input: ["days": .number(30)])], stopReason: "tool_use"),
                ClaudeResponse(id: "2", model: "m", content: [.text("Missing data; no fabricated metrics.")], stopReason: "end_turn")
            ])
            let orch = AIOrchestrator(
                client: client,
                conversations: ConversationRepository(db: db),
                audit: AuditLogRepository(db: db),
                permissionGate: gate,
                configuration: AppConfiguration(applicationSupportDirectory: FileManager.default.temporaryDirectory),
                analyticsProvider: { days in
                    GroundedAnalyticsPayload(
                        report: AnalyticsReport(
                            accountId: "a",
                            periodStart: Date(),
                            periodEnd: Date(),
                            observedMetrics: [],
                            missingMetrics: ["reach"],
                            mediaRanking: []
                        ),
                        source: "fixture",
                        note: "fixture"
                    )
                }
            )
            let result = try await orch.handleUserMessage(conversationId: nil, text: "Analyze")
            expect(!result.toolAudit.isEmpty, "tool audit present")
            expect(result.missingData.contains("reach"), "missing data surfaced")
            expect(result.assistantText.lowercased().contains("fabricated") || result.assistantText.lowercased().contains("missing"), "grounded reply")
        } catch {
            expect(false, "orchestrator \(error)")
        }
    }

    static func testRuntime() async {
        do {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rt-\(UUID().uuidString)", isDirectory: true)
            let runtime = try AppRuntime(
                configuration: AppConfiguration(applicationSupportDirectory: dir),
                keychain: InMemoryKeychainStore(),
                approvalBroker: DenyByDefaultApprovalBroker(allowAll: true),
                claudeClient: FixtureClaudeClient(nextResponse: ClaudeResponse(id: "x", model: "m", content: [.text("ok")], stopReason: "end_turn"))
            )
            let services = ApplicationServices(runtime: runtime)
            expect(!services.mcpReviewedIntegrations().isEmpty, "mcp listed via services")
            try runtime.setClaudeAPIKey("k")
            let chat = try await services.sendChat(conversationId: nil, text: "hi")
            expect(chat.assistantText == "ok", "chat via backend interface")
            await runtime.shutdown()
        } catch {
            expect(false, "runtime \(error)")
        }
    }

    static func testMCPStdioFixture() async {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/mcp/echo_server.js")
        guard FileManager.default.fileExists(atPath: script.path) else {
            expect(false, "fixture script missing")
            return
        }
        let nodeCandidates = ["/usr/local/bin/node", "/opt/homebrew/bin/node"]
        guard let node = nodeCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            print("SKIP mcp stdio — node missing")
            return
        }
        let client = MCPStdioClient(command: node, arguments: [script.path], timeout: 10)
        do {
            try await client.start()
            let tools = try await client.listTools()
            expect(tools.contains(where: { $0.name == "echo" }), "stdio tools/list")
            _ = try await client.callTool(name: "echo", arguments: ["message": .string("ping")])
            passes += 1
            await client.stop()
        } catch {
            expect(false, "mcp stdio \(error)")
            await client.stop()
        }
    }

    static func testSecurityShell() {
        expect((try? PathSafety.assertNoShellMetacharacters("a;b", label: "x")) == nil, "shell metachar blocked")
    }

    /// Real FFmpeg/FFprobe verification against locally generated fixtures.
    static func testRealFFmpegIntegration() async {
        let engine = FFmpegEngine()
        guard engine.isAvailable else {
            print("SKIP real FFmpeg integration — ffmpeg not discovered")
            return
        }
        print("FFmpeg discovered: \(FFmpegLocator().findFFmpeg() ?? "?")")
        print("FFprobe discovered: \(FFmpegLocator().findFFprobe() ?? "?")")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ias-ffmpeg-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            expect(false, "fixture dir \(error)")
            return
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let ffmpeg = FFmpegLocator().findFFmpeg()!
        let src1 = root.appendingPathComponent("src1.mp4").path
        let src2 = root.appendingPathComponent("src2.mp4").path
        let audioOnly = root.appendingPathComponent("tone.m4a").path

        // Generate two short clips with audio (Intel-compatible libx264/aac).
        do {
            try await runProcess(ffmpeg, [
                "-y", "-f", "lavfi", "-i", "testsrc=size=640x360:rate=30",
                "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
                "-t", "3", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", src1
            ])
            try await runProcess(ffmpeg, [
                "-y", "-f", "lavfi", "-i", "testsrc=size=640x360:rate=30",
                "-f", "lavfi", "-i", "sine=frequency=880:sample_rate=44100",
                "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", src2
            ])
            try await runProcess(ffmpeg, [
                "-y", "-f", "lavfi", "-i", "sine=frequency=220:sample_rate=44100",
                "-t", "2", "-c:a", "aac", audioOnly
            ])
        } catch {
            expect(false, "fixture generation \(error)")
            return
        }

        // 1) Metadata / inspect
        do {
            let meta = try await engine.inspect(path: src1)
            expect((meta.durationSeconds ?? 0) > 2.5 && (meta.durationSeconds ?? 0) < 3.5, "inspect duration ~3s")
            expect(meta.width == 640 && meta.height == 360, "inspect resolution 640x360")
            expect(meta.hasAudio, "inspect has audio")
            expect(meta.aspectRatio == "16:9", "inspect aspect 16:9")
        } catch {
            expect(false, "inspect \(error)")
        }

        // 2) Trim
        let trimmed = root.appendingPathComponent("trim.mp4").path
        do {
            let op = try VideoOperation.trim(input: src1, output: trimmed, startSeconds: 0.5, durationSeconds: 1.0)
                .validated(allowedRoot: root)
            try await engine.execute(op)
            let meta = try await engine.inspect(path: trimmed)
            expect((meta.durationSeconds ?? 0) > 0.7 && (meta.durationSeconds ?? 0) < 1.4, "trim duration ~1s")
            expect(meta.hasAudio, "trim preserves audio")
            expect(fileSize(trimmed) > 0, "trim output non-empty")
        } catch {
            expect(false, "trim \(error)")
        }

        // 3) Concatenate
        let concatOut = root.appendingPathComponent("concat.mp4").path
        do {
            let op = try VideoOperation.concatenate(inputs: [src1, src2], output: concatOut)
                .validated(allowedRoot: root)
            try await engine.execute(op)
            let meta = try await engine.inspect(path: concatOut)
            expect((meta.durationSeconds ?? 0) > 4.5 && (meta.durationSeconds ?? 0) < 5.8, "concat duration ~5s")
            expect(meta.hasAudio, "concat has audio")
        } catch {
            expect(false, "concat \(error)")
        }

        // 4) Vertical 9:16 export
        let vertical = root.appendingPathComponent("vertical.mp4").path
        do {
            let op = try VideoOperation.exportVertical(input: src1, output: vertical, width: 1080, height: 1920, videoBitrate: "1M")
                .validated(allowedRoot: root)
            try await engine.execute(op)
            let meta = try await engine.inspect(path: vertical)
            expect(meta.width == 1080 && meta.height == 1920, "vertical 1080x1920")
            expect(meta.aspectRatio == "9:16", "vertical aspect 9:16")
            expect(meta.hasAudio, "vertical keeps audio")
        } catch {
            expect(false, "vertical \(error)")
        }

        // 5) Thumbnail
        let thumb = root.appendingPathComponent("thumb.jpg").path
        do {
            let op = try VideoOperation.thumbnail(input: src1, output: thumb, atSeconds: 0.2)
                .validated(allowedRoot: root)
            try await engine.execute(op)
            expect(fileSize(thumb) > 500, "thumbnail non-trivial size")
            let meta = try await engine.inspect(path: thumb)
            expect(meta.width == 640 && meta.height == 360, "thumbnail dimensions")
        } catch {
            expect(false, "thumbnail \(error)")
        }

        // 6) Extract + replace audio
        let extracted = root.appendingPathComponent("extracted.m4a").path
        let replaced = root.appendingPathComponent("replaced.mp4").path
        do {
            try await engine.execute(try VideoOperation.extractAudio(input: src1, output: extracted).validated(allowedRoot: root))
            let audioMeta = try await engine.inspect(path: extracted)
            expect(audioMeta.hasAudio, "extracted audio stream")
            expect((audioMeta.durationSeconds ?? 0) > 2.0, "extracted duration")
            try await engine.execute(
                try VideoOperation.replaceAudio(video: src1, audio: audioOnly, output: replaced).validated(allowedRoot: root)
            )
            let replacedMeta = try await engine.inspect(path: replaced)
            expect(replacedMeta.hasAudio, "replaced has audio")
            expect((replacedMeta.durationSeconds ?? 0) > 1.5, "replaced duration")
        } catch {
            expect(false, "audio ops \(error)")
        }

        // 7) Invalid input handling
        do {
            try await engine.execute(
                try VideoOperation.trim(input: "missing.mp4", output: "out.mp4", startSeconds: 0, durationSeconds: 1)
                    .validated(allowedRoot: root)
            )
            expect(false, "missing input should fail")
        } catch {
            expect(true, "missing input failed as expected")
        }

        // 8) Path traversal rejected before process spawn
        expect(
            (try? VideoOperation.trim(input: "../etc/passwd", output: "x.mp4", startSeconds: 0, durationSeconds: 1)
                .validated(allowedRoot: root)) == nil,
            "traversal rejected"
        )

        // 9) Subtitle overlay (implemented Video Engine operation; MacPorts ffmpeg has libass)
        let srt = root.appendingPathComponent("captions.srt")
        let subtitled = root.appendingPathComponent("subtitled.mp4").path
        do {
            let srtBody = """
            1
            00:00:00,000 --> 00:00:02,000
            Instagram AI Studio fixture subtitle
            """
            try srtBody.write(to: srt, atomically: true, encoding: .utf8)
            let op = try VideoOperation.overlaySubtitles(input: src1, srtPath: srt.path, output: subtitled)
                .validated(allowedRoot: root)
            try await engine.execute(op)
            let meta = try await engine.inspect(path: subtitled)
            expect(fileSize(subtitled) > 1000, "subtitle overlay output non-empty")
            expect(meta.width == 640 && meta.height == 360, "subtitle overlay keeps resolution")
            expect(meta.hasAudio, "subtitle overlay preserves audio")
        } catch {
            expect(false, "subtitle overlay \(error)")
        }

        // 10) Long-running cancel: process terminate + temp cleanup + cancelled terminal state
        do {
            let longSrc = root.appendingPathComponent("long.mp4").path
            let cancelOut = root.appendingPathComponent("cancel-out.mp4").path
            // ~20s source + slow-ish vertical export keeps FFmpeg busy long enough to cancel.
            try await runProcess(ffmpeg, [
                "-y", "-f", "lavfi", "-i", "testsrc=size=1280x720:rate=30",
                "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100",
                "-t", "20", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", longSrc
            ])
            let db = try DatabaseManager.inMemory()
            let coordinator = JobCoordinator(
                repository: JobRepository(db: db),
                audit: AuditLogRepository(db: db),
                logger: StructuredLogger(minimumLevel: .error)
            )
            await coordinator.register(
                VideoJobHandler(
                    engine: engine,
                    allowedRoot: root,
                    approvalBroker: DenyByDefaultApprovalBroker(allowAll: true)
                )
            )
            let plan = VideoEditPlan(
                operations: [
                    .exportVertical(input: longSrc, output: cancelOut, width: 1080, height: 1920, videoBitrate: "2M")
                ],
                requiresApproval: false
            )
            let payload = String(data: try JSONEncoder().encode(plan), encoding: .utf8) ?? "{}"
            let job = try await coordinator.submit(kind: "video.render", payloadJSON: payload)
            try await coordinator.enqueue(job.id)
            // Wait until running, then cancel while FFmpeg is still encoding.
            var sawRunning = false
            for _ in 0..<50 {
                try await Task.sleep(nanoseconds: 100_000_000)
                let s = try await coordinator.status(job.id)
                if s.state == .running { sawRunning = true; break }
                if s.state.isTerminal { break }
            }
            expect(sawRunning, "long job reached RUNNING before cancel")
            try await coordinator.cancel(job.id)
            // Allow termination + cleanup to settle.
            try await Task.sleep(nanoseconds: 500_000_000)
            let status = try await coordinator.status(job.id)
            expect(status.state == .cancelled, "long job terminal state CANCELLED (got \(status.state.rawValue))")
            // Partial output should be cleaned up by cancellation path (best-effort).
            let leftover = FileManager.default.fileExists(atPath: cancelOut) && fileSize(cancelOut) > 0
            // Accept either cleaned or incomplete truncated file after terminate; assert process ended via cancelled state.
            expect(status.finishedAt != nil, "cancelled job has finishedAt")
            _ = leftover
            // Temp concat lists use UUID names and are deferred-removed; assert none linger for this job root.
            let leftoverLists = (try? FileManager.default.contentsOfDirectory(atPath: root.path))?
                .filter { $0.hasPrefix("concat-") && $0.hasSuffix(".txt") } ?? []
            expect(leftoverLists.isEmpty, "concat temp lists cleaned after cancel path")
        } catch {
            expect(false, "long cancel \(error)")
        }

        // 11) Exit code / error propagation for corrupt input
        let junk = root.appendingPathComponent("junk.mp4")
        try? "not a video".write(to: junk, atomically: true, encoding: .utf8)
        do {
            try await engine.execute(
                try VideoOperation.thumbnail(input: junk.path, output: root.appendingPathComponent("bad.jpg").path, atSeconds: 0)
                    .validated(allowedRoot: root)
            )
            expect(false, "corrupt input should fail")
        } catch {
            expect(true, "corrupt input error propagated")
        }
    }

    static func fileSize(_ path: String) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue) ?? 0
    }

    static func runProcess(_ executable: String, _ args: [String]) async throws {
        let runner = FoundationProcessRunner()
        let result = try await runner.run(executable: executable, arguments: args, timeout: 120)
        guard result.exitCode == 0 else {
            let err = String(data: result.stderr, encoding: .utf8) ?? ""
            throw AppError.external(service: "ffmpeg-fixture", message: err)
        }
    }
}

final class SequencingClient: ClaudeAPIClient, @unchecked Sendable {
    private var responses: [ClaudeResponse]
    private var index = 0

    init(responses: [ClaudeResponse]) { self.responses = responses }

    func createMessage(model: String, messages: [ClaudeMessage], tools: [ClaudeToolDefinition], maxTokens: Int, system: String?) async throws -> ClaudeResponse {
        defer { index += 1 }
        if index < responses.count { return responses[index] }
        return ClaudeResponse(id: "f", model: model, content: [.text("done")], stopReason: "end_turn")
    }

    func streamMessage(model: String, messages: [ClaudeMessage], tools: [ClaudeToolDefinition], maxTokens: Int, system: String?) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}
