# Helm

Helm is a native Apple platform client for OpenClaw.

## Vision

Helm begins as the cleanest native way to interact with an OpenClaw-powered assistant on Apple devices. Over time, it should grow into a broader control surface for connection management, operational visibility, approvals, and assistant operations.

Helm is not meant to become a generic chat shell. The long-term product is a cockpit. The product starts with chat because the core assistant loop must feel trustworthy before broader control-plane features are added.

## Current MVP Scope

The first milestone is intentionally narrow:

- configure one OpenClaw gateway
- connect and disconnect cleanly
- establish one active runtime chat context
- send a message
- receive a response
- persist lightweight connection settings only

The MVP is successful only if the first conversation feels like a real product surface, not a debug terminal.

Out of scope for the MVP:
- dashboard surfaces
- durable chat history across launches
- multi-gateway management
- CloudKit sync
- notifications
- attachments
- broader assistant administration features

## Design Principles

- Native Apple UX first
- Clarity over visual noise
- Restrained polish
- Excellent readability
- Honest system status
- Small, durable architecture

Helm should feel like a modern Apple app, not a web UI wrapped in SwiftUI. Materials, translucency, and depth should be used carefully and only where they improve hierarchy and calm.

## Integration Direction

Helm uses an internal integration boundary to isolate OpenClaw-specific networking from app state and UI.

That boundary should be shaped around what Helm needs to do, not around unverified assumptions about the exact OpenClaw wire contract. Transport, session, and streaming semantics should be validated against real OpenClaw docs, source, or runtime behavior before they are treated as settled facts in the codebase.

## Tech Stack

- SwiftUI
- Swift Concurrency
- URLSession
- Swift Testing for unit and integration-style tests
- XCTest for UI tests
- UserDefaults and Keychain for lightweight local storage

## Development Direction

Helm is iOS-first. The initial architecture should leave room for future iPadOS and macOS expansion, richer session handling, dashboard surfaces, approvals, notifications, and possible sync.

Those future directions should not dominate the MVP.

The project should prefer:
- simple types over clever abstractions
- explicit boundaries over hidden magic
- native Apple APIs over heavy dependencies
- vertical slices over broad scaffolding
- validated integration knowledge over speculative protocol design

## Roadmap

1. Foundation: docs, app structure, mock integration seam, root empty state.
2. Connection: gateway settings, persistence, connect/disconnect lifecycle.
3. Transport: live OpenClaw adapter, validated request/stream handling.
4. Chat: transcript UI, send/receive loop, retry and recovery behavior.
5. Polish: accessibility, status language, contextual errors, tests.
6. Expansion: history, dashboard surfaces, approvals, and broader control features.

## Contributing

Please keep changes small, testable, and product-minded.

Expectations:
- follow Apple-native UX patterns
- keep architecture explicit and lightweight
- avoid speculative abstractions
- validate integration assumptions before cementing them
- update docs when product direction or guardrails change
- prefer incremental vertical slices over large refactors

## Status

Helm is at the beginning of its lifecycle. The repository is establishing the product and architectural foundation for the first real iOS milestone.
