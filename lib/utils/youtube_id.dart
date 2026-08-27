/// Extracts an 11-character YouTube video id from a URL or raw id.
String? extractYoutubeVideoId(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;

  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(value)) {
    return value;
  }

  final uri = Uri.tryParse(value);
  if (uri == null) return null;

  if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
    final id = uri.pathSegments.first;
    return id.length == 11 ? id : null;
  }

  if (uri.queryParameters['v'] != null) {
    final id = uri.queryParameters['v']!;
    return id.length == 11 ? id : null;
  }

  final embedIndex = uri.pathSegments.indexOf('embed');
  if (embedIndex != -1 && embedIndex + 1 < uri.pathSegments.length) {
    final id = uri.pathSegments[embedIndex + 1];
    return id.length == 11 ? id : null;
  }

  final shortsIndex = uri.pathSegments.indexOf('shorts');
  if (shortsIndex != -1 && shortsIndex + 1 < uri.pathSegments.length) {
    final id = uri.pathSegments[shortsIndex + 1];
    return id.length == 11 ? id : null;
  }

  return null;
}
