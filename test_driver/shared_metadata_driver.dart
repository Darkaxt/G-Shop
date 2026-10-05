import 'package:integration_test/integration_test_driver.dart';

// A driver success without the expected fixture report is not verification.
Future<void> main() => integrationDriver(responseDataCallback: (data) async {
      if (data == null ||
          !(data['native_lifecycle_requires_supervisor_evidence'] == true ||
              (data['external_workflow'] is Map &&
                  data['sqlite_rebuild'] is Map))) {
        throw StateError(
            'Native shared metadata proof returned no complete report');
      }
      await writeResponseData(data);
    });
