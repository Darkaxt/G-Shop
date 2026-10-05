import 'package:flutter/foundation.dart';

import 'shared_metadata_persistence_test.dart' as persistence;
import 'shared_metadata_workflow_test.dart' as workflow;

// One expendable APK for the current workflow and its OS lifecycle boundaries.
void main() {
  if (PlatformDispatcher.instance.defaultRouteName == '/workflow') {
    workflow.main();
  } else {
    persistence.main();
  }
}
