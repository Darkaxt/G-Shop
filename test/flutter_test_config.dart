import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Keeps exact golden comparisons while routing this task's diagnostic output
/// away from pre-existing user files. CI/default runs retain Flutter's behavior.
class _TaskGoldenOutput extends LocalFileComparator {
  _TaskGoldenOutput(super.testFile, this.output);
  final Uri output;
  @override
  Future<String> generateFailureOutput(
          ComparisonResult result, Uri golden, Uri basedir,
          {String key = ''}) =>
      super.generateFailureOutput(result, golden, output, key: key);
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final output = Platform.environment['GSHOP_TEST_ARTIFACTS'];
  final current = goldenFileComparator;
  if (output != null && current is LocalFileComparator) {
    goldenFileComparator = _TaskGoldenOutput(
        current.basedir.resolve('_test.dart'), Uri.directory(output));
  }
  await testMain();
}
