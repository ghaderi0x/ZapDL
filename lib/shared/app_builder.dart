import 'package:flutter/material.dart';

import '../core/theme/app_fonts.dart';

/// MaterialApp.builder that makes both text direction and typography follow
/// the active language: Persian and Arabic are right-to-left with Vazirmatn;
/// English, Spanish and Russian are left-to-right with Inter; Chinese uses
/// Noto Sans SC. The language comes from Settings, or the system language when
/// "System default" is chosen.
Widget zapAppBuilder(BuildContext context, Widget? child) {
  final code = Localizations.localeOf(context).languageCode;
  return Directionality(
    textDirection: AppFonts.directionFor(code),
    child: Theme(
      data: AppFonts.applyTo(Theme.of(context), code),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}
