import 'models.dart';
import 'package:path/path.dart' as p;

/// A helper class to represent a node in the route tree.
class _RouteNode {
  final String segment;
  NavigationInvocation? invocation;
  final Map<String, _RouteNode> children = {};

  _RouteNode(this.segment);
}

/// Generates the `generated_router.dart` file content from a list of
/// [NavigationInvocation]s.
///
/// Builds a route tree from the flat list of invocations and generates
/// a nested `GoRoute` configuration. It can also intelligently update an

/// existing router file to preserve manual changes.
class RouterGenerator {
  final List<NavigationInvocation> invocations;
  final String libDirectoryPath;
  final String? packageName;

  RouterGenerator(this.invocations,
      {required this.libDirectoryPath, this.packageName});

  /// Generates the full source code for the router file.
  ///
  /// If [existingContent] is provided, it will attempt to surgically
  /// replace the `routes` list within that content. Otherwise, it generates
  /// a new file from scratch.
  String generate({String? existingContent}) {
    // Generate the code for the routes list.
    final routesBuffer = StringBuffer();
    _buildRoutes(routesBuffer);
    final newRoutesList = routesBuffer.toString();

    if (existingContent != null) {
      // If the file already exists, perform a surgical replacement of the routes list.
      return _updateExistingRoutes(existingContent, newRoutesList);
    } else {
      // Otherwise, generate the file from scratch.
      return _generateNewRouterFile(newRoutesList);
    }
  }

  String _updateExistingRoutes(String existingContent, String newRoutesList) {
    final routesRegex = RegExp(r'routes:\s*(?:<RouteBase>)?\s*\[');
    final match = routesRegex.firstMatch(existingContent);

    if (match == null) {
      print(
          'Warning: Could not find "routes: [...]" list in the existing router file. Overwriting file.');
      return _generateNewRouterFile(newRoutesList);
    }

    final listStartIndex = match.end - 1; // Index of the opening '['
    final listEndIndex = _findMatchingBracket(existingContent, listStartIndex);

    if (listEndIndex == -1) {
      print(
          'Warning: Could not find matching "]" for the routes list. Overwriting file.');
      return _generateNewRouterFile(newRoutesList);
    }

    // Replace the content between the brackets.
    return existingContent.replaceRange(
        listStartIndex + 1, listEndIndex, '\n$newRoutesList  ');
  }

  int _findMatchingBracket(String text, int startIndex) {
    if (text[startIndex] != '[') return -1;
    int depth = 1;
    for (int i = startIndex + 1; i < text.length; i++) {
      if (text[i] == '[') {
        depth++;
      } else if (text[i] == ']') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  String _generateNewRouterFile(String routesList) {
    final buffer = StringBuffer();
    final uniqueInvocations = invocations;

    final imports = <String>{
      "import 'package:flutter/material.dart';",
      "import 'package:go_router/go_router.dart';",
    };
    final packageImports = <String>{};

    for (final inv in uniqueInvocations) {
      if (inv.targetWidgetName != null && inv.targetFilePath != null) {
        final pathForImport = inv.targetFilePath!;
        String importPath;
        if (packageName != null && pathForImport.startsWith(libDirectoryPath)) {
          final pathInLib = p.relative(pathForImport, from: libDirectoryPath);
          importPath =
              'package:$packageName/${pathInLib.replaceAll(r'\', '/')}';
        } else {
          final relativePath =
              p.relative(pathForImport, from: libDirectoryPath);
          importPath = relativePath.replaceAll(r'\', '/');
        }
        packageImports.add("import '$importPath';");
      }
    }

    buffer.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
    buffer.writeln('// ignore_for_file: constant_identifier_names');
    buffer.writeln();
    imports.forEach(buffer.writeln);
    packageImports.toList()
      ..sort()
      ..forEach(buffer.writeln);
    buffer.writeln();

    buffer.writeln('/// The router configuration.');
    buffer.writeln('final GoRouter router = GoRouter(');
    buffer.writeln('  routes: [');
    buffer.write(routesList);
    buffer.writeln('  ],');
    buffer.writeln(');');

    return buffer.toString();
  }

  void _buildRoutes(StringBuffer buffer) {
    final root = _RouteNode('');
    NavigationInvocation? rootInvocation;

    final sortedInvocations = invocations.toList()
      ..sort((a, b) => a.routeName.compareTo(b.routeName));

    for (final inv in sortedInvocations) {
      if (inv.routeName == '/') {
        rootInvocation = inv;
        continue;
      }

      var currentNode = root;
      final segments =
          inv.routeName.split('/').where((s) => s.isNotEmpty).toList();

      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final isLastSegment = i == segments.length - 1;

        currentNode = currentNode.children
            .putIfAbsent(segment, () => _RouteNode(segment));

        if (isLastSegment) {
          currentNode.invocation = inv;
        }
      }
    }

    if (rootInvocation != null) {
      // This is a special case for the root, might need adjustment
      // For now, handling within the main loop is sufficient.
    }

    for (final node in root.children.values) {
      _generateRouteCode(buffer, node, '    ', isTopLevel: true);
    }
  }

  void _generateRouteCode(StringBuffer buffer, _RouteNode node, String indent,
      {bool isTopLevel = false}) {
    if (node.invocation?.originalCodeBlock != null) {
      // This route was parsed from an existing router file.
      // We print its original source code directly to preserve any manual changes.
      buffer.writeln('$indent${node.invocation!.originalCodeBlock},');
      return;
    }

    buffer.writeln('$indent GoRoute(');

    final path = isTopLevel ? '/${node.segment}' : node.segment;
    buffer.writeln("$indent   path: '$path',");

    if (node.invocation != null) {
      _writeBuilder(buffer, node.invocation!, '$indent   ');
    } else {
      buffer.writeln(
          '$indent   // TODO: This is a parent route. Consider using a ShellRoute or provide a builder.');
      buffer.writeln(
          '$indent   builder: (BuildContext context, GoRouterState state) => const SizedBox.shrink(), // Placeholder');
    }

    if (node.children.isNotEmpty) {
      buffer.writeln('$indent   routes: <RouteBase>[');
      for (final child in node.children.values) {
        _generateRouteCode(buffer, child, '$indent     ');
      }
      buffer.writeln('$indent   ],');
    }

    buffer.writeln('$indent ),');
  }

  void _writeBuilder(
      StringBuffer buffer, NavigationInvocation inv, String indent) {
    if (inv.targetWidgetName != null) {
      buffer.writeln(
          '$indent builder: (BuildContext context, GoRouterState state) {');

      if (inv.constructorArguments != null &&
          inv.constructorArguments!.isNotEmpty) {
        if (inv.constructorArguments!.length == 1) {
          // Single argument case
          final argName = inv.constructorArguments!.keys.first;
          buffer.writeln(
              '$indent   final argument = state.extra as dynamic; // TODO: Cast to the correct type.');
          buffer.writeln(
              '$indent   return ${inv.targetWidgetName}($argName: argument);');
        } else {
          // Multiple arguments case
          buffer.writeln(
              '$indent   final args = state.extra as Map<String, dynamic>;');
          final constructorArgsString = inv.constructorArguments!.keys
              .map((key) => "$key: args['$key'],")
              .join('\n$indent     ');
          buffer.writeln('$indent   return ${inv.targetWidgetName}(');
          buffer.writeln('$indent     $constructorArgsString');
          buffer.writeln('$indent   );');
        }
      } else if (inv.argumentsExpression != null) {
        // from pushNamed
        buffer.writeln(
            '$indent   // Arguments are passed via the `extra` field. You can get them from state.extra.');
        if (inv.argumentsAreMap) {
          buffer.writeln(
              '$indent   final arguments = state.extra as Map<String, dynamic>;');
          buffer.writeln(
              '$indent   // TODO: Pass the map entries to your widget constructor.');
          buffer.writeln(
              '$indent   // e.g. return ${inv.targetWidgetName}(id: arguments[\'id\'], name: arguments[\'name\']);');
        } else {
          buffer.writeln(
              '$indent   final arguments = state.extra as dynamic; // Or use a specific type like `int` or `String`');
          buffer.writeln(
              '$indent   // TODO: Pass the arguments to your widget constructor.');
          buffer.writeln(
              '$indent   // e.g. return ${inv.targetWidgetName}(id: arguments);');
        }
        buffer.writeln('$indent   return const ${inv.targetWidgetName}();');
      } else {
        buffer.writeln('$indent   return const ${inv.targetWidgetName}();');
      }

      buffer.writeln('$indent },');
    } else {
      buffer.writeln(
          '$indent // TODO: This route was found via ${inv.methodName}() and requires a builder function.');
      buffer.writeln(
          '$indent builder: (BuildContext context, GoRouterState state) => const SizedBox.shrink(), // Placeholder. Replace with your widget.');
    }
  }
}
