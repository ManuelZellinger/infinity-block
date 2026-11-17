import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

/// Fertiger Freund-Eintrag mit Mistkübel zum Entfernen.
/// Einfach in deine Freunde-Liste einbauen.
class FriendTile extends StatelessWidget {
  final String myPlayerId;
  final String friendPlayerId;
  final String displayName;
  final String? avatar;
  final int? highscore;
  final VoidCallback? onRemoved;

  const FriendTile({
    super.key,
    required this.myPlayerId,
    required this.friendPlayerId,
    required this.displayName,
    this.avatar,
    this.highscore,
    this.onRemoved,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.white10,
        child: Text(
          (avatar != null && avatar!.isNotEmpty)
              ? avatar!
              : displayName.isNotEmpty
                  ? displayName[0].toUpperCase()
                  : '?',
          style: const TextStyle(fontSize: 18),
        ),
      ),
      title: Text(
        displayName,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        friendPlayerId,
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (highscore != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '$highscore',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          // Mistkübel
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              size: 20,
              color: Colors.redAccent,
            ),
            tooltip: 'Entfernen',
            onPressed: () async {
              final ok = await SupabaseService.instance.removeFriend(
                myPlayerId: myPlayerId,
                friendPlayerId: friendPlayerId,
              );
              if (ok) {
                onRemoved?.call();
              }
            },
          ),
        ],
      ),
    );
  }
}
