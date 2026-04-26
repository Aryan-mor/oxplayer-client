/// Formats a byte size for download progress (binary units).
String myTelegramFormatBytesShort(int bytes) {
  if (bytes < 0) return '?';
  if (bytes < 1024) return '$bytes B';
  const u = <String>['KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  final dec = (i == 0 && v < 10) ? 0 : 1;
  return '${v.toStringAsFixed(dec)} ${u[i]}';
}

/// Formats a wall-clock duration for Telegram media UI (`00:15:00`, `01:23:45`).
String myTelegramFormatDurationHms(int totalSeconds) {
  if (totalSeconds < 0) {
    return '00:00:00';
  }
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return '${h.toString().padLeft(2, '0')}:'
      '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}';
}
