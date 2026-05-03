# Codexkit 0.2.3 Release Notes

Release date: 2026-05-04 (Asia/Shanghai)
Tag: `v0.2.3`

## Summary

This release improves Codexkit's bundled API Service integration without upgrading the bundled CLIProxyAPI runtime itself. The bundled service remains `CLIProxyAPI v6.9.29`; the changes are host-side adaptations in Codexkit for better observability, routing reliability, and update-state correctness.

## Added

- API Service usage statistics now retain daily and hourly request buckets.
- API Service usage statistics now retain daily and hourly token buckets.
- Per-account usage rows now include token breakdown fields for input, output, reasoning, and cached tokens.
- Management usage decoding now understands richer runtime fields including timestamp, latency, source, request buckets, and token buckets.
- Added a macOS open-source app release checklist covering local validation, unsigned distribution, GitHub Release packaging, and post-download checks.

## Changed

- API Service runtime refresh and monitoring now propagate usage bucket data through the runtime state instead of dropping it during state sync.
- TokenStore synchronization now preserves API Service usage buckets when reconciling local configuration and runtime state.
- Routing enablement probes now validate the effective runtime configuration after applying settings, reducing false success/failure states when draft settings differ from the running service.

## Fixed

- Routing startup probes now retry transient `cannotConnectToHost` failures, which makes first-start routing checks more resilient to local service startup races.
- CLIProxyAPI update execution now converges to an up-to-date state after a successful install instead of leaving stale pending update availability.
- CLIProxyAPI update checks now fail clearly when a release has no compatible artifact, without preserving stale pending-update state.

## Compatibility and migration notes

- No user data migration is required.
- No bundled CLIProxyAPI version upgrade is included in this release.
- Existing API Service configuration remains compatible; newly decoded usage buckets are additive.
- Existing update settings continue to use the same guided download / managed runtime flow.

## Validation

- `git diff --check` passed.
- `swift test --no-parallel` passed: 449 tests, 0 failures.
- GitHub Actions release packaging is triggered by pushing the `v0.2.3` tag and builds macOS Apple Silicon and Intel artifacts.

## Known distribution note

Current GitHub Actions packaging uses ad-hoc codesign and does not notarize the app yet. Users may still need to use macOS Gatekeeper's right-click Open flow or remove quarantine manually for unsigned builds.
