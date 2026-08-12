# Research: Local AI and Generation

## Decision 1: Retain protocol-based local-provider integration

- **Decision**: Keep MLX, Core ML, Hugging Face, Ollama, and LM Studio behind the existing `APIService`/`APIProtocol` path and select them only through `APIServiceFactory`.
- **Rationale**: This preserves chat lifecycle, cancellation, persistence, and error handling without adding a parallel local-model subsystem.
- **Alternatives considered**: A separate local inference manager was rejected because it would duplicate provider selection and stream ownership.

## Decision 2: Private endpoint boundary

- **Decision**: Treat loopback and private-LAN endpoints as local-provider endpoints; do not add public endpoint support under this feature.
- **Rationale**: This implements the clarified user choice while preserving a bounded privacy model.
- **Alternatives considered**: Loopback-only was rejected by the user. Arbitrary public endpoints are outside scope because they change the disclosure boundary.

## Decision 3: Capability validation before dispatch

- **Decision**: Use the existing local model type/asset checks and add deterministic routing/capability helpers where needed before starting inference.
- **Rationale**: A missing asset or unsupported text/vision/image request should fail before it changes chat selection or creates misleading output.
- **Alternatives considered**: Letting each runtime fail after dispatch was rejected because errors are inconsistent and harder to test.

## Decision 4: No persistence migration

- **Decision**: Reuse existing service configuration and model metadata structures; make no Core Data schema change.
- **Rationale**: Local paths and provider selections already persist through the existing configuration path. Invalid legacy paths can surface recoverable runtime errors.
- **Alternatives considered**: Adding model-install inventory entities was rejected as model download/inventory management is out of scope.

## Decision 5: Deterministic test seams

- **Decision**: Cover factory selection, local metadata identity, endpoint classification, Core ML asset validation, and MLX capability classification using temporary fixtures and no live model/server.
- **Rationale**: The constitution requires tests without credentials and CI-safe hardware-independent evidence.
- **Alternatives considered**: Live Ollama/MLX inference tests were rejected due to model availability and hardware variability.
