import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// Version-tolerant access to call arguments.
///
/// In recent analyzer releases an argument list holds `Argument`s: plain
/// [Expression]s for positional arguments and `NamedArgument`s (formerly
/// `NamedExpression`) for named ones. Everything that touches that split
/// lives here, so any further API change only needs fixing in one place.
extension ArgumentListUtils on ArgumentList {
  /// The positional arguments, in order.
  List<Expression> get positional => arguments.whereType<Expression>().toList();

  /// The positional argument at [index], or `null` if there is none.
  Expression? positionalAt(int index) {
    final list = positional;
    return index >= 0 && index < list.length ? list[index] : null;
  }

  /// The named arguments as `name -> expression`, in source order.
  Map<String, Expression> get named {
    final result = <String, Expression>{};
    for (final arg in arguments) {
      if (arg is NamedArgument) {
        result[_nameOf(arg.name)] = arg.argumentExpression;
      }
    }
    return result;
  }

  /// The expression of the first named argument matching any of [names].
  Expression? namedAny(List<String> names) {
    final map = named;
    for (final entry in map.entries) {
      if (names.contains(entry.key)) return entry.value;
    }
    return null;
  }
}

String _nameOf(Object? name) {
  if (name is Token) return name.lexeme;
  // Older shape: a `Label` wrapping a SimpleIdentifier.
  final dynamic label = name;
  return label.label.name as String;
}
