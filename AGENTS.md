# AGENTS.md

## Product Intent

Helm is a native Apple platform client for OpenClaw.

The long-term goal is a calm, premium control surface for interacting with and eventually managing a personal AI assistant. That future may include session history, assistant management, dashboard and status views, approvals, notifications, persistence, sync, and expansion to iPadOS and macOS.

Do not build that future all at once.

## Current MVP

The current milestone is only this vertical slice:

- configure one OpenClaw gateway
- connect
- disconnect
- establish one active runtime chat context
- send a message
- receive a response
- show the conversation in a product-quality way

Defaults for this stage:
- single saved gateway profile
- lightweight config persistence only
- one in-memory active chat runtime
- stream-capable reply pipeline
- iOS-first SwiftUI app

Not part of the MVP:
- multi-session history UI
- dashboard surfaces
- approvals and operational controls
- CloudKit sync
- multi-gateway management
- attachments and broader assistant tooling

## Product Quality Guardrail

The first conversation surface is the product.

Do not let Helm feel like:
- a debug terminal
- a transport inspector
- a raw API harness
- a placeholder chat screen with connection controls bolted on

Prioritize:
- calm empty states
- trustworthy status language
- contextual errors instead of alert-heavy UX
- readable transcript presentation
- retry and recovery behavior that keeps the user oriented

## Architecture Guardrails

- Keep the app small and explicit.
- Prefer one app target with feature-first folders until there is clear pressure to split modules.
- Use `@MainActor @Observable` models for app and feature state.
- Keep transport behind a thin internal `OpenClawClient` boundary with one live implementation and one mock.
- Use `URLSession` and Swift concurrency.
- Use `UserDefaults` for non-secret config and Keychain for secrets.
- Do not keep or introduce SwiftData unless durable product data actually exists.
- Do not let CloudKit influence MVP structure yet.
- Do not add TCA, reducer frameworks, Combine-heavy patterns, or third-party architecture frameworks without a compelling reason.

## OpenClaw Integration Guardrails

Treat `OpenClawClient` as a Helm-internal boundary, not as proof of the official OpenClaw protocol model.

This means:
- do not assume OpenClaw definitely has a specific session lifecycle unless validated
- do not encode speculative wire semantics into type names prematurely
- do not invent protocol nouns just because the app needs internal structure
- validate behavior against real OpenClaw docs, source, or runtime before hardening integration assumptions

Internal app concepts may describe Helm’s needs:
- connection readiness
- runtime chat context
- streaming response assembly

Those concepts may later map to validated OpenClaw concepts, but they should not pretend to be source-of-truth protocol definitions before verification.

## Coding Style Expectations

- Prefer small, plainly named types.
- Prefer one primary type per file.
- Make side effects explicit.
- Keep logic out of SwiftUI view bodies.
- Prefer value types for models unless reference semantics are genuinely needed.
- Add comments only when a decision is not obvious from the code.
- Choose clarity over cleverness.

## SwiftUI Expectations

- Build the iOS MVP around `NavigationStack`.
- Use native presentation patterns: sheets, alerts, confirmation dialogs, toolbars, grouped forms.
- Use `ContentUnavailableView` when it fits.
- Keep state ownership clear and local.
- Compose focused subviews rather than giant all-in-one screens.
- Respect Dynamic Type, VoiceOver, Reduce Motion, and standard tap target sizes.
- Avoid hard-coded layout values unless they are part of a shared token set.

## Design Expectations

Helm should feel like a modern Apple app, not a web dashboard skinned in SwiftUI.

Aim for:
- clarity
- calm hierarchy
- restrained polish
- excellent readability
- native interaction patterns
- honest status communication

Use translucency and Liquid Glass ideas carefully:
- good places: connection chrome, composer housing, subtle header and status surfaces
- bad places: transcript backgrounds, dense forms, or anywhere material harms contrast

Avoid:
- noisy gradients
- decorative AI aesthetics
- oversized floating cards
- custom controls where system controls are stronger
- diagnostic noise in the main chat experience

## How To Approach Changes

- Work in vertical slices that produce user-visible progress.
- Prefer the smallest change that moves the product forward cleanly.
- If you introduce a new abstraction, explain the immediate concrete benefit.
- If a future-facing change does not help the MVP today, do not add it yet.
- When changing product direction, also update `README.md` and this file.

## Error and Recovery Expectations

Prefer contextual recovery over interruption.

Examples:
- form validation errors stay in forms
- connection failures stay near connection UI
- failed messages stay in transcript context with retry
- connection-lost states should keep the user oriented and offer a clear path to reconnect

Use alerts sparingly and only when blocking attention is truly required.

## Future Expansion Without MVP Contamination

Keep the codebase ready for future sessions, dashboards, approvals, notifications, iPadOS, macOS, and possible CloudKit sync by doing only these things now:
- choose clear names
- keep model boundaries explicit
- isolate transport and persistence seams
- avoid baking speculative integration details into shared models

Do not scaffold future features preemptively.

## Testing Expectations

- Use Swift Testing for model, store, and client behavior.
- Use XCTest for UI flows.
- Prefer mocks and deterministic streams for repeatable tests.
- Cover connection success and failure transitions.
- Cover repeated connect and disconnect taps.
- Cover send while disconnected.
- Cover streamed reply assembly.
- Cover retry behavior for failed sends.
- Cover disconnect clearing runtime chat state while preserving saved config.

## Agent Workflow

Before changing code:
- read nearby feature files and tests
- understand the current milestone
- preserve product clarity
- avoid adding debug-first UI to main surfaces
- check whether any OpenClaw integration assumption is actually validated

When proposing work:
- describe the user-visible outcome
- describe the architectural impact
- keep changes incremental
- call out any unverified integration assumptions explicitly

When in doubt, choose the simpler implementation that keeps Helm more native, more readable, and less speculative.
