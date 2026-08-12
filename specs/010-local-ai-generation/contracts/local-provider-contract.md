# Local Provider Contract

## Service construction

| Provider | Factory result | Local source |
|---|---|---|
| MLX | `MLXHandler` | User-selected local model directory |
| Core ML LLM | `CoreMLTextGenerationService` | User-selected compiled model directory |
| Hugging Face | `HuggingFaceService` | User-installed compatible model assets |
| Ollama | `OllamaHandler` | User-configured loopback/private-LAN endpoint |
| LM Studio | `LMStudioHandler` | User-configured loopback/private-LAN endpoint |

## Request behavior

- All provider implementations conform to the existing app provider protocol.
- Local inference must use the standard cancellable chat request lifecycle.
- A selected model must be compatible with the requested text, vision, or image-generation capability before dispatch.
- Incremental streaming must not repeat already emitted final content.

## Failure behavior

- Missing assets, unreadable paths, unreachable endpoints, malformed responses, and unsupported capabilities return actionable errors.
- Failure/cancellation must not replace draft content, corrupt a persisted chat, or open an unrelated chat.
- Errors and diagnostics must not reveal API credentials, authorization values, or user prompt content.

## Endpoint policy

- Local server endpoints may be loopback or private-LAN destinations.
- This feature does not introduce public endpoint support or telemetry.
