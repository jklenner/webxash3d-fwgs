# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-09-03
### Changed
- gles3compat renderer wasm replaced with gl4es and will be removed in the next major release
- Extended net module
- Added engine callbacks

---

## [1.0.1] - 2025-08-01
### Fixed
- Screen lock without Net

---

## [1.0.0] - 2025-07-30
### Changed
- Engine constructor options
- Net improvements

---

## [0.0.4] - 2025-07-23
### Changed
- Exported FS from Emscripten module

---

## [0.0.3] - 2025-07-22
### Changed
- WASM web env

### Fixed
- Register net callbacks name typo

---

## [0.0.2] - 2025-07-20
### Changed
- Minified WASM files

---

## [0.0.1] - 2025-07-17
### Changed
- Improved package.json

---

## [0.0.0] - 2025-07-14
### Added
- Initial release with core features:
    - WASM Engine + TypeScript Class Wrapper
    - Net Module
