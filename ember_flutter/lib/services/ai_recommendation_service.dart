import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:ember_flutter/services/database_service.dart';
import 'package:ember_flutter/services/recommender_service.dart';
import 'package:ember_flutter/services/python_service.dart';

class AiRecommendationResponse {
  final List<Map<String, String>> songs;
  final String reason;

  AiRecommendationResponse({required this.songs, required this.reason});
}

class AiRecommendationService {
  static final Map<String, Future<AiRecommendationResponse>> _activeRequests = {};

  /// Gets a Mix, falling back to local SQLite if it fails
  static Future<AiRecommendationResponse> getAiMix(String mood) async {
    // 1. Debounce and Lock (Prevent users from spamming the button)
    if (_activeRequests.containsKey(mood)) {
      return _activeRequests[mood]!;
    }

    final future = _getAiMixInternal(mood);
    _activeRequests[mood] = future;

    try {
      return await future;
    } finally {
      _activeRequests.remove(mood);
    }
  }

  static Future<AiRecommendationResponse> _getAiMixInternal(String mood) async {
    try {
      final db = DatabaseService.instance;
      
      // 2. Cache Layer
      final cacheKey = 'local_mix_$mood';
      final cachedString = await db.getCache(cacheKey);
      if (cachedString != null) {
        try {
           final decoded = jsonDecode(cachedString);
           final timestamp = decoded['timestamp'] ?? 0;
           // 12 hour cache expiration (12 * 60 * 60 * 1000 = 43200000 ms)
           if (DateTime.now().millisecondsSinceEpoch - timestamp < 43200000) {
             final List<Map<String, String>> cachedSongs = (decoded['songs'] as List).map((e) => Map<String, String>.from(e)).toList();
             return AiRecommendationResponse(songs: cachedSongs, reason: decoded['reason']);
           }
        } catch (_) {}
      }

      final List<Map<String, String>> resolvedSongs = [];

      // Combine direct Python search with local RecommenderService
      final songSearchRes = await PythonService.search("$mood songs", filterType: "songs");
      if (songSearchRes.isSuccess && songSearchRes.data != null && (songSearchRes.data as List).isNotEmpty) {
         for(var item in (songSearchRes.data as List).take(10)) {
           resolvedSongs.add(Map<String, String>.from(item.map((key, value) => MapEntry(key.toString(), value?.toString() ?? ''))));
         }
      }

      final playHistory = await db.getPlayHistory();
      final recentIds = playHistory.take(3).map((e) => e['videoId']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
      final seedIds = recentIds.isNotEmpty ? recentIds : ['default'];
      
      final localRecs = await RecommenderService.instance.getRecommendations(seedIds);
      for(var rec in localRecs.take(10)) {
          final mapped = Map<String, String>.from(rec.map((key, value) => MapEntry(key.toString(), value?.toString() ?? '')));
          if(!resolvedSongs.any((s) => s['videoId'] == mapped['videoId'])) {
              resolvedSongs.add(mapped);
          }
      }

      if (resolvedSongs.isNotEmpty) {
        final responseObj = AiRecommendationResponse(
            songs: resolvedSongs.take(15).toList(), 
            reason: "Curated locally based on your taste and $mood vibe!"
        );
        // Save to Cache
        await db.setCache(cacheKey, jsonEncode({
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'songs': responseObj.songs,
          'reason': responseObj.reason
        }));
        return responseObj;
      }
    } catch (e) {
      debugPrint("Local Recommendation Request Failed. $e");
    }

    // 3. Fallback to Local Recommendations
    return _getLocalFallback(mood);
  }

  static Future<AiRecommendationResponse> _getLocalFallback(String mood) async {
    final localRecs = await RecommenderService.instance.getRecommendations(['default']);
    return AiRecommendationResponse(
      songs: localRecs.take(5).toList(), 
      reason: "Here are some local tracks picked from your favorites."
    );
  }
}
