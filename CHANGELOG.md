# Changelog

## 0.2.0

- Added a `--router-only` flag to the `migrate` command. When passed, the tool generates/updates `lib/generated_router.dart` as usual but skips the source code refactoring step entirely, so no Navigator 2.0 calls are modified.

## 0.1.0

- Updated the `analyzer` dependency to `^14.7.0`.
- Updated AST and element handling to support the new Analyzer API.
- Improved compatibility with the latest Analyzer version.

## 0.0.4

- Updated package documentation.
- Refactored `pushReplacementNamed` to `pushReplacement`.

## 0.0.3

- Removed `dependency_overrides` to improve dependency compatibility.

## 0.0.2

- Updated package version and configuration.

## 0.0.1

- Initial release of Push2GoRouter.