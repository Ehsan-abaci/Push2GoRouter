import 'dart:io';
import 'package:args/args.dart';
import '../src/migration_runner.dart';
import 'package:path/path.dart' as p;

const String version = '16.2.1';

/// The entry point for the migration CLI tool.
///
/// Parses command-line arguments and orchestrates the migration process.
void main(List<String> args) async {
  final parser = ArgParser()
    ..addCommand(
        'migrate',
        ArgParser()
          ..addFlag('dry-run',
              negatable: false,
              help: 'Preview the changes without modifying files.',
              defaultsTo: true)
          ..addFlag('write',
              negatable: false,
              help: 'Apply the refactoring changes to the files.'))
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Shows usage information.');

  final argResults = parser.parse(args);

  if (argResults['help'] as bool || argResults.command == null) {
    _printUsage(parser);
    return;
  }

  if (argResults.command?.name == 'migrate') {
    final migrateArgs = argResults.command!;
    final isDryRun = migrateArgs['write'] != true;

    final projectDir = Directory.current;
    final libDir = Directory(p.join(projectDir.path, 'lib'));

    if (!await libDir.exists()) {
      stderr.writeln('Error: `lib` directory not found.');
      stderr.writeln(
          'Please run this command from the root of a Flutter project.');
      exit(1);
    }

    print('Starting migration analysis for project at ${projectDir.path}...');
    // The runner now takes the validated lib directory and the project directory separately.
    final runner =
        MigrationRunner(projectDirectory: projectDir, applyChanges: !isDryRun);
    await runner.run();

    print('\nMigration process finished.');
    if (isDryRun) {
      print('This was a dry run. No files were modified.');
      print('To apply these changes, run the command with the --write flag:');
      print('  dart run push2gorouter migrate --write');
    } else {
      print('Your source code has been modified.');
    }
  }
}

void _printUsage(ArgParser parser) {
  print('Navigation Migrator for go_router v$version');
  print('Usage: push2gorouter <command> [options]');
  print('\nAvailable commands:');
  print('  migrate   Scans the project and refactors Navigator 2.0 calls.');
  print('\nOptions for migrate:');
  print(parser.commands['migrate']!.usage);
}
