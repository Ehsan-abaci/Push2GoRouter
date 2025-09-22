import 'dart:io';
import 'models.dart';
import 'package:path/path.dart' as p;

/// Handles the modification of Dart files to replace Navigator 2.0 calls
/// with their `go_router` equivalents.
class Refactorer {
  final List<NavigationInvocation> invocations;
  final Directory projectDirectory;

  Refactorer(this.invocations, this.projectDirectory);

  /// Performs the refactoring process by applying changes to the source files.
  ///
  /// Groups invocations by file and replaces the original code with
  /// `go_router` method calls. Can be run in `dryRun` mode to only
  /// print the proposed changes.
  Future<void> performRefactoring({bool dryRun = false}) async {
    final grouped = _groupInvocationsByFile();
    if (grouped.isEmpty) return;

    print('\n--- Starting Refactoring ---');
    if (dryRun) print('Running in dry-run mode. No files will be modified.');

    for (final filePath in grouped.keys) {
      await _refactorFile(filePath, grouped[filePath]!, dryRun: dryRun);
    }

    if (!dryRun) {
      print('\nRefactoring complete!');
      print('Please run `dart format .` to clean up the generated code.');
    }
    print('--- End of Refactoring ---');
  }

  Future<void> _refactorFile(
      String filePath, List<NavigationInvocation> fileInvocations,
      {required bool dryRun}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      print('Warning: File not found, skipping: $filePath');
      return;
    }
    String content = await file.readAsString();
    fileInvocations.sort((a, b) => b.lineNumber.compareTo(a.lineNumber));

    final relativePath = p.relative(filePath, from: projectDirectory.path);
    print('\nRefactoring file: $relativePath');
    bool needsGoRouterImport = false;

    for (final inv in fileInvocations) {
      String newCode;
      final extra = inv.argumentsExpression != null
          ? ', extra: ${inv.argumentsExpression}'
          : '';
      final routeIdentifier = inv.routeNameExpression ?? "'${inv.routeName}'";
      final typeArgs = inv.typeArguments ?? '';

      switch (inv.methodName) {
        case 'pushNamedHelper': // New case for helper calls
        case 'pushNamed':
          newCode = "context.push$typeArgs($routeIdentifier$extra)";
          needsGoRouterImport = true;
          break;
        case 'pushReplacementNamed':
          newCode = "context.pushReplacement$typeArgs($routeIdentifier$extra)";
          needsGoRouterImport = true;
          break;
        case 'pop':
          final result = inv.argumentsExpression ?? '';
          newCode = "context.pop($result)";
          needsGoRouterImport = true;
          break;
        case 'canPop':
          newCode = "context.canPop()";
          needsGoRouterImport = true;
          break;
        case 'maybePop':
          final result = inv.argumentsExpression ?? '';
          newCode = "context.maybePop($result)";
          needsGoRouterImport = true;
          break;
        case 'push':
        case 'pushReplacement':
          String extraString = '';
          if (inv.constructorArguments != null &&
              inv.constructorArguments!.isNotEmpty) {
            if (inv.constructorArguments!.length == 1) {
              // Single argument: pass its value directly.
              final singleArgumentValue =
                  inv.constructorArguments!.values.first;
              extraString = ", extra: $singleArgumentValue";
            } else {
              // Multiple arguments: bundle them in a map.
              final mapEntries = inv.constructorArguments!.entries
                  .map((e) => "'${e.key}': ${e.value}")
                  .join(', ');
              extraString = ", extra: <String, dynamic>{$mapEntries}";
            }
          }
          final methodName =
              inv.methodName == 'pushReplacement' ? 'pushReplacement' : 'push';
          newCode =
              "context.$methodName$typeArgs($routeIdentifier$extraString)";
          needsGoRouterImport = true;
          break;
        default:
          newCode = '// TODO: Manual migration for ${inv.methodName}';
          break;
      }

      if (dryRun) {
        print('  L${inv.lineNumber}:');
        print('    - ${inv.originalCode}');
        print('    + $newCode');
      } else {
        content =
            content.replaceRange(inv.offset, inv.offset + inv.length, newCode);
      }
    }

    const goRouterImport = "import 'package:go_router/go_router.dart';";
    if (needsGoRouterImport && !content.contains(goRouterImport)) {
      final lines = content.split('\n');
      final lastImportIndex =
          lines.lastIndexWhere((line) => line.trim().startsWith('import '));
      lines.insert(
          lastImportIndex != -1 ? lastImportIndex + 1 : 0, goRouterImport);
      content = lines.join('\n');
      if (dryRun) print('  + $goRouterImport');
    }

    if (!dryRun) await file.writeAsString(content);
  }

  Map<String, List<NavigationInvocation>> _groupInvocationsByFile() {
    final map = <String, List<NavigationInvocation>>{};
    for (final inv in invocations) {
      (map[inv.filePath] ??= []).add(inv);
    }
    return map;
  }
}
