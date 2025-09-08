import 'package:analyzer/dart/element/element2.dart';

/// Represents a user-defined method that wraps a `Navigator.pushNamed` call.
///
/// The migration tool uses this to identify and correctly refactor
/// custom navigation helper functions.
class NavigationHelper {
  /// The executable element of the declared method.
  final ExecutableElement2 element;

  /// The index of the parameter in the method signature that holds the route name.
  final int routeNameParameterIndex;

  /// Creates a model for a navigation helper method.
  NavigationHelper({
    required this.element,
    required this.routeNameParameterIndex,
  });
}
