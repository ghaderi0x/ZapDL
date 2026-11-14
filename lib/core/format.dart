import 'package:intl/intl.dart';

String formatBytes(num bytes, String locale) {
  if (bytes < 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final f = NumberFormat(i == 0 ? '#,##0' : '#,##0.0', locale);
  return '${f.format(v)} ${units[i]}';
}

String formatSpeed(num bytesPerSecond, String locale) =>
    '${formatBytes(bytesPerSecond, locale)}/s';

String formatDuration(int seconds, String locale) {
  final two = NumberFormat('00', locale);
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${NumberFormat('#0', locale).format(h)}:${two.format(m)}:${two.format(s)}';
  return '${NumberFormat('#0', locale).format(m)}:${two.format(s)}';
}

String formatDate(DateTime d, String locale) => DateFormat.yMd(locale).format(d);

String formatDateTime(DateTime d, String locale) => DateFormat.yMd(locale).add_jm().format(d);

String formatInt(int v, String locale) => NumberFormat.decimalPattern(locale).format(v);

String formatDayShort(DateTime d, String locale) => DateFormat.E(locale).format(d);

String formatPercent(double fraction, String locale) =>
    NumberFormat.percentPattern(locale).format(fraction);
