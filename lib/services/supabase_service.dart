import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  static const String supabaseUrl = 'https://hsksksqgehtxrgumkbxv.supabase.co';
  static const String supabasePublishableKey =
      'sb_publishable_STyYekqJ-vuaH8kIHChU4A_hmK5f2-h';

  SupabaseClient get _client => Supabase.instance.client;

  /// Initialize once in main()
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabasePublishableKey,
    );
  }

  // ─────────────────────────────────────────────
  // Scores / Leaderboard
  // ─────────────────────────────────────────────

  Future<void> submitScore({
    required String playerId,
    required String displayName,
    required int score,
    String game = 'classic',
  }) async {
    try {
      await _client.from('scores').insert({
        'player_id': playerId,
        'display_name': displayName,
        'score': score,
        'game': game,
      });
    } catch (e) {
      debugPrint('submitScore error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getTopScores({
    String game = 'classic',
    int limit = 50,
  }) async {
    try {
      final res = await _client
          .from('scores')
          .select()
          .eq('game', game)
          .order('score', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('getTopScores error: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────────
  // Friends
  // ─────────────────────────────────────────────

  /// Send friend request
  Future<bool> sendFriendRequest({
    required String fromPlayerId,
    required String toPlayerId,
  }) async {
    try {
      await _client.from('friend_requests').insert({
        'from_player_id': fromPlayerId,
        'to_player_id': toPlayerId,
        'status': 'pending',
      });
      return true;
    } catch (e) {
      debugPrint('sendFriendRequest error: $e');
      return false;
    }
  }

  /// Accept friend request
  Future<bool> acceptFriendRequest({
    required String fromPlayerId,
    required String toPlayerId,
  }) async {
    try {
      await _client
          .from('friend_requests')
          .update({'status': 'accepted'})
          .eq('from_player_id', fromPlayerId)
          .eq('to_player_id', toPlayerId)
          .eq('status', 'pending');
      return true;
    } catch (e) {
      debugPrint('acceptFriendRequest error: $e');
      return false;
    }
  }

  /// Remove friend (both directions)
  Future<bool> removeFriend({
    required String myPlayerId,
    required String friendPlayerId,
  }) async {
    try {
      await _client
          .from('friend_requests')
          .update({
            'status': 'removed',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .or(
            'and(from_player_id.eq.$myPlayerId,to_player_id.eq.$friendPlayerId),'
            'and(from_player_id.eq.$friendPlayerId,to_player_id.eq.$myPlayerId)',
          );
      return true;
    } catch (e) {
      debugPrint('removeFriend error: $e');
      return false;
    }
  }

  /// Get accepted friends for a player
  Future<List<Map<String, dynamic>>> getFriends(String playerId) async {
    try {
      final res = await _client
          .from('friend_requests')
          .select()
          .eq('status', 'accepted')
          .or('from_player_id.eq.$playerId,to_player_id.eq.$playerId');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('getFriends error: $e');
      return [];
    }
  }

  // ─────────────────────────────────────────────
  // Usage events (Creator stats)
  // ─────────────────────────────────────────────

  Future<void> logUsageEvent({
    required String eventType,
    String? game,
    String? playerId,
  }) async {
    try {
      await _client.from('usage_events').insert({
        'event_type': eventType,
        'game': game,
        'player_id': playerId,
      });
    } catch (e) {
      debugPrint('logUsageEvent error: $e');
    }
  }
}
