import 'dart:typed_data';

import 'models.dart';

/// A full hash from `hashes:search` with the threat types that are valid for
/// enforcement.
class FullHashEntry {
  const FullHashEntry(this.hash, this.threats);
  final List<int> hash;
  final Set<ThreatType> threats;
}

class SearchHashesResponse {
  const SearchHashesResponse(this.entries, this.cacheDuration);
  final List<FullHashEntry> entries;
  final Duration cacheDuration;
}

/// Minimal decoder for `google.security.safebrowsing.v5.SearchHashesResponse`
/// (the v5 endpoint only answers in protobuf):
///
///     SearchHashesResponse { repeated FullHash full_hashes = 1; Duration cache_duration = 2; }
///     FullHash { bytes full_hash = 1; repeated FullHashDetail full_hash_details = 2; }
///     FullHashDetail { ThreatType threat_type = 1; repeated ThreatAttribute attributes = 2; }
///     Duration { int64 seconds = 1; int32 nanos = 2; }
///
/// Throws [FormatException] on malformed input.
SearchHashesResponse parseSearchHashesResponse(Uint8List bytes) {
  final entries = <FullHashEntry>[];
  var cache = Duration.zero;
  final r = _Reader(bytes);
  while (!r.done) {
    final tag = r.varint();
    switch (tag) {
      case 0x0A: // full_hashes
        final entry = _parseFullHash(_Reader(r.lengthDelimited()));
        if (entry != null) entries.add(entry);
      case 0x12: // cache_duration
        cache = _parseDuration(_Reader(r.lengthDelimited()));
      default:
        r.skip(tag);
    }
  }
  return SearchHashesResponse(entries, cache);
}

FullHashEntry? _parseFullHash(_Reader r) {
  List<int>? hash;
  final threats = <ThreatType>{};
  while (!r.done) {
    final tag = r.varint();
    switch (tag) {
      case 0x0A: // full_hash
        hash = r.lengthDelimited();
      case 0x12: // full_hash_details
        final t = _parseDetail(_Reader(r.lengthDelimited()));
        if (t != null) threats.add(t);
      default:
        r.skip(tag);
    }
  }
  return hash == null ? null : FullHashEntry(hash, threats);
}

/// Returns the threat type, or null when the detail must be disregarded:
/// unknown threat type, or any attribute present (CANARY / FRAME_ONLY and
/// unknown attributes are not for whole-page enforcement).
ThreatType? _parseDetail(_Reader r) {
  var type = 0;
  var hasAttributes = false;
  while (!r.done) {
    final tag = r.varint();
    switch (tag) {
      case 0x08: // threat_type
        type = r.varint();
      case 0x10 || 0x12: // attributes (unpacked / packed)
        hasAttributes = true;
        r.skip(tag);
      default:
        r.skip(tag);
    }
  }
  if (hasAttributes) return null;
  return switch (type) {
    1 => ThreatType.malware,
    2 => ThreatType.socialEngineering,
    3 => ThreatType.unwantedSoftware,
    4 => ThreatType.harmfulApp,
    _ => null,
  };
}

Duration _parseDuration(_Reader r) {
  var seconds = 0;
  var nanos = 0;
  while (!r.done) {
    final tag = r.varint();
    switch (tag) {
      case 0x08:
        seconds = r.varint();
      case 0x10:
        nanos = r.varint();
      default:
        r.skip(tag);
    }
  }
  return Duration(seconds: seconds, microseconds: nanos ~/ 1000);
}

class _Reader {
  _Reader(this._b);

  final Uint8List _b;
  int _p = 0;

  bool get done => _p >= _b.length;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_p >= _b.length || shift > 63) throw const FormatException('bad varint');
      final byte = _b[_p++];
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
  }

  Uint8List lengthDelimited() {
    final len = varint();
    if (len < 0 || _p + len > _b.length) throw const FormatException('bad length');
    final out = Uint8List.sublistView(_b, _p, _p + len);
    _p += len;
    return out;
  }

  /// Skips the value of a field whose [tag] was just read.
  void skip(int tag) {
    switch (tag & 7) {
      case 0:
        varint();
      case 1:
        _advance(8);
      case 2:
        lengthDelimited();
      case 5:
        _advance(4);
      default:
        throw const FormatException('unsupported wire type');
    }
  }

  void _advance(int n) {
    if (_p + n > _b.length) throw const FormatException('truncated');
    _p += n;
  }
}
