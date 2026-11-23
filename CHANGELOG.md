# Changelog

## 1.0.0

- Added a `generate` command that creates or updates the router file (`lib/generated_router.dart` by default) without migrating anything. Your Navigator calls and other source files are never modified.
  - Preview with `dart run push2gorouter generate`, write with `--write`.
  - Choose a different file with `--output` / `-o`, e.g. `generate --write -o lib/app_router.dart`.
  - An existing router file is merged the same way as in `migrate`, so hand-edited routes are preserved.
- Fixed `--dry-run` writing the router file to disk. A dry run now only prints a preview of the router code, and nothing is written until you pass `--write`.
- Fixed refactoring corrupting code when several Navigator calls were on the same line. Edits are now applied by character offset instead of line number.
- Fixed the CLI reporting the wrong version in its usage text.

## 0.1.0

- Updated the `analyzer` dependency to `14.7.0` and the minimum Dart SDK to `3.13.0`.
- Updated AST and element handling to the new analyzer API:
  - `element2.dart` types replaced with `element.dart` types.
  - `NamedType.name2` replaced with `name`.
  - `NamedExpression` replaced with `NamedArgument`, with argument handling moved into `src/ast_utils.dart`.
  - Constant route names (e.g. `Routes.home`) are resolved through the new `variable` getter.
- Fixed navigation helper detection, which compared a parameter fragment to an element and so never matched.
- The existing router file is now read with `parseString` instead of `resolveFile2`, so `GoRoute(...)` is found with or without `const`/`new`, and without running `pub get` first.

## 0.0.4

- Updated package documentation.
- Refactored `pushReplacementNamed` to `pushReplacement`.

## 0.0.3

- Removed `dependency_overrides` to improve dependency compatibility.

## 0.0.2

- Updated package version and configuration.

## 0.0.1

- Initial release of Push2GoRouter.
