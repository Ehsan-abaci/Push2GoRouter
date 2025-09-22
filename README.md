# **Push2GoRouter 🚀**

A command-line interface (CLI) tool designed to automate the migration of routing logic in Flutter projects from the imperative **Navigator 2.0** API to the declarative **go_router** package. This tool scans your codebase, generates a complete GoRouter configuration, and refactors your old Navigator calls to their modern equivalents.

## **Why Push2GoRouter? 🤔**

Manually migrating a large codebase from Navigator.pushNamed and Navigator.push to go_router can be a tedious and error-prone process. This tool was built to automate the migration, helping you:

- **Save Time & Effort**: Instead of manually changing hundreds of method calls, the tool does the heavy lifting in seconds.
- **Prevent Errors**: Static analysis ensures that all navigation calls are found and refactored, reducing the risk of missed instances.
- **Ensure Consistency**: By generating a centralized router file, it helps you manage all your app's routes in one place.
- **Migrate Intelligently**: If you already have a go_router file, the tool intelligently updates it, preserving any manual changes or complex routes you've already configured.

## **Features ✨**

- **Automatic Call Detection**: Finds all common Navigator calls, including push, pushNamed, pop, canPop, pushReplacementNamed, and more.
- **Helper Method Support**: Intelligently detects custom wrapper functions (e.g., MapsToUserDetails(context, id)) that you've created around the standard Navigator API.
- **Router File Generation**: Creates or updates a generated_router.dart file containing the complete GoRouter configuration based on the routes and widgets found in your project.
- **Smart Code Refactoring**: Automatically replaces old calls like Navigator.pushNamed(context, '/home') with the modern equivalent context.push('/home') and adds the necessary go_router import.
- **Safe Dry Run Mode**: Preview all proposed changes in the console without modifying a single file, giving you full control over the migration.
- **Preservation of Manual Changes**: When updating an existing router file, the tool preserves the original source code of GoRoute blocks it recognizes, ensuring your custom logic is not overwritten.

## **Installation**

Add this package to your project's pubspec.yaml as a development dependency.

```yaml
dev_dependencies:
  push2gorouter: ^0.0.1 # Replace with the latest version
```

Then, run flutter pub get.

## **Usage Instructions 🛠️**

Run the tool from the root of your Flutter project.

### **1\. Previewing Changes (Dry Run)**

First, run the tool in its default "dry run" mode. This will analyze your project and print a report of all the changes it plans to make without actually saving them. This is the recommended first step.

```sh
dart run push2gorouter migrate
```

You can also explicitly use the \--dry-run flag:

```sh
dart run push2gorouter migrate --dry-run
```

### **2\. Applying Changes**

Once you've reviewed the dry run and are ready to proceed, run the command with the \--write flag. This will perform the migration, creating/updating lib/generated_router.dart and refactoring all relevant source code files.

```sh
dart run push2gorouter migrate --write
```

After running the command, it's highly recommended to format your code:

```sh
dart format .
```

## **How It Works: The Migration Process**

The tool operates in a series of passes to ensure a comprehensive and safe migration:

1. **Helper Discovery**: The tool first scans your entire codebase to identify any custom "helper" methods that wrap Navigator.pushNamed calls. This allows it to understand your project-specific navigation abstractions.
2. **Invocation Analysis**: It performs a second scan to find all navigation invocations. This includes direct calls to Navigator (e.g., Navigator.of(context).pop()) and calls made via the helper methods discovered in the first pass.
3. **Existing Router Parsing**: The tool checks for an existing generated_router.dart file. If found, it parses the file to extract a list of all currently defined GoRoutes. This is crucial for preserving manually added routes.
4. **Route Merging**: The newly discovered routes from the code scan are intelligently merged with the routes from the existing router file. If a route exists in both places, the tool uses the latest information but preserves the original GoRoute source code block to avoid overwriting custom implementations.
5. **Router Generation**: The final, merged list of routes is passed to a generator that builds the new GoRouter configuration file. If an old file existed, it performs a surgical replacement of just the routes list to preserve other surrounding code.
6. **Code Refactoring**: Finally, a refactorer iterates through all the navigation calls found and replaces them in your Dart files with their go_router equivalents (context.push, context.go, context.pop, etc.).

## **Example Migration**

### **Before**

Your old navigation code might look like this:

```dart
// In some widget
onPressed: () {
 Navigator.pushNamed(context, '/details', arguments: {'id': 123});
}
// OR
onPressed: () {
 Navigator.pushNamed(context, Routes.details, arguments: {'id': 123});
}

// Another navigation call
onTap: () {
 Navigator.push(
 context,
 MaterialPageRoute(builder: (context) => const SettingsScreen(userId: 456)),
 );
}
```

### **After**

After running the migrator with \--write, your code is transformed:

```dart
import 'package:go_router/go_router.dart';

// In some widget
onPressed: () {
 context.push('/details', extra: <String, dynamic>{'id': 123});
}
// OR
onPressed: () {
 context.push(Routes.details, arguments: {'id': 123});
}

// Another navigation call
onTap: () {
 context.push('/settings-screen', extra: 456);
}
```

And a lib/generated_router.dart file is created/updated:

```dart
// GENERATED CODE \- DO NOT MODIFY BY HAND
import 'package.flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:my_app/screens/details_screen.dart';
import 'package:my_app/screens/settings_screen.dart';

final GoRouter router = GoRouter(
  routes: [
    GoRoute(
      path: '/details',
      builder: (BuildContext context, GoRouterState state) {
        final args = state.extra as Map<String, dynamic>;
        // TODO: Pass the map entries to your widget constructor.
        // e.g. return DetailsScreen(id: args\['id'\]);
        return const DetailsScreen();
        },
      ),
    GoRoute(
      path: '/settings-screen',
      builder: (BuildContext context, GoRouterState state) {
        final argument = state.extra as dynamic; // TODO: Cast to the correct type.
        return SettingsScreen(userId: argument);
        },
      ),
    ],
);
```

## **Limitations and Considerations**

- **Dynamic Routes**: Route names that are resolved at runtime from a variable cannot be statically determined. The tool will flag these as 'dynamic_route' and they will require manual migration.
- **Complex Arguments**: The tool generates // TODO comments for passing arguments (state.extra) to your widgets. You will need to complete this logic by casting to the correct type and passing the data to your widget's constructor.
- **pushAndRemoveUntil / popAndPushNamed**: These complex navigation patterns are replaced with a `TODO: Manual migration` and require manual review to ensure the navigation stack behavior matches your intent.

## **Contributing**

Contributions are welcome\! If you find a bug or have a feature request, please open an issue. If you'd like to contribute code, please fork the repository and submit a pull request.
