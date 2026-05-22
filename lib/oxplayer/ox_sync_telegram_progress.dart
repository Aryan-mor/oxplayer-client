/// Progress for Telegram TDLib offline sync (`[OX_SYNC]` download + copy phases).
typedef OxTelegramSyncProgressCallback = void Function(
  double fraction, {
  int? downloadedBytes,
  int? totalBytes,
  String? speedLabel,
});

String oxSyncFormatBytesPerSec(double bytesPerSec) {
  if (bytesPerSec.isNaN || bytesPerSec.isInfinite || bytesPerSec <= 0) {
    return '';
  }
  if (bytesPerSec >= 1024 * 1024) {
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  if (bytesPerSec >= 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s';
  }
  return '${bytesPerSec.toStringAsFixed(0)} B/s';
}
