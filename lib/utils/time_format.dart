/// Formats a duration in seconds as `mm:ss`.
String formatMmSs(double seconds) {
  final total = seconds.round().clamp(0, 99 * 60 + 59);
  final minutes = total ~/ 60;
  final secs = total % 60;
  return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

/// Parses `mm:ss`, `m:ss`, `hh:mm:ss`, or plain seconds into seconds.
double? parseTimeInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final parts = text.split(':');
  if (parts.length == 1) {
    final value = double.tryParse(parts[0]);
    if (value == null || value < 0) return null;
    return value;
  }

  if (parts.length == 2 || parts.length == 3) {
    final numbers = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0) return null;
      numbers.add(n);
    }
    if (parts.length == 2) {
      final minutes = numbers[0];
      final secs = numbers[1];
      if (secs >= 60) return null;
      return (minutes * 60 + secs).toDouble();
    }
    final hours = numbers[0];
    final minutes = numbers[1];
    final secs = numbers[2];
    if (minutes >= 60 || secs >= 60) return null;
    return (hours * 3600 + minutes * 60 + secs).toDouble();
  }

  return null;
}
