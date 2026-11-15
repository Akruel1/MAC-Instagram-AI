import XCTest
@testable import MCP
@testable import Core

final class MCPTests: XCTestCase {
    func testRegistryOnlyReviewed() throws {
        let registry = MCPRegistry()
        XCTAssertNoThrow(try registry.descriptor(id: "fixture-echo"))
        XCTAssertThrowsError(try registry.descriptor(id: "arbitrary-unreviewed-package"))
    }

    func testInMemoryTransportTools() async throws {
        let transport = MCPInMemoryTransport()
        try await transport.start()
        let list = try await transport.send(request: MCPRequest(method: "tools/list"))
        guard case .object(let obj)? = list.result, case .array(let tools)? = obj["tools"] else {
            return XCTFail("Expected tools")
        }
        XCTAssertFalse(tools.isEmpty)
        let call = try await transport.send(request: MCPRequest(method: "tools/call", params: [
            "name": .string("echo"),
            "arguments": .object(["message": .string("hi")])
        ]))
        XCTAssertNil(call.error)
        await transport.stop()
        let healthy = await transport.isHealthy()
        XCTAssertFalse(healthy)
    }

    func testPermissionGateDeniesDisallowedCategory() async {
        let broker = DenyByDefaultApprovalBroker(allowAll: true)
        var policy = ToolPermissionPolicy(allowedRoots: [FileManager.default.temporaryDirectory])
        policy.allowedCategories = [.networkAccess]
        let gate = ToolPermissionGate(policy: policy, approvalBroker: broker)
        do {
            try await gate.authorize(toolName: "publish", category: .instagramPublishing, summary: "publish")
            XCTFail("Should deny")
        } catch {
            // expected
        }
    }
}
