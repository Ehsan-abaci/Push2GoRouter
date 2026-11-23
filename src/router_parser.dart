
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'models.dart';

/// Parses an existing `generated_router.dart` file to extract its routes.
///
/// This is used to identify routes that may have been added or modified
/// manually, so they can be preserved during the migration.
class RouterParser {
  /// Parses the file at the given [filePath] and returns a list of
  /// [NavigationInvocation] objects representing the `GoRoute`s found.
  Future<List<NavigationInvocation>> parse(String filePath) async {
    final result = await resolveFile(path: filePath);

    if (result is! ResolvedUnitResult) {
      return [];
    }

    final invocations = <NavigationInvocation>[];

    final visitor = _RouterVisitor(
      filePath: filePath,
      invocations: invocations,
    );

    result.unit.accept(visitor);

    return invocations;
  }
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

  /// Finds a named argument by its name.
  NamedArgument? _getNamedArgument(
    ArgumentList argumentList,
    String name,
  ) {
    for (final argument in argumentList.arguments) {
      if (argument is NamedArgument && argument.name.lexeme == name) {
        return argument;
      }
    }

    return null;
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final isGoRoute =
        node.constructorName.type.name.lexeme == 'GoRoute';

    if (isGoRoute) {
      String? routeSegment;
      String? widgetName;

      // Extract the path argument.
      final pathArg = _getNamedArgument(
        node.argumentList,
        'path',
      );

      final pathExpression = pathArg?.argumentExpression;

      if (pathExpression is StringLiteral) {
        routeSegment = pathExpression.stringValue;
      }

      // Extract the widget name from the builder argument.
      final builderArg = _getNamedArgument(
        node.argumentList,
        'builder',
      );

      final builderExpression = builderArg?.argumentExpression;

      if (builderExpression is FunctionExpression) {
        final body = builderExpression.body;

        if (body is ExpressionFunctionBody &&
            body.expression is InstanceCreationExpression) {
          final creationExpression =
              body.expression as InstanceCreationExpression;

          widgetName =
              creationExpression.constructorName.type.name.lexeme;
        }
      }

      if (routeSegment != null) {
        final currentPath =
            ('$parentPath/$routeSegment').replaceAll('//', '/');

        invocations.add(
          NavigationInvocation(
            filePath: 'from_router',
            methodName: 'from_router',
            routeName: currentPath,
            targetWidgetName: widgetName,
            lineNumber: 0,
            offset: 0,
            length: 0,
            originalCode: '',
            targetFilePath: null,
            resultExpression: null,
            argumentsAreMap: false,
            argumentsExpression: null,
            constructorArguments: null,
            routeNameExpression: null,
            typeArguments: null,
            originalCodeBlock: node.toSource(),
          ),
        );

        // Visit nested GoRoutes.
        final routesArg = _getNamedArgument(
          node.argumentList,
          'routes',
        );

        if (routesArg != null) {
          routesArg.argumentExpression.visitChildren(
            _RouterVisitor(
              filePath: filePath,
              invocations: invocations,
              parentPath: currentPath,
            ),
          );
        }
      }
    }

    // Avoid visiting nested GoRoutes twice.
    if (!isGoRoute) {
      super.visitInstanceCreationExpression(node);
    }
  }
}
