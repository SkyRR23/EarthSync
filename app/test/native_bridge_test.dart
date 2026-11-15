import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/nasa_bridge_checks.dart';

// Build app/rust in release mode before running: uses the actual generated FFI
// loader and native library, not RustLib.initMock or a substituted calculation.
void main() {
  SharedPreferences.setMockInitialValues({});
  registerNasaBridgeChecks();
}
