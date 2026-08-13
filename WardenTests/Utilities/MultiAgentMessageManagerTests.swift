import XCTest
@testable import Warden

@MainActor
final class MultiAgentMessageManagerTests: XCTestCase {
    func testCappedServicesUsesSharedMaximum() {
        let services = [1, 2, 3, 4]

        let capped = MultiAgentMessageManager.cappedServices(services)

        XCTAssertEqual(capped.count, AppConstants.MultiAgent.maxConcurrentServices)
        XCTAssertEqual(capped, [1, 2, 3])
    }

    func testAgentResponseCompletionAndFailureTransitions() {
        var response = MultiAgentMessageManager.AgentResponse(
            serviceName: "Fixture",
            serviceType: "fixture",
            model: "fixture-model"
        )

        response.markCompleted()
        XCTAssertTrue(response.isComplete)
        XCTAssertNil(response.error)

        response.markFailed(.unknown("fixture failure"))
        XCTAssertTrue(response.isComplete)
        assertUnknownError(response.error, equals: "fixture failure")
    }

    func testCancellationFinalizesOnlyIncompleteResponsesWithErrors() {
        var responses = [
            MultiAgentMessageManager.AgentResponse(serviceName: "First", serviceType: "fixture", model: "one"),
            MultiAgentMessageManager.AgentResponse(serviceName: "Second", serviceType: "fixture", model: "two")
        ]
        responses[1].markCompleted()

        MultiAgentMessageManager.finalizeCancellation(of: &responses, message: "Request cancelled by user")

        XCTAssertTrue(responses.allSatisfy(\.isComplete))
        assertUnknownError(responses[0].error, equals: "Request cancelled by user")
        XCTAssertNil(responses[1].error)
    }

    private func assertUnknownError(_ error: APIError?, equals expectedMessage: String, file: StaticString = #filePath, line: UInt = #line) {
        guard case .unknown(let message)? = error else {
            return XCTFail("Expected unknown API error", file: file, line: line)
        }
        XCTAssertEqual(message, expectedMessage, file: file, line: line)
    }
}
