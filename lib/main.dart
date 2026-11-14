import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Makes the bundled-font licenses appear in Settings > About > Licenses.
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/LICENSES.txt');
    yield LicenseEntryWithLineBreaks(['Vazirmatn', 'Inter', 'Noto Sans SC'], text);
  });
  runApp(const Bootstrap());
}
