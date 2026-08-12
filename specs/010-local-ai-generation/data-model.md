# Data Model: Local AI and Generation

## Persistence Impact

**No Core Data schema change.** Existing chats, messages, services, and Keychain-backed credentials remain compatible.

## Existing Entities and Value Objects

### API service configuration
- **Ownership**: Existing persisted provider configuration.
- **Relevant values**: provider identity, model identifier or local model path, and endpoint where applicable.
- **Rules**: A configured local provider resolves via `APIServiceFactory`; invalid paths/endpoints do not modify chat history.

### Local model metadata
- **Ownership**: Existing `ModelMetadata` cache/value model.
- **Relevant values**: model identifier, provider label, capabilities, pricing classification, and source.
- **Rules**: Local models remain self-hosted/free; unavailable metadata refreshes never erase the current usable selection.

### Local model assets
- **Ownership**: User-managed filesystem location, outside Core Data.
- **Relevant values**: model package/assets, tokenizer/configuration, and model-specific support files.
- **Rules**: Validate existence/readability and required assets before loading. Do not copy weights into chat persistence or logs.

## State Transitions

1. Configured → Validated: selected service/path/endpoint passes local requirements.
2. Validated → Generating: request starts through the existing cancellable provider workflow.
3. Generating → Completed: response/media is attached through the existing assistant-message route.
4. Generating → Cancelled/Failed: draft and existing conversation remain unchanged; user receives a privacy-safe error.
