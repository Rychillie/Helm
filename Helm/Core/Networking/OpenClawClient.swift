import Foundation

typealias OpenClawClientFactory =
    @MainActor @Sendable (GatewayConfiguration, String?, @escaping @Sendable (UserFacingError) -> Void) -> any OpenClawClient

protocol OpenClawClient: Sendable {
    func connect(using configuration: GatewayConfiguration) async throws
    func disconnect() async
    func prepareChatContext() async throws -> ChatRuntimeContext
    func sendMessage(
        _ text: String,
        context: ChatRuntimeContext
    ) -> AsyncThrowingStream<AssistantStreamEvent, Error>
}
