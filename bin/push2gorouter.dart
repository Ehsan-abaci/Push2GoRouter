import 'dart:io';
import 'package:args/args.dart';
import '../src/migration_runner.dart';
import 'package:path/path.dart' as p;

const String version = '0.0.5';

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
    ..addCommand(
        'generate',
        ArgParser()
          ..addFlag('dry-run',
              negatable: false,
              help: 'Preview the router file without writing it.',
              defaultsTo: true)
          ..addFlag('write',
              negatable: false,
              help: 'Write the router file. Source files are never modified.')
          ..addOption('output',
              abbr: 'o',
              help: 'Router file path, relative to the project root.',
              defaultsTo: 'lib/generated_router.dart'))
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Shows usage information.');

  final argResults = parser.parse(args);

  if (argResults['help'] as bool || argResults.command == null) {
    _printUsage(parser);
    return;
  }

  final command = argResults.command!;
  final isMigrate = command.name == 'migrate';
  final isDryRun = command['write'] != true;

  final projectDir = Directory.current;
  final libDir = Directory(p.join(projectDir.path, 'lib'));

  if (!await libDir.exists()) {
    stderr.writeln('Error: `lib` directory not found.');
    stderr.writeln('Please run this command from the root of a Flutter project.');
    exit(1);
  }

  print('Starting ${isMigrate ? 'migration' : 'router generation'} analysis '
      'for project at ${projectDir.path}...');
  final runner = MigrationRunner(
    projectDirectory: projectDir,
    applyChanges: !isDryRun,
    refactorSources: isMigrate,
    routerFileOverride: isMigrate ? null : command['output'] as String,
  );
  await runner.run();

  final flag = command.name;
  print('\nProcess finished.');
  if (isDryRun) {
    print('This was a dry run. No files were modified.');
    print('To apply these changes, run the command with the --write flag:');
    print('  dart run push2gorouter $flag --write');
  } else if (isMigrate) {
    print('Your source code has been modified.');
  } else {
    print('The router file has been written. Your source code was not modified.');
  }
}

void _printUsage(ArgParser parser) {
  print('Navigation Migrator for go_router v$version');
  print('Usage: push2gorouter <command> [options]');
  print('\nAvailable commands:');
  print('  migrate   Scans the project, generates the router and refactors Navigator calls.');
  print('  generate  Only generates/updates the go_router file; no source changes.');
  print('\nOptions for migrate:');
  print(parser.commands['migrate']!.usage);
  print('\nOptions for generate:');
  print(parser.commands['generate']!.usage);
}
