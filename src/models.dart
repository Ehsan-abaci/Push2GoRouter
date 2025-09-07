/// Represents a single invocation of a Navigator 2.0 method in the source code.
///
/// This class holds all the analyzed information about a navigation call,
/// such as the method name, route name, arguments, and location in the file.
class NavigationInvocation {
  /// The absolute file path where the invocation was found.
  final String filePath;

  /// The name of the Navigator method that was called (e.g., 'pushNamed').
  final String methodName;

  /// The resolved string value of the route name (e.g., '/home').
  final String routeName;

  /// The source code of the route name expression (e.g., `Routes.home`).
  final String? routeNameExpression;

  /// The name of the target widget being pushed, if determinable.
  final String? targetWidgetName;

  /// The line number where the invocation occurs.
  final int lineNumber;

  /// The character offset where the invocation starts in the file.
  final int offset;

  /// The character length of the invocation's source code.
  final int length;

  /// The original source code of the entire method invocation.
  final String originalCode;

  /// The source code of the type arguments passed to the method (e.g., `<bool>`).
  final String? typeArguments;

  /// The source code of the 'arguments' parameter, if it exists.
  final String? argumentsExpression;

  /// A map of constructor argument names to their source code values.
  ///
  /// This is populated for `Navigator.push` calls where a widget is
  /// instantiated directly.
  final Map<String, String>? constructorArguments;

  /// True if the 'arguments' parameter was a Map literal.
  final bool argumentsAreMap;

  /// The resolved file path of the target widget.
  final String? targetFilePath;

  /// The source code of the 'result' parameter for pop methods.
  final String? resultExpression;

  /// The full original source code of the GoRoute, if parsed from a router file.
  ///
  /// This is used to preserve manually-edited routes.
  final String? originalCodeBlock;

  NavigationInvocation({
    required this.filePath,
    required this.methodName,
    required this.routeName,
    this.routeNameExpression,
    required this.targetWidgetName,
    required this.lineNumber,
    required this.offset,
    required this.length,
    required this.originalCode,
    this.argumentsExpression,
    this.typeArguments,
    this.constructorArguments,
    this.argumentsAreMap = false,
    this.targetFilePath,
    this.resultExpression,
    this.originalCodeBlock,
  });
}
