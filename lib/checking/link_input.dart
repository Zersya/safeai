final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);
final _bareDomain = RegExp(
  r'^[a-z0-9-]+(\.[a-z0-9-]+)+(/\S*)?$',
  caseSensitive: false,
);
final _trailing = RegExp(r'''[.,;:!?)\]}'"]+$''');

/// Extracts the first http(s) link from free text. Returns null when there is
/// none; non-http(s) schemes never match.
String? extractUrl(String text) {
  final trimmed = text.trim();
  String? candidate = _urlPattern.firstMatch(trimmed)?.group(0);
  if (candidate == null) {
    for (final token in trimmed.split(RegExp(r'\s+'))) {
      final cleaned = token.replaceFirst(_trailing, '');
      if (_bareDomain.hasMatch(cleaned)) {
        candidate = 'https://$cleaned';
        break;
      }
    }
  }
  if (candidate == null) return null;
  candidate = candidate.replaceFirst(_trailing, '');
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return candidate;
}
