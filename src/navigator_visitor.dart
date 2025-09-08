import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'helper_models.dart';
import 'models.dart';

/// An AST Visitor that finds user-defined helper methods that wrap Navigator.
class HelperFinderVisitor extends RecursiveAstVisitor<void> {
  final List<NavigationHelper> helpers = [];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    // A simple visitor to find Navigator.pushNamed inside a method body.
    final navigatorVisitor = _InternalNavigatorVisitor();
    node.body.accept(navigatorVisitor);

    if (navigatorVisitor.foundPushNamedCall != null) {
      final call = navigatorVisitor.foundPushNamedCall!;
      final routeArg = call.argumentList.arguments.length > 1
          ? call.argumentList.arguments[1]
          : null;

      if (routeArg is SimpleIdentifier) {
        // Find which parameter of the outer method corresponds to the route name.
        final routeParameter = node.parameters?.parameters
            .where(
              (p) => p.declaredFragment == routeArg.element,
            )
            .firstOrNull;
        if (routeParameter != null &&
            node.declaredFragment is ExecutableElement) {
          helpers.add(NavigationHelper(
            element: node.declaredFragment as ExecutableElement,
            routeNameParameterIndex:
                node.parameters!.parameters.indexOf(routeParameter),
          ));
        }
      }
    }
    super.visitMethodDeclaration(node);
  }
}

/// An internal visitor to find a `Navigator.pushNamed` call within a method body.
class _InternalNavigatorVisitor extends RecursiveAstVisitor<void> {
  MethodInvocation? foundPushNamedCall;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target is SimpleIdentifier &&
        (node.target as SimpleIdentifier).name == 'Navigator' &&
        node.methodName.name == 'pushNamed') {
      foundPushNamedCall = node;
    }
    super.visitMethodInvocation(node);
  }
}

/// An AST Visitor that finds all relevant Navigator calls, including via helpers.
class NavigatorVisitor extends RecursiveAstVisitor<void> {
  final String filePath;
  final LineInfo lineInfo;
  final List<NavigationHelper> knownHelpers;
  final List<NavigationInvocation> invocations = [];

  NavigatorVisitor({
    required this.filePath,
    required this.lineInfo,
    this.knownHelpers = const [],
  });

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    if (element == null) {
      super.visitMethodInvocation(node);
      return;
    }

    NavigationHelper? foundHelper;
    for (final helper in knownHelpers) {
      if (helper.element == element) {
        foundHelper = helper;
        break;
      }
    }

    if (foundHelper != null) {
      // It's a helper call! Treat as a non-static call for argument parsing.
      _handleInvocation(node,
          isHelper: true,
          routeArgIndex: foundHelper.routeNameParameterIndex,
          isStaticCall: false);
    } else if (node.target is SimpleIdentifier &&
        (node.target as SimpleIdentifier).name == 'Navigator') {
      // It's a direct static call, e.g., `Navigator.pop(context)`.
      _handleInvocation(node, isStaticCall: true);
    } else if (node.target is MethodInvocation) {
      // Check for chained calls like `Navigator.of(context).pop()`.
      final innerInvocation = node.target as MethodInvocation;
      if (innerInvocation.target is SimpleIdentifier &&
          (innerInvocation.target as SimpleIdentifier).name == 'Navigator' &&
          innerInvocation.methodName.name == 'of') {
        // The node is the outer call (e.g., `pop`), which is what we need to handle.
        _handleInvocation(node, isStaticCall: false);
      }
    }

    super.visitMethodInvocation(node);
  }

  void _handleInvocation(MethodInvocation node,
      {bool isHelper = false,
      int routeArgIndex = 1,
      required bool isStaticCall}) {
    final methodName = node.methodName.name;
    const relevantMethods = [
      'push',
      'pushNamed',
      'pushReplacementNamed',
      'pop',
      'canPop',
      'maybePop',
      'pushReplacement',
      'pushNamedAndRemoveUntil',
      'popAndPushNamed',
    ];

    final effectiveMethodName = isHelper ? 'pushNamed' : methodName;

    if (relevantMethods.contains(effectiveMethodName)) {
      String? routeName;
      String? routeNameExpression;
      String? targetWidget;
      String? argumentsExpression;
      String? typeArgumentsSource;
      Map<String, String>? constructorArguments;
      bool argumentsAreMap = false;
      String? targetFilePath;
      String? resultExpression;

      // Static calls have `context` as the first argument, so the real arguments are offset by 1.
      final argOffset = isStaticCall ? 1 : 0;

      if (node.typeArguments != null) {
        typeArgumentsSource = node.typeArguments!.toSource();
      }

      if (effectiveMethodName == 'pushNamed' ||
          effectiveMethodName == 'pushReplacementNamed' ||
          effectiveMethodName == 'pushNamedAndRemoveUntil') {
        final routeNameArgIndex = isHelper ? routeArgIndex : argOffset;
        if (node.argumentList.arguments.length > routeNameArgIndex) {
          final routeArg = node.argumentList.arguments[routeNameArgIndex];
          routeNameExpression = routeArg.toSource();
          routeName = _resolveRouteName(routeArg);
          if (routeName == null) routeName = 'dynamic_route';
        }
        final argumentsArg = node.argumentList.arguments
            .whereType<NamedExpression>()
            .where(
              (arg) =>
                  arg.name.label.name == 'arguments' ||
                  arg.name.label.name == 'extra',
            )
            .firstOrNull;
        if (argumentsArg != null) {
          argumentsExpression = argumentsArg.expression.toSource();
          if (argumentsArg.expression is SetOrMapLiteral) {
            final literal = argumentsArg.expression as SetOrMapLiteral;
            if (!literal.isSet) {
              argumentsAreMap = true;
            }
          }
        }
      } else if (effectiveMethodName == 'popAndPushNamed') {
        if (node.argumentList.arguments.length > argOffset) {
          final routeArg = node.argumentList.arguments[argOffset];
          routeNameExpression = routeArg.toSource();
          routeName = _resolveRouteName(routeArg);
          if (routeName == null) routeName = 'dynamic_route';
        }
        final argumentsArg = node.argumentList.arguments
            .whereType<NamedExpression>()
            .where(
              (arg) => arg.name.label.name == 'arguments',
            )
            .firstOrNull;
        if (argumentsArg != null) {
          argumentsExpression = argumentsArg.expression.toSource();
        }
        final resultArg = node.argumentList.arguments
            .whereType<NamedExpression>()
            .where(
              (arg) => arg.name.label.name == 'result',
            )
            .firstOrNull;
        if (resultArg != null) {
          resultExpression = resultArg.expression.toSource();
        }
      } else if (effectiveMethodName == 'push' ||
          effectiveMethodName == 'pushReplacement') {
        final routeArg = node.argumentList.arguments.length > argOffset
            ? node.argumentList.arguments[argOffset]
            : null;
        if (routeArg is InstanceCreationExpression) {
          final constructorName = routeArg.constructorName.type.name.lexeme;
          if (constructorName.contains('Page')) {
            NamedExpression? builderArg;
            try {
              builderArg = routeArg.argumentList.arguments
                  .whereType<NamedExpression>()
                  .where((arg) => arg.name.label.name == 'builder')
                  .firstOrNull;
            } on StateError {
              builderArg = null;
            }
            if (builderArg != null &&
                builderArg.expression is FunctionExpression) {
              final body = (builderArg.expression as FunctionExpression).body;
              if (body is ExpressionFunctionBody &&
                  body.expression is InstanceCreationExpression) {
                final widgetCreation =
                    body.expression as InstanceCreationExpression;
                targetWidget = widgetCreation.constructorName.type.name.lexeme;
                final element = widgetCreation.constructorName.element;
                if (element != null) {
                  targetFilePath =
                      element.firstFragment.libraryFragment.source.fullName;
                }
                final args = <String, String>{};
                for (final arg in widgetCreation.argumentList.arguments) {
                  if (arg is NamedExpression) {
                    args[arg.name.label.name] = arg.expression.toSource();
                  }
                }
                if (args.isNotEmpty) {
                  constructorArguments = args;
                }
              }
            }
          } else {
            targetWidget = constructorName;
          }
          routeName = '/${_toKebabCase(targetWidget ?? 'unknown')}';
          routeNameExpression = "'$routeName'";
        }
      } else if (effectiveMethodName == 'pop') {
        routeName = 'N/A';
        if (node.argumentList.arguments.length > argOffset) {
          argumentsExpression =
              node.argumentList.arguments[argOffset].toSource();
        }
      } else if (effectiveMethodName == 'canPop') {
        routeName = 'N/A';
      } else if (effectiveMethodName == 'maybePop') {
        routeName = 'N/A';
        if (node.argumentList.arguments.length > argOffset) {
          argumentsExpression =
              node.argumentList.arguments[argOffset].toSource();
        }
      }

      if (routeName != null) {
        invocations.add(
          NavigationInvocation(
            filePath: filePath,
            methodName: isHelper ? 'pushNamedHelper' : methodName,
            routeName: routeName,
            routeNameExpression: routeNameExpression,
            targetWidgetName: targetWidget,
            lineNumber: lineInfo.getLocation(node.offset).lineNumber,
            offset: node.offset,
            length: node.length,
            originalCode: node.toSource(),
            argumentsExpression: argumentsExpression,
            typeArguments: typeArgumentsSource,
            constructorArguments: constructorArguments,
            argumentsAreMap: argumentsAreMap,
            targetFilePath: targetFilePath,
            resultExpression: resultExpression,
          ),
        );
      }
    }
  }

  String? _resolveRouteName(Expression routeArg) {
    if (routeArg is StringLiteral) return routeArg.stringValue;
    if (routeArg is Identifier) {
      final element = routeArg.element;
      if (element is PropertyAccessorElement) {
        final variable = element.variable;
        final constValue = variable.computeConstantValue();
        if (constValue != null && constValue.hasKnownValue) {
          return constValue.toStringValue();
        }
      }
    }
    return null;
  }

  String _toKebabCase(String text) => text
      .replaceAllMapped(
          RegExp(r'(?<!^)(?=[A-Z])'), (match) => '-${match.group(0)}')
      .toLowerCase();
}
