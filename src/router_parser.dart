import 'dart:io';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'ast_utils.dart';
import 'models.dart';

/// Parses an existing `generated_router.dart` file to extract its routes.
///
/// This is used to identify routes that may have been added or modified
/// manually, so they can be preserved during the migration.
class RouterParser {
  /// Parses the file at the given [filePath] and returns a list of
  /// [NavigationInvocation] objects representing the `GoRoute`s found.
  ///
  /// Only the syntax tree is needed, so the file is parsed without
  /// resolution. In an unresolved tree, `GoRoute(...)` (written without
  /// `new`/`const`) is a [MethodInvocation] rather than an
  /// [InstanceCreationExpression]; the visitor handles both.
  Future<List<NavigationInvocation>> parse(String filePath) async {
    final content = await File(filePath).readAsString();
    final result = parseString(content: content, path: filePath);
    final invocations = <NavigationInvocation>[];
    result.unit.accept(
        _RouterVisitor(filePath: filePath, invocations: invocations));
    return invocations;
  }
}

/// The name and arguments of a constructor-like call, regardless of whether
/// the parser produced an [InstanceCreationExpression] or a [MethodInvocation].
class _Creation {
  final String name;
  final ArgumentList arguments;
  _Creation(this.name, this.arguments);
}

_Creation? _asCreation(Expression? e) {
  if (e is InstanceCreationExpression) {
    return _Creation(e.constructorName.type.name.lexeme, e.argumentList);
  }
  if (e is MethodInvocation && e.target == null) {
    return _Creation(e.methodName.name, e.argumentList);
  }
  return null;
}

/// An AST visitor that finds `GoRoute` declarations and reconstructs their info.
class _RouterVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final List<NavigationInvocation> invocations;
  final String parentPath;

  _RouterVisitor({
    required this.filePath,
    required this.invocations,
    this.parentPath = '',
  });

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (!_handle(node)) super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (!_handle(node)) super.visitMethodInvocation(node);
  }

  /// Returns true if [node] was a `GoRoute` (children are then visited
  /// manually to avoid visiting nodes multiple times).
  bool _handle(Expression node) {
    final creation = _asCreation(node);
    if (creation == null || creation.name != 'GoRoute') return false;

    Expression? namedArg(String name) =>
        creation.arguments.namedAny([name]);

    String? routeSegment;
    String? widgetName;

    // Find the 'path' argument and get its string value.
    final pathExpr = namedArg('path');
    if (pathExpr is StringLiteral) routeSegment = pathExpr.stringValue;

    // Find the 'builder' argument and extract the widget name from its body.
    final builderExpr = namedArg('builder');
    if (builderExpr is FunctionExpression) {
      final body = builderExpr.body;
      if (body is ExpressionFunctionBody) {
        widgetName = _asCreation(body.expression)?.name;
      }
    }

    if (routeSegment != null) {
      // Construct the full path for the route, handling nested cases.
      final currentPath = ('$parentPath/$routeSegment').replaceAll('//', '/');

      invocations.add(NavigationInvocation(
        filePath: 'from_router', // Mark as sourced from the router file
        methodName: 'from_router',
        routeName: currentPath,
        targetWidgetName: widgetName,
        lineNumber: 0,
        offset: 0,
        length: 0,
        originalCode: '',
        originalCodeBlock: node.toSource(),
      ));

      // Recursively visit nested GoRoutes, passing down the current path.
      final routesArg = namedArg('routes');
      if (routesArg != null) {
        routesArg.accept(_RouterVisitor(
          filePath: filePath,
          invocations: invocations,
          parentPath: currentPath,
        ));
      }
    }
    return true;
  }
}
