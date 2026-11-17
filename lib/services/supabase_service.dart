import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  static const String _url = 'https://hsksksqgehtxrgumkbxv.supabase.co';
  static const String _key =
      'sb_publishable_STyYekqJ-vuaH8kIHChU4A_hmK5f2-h';

  SupabaseClient get _client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _url,
      anonKey: _key,
    );
  }

  // ─── Scores ───────────────────────────────────────────────

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
      debugPrint('submitScore: $e');
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
      debugPrint('getTopScores: $e');
      return [];
    }
  }

  // ─── Friends ──────────────────────────────────────────────

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
      debugPrint('sendFriendRequest: $e');
      return false;
    }
  }

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
      debugPrint('acceptFriendRequest: $e');
      return false;
    }
  }

  /// Freund entfernen (Mistkübel)
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
      debugPrint('removeFriend: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getFriends(String playerId) async {
    try {
      final res = await _client
          .from('friend_requests')
          .select()
          .eq('status', 'accepted')
          .or('from_player_id.eq.$playerId,to_player_id.eq.$playerId');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('getFriends: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getPendingRequests(String myPlayerId) async {
    try {
      final res = await _client
          .from('friend_requests')
          .select()
          .eq('to_player_id', myPlayerId)
          .eq('status', 'pending');
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('getPendingRequests: $e');
      return [];
    }
  }

  // ─── Usage ────────────────────────────────────────────────

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
      debugPrint('logUsageEvent: $e');
    }
  }
}
