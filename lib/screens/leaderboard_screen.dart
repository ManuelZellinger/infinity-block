import '../widgets/friend_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_settings.dart';
import '../widgets/liquid_glass.dart';

class _Entry {
  final String name;
  final String id;
  final int score;
  final bool isCreator;
  final bool isFriend;
  final bool isCloseFriend;
  final bool isLive;
  _Entry({
    required this.name,
    required this.id,
    required this.score,
    this.isCreator = false,
    this.isFriend = false,
    this.isCloseFriend = false,
    this.isLive = false,
  });
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  final _listCtrl = ScrollController();
  final _friendIds = <String>{};
  final _incoming = <String>{};
  final _outgoing = <String>{};

  late List<_Entry> _all;
  final Set<String> _closeFriends = {};
  final Set<String> _otherFriends = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _all = [
      _Entry(
          name: 'Manuel Zellinger (Creator)',
          id: '@manuelzellinger',
          score: 12840,
          isCreator: true,
          isLive: true),
      _Entry(name: 'Nova Fox', id: 'nova_fox42', score: 128400, isLive: true),
      _Entry(name: 'Pixel Knight', id: 'pixel_knight7', score: 110200),
      _Entry(
          name: 'Echo Storm', id: 'echo_storm3', score: 98500, isLive: true),
      _Entry(name: 'Lucky Dragon', id: 'lucky_dragon9', score: 87200),
      _Entry(name: 'Cosmic Velvet', id: 'cosmic_velvet1', score: 76000),
      _Entry(
          name: 'Turbo Quiet', id: 'turbo_quiet5', score: 65400, isLive: true),
      _Entry(name: 'Moon Pixel', id: 'moon_pixel2', score: 54000),
      _Entry(name: 'Crystal Neon', id: 'crystal_neon8', score: 43000),
      _Entry(name: 'Storm Echo', id: 'storm_echo4', score: 32000),
      for (var i = 11; i <= 40; i++)
        _Entry(name: 'Player $i', id: 'player_$i', score: 30000 - i * 400),
    ];
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  List<_Entry> _withMe(AppSettings s) {
    final meId = s.playerId.isEmpty ? 'local_player' : s.playerId;
    final meName = s.playerName.isEmpty ? 'Player' : s.playerName;
    final list = List<_Entry>.from(_all);
    list.removeWhere((e) => e.id == meId && !e.isCreator);
    if (!s.isCreator) {
      list.add(_Entry(
        name: meName,
        id: meId,
        score: 1200,
        isFriend: false,
        isLive: true,
      ));
    }
    list.sort((a, b) {
      if (a.isCreator) return -1;
      if (b.isCreator) return 1;
      return b.score.compareTo(a.score);
    });
    return list;
  }

  List<_Entry> _filtered(List<_Entry> src) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return src;
    return src.where((e) {
      if (e.name.toLowerCase().contains(q)) return true;
      if (e.id.toLowerCase().contains(q)) return true;
      if (q == '∞' && e.isCreator) return true;
      final idx = src.indexWhere((x) => x.id == e.id);
      final place = e.isCreator ? 0 : idx;
      if (int.tryParse(q) != null && int.parse(q) == place) return true;
      return false;
    }).toList();
  }

  Color _markColor(_Entry e, bool isMe) {
    if (e.isCreator) return const Color(0xFFFFD60A);
    final friend = _friendIds.contains(e.id) || e.isFriend;
    if (friend && e.isLive) return const Color(0xFF30D158);
    if (friend) return const Color(0xFF30D158);
    if (e.isLive) return const Color(0xFF64D2FF);
    return Colors.white24;
  }

  void _sendRequest(_Entry e) {
    setState(() {
      _outgoing.add(e.id);
      _incoming.add(e.id);
    });
  }

  void _acceptRequest(_Entry e) {
    setState(() {
      _incoming.remove(e.id);
      _outgoing.remove(e.id);
      _otherFriends.add(e.id);
      _friendIds.add(e.id);
    });
  }

  void _declineRequest(_Entry e) {
    setState(() {
      _incoming.remove(e.id);
      _outgoing.remove(e.id);
    });
  }

  void _promoteToClose(_Entry e) {
    setState(() {
      _otherFriends.remove(e.id);
      _closeFriends.add(e.id);
    });
  }

  void _removeFriend(_Entry e) {
    setState(() {
      _otherFriends.remove(e.id);
      _closeFriends.remove(e.id);
      _friendIds.remove(e.id);
    });
  }

  List<_Entry> _byIds(Iterable<String> ids, List<_Entry> all) {
    final map = {for (final e in all) e.id: e};
    return [for (final i in ids) if (map.containsKey(i)) map[i]!];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final board = _filtered(_withMe(s));

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF070A12) : const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Infinity',
            style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        iconTheme:
            IconThemeData(color: isDark ? Colors.white : Colors.black87),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: isDark ? Colors.cyanAccent : Colors.blueAccent,
          unselectedLabelColor: isDark ? Colors.white54 : Colors.black45,
          tabs: const [
            Tab(text: 'Leaderboard'),
            Tab(text: 'Friends'),
            Tab(text: 'Requests'),
            Tab(text: 'Map'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: LiquidGlass(
              isDark: isDark,
              radius: 28,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search name, ID or rank',
                  hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38),
                  icon: Icon(Icons.search,
                      color: isDark ? Colors.white54 : Colors.black45),
                ),
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _list(board, s, isDark, showAdd: true),
                _list(
                  board
                      .where((e) =>
                          _friendIds.contains(e.id) ||
                          e.isFriend ||
                          _closeFriends.contains(e.id) ||
                          _otherFriends.contains(e.id))
                      .toList(),
                  s,
                  isDark,
                  showAdd: false,
                ),
                _requests(s, isDark),
                _mapPlaceholder(s, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<_Entry> board, AppSettings s, bool isDark,
      {required bool showAdd}) {
    final meId = s.playerId;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: board.length,
      itemBuilder: (_, i) {
        final e = board[i];
        final isMe = e.id == meId || (s.isCreator && e.isCreator);
        final place = e.isCreator
            ? '∞'
            : '${board.where((x) => !x.isCreator).toList().indexWhere((x) => x.id == e.id) + 1}';

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LiquidGlass(
            isDark: isDark,
            radius: 22,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 36,
                  child: Text(
                    e.isCreator ? '∞' : place,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: e.isCreator
                          ? const Color(0xFFFFD60A)
                          : (isDark ? Colors.white70 : Colors.black54),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _markColor(e, isMe),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.name + (isMe ? ' (you)' : ''),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        e.id,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${e.score}',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!isMe && !e.isCreator) ...[
                  const SizedBox(width: 8),
                  if (showAdd)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          _outgoing.add(e.id);
                          _incoming.add(e.id);
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('Friend request sent to ${e.id}')),
                        );
                      },
                      icon: Icon(
                        _friendIds.contains(e.id)
                            ? Icons.check_circle
                            : Icons.person_add_alt_1,
                        color: _friendIds.contains(e.id)
                            ? const Color(0xFF30D158)
                            : const Color(0xFF64D2FF),
                      ),
                    )
                  else
                    // Mistkübel
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Entfernen',
                      onPressed: () {
                        _removeFriend(e);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${e.name} entfernt')),
                        );
                      },
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.redAccent,
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _requests(AppSettings s, bool isDark) {
    final ids = _incoming.toList();
    if (ids.isEmpty) {
      return Center(
        child: Text(
          'No friend requests',
          style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final id in ids)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LiquidGlass(
              isDark: isDark,
              radius: 22,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      id,
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _friendIds.add(id);
                        _incoming.remove(id);
                        _outgoing.remove(id);
                        _otherFriends.add(id);
                      });
                    },
                    child: const Text('Accept'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _incoming.remove(id);
                      _outgoing.remove(id);
                    }),
                    child: const Text('Decline'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _mapPlaceholder(AppSettings s, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LiquidGlass(
          isDark: isDark,
          radius: 28,
          padding: const EdgeInsets.all(20),
          child: Text(
            s.isCreator
                ? ''
                : 'Map: mutual friends with location visible only. No strangers.',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      ),
    );
  }
}

class _DemoMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF1A2332);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Offset.zero & size, const Radius.circular(16)),
        bg);
    final grid = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      final y = size.height * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    void pin(double nx, double ny, Color c) {
      final o = Offset(size.width * nx, size.height * ny);
      canvas.drawCircle(o, 7, Paint()..color = c);
      canvas.drawCircle(o, 3, Paint()..color = Colors.white);
    }

    pin(0.3, 0.4, const Color(0xFF22C55E));
    pin(0.55, 0.35, const Color(0xFF22C55E));
    pin(0.7, 0.55, const Color(0xFF3B82F6));
    pin(0.4, 0.65, const Color(0xFF3B82F6));
    pin(0.2, 0.7, const Color(0xFFEF4444));
    pin(0.8, 0.3, const Color(0xFFEF4444));
    pin(0.6, 0.75, const Color(0xFFEF4444));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
