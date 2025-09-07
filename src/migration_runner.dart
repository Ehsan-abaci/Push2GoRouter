import 'dart:io';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'helper_models.dart';
import 'models.dart';
import 'navigator_visitor.dart';
import 'refactorer.dart';
import 'router_generator.dart';
import 'router_parser.dart';
import 'package:path/path.dart' as p;

/// Orchestrates the entire migration process from Navigator 2.0 to go_router.
///
/// This class coordinates finding navigation calls, parsing existing router files,
/// generating a new router configuration, and refactoring the source code.
class MigrationRunner {
  /// The root directory of the Flutter project being migrated.
  final Directory projectDirectory;

  /// Whether to apply the refactoring changes to the files on disk.
  /// If `false`, the tool runs in "dry run" mode.
  final bool applyChanges;

  MigrationRunner({required this.projectDirectory, this.applyChanges = false});

  /// Finds the package name from the pubspec.yaml file.
  Future<String?> _getPackageName() async {
    final pubspecFile = File(p.join(projectDirectory.path, 'pubspec.yaml'));
    if (!await pubspecFile.exists()) {
      print(
          'Warning: pubspec.yaml not found. Falling back to relative imports.');
      return null;
    }
    try {
      final content = await pubspecFile.readAsString();
      // Use a simple regex to extract the package name.
      final match =
          RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(content);
      return match?.group(1);
    } catch (e) {
      print('Warning: Could not read package name from pubspec.yaml: $e');
      return null;
    }
  }

  /// Runs the complete migration process.
  ///
  /// This involves multiple passes:
  /// 1. Find user-defined navigation helper methods.
  /// 2. Find all Navigator 2.0 invocations (direct and via helpers).
  /// 3. Parse any existing `go_router` file.
  /// 4. Merge found routes with existing routes.
  /// 5. Generate or update the `generated_router.dart` file.
  /// 6. Refactor the source code to use `go_router` APIs.
  Future<void> run() async {
    final libDirPath = p.join(projectDirectory.path, 'lib');
    final collection = AnalysisContextCollection(includedPaths: [libDirPath]);
    final packageName = await _getPackageName();

    // --- PASS 1: Find all navigation helper methods ---
    print("\nPass 1: Searching for navigation helper methods...");
    final foundHelpers = <NavigationHelper>[];
    for (final context in collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        if (!filePath.endsWith('.dart')) continue;
        final result = await context.currentSession.getResolvedUnit(filePath);
        if (result is ResolvedUnitResult) {
          final helperVisitor = HelperFinderVisitor();
          result.unit.accept(helperVisitor);
          foundHelpers.addAll(helperVisitor.helpers);
        }
      }
    }
    if (foundHelpers.isNotEmpty) {
      print("-> Found ${foundHelpers.length} helper method(s).");
    }

    // --- PASS 2: Find all invocations (direct and via helpers) ---
    print("Pass 2: Analyzing all navigation calls...");
    final newlyFoundInvocations = <NavigationInvocation>[];
    for (final context in collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        if (!filePath.endsWith('.dart')) continue;

        final result = await context.currentSession.getResolvedUnit(filePath);
        if (result is ResolvedUnitResult) {
          // Pass the list of found helpers to the main visitor.
          final visitor = NavigatorVisitor(
            filePath: filePath,
            lineInfo: result.lineInfo,
            knownHelpers: foundHelpers,
          );
          result.unit.accept(visitor);
          newlyFoundInvocations.addAll(visitor.invocations);
        }
      }
    }

    final routerFilePath = p.join(libDirPath, 'generated_router.dart');
    final routerFile = File(routerFilePath);
    List<NavigationInvocation> existingInvocations = [];
    String? existingRouterContent;

    if (await routerFile.exists()) {
      print('Found existing router file. Parsing for existing routes...');
      existingRouterContent = await routerFile.readAsString();
      final parser = RouterParser();
      existingInvocations = await parser.parse(routerFilePath);
      print('-> Found ${existingInvocations.length} existing routes.');
    }

    final finalInvocationsMap = <String, NavigationInvocation>{};
    final existingInvocationsMap = {
      for (var inv in existingInvocations) inv.routeName: inv
    };

    for (final inv in newlyFoundInvocations) {
      if (inv.routeName != 'N/A' && inv.routeName != 'dynamic_route') {
        final existing = existingInvocationsMap[inv.routeName];

        if (existing != null) {
          // Route exists in both the router file and the source code scan.
          // We create a "merged" invocation. It's based on the new scan, but
          // carries the original GoRoute code block from the existing router file
          // so the generator can preserve it.
          final mergedInv = NavigationInvocation(
            filePath: inv.filePath,
            methodName: inv.methodName,
            routeName: inv.routeName,
            routeNameExpression: inv.routeNameExpression,
            targetWidgetName: inv.targetWidgetName ?? existing.targetWidgetName,
            lineNumber: inv.lineNumber,
            offset: inv.offset,
            length: inv.length,
            originalCode: inv.originalCode,
            argumentsExpression: inv.argumentsExpression,
            typeArguments: inv.typeArguments,
            constructorArguments: inv.constructorArguments,
            argumentsAreMap: inv.argumentsAreMap,
            targetFilePath: inv.targetFilePath,
            resultExpression: inv.resultExpression,
            originalCodeBlock: existing.originalCodeBlock,
          );
          finalInvocationsMap[inv.routeName] = mergedInv;
          // Remove from the map so we can later identify routes that are only in the router file.
          existingInvocationsMap.remove(inv.routeName);
        } else {
          // This is a new route found in the scan that wasn't in the old router file.
          finalInvocationsMap[inv.routeName] = inv;
        }
      }
    }

    // Add back any routes that were only in the original router file.
    // These could be manually added routes that don't have a corresponding Navigator call.
    for (final remainingInv in existingInvocationsMap.values) {
      finalInvocationsMap.putIfAbsent(
          remainingInv.routeName, () => remainingInv);
    }

    final finalInvocations = finalInvocationsMap.values.toList();

    if (newlyFoundInvocations.isEmpty && existingInvocations.isEmpty) {
      print("No Navigator 2.0 invocations found and no existing router file.");
      return;
    }

    _printReport(newlyFoundInvocations);

    final generator = RouterGenerator(
      finalInvocations,
      libDirectoryPath: libDirPath,
      packageName: packageName, // Pass the package name to the generator
    );
    final routerCode =
        generator.generate(existingContent: existingRouterContent);

    final relativePath =
        p.relative(routerFilePath, from: projectDirectory.path);
    if (existingInvocations.isNotEmpty) {
      print('\nUpdating router configuration at $relativePath...');
    } else {
      print('\nGenerating router configuration at $relativePath...');
    }
    await routerFile.writeAsString(routerCode);

    final refactorer = Refactorer(newlyFoundInvocations, projectDirectory);
    await refactorer.performRefactoring(dryRun: !applyChanges);
  }

  void _printReport(List<NavigationInvocation> invocations) {
    if (invocations.isEmpty) return;

    print('\n--- Navigation Analysis Report ---');
    final grouped = <String, List<NavigationInvocation>>{};
    for (final invocation in invocations) {
      (grouped[invocation.filePath] ??= []).add(invocation);
    }

    grouped.forEach((filePath, invs) {
      final relativePath = p.relative(filePath, from: projectDirectory.path);
      print('\nFile: $relativePath');
      invs.sort((a, b) => a.lineNumber.compareTo(b.lineNumber));
      for (final inv in invs) {
        final target = inv.routeName == 'dynamic_route'
            ? '(dynamic route)'
            : "'${inv.routeName}'";
        print(
          '  - L${inv.lineNumber}: Found call to ${inv.methodName} targeting $target',
        );
      }
    });
    print('--- End of Report ---');
  }
}
