# Architecture

## Layers

Ordered from highest (closest to user) to lowest (foundational). Higher layers may depend on lower layers but not the reverse.

### Apps
Entry points, UI, and CLI. Depends on: Features, Services, SDKs.
- **AIDevToolsKitCLI** — Command-line interface for evals, planning, and chat
- **AIDevToolsKitMac** — macOS SwiftUI application

### Features
Business logic orchestration and use cases. Depends on: Services, SDKs.
- **ArchitecturePlannerFeature** — Architecture-driven planning with requirements, guidelines, and conformance scoring
- **ChatFeature** — Unified chat protocol, provider adapters, and use cases for any AI provider
- **EvalFeature** — Eval execution, grading, and result analysis
- **MarkdownPlannerFeature** — Plan generation and phase execution
- **SkillBrowserFeature** — Repository and skill browsing

### Services
Domain services and data persistence. Depends on: SDKs.
- **ArchitecturePlannerService** — SwiftData models and persistence for architecture-driven planning
- **DataPathsService** — Application data directory management
- **EvalService** — Eval case storage and artifact management
- **MarkdownPlannerService** — Plan settings, plan entry model, architecture diagram model
- **ProviderRegistryService** — AI provider registration and discovery
- **SkillService** — Skill configuration and repository settings

### SDKs
Foundational utilities and external system interfaces. No internal dependencies.
- **AnthropicSDK** — Anthropic API client wrapper
- **ClaudeCLISDK** — Claude CLI process management
- **ClaudePythonSDK** — Claude Python SDK process management
- **CodexCLISDK** — Codex CLI process management
- **ConcurrencySDK** — Concurrency utilities
- **EnvironmentSDK** — Environment variable access
- **EvalSDK** — Eval case and assertion data models
- **GitSDK** — Git operations
- **LoggingSDK** — Logging configuration
- **RepositorySDK** — Repository configuration and storage
- **SkillScannerSDK** — Skill file scanning and parsing

## Dependency Rules
- Apps → Features, Services, SDKs
- Features → Services, SDKs
- Services → SDKs
- SDKs → (none)
