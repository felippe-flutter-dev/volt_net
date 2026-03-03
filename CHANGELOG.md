# Changelog
All notable changes to this project will be documented in this file.

## \[Unreleased\]
### Added
- **Full REST Support**: `SyncQueueManager` now supports `PUT` and `DELETE` requests in the offline sync queue.
- **Dependency Injection (DI)**: Refactored `CacheManager` and `SyncQueueManager` to support constructor-based dependency injection for better testability.

### Changed
- **Robust Cache Keys**: Replaced `.hashCode` with a deterministic, collision-resistant string-based key strategy.
- **Typed Error Handling**: Replaced string-based error checking with proper type-based catch blocks (`http.ClientException`).
- **Standardized Naming**: Completely removed legacy naming ("EcoloteNetwork") in favor of **VoltNet**.
- **Global Logs**: All debug logs and messages have been standardized to English for global compatibility.
- **Reliable URL Building**: Integrated `Uri.resolve()` for absolute path construction, replacing error-prone manual concatenation.

### Fixed
- Compilation errors in `CacheManager.clearAll` method.
- Improved Isolate parsing reliability.

## \[1.0.2\] - 2026-03-02
### Fixed
- Automated versioning pipeline fixes and Cider integration.

## \[1.0.1\] - 2026-03-02
### Added
- Initial stable release with Hybrid Cache (L1/L2), Isolates, and Offline-First engine.

## 1.1.0 - 2026-03-03
### Added
- feat: implement Randal Schwartz refinements
