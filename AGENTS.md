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
- PRs run soundness checks, including API compatibility, documentation, formatting, shellcheck,
  and yamllint. The docs workflow adds the DocC plugin only in its temporary checkout.
  License-header checking stays disabled because source files use the author-header convention.
- PRs, main pushes, and the weekly schedule run Linux tests on Swift 6.3 and 6.4, next/main
  snapshots, release builds, and static Linux SDK compatibility. Require supported stable
  checks in branch protection; snapshot failures remain visible and advisory unless
  maintainers explicitly require them.
- CI is Linux-only by project choice. macOS and other Apple-platform builds/tests are
  outside this pipeline; Linux success does not establish Apple-platform compatibility.
- Actions and reusable workflows are SHA-pinned. The reviewed SwiftNIO main commit supplies
  Swift 6.4 inputs absent from release 2.103.0; its nested workflows and downloaded scripts
  still follow upstream main. Caller pins do not make that execution chain immutable.
- Keep the separate Foundation-linking consumer check; a successful static SDK build
  does not prove that the resolved graph avoids full Foundation.
