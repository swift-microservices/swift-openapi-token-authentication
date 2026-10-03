# Repository guidelines

This library supplies reusable OpenAPI authentication middleware and token storage. Preserve
its public API and follow the existing Swift 6.3 conventions. Tests use Swift Testing.

## Swift

Use the checked-in `.swift-format`, copied exactly from apple/swift-temporal-sdk at
`508797b5468dbc532f77c317bf9df0cb3231f5c1`: four-space indentation, 150-column lines,
and ordered imports. Format and lint all tracked Swift files, including `Package.swift`.
Document public declarations even though this formatter does not enforce documentation.

## Releases

Every PR carries exactly one existing SemVer label. Use the existing manual Auto Release
workflow on `main`; source dependencies stay on released version requirements.

## Library CI profile

- This repository profile overrides general service CI and formatting defaults. Libraries
  never commit `Package.resolved`; CI resolves released dependencies from the manifest.
- PRs run documentation, formatting, compact license-header, shellcheck, and yamllint checks.
  Automatic API-breakage checking is disabled by project choice; SemVer labels still describe
  the public API impact. The docs workflow adds the DocC plugin only in its temporary checkout.
- PRs and main pushes run Linux tests on Swift 6.3 and 6.4, next/main snapshots, and release
  builds. PRs also run x86_64 static Linux SDK builds against the released and Swift main SDKs.
  CI has no scheduled runs. Require supported stable checks in branch protection; snapshot
  failures remain visible and advisory unless maintainers explicitly require them.
- Static SDK checks follow Swift Temporal SDK's PR-only setup and cross-compile only.
- CI is Linux-only by project choice. macOS and other Apple-platform builds/tests are
  outside this pipeline; Linux success does not establish Apple-platform compatibility.
- Shared library workflows and the SwiftNIO SemVer action follow `@main` by project choice.
  Soundness uses its release tag, and standard Actions use major-version tags. These moving
  references include upstream changes; do not describe them as immutable.
- Dependabot checks weekly, targets main, and labels workflow-update PRs `semver/none`.
- Use the three-line MIT header matched by `.license_header_template`. Keep the tools-version
  directive first in `Package.swift`, followed by that header. `.licenseignore` excludes the
  manifest (the upstream checker requires a header at line one) and the plain-text `LICENSE`.
- Keep the separate Foundation-linking consumer check on Swift 6.3 and 6.4 Noble; a successful
  static SDK build does not prove that the resolved graph avoids full Foundation.
