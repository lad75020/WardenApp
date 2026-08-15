# Provider reference

WardenApp supports hosted providers, local runtimes, and specialized media paths through one internal Swift service abstraction. Provider behavior is implemented in `Warden/Utilities/APIHandlers/` and selected by `APIServiceFactory`.

## Internal contract

`APIService` in `APIProtocol.swift` defines the internal integration surface:

- `name`, `baseURL`, `session`, and `model`.
- Non-streaming message sending.
- Streaming message sending as an async throwing stream.
- Model discovery.
- Request construction.
- Full-response parsing.
- Delta/stream parsing.

`APIError` maps transport and HTTP failures into user-safe categories such as request failure, invalid response, decoding failure, unauthorized, rate limited, server error, unknown error, and missing service.

This is an in-process Swift protocol. WardenApp does not expose this protocol as a public HTTP API.

## Provider types in the current configuration

The following provider types are defined by the current `AppConstants.defaultApiConfigurations` table. Model availability and remote endpoint behavior can change independently of the application defaults.

| Type | Display/provider role | Current implementation path | Typical capability |
| --- | --- | --- | --- |
| `chatgpt` | OpenAI-compatible hosted chat | `ChatGPTHandler` / `BaseAPIHandler` | Text chat and streaming; image input where configured |
| `chatgpt image` | OpenAI image generation | Image-capable provider path | Image generation and image input where configured |
| `claude` | Anthropic Claude | `ClaudeHandler` | Text chat with provider-specific request/response format |
| `gemini` | Google Gemini | `GeminiHandler` | Text and configured image-capable requests |
| `veo` | Google video generation | `VeoHandler` | Video generation path; no ordinary image-upload flag |
| `deepseek` | DeepSeek | `DeepseekHandler` | Text chat and provider-specific models |
| `openrouter` | OpenRouter gateway | `OpenRouterHandler` | OpenAI-style multi-model access |
| `perplexity` | Perplexity | `PerplexityHandler` | Text chat and search-oriented remote models |
| `mistral` | Mistral | `MistralHandler` | Text chat |
| `groq` | OpenAI-compatible hosted endpoint | ChatGPT-compatible handler path | Text chat and streaming where endpoint supports it |
| `xai` | xAI | ChatGPT-compatible handler path | Text chat and streaming where endpoint supports it |
| `ollama` | Local Ollama runtime | `OllamaHandler` | Local text and configured local capabilities |
| `lmstudio` | Local LM Studio server | `LMStudioHandler` | OpenAI-compatible local text and model discovery |
| `huggingface` | Local Hugging Face path | local model path | Local inference when assets are available |
| `coreml llm` | Local Core ML text generation | local Core ML path | Local text generation from supported assets |
| `mlx` | Local MLX runtime | `MLXHandler` | Local text and supported image generation flows |

The factory and source files are authoritative if a display name, handler relationship, or capability differs from this table.

## Endpoint and transport rules

`APIServiceManager` and the shared `APIService` behavior apply the following rules:

- An endpoint must be syntactically valid before save, test, or discovery.
- Credential-bearing remote requests must use HTTPS.
- Credential-bearing loopback/local HTTP can be permitted by the explicit local transport rule.
- Sensitive credentials must not be placed in URLs.
- Request and resource timeouts use the application request timeout, currently 180 seconds.
- Standard URL sessions disable ordinary caching and use bounded connection counts.
- Streaming is disabled for image providers and for model identifiers that use the image-generation path.

## Service lifecycle

A saved service has a stable UUID and stores non-secret values in Core Data. A credential is referenced by an identifier and stored through `TokenManager` in the Keychain.

The lifecycle is:

1. Create or duplicate a service.
2. Apply provider-compatible defaults.
3. Validate the endpoint.
4. Load or enter the credential through the UI.
5. Test the connection.
6. Refresh or manually select a model.
7. Save the configuration.
8. Optionally set it as the default.

Deleting a service does not remove chats that reference it. The chat remains available for explicit repair or deletion.

## Model discovery

Discovery is optional and provider-specific:

- Some hosted providers expose a model endpoint or known model list.
- Ollama and LM Studio can discover local models when their local server is available.
- Image, video, Core ML, MLX, and Hugging Face entries may use fixed or local model values rather than remote discovery.
- A failed refresh preserves the previously selected model.
- Custom model identifiers are accepted only where the provider UI and handler support them.

Model metadata is cached separately and must remain non-sensitive. Missing or stale metadata does not automatically make a previously valid selection unusable.

## Streaming behavior

A provider may support either streamed or non-streamed response handling. The selected service configuration and provider/model capability determine the path.

For streams:

- Handlers parse provider-specific event formats into the shared delta result.
- `ChatStreamingSession` handles arbitrary transport chunk boundaries.
- Keep-alive/comment events are ignored.
- Cancellation stops appending stale content.
- The final assistant response is persisted once.

For non-streaming services, the UI still exposes waiting, success, and failure states but does not pretend that the response is incremental.

## Attachments and media capability

The service configuration includes whether image uploads are supported. `DatabasePatcher` updates older service records from the current provider defaults where appropriate.

Media requests must be routed to a provider/model that supports the requested capability. A text-only or incompatible local model must not be used as a silent fallback for image, vision, or video generation.

## Error mapping

The shared handler path maps common HTTP categories:

- `401`: unauthorized.
- `429`: rate limited.
- Other `4xx`: client/provider error.
- `5xx`: server error.
- No usable HTTP response: invalid response or request failure.
- Invalid body: decoding failure.

User-facing errors must be actionable but must not include credentials, authorization headers, complete prompts, or raw response bodies.

## Adding or changing a provider

1. Add or revise the provider default in `AppConstants.swift`.
2. Choose whether an existing compatible handler is sufficient.
3. Add a dedicated handler only when request/response behavior differs materially.
4. Register the type in `APIServiceFactory.swift`.
5. Add transport, authentication, response, streaming, model discovery, and cancellation tests.
6. Confirm image/video/stream flags are accurate.
7. Update [Functional requirements](functional-requirements.md), [Feature reference](feature-reference.md), and this document.

Do not log raw keys, authorization headers, provider bodies, or private prompts while diagnosing a provider.
