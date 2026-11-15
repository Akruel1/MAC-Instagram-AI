import XCTest
@testable import Core

final class UIApprovalBrokerTests: XCTestCase {
    func testResolveApprovesPendingRequest() async throws {
        let broker = UIApprovalBroker()
        let request = ApprovalRequest(category: "jobs", action: "render", summary: "Export clip")
        async let decision = broker.requestApproval(request)
        try await Task.sleep(nanoseconds: 50_000_000)
        await broker.resolve(id: request.id, decision: .approved)
        let result = try await decision
        XCTAssertEqual(result, .approved)
    }

    func testPendingStreamYieldsHead() async throws {
        let broker = UIApprovalBroker()
        let request = ApprovalRequest(category: "mcp", action: "call", summary: "Call tool")
        let stream = await broker.pendingApprovals()
        let expectation = expectation(description: "pending")
        let task = Task {
            for await pending in stream {
                if pending?.id == request.id {
                    expectation.fulfill()
                    break
                }
            }
        }
        async let decision = broker.requestApproval(request)
        await fulfillment(of: [expectation], timeout: 2)
        await broker.resolve(id: request.id, decision: .denied)
        let result = try await decision
        XCTAssertEqual(result, .denied)
        task.cancel()
    }
}
