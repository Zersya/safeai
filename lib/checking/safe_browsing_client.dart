import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'url_expressions.dart';

sealed class GsbResult {
  const GsbResult();
}

class GsbClean extends GsbResult {
  const GsbClean();
}

class GsbThreats extends GsbResult {
  const GsbThreats(this.threats);
  final Set<ThreatType> threats;
}

class GsbFailed extends GsbResult {
  const GsbFailed(this.reason);
  final ReasonCode reason;
}

/// Source of Safe Browsing verdicts; faked in orchestrator tests.
abstract class ThreatSource {
  Future<GsbResult> check(List<String> asciiUrls);
}

class FullHashEntry {
  const FullHashEntry(this.hash, this.threats);
  final List<int> hash;
  final Set<ThreatType> threats;
}

typedef _CacheSlot = ({DateTime expiry, List<FullHashEntry> entries});

const _minCleanCache = Duration(minutes: 5);
const _maxCache = Duration(hours: 24);
const _maxPrefixesPerRequest = 30;
const _requestTimeout = Duration(seconds: 8);

/// Google Safe Browsing v5 `hashes:search`, "No Storage Real Time Mode".
/// Only 4-byte hash prefixes ever leave the device.
class SafeBrowsingClient implements ThreatSource {
  SafeBrowsingClient(this._client, this._apiKey, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final http.Client _client;
  final String _apiKey;
  final DateTime Function() _now;
  final Map<String, _CacheSlot> _cache = {};

  @override
  Future<GsbResult> check(List<String> asciiUrls) async {
    if (_apiKey.isEmpty) return const GsbFailed(ReasonCode.noApiKey);

    final expressions = <String>{
      for (final u in asciiUrls) ...expressionsFor(u),
    }.toList();
    final hashes = fullHashes(expressions);
    final prefixes = <String>{for (final h in hashes) base64.encode(h.sublist(0, 4))};

    final now = _now();
    _cache.removeWhere((_, slot) => !slot.expiry.isAfter(now));
    final missing = prefixes.where((p) => !_cache.containsKey(p)).toList();

    GsbFailed? failure;
    if (missing.isNotEmpty) {
      final chunks = [
        for (var i = 0; i < missing.length; i += _maxPrefixesPerRequest)
          missing.sublist(i, (i + _maxPrefixesPerRequest).clamp(0, missing.length)),
      ];
      final outcomes = await Future.wait(chunks.map(_fetch));
      for (final o in outcomes) {
        if (o != null) failure ??= o;
      }
    }

    final threats = <ThreatType>{};
    for (final h in hashes) {
      final slot = _cache[base64.encode(h.sublist(0, 4))];
      if (slot == null) continue;
      for (final e in slot.entries) {
        if (_equal(e.hash, h)) threats.addAll(e.threats);
      }
    }
    if (threats.isNotEmpty) return GsbThreats(threats);
    return failure ?? const GsbClean();
  }

  /// Returns null on success, otherwise the failure. Populates the cache.
  Future<GsbFailed?> _fetch(List<String> chunk) async {
    final uri = Uri(
      scheme: 'https',
      host: 'safebrowsing.googleapis.com',
      path: '/v5/hashes:search',
      queryParameters: {'key': _apiKey, 'alt': 'json', 'hashPrefixes': chunk},
    );
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(_requestTimeout);
    } on TimeoutException {
      return const GsbFailed(ReasonCode.noInternet);
    } on IOException {
      return const GsbFailed(ReasonCode.noInternet);
    } on http.ClientException {
      return const GsbFailed(ReasonCode.noInternet);
    }
    if (response.statusCode != 200) return const GsbFailed(ReasonCode.serviceError);

    final List<FullHashEntry> entries;
    Duration cacheDuration;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) throw const FormatException('not an object');
      entries = _parseEntries(body['fullHashes']);
      cacheDuration = _parseDuration(body['cacheDuration']);
    } on FormatException {
      return const GsbFailed(ReasonCode.serviceError);
    } on TypeError {
      return const GsbFailed(ReasonCode.serviceError);
    }

    final now = _now();
    for (final prefix in chunk) {
      final raw = base64.decode(prefix);
      final matching = [
        for (final e in entries)
          if (_startsWith(e.hash, raw)) e,
      ];
      var ttl = cacheDuration;
      if (matching.isEmpty && ttl < _minCleanCache) ttl = _minCleanCache;
      if (ttl > _maxCache) ttl = _maxCache;
      _cache[prefix] = (expiry: now.add(ttl), entries: matching);
    }
    return null;
  }

  static List<FullHashEntry> _parseEntries(Object? raw) {
    if (raw == null) return const [];
    final out = <FullHashEntry>[];
    for (final item in raw as List) {
      final map = item as Map<String, dynamic>;
      final hash = _decodeBase64(map['fullHash'] as String);
      final threats = <ThreatType>{};
      for (final d in (map['fullHashDetails'] as List? ?? const [])) {
        final detail = d as Map<String, dynamic>;
        final attrs = detail['attributes'] as List?;
        if (attrs != null && attrs.isNotEmpty) continue; // CANARY / FRAME_ONLY
        final t = ThreatType.fromApi(detail['threatType'] as String?);
        if (t != null) threats.add(t);
      }
      out.add(FullHashEntry(hash, threats));
    }
    return out;
  }

  static List<int> _decodeBase64(String s) {
    var v = s.replaceAll('-', '+').replaceAll('_', '/');
    while (v.length % 4 != 0) {
      v += '=';
    }
    return base64.decode(v);
  }

  static Duration _parseDuration(Object? raw) {
    if (raw is! String || !raw.endsWith('s')) return Duration.zero;
    final seconds = double.tryParse(raw.substring(0, raw.length - 1));
    if (seconds == null || seconds < 0) return Duration.zero;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  static bool _startsWith(List<int> a, List<int> prefix) {
    if (a.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (a[i] != prefix[i]) return false;
    }
    return true;
  }

  static bool _equal(List<int> a, List<int> b) =>
      a.length == b.length && _startsWith(a, b);
}
