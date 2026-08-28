import 'dart:html' as html;

String createMediaBlobUrl(List<int> bytes, String mimeType) {
  return html.Url.createObjectUrlFromBlob(html.Blob([bytes], mimeType));
}

void revokeMediaBlobUrl(String? url) {
  if (url != null && url.startsWith('blob:')) {
    html.Url.revokeObjectUrl(url);
  }
}