import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Safe Browsing URL canonicalization and hashing, following
/// https://developers.google.com/safe-browsing/reference/URLs.and.Hashing.
/// Works on bytes because [Uri] re-normalizes what we must keep literal.

class CanonicalUrl {
  const CanonicalUrl(this.host, this.path, this.query);

  final String host;
  final String path;

  /// Text after the first `?`, or null when the URL has no `?`.
  final String? query;

  String get pathAndQuery => query == null ? path : '$path?$query';

  @override
  String toString() => '$host$pathAndQuery';
}

const _tab = 0x09, _lf = 0x0A, _cr = 0x0D;
const _slash = 0x2F, _question = 0x3F, _hash = 0x23, _at = 0x40;
const _colon = 0x3A, _percent = 0x25;

int _hexVal(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

List<int> _unescapeOnce(List<int> input) {
  final out = <int>[];
  var i = 0;
  while (i < input.length) {
    if (input[i] == _percent && i + 2 < input.length) {
      final h = _hexVal(input[i + 1]);
      final l = _hexVal(input[i + 2]);
      if (h >= 0 && l >= 0) {
        out.add(h * 16 + l);
        i += 3;
        continue;
      }
    }
    out.add(input[i]);
    i++;
  }
  return out;
}

List<int> _unescapeFully(List<int> input) {
  var current = input;
  for (var round = 0; round < 1024; round++) {
    final next = _unescapeOnce(current);
    if (next.length == current.length) return next;
    current = next;
  }
  return current;
}

int _indexOf(List<int> bytes, int value, [int from = 0]) {
  for (var i = from; i < bytes.length; i++) {
    if (bytes[i] == value) return i;
  }
  return -1;
}

int _lastIndexOf(List<int> bytes, int value) {
  for (var i = bytes.length - 1; i >= 0; i--) {
    if (bytes[i] == value) return i;
  }
  return -1;
}

/// inet_aton-style IPv4 parsing (decimal, octal, hex; 1-4 components).
String? _parseIpv4(String host) {
  final parts = host.split('.');
  if (parts.isEmpty || parts.length > 4) return null;
  final values = <int>[];
  for (final p in parts) {
    if (p.isEmpty) return null;
    int? v;
    if (p.length > 2 && (p.startsWith('0x') || p.startsWith('0X'))) {
      v = int.tryParse(p.substring(2), radix: 16);
    } else if (p.length > 1 && p.startsWith('0')) {
      v = int.tryParse(p.substring(1), radix: 8);
    } else if (p == '0x' || p == '0X') {
      v = 0;
    } else {
      v = int.tryParse(p);
    }
    if (v == null || v < 0) return null;
    values.add(v);
  }
  for (var i = 0; i < values.length - 1; i++) {
    if (values[i] > 255) return null;
  }
  final lastBits = 32 - 8 * (values.length - 1);
  if (values.last >= (1 << lastBits)) return null;
  var addr = 0;
  for (var i = 0; i < values.length - 1; i++) {
    addr |= values[i] << (24 - 8 * i);
  }
  addr |= values.last;
  return '${(addr >> 24) & 255}.${(addr >> 16) & 255}.${(addr >> 8) & 255}.${addr & 255}';
}

final _v4Mapped = RegExp(r'^\[(?:::ffff:|64:ff9b::)(\d+\.\d+\.\d+\.\d+)\]$');

String _canonicalHost(List<int> hostBytes) {
  var host = latin1.decode(_unescapeFully(hostBytes)).toLowerCase();
  if (host.startsWith('[')) {
    final mapped = _v4Mapped.firstMatch(host);
    if (mapped != null) {
      final v4 = _parseIpv4(mapped.group(1)!);
      if (v4 != null) return v4;
    }
    return host;
  }
  host = host.replaceAll(RegExp(r'^\.+|\.+$'), '').replaceAll(RegExp(r'\.{2,}'), '.');
  return _parseIpv4(host) ?? host;
}

String _canonicalPath(String path) {
  final segments = path.split('/');
  final out = <String>[];
  for (final s in segments) {
    if (s.isEmpty || s == '.') continue;
    if (s == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(s);
  }
  final last = segments.last;
  final trailing = last.isEmpty || last == '.' || last == '..';
  if (out.isEmpty) return '/';
  return '/${out.join('/')}${trailing ? '/' : ''}';
}

String _escape(String s) {
  final sb = StringBuffer();
  for (final c in latin1.encode(s)) {
    if (c <= 0x20 || c >= 0x7F || c == _hash || c == _percent) {
      sb.write('%${c.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    } else {
      sb.writeCharCode(c);
    }
  }
  return sb.toString();
}

CanonicalUrl canonicalize(String url) {
  var bytes = utf8.encode(url).where((b) => b != _tab && b != _cr && b != _lf).toList();
  final hashAt = _indexOf(bytes, _hash);
  if (hashAt >= 0) bytes = bytes.sublist(0, hashAt);

  var rest = bytes;
  final schemeEnd = _indexOfSequence(bytes, const [_colon, _slash, _slash]);
  if (schemeEnd >= 0) rest = bytes.sublist(schemeEnd + 3);

  var authorityEnd = rest.length;
  for (var i = 0; i < rest.length; i++) {
    if (rest[i] == _slash || rest[i] == _question) {
      authorityEnd = i;
      break;
    }
  }
  var authority = rest.sublist(0, authorityEnd);
  var pathQuery = rest.sublist(authorityEnd);
  if (pathQuery.isEmpty) pathQuery = const [_slash];
  if (pathQuery.first == _question) pathQuery = [_slash, ...pathQuery];

  final at = _lastIndexOf(authority, _at);
  if (at >= 0) authority = authority.sublist(at + 1);
  if (authority.isNotEmpty && authority.first == 0x5B) {
    final close = _indexOf(authority, 0x5D);
    if (close >= 0) authority = authority.sublist(0, close + 1);
  } else {
    final colon = _lastIndexOf(authority, _colon);
    if (colon >= 0 && authority.skip(colon + 1).every((b) => b >= 0x30 && b <= 0x39)) {
      authority = authority.sublist(0, colon);
    }
  }

  final host = _canonicalHost(authority);

  final unescaped = _unescapeFully(pathQuery);
  final q = _indexOf(unescaped, _question);
  final pathRaw = latin1.decode(q < 0 ? unescaped : unescaped.sublist(0, q));
  final query = q < 0 ? null : latin1.decode(unescaped.sublist(q + 1));

  return CanonicalUrl(
    _escape(host),
    _escape(_canonicalPath(pathRaw)),
    query == null ? null : _escape(query),
  );
}

int _indexOfSequence(List<int> bytes, List<int> needle) {
  for (var i = 0; i + needle.length <= bytes.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}

/// Host-suffix / path-prefix expressions to look up for [asciiUrl].
List<String> expressionsFor(String asciiUrl) {
  final c = canonicalize(asciiUrl);

  final hosts = <String>[c.host];
  final isIp = c.host.startsWith('[') || RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(c.host);
  if (!isIp) {
    final labels = c.host.split('.');
    for (var n = labels.length < 5 ? labels.length : 5; n >= 2; n--) {
      final candidate = labels.sublist(labels.length - n).join('.');
      if (!hosts.contains(candidate)) hosts.add(candidate);
    }
  }

  final paths = <String>[];
  void addPath(String p) {
    if (!paths.contains(p)) paths.add(p);
  }

  if (c.query != null) addPath(c.pathAndQuery);
  addPath(c.path);
  addPath('/');
  final dirs = c.path.split('/').where((s) => s.isNotEmpty).toList();
  // The final segment is a file name unless the path ends with '/'.
  if (!c.path.endsWith('/') && dirs.isNotEmpty) dirs.removeLast();
  var prefix = '/';
  for (final d in dirs.take(3)) {
    prefix = '$prefix$d/';
    addPath(prefix);
  }

  return [
    for (final h in hosts)
      for (final p in paths) '$h$p',
  ];
}

List<List<int>> fullHashes(List<String> expressions) =>
    [for (final e in expressions) sha256.convert(utf8.encode(e)).bytes];
