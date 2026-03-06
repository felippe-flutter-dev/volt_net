# Changelog

All notable changes to this project will be documented in this file.

## 2.1.1 (Pending)

### Added
- **Integrated Logging System**: Added a built-in logger that uses `DebugUtils` to display structured Request/Response data.
- **CURL Generation**: Every network request now automatically generates a ready-to-use CURL command in the console when logging is enabled.
- **Enhanced Documentation**: Refactored the entire codebase with triple-slash (`///`) documentation comments and usage examples in English.

### Changed
- **Logging Flag**: Added `logging` parameter to `Volt.initialize()` to control the output of internal network logs.
- **DebugUtils Integration**: Unified all request handlers (`GET`, `POST`, `PUT`, `DELETE`) to use `DebugUtils` for visual consistency.
- **English Standards**: Translated all internal code comments and log labels to English.

### Fixed
- **Binding Initialization in Tests**: Fixed `volt_log_test.dart` to properly initialize Flutter bindings and handle sync monitoring during unit tests.

## 2.0.0 - 2026-03-04

### Added
- **Full REST Support**: Implementation of `PutRequest` and `DeleteRequest` with the same resilience and cache patterns as GET/POST.
- **Enterprise Resilience**: Introduced `resilientBatch` in `PostRequest` with automatic rollback on failure and idempotency key support.
- **Advanced Offline Sync**: `SyncQueueManager` now persists `PUT` and `DELETE` operations.
- **Multipart Media Sync**: Added capability to keep files in the sync queue using `VoltFile` for deferred offline uploads.
- **VoltInterceptor**: New interceptor system for global request/response modification and centralized error handling.
- **New Models**: Introduced `VoltFile` for file abstractions and improved `ResultModel<T>` with isolate-based parsing.
- **Testing Suite**: Achieved ~95% code coverage with new integration and edge-case tests.
- **Utilities**: Added `Debouncer` for high-frequency event management.

### Changed
- **BREAKING**: Completely removed legacy naming ("EcoloteNetwork") in favor of `VoltNet`.
- **BREAKING**: Refactored `CacheManager`, `SyncQueueManager`, and Request classes to support constructor-based Dependency Injection.
- **Error Mapping**: `ThrowHttpException` now maps native exceptions (Socket, Timeout, Client) into typed `VoltNetException` subclasses.
- **Deterministic Cache**: Replaced `.hashCode` with a collision-resistant string-based key strategy.
- **Standardization**: All debug logs and messages are now in English for global compatibility.
- **URL Building**: Integrated `Uri.resolve()` for more reliable absolute path construction.

### Fixed
- Handling of `null` and empty bodies in `ResultApi`.
- Persistence issues with multipart fields in the offline sync queue.
- Isolate parsing reliability for complex or deeply nested JSON structures.
- Compilation errors in `CacheManager.clearAll`.
