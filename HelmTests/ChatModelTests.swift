import Foundation
import Testing

@testable import Helm

struct ChatModelTests {
    @MainActor
    @Test
    func sendWhileDisconnectedShowsContextualError() async {
        let model = ChatModel()
        model.draft = "Hello"

        await model.send(using: nil, connectionState: .disconnected)

        #expect(model.messages.isEmpty)
        #expect(model.composerError == .connectionRequired())
    }

    @MainActor
    @Test
    func streamedResponseAssemblyProducesAssistantMessage() async throws {
        let client = StubChatClient(sendPlans: [
            .init(events: [.started, .delta("Helm "), .delta("reply"), .completed]),
            .init(events: [.started, .delta("Second reply"), .completed]),
        ])
        let model = ChatModel()
        model.draft = "Hello"

        await model.send(using: client, connectionState: .connected)

        #expect(model.messages.count == 2)
        #expect(model.messages[0].role == .user)
        #expect(model.messages[1].role == .assistant)
        #expect(model.messages[1].body == "Helm reply")

        model.draft = "Again"
        await model.send(using: client, connectionState: .connected)

        #expect(await client.prepareCallCount() == 1)
    }

    @MainActor
    @Test
    func failedSendLeavesMessageRetryable() async {
        let client = StubChatClient(sendPlans: [
            .init(events: [.started, .failed(.sendFailed(details: "Mock failure"))]),
        ])
        let model = ChatModel()
        model.draft = "This will fail"

        await model.send(using: client, connectionState: .connected)

        #expect(model.messages.first?.isRetryable == true)
        #expect(model.composerError?.title == "Message failed")
    }

    @MainActor
    @Test
    func resetRuntimeStateClearsTranscriptAndContext() {
        let model = ChatModel()
        model.messages = PreviewFixtures.conversation
        model.draft = "Draft"
        model.runtimeContext = .ephemeral(prefix: "reset")

        model.resetRuntimeState()

        #expect(model.messages.isEmpty)
        #expect(model.draft.isEmpty)
        #expect(model.runtimeContext == nil)
    }
}

private struct SendPlan: Sendable {
    let events: [AssistantStreamEvent]
}

private actor StubChatClient: OpenClawClient {
    private var sendPlans: [SendPlan]
    private var prepareCalls = 0
    private let runtimeContext = ChatRuntimeContext.ephemeral(prefix: "stub")

    init(sendPlans: [SendPlan]) {
        self.sendPlans = sendPlans
    }

    func connect(using configuration: GatewayConfiguration) async throws {}

    func disconnect() async {}

    func prepareChatContext() async throws -> ChatRuntimeContext {
        self.prepareCalls += 1
        return self.runtimeContext
    }

    func sendMessage(
        _ text: String,
        context: ChatRuntimeContext
    ) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        let plan = self.sendPlans.isEmpty ? SendPlan(events: []) : self.sendPlans.removeFirst()

        return AsyncThrowingStream { continuation in
            Task {
                for event in plan.events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    func prepareCallCount() -> Int {
        self.prepareCalls
    }
}
