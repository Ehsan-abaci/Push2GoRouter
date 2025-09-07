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
    // Resolve the file to get its abstract syntax tree (AST).
    final result = await resolveFile2(path: filePath);
    if (result is ResolvedUnitResult) {
      final invocations = <NavigationInvocation>[];
      // The visitor will traverse the AST and populate the invocations list.
      final visitor =
          _RouterVisitor(filePath: filePath, invocations: invocations);
      result.unit.accept(visitor);
      return invocations;
    }
    return [];
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

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    // We are only interested in expressions that create a 'GoRoute'.
    if (node.constructorName.type.name2.lexeme == 'GoRoute') {
      String? routeSegment;
      String? widgetName;

      // Find the 'path' argument and get its string value.
      final pathArg = node.argumentList.arguments
          .whereType<NamedExpression>()
          .where(
            (arg) => arg.name.label.name == 'path',
          )
          .firstOrNull;
      if (pathArg?.expression is StringLiteral) {
        routeSegment = (pathArg!.expression as StringLiteral).stringValue;
      }

      // Find the 'builder' argument and extract the widget name from its body.
      final builderArg = node.argumentList.arguments
          .whereType<NamedExpression>()
          .where(
            (arg) => arg.name.label.name == 'builder',
          )
          .firstOrNull;
      if (builderArg?.expression is FunctionExpression) {
        final body = (builderArg!.expression as FunctionExpression).body;
        if (body is ExpressionFunctionBody &&
            body.expression is InstanceCreationExpression) {
          final creationExpression =
              body.expression as InstanceCreationExpression;
          widgetName = creationExpression.constructorName.type.name2.lexeme;
        }
      }

      if (routeSegment != null) {
        // Construct the full path for the route, handling nested cases.
        final currentPath = ('$parentPath/$routeSegment').replaceAll('//', '/');

        // Add a representation of the found route to our list.
        invocations.add(NavigationInvocation(
          filePath: 'from_router', // Mark as sourced from the router file
          methodName: 'from_router',
          routeName: currentPath,
          targetWidgetName: widgetName,
          lineNumber: 0,
          offset: 0,
          length: 0,
          originalCode: '',
          // Add all nullable fields to match the constructor
          targetFilePath: null,
          resultExpression: null,
          argumentsAreMap: false,
          argumentsExpression: null,
          constructorArguments: null,
          routeNameExpression: null,
          typeArguments: null,
          originalCodeBlock: node.toSource(),
        ));

        // Find the 'routes' argument to visit nested GoRoutes.
        final routesArg = node.argumentList.arguments
            .whereType<NamedExpression>()
            .where((arg) => arg.name.label.name == 'routes')
            .firstOrNull;

        if (routesArg != null) {
          // Recursively visit children, passing down the current path.
          routesArg.visitChildren(_RouterVisitor(
            filePath: filePath,
            invocations: invocations,
            parentPath: currentPath,
          ));
        }
      }
    }

    // Manually control recursion to avoid visiting nodes multiple times.
    if (node.constructorName.type.name2.lexeme != 'GoRoute') {
      super.visitInstanceCreationExpression(node);
    }
  }
}
