import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const SBArenaApp());

/* ==========================
   S&B ARENA (TEK DOSYA DEMO)
   Türkçe • Material 3 • Web+Mobil
   ========================== */

const String kAppName = 'S&B ARENA';

// Premium
const String kPremiumTierName = 'DARK GOLD';
const String kPremiumCrown = '👑';
const String kPremiumTitleTR = 'KARA ALTIN ELİT';

// Level/XP
const int kMaxLevel = 99;
const int kChatXp = 2;
const int kPostXp = 25;
const int kMinuteXp = 1;
const double kPremiumXpMultiplier = 1.25; // premium XP bonusu
const int kDailyXpCapUser = 300;
const int kDailyXpCapPremium = 450;

// Limits
const Duration kChatXpCooldown = Duration(seconds: 10);
const int kChatMaxLen = 280;
const int kForumTitleMax = 80;
const int kForumContentMax = 2000;

// Weekly leaderboard demo
const int kWeeklyDays = 7;

enum UserRole { user, admin }
enum MessageType { user, system }

DateTime _todayKey() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _norm(String s) => s.trim().toLowerCase();
String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
String _ddmmyyyy(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );
}

Future<void> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required VoidCallback ok,
  String okText = 'Onayla',
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(okText)),
      ],
    ),
  );
  if (res == true) ok();
}

/* ==========================
   MODELLER
   ========================== */

class UserModel {
  UserModel({
    required this.uid,
    required this.username,
    required this.password,
    required this.displayName,
    required this.role,
    required this.createdAt,
  });

  final String uid;
  String username; // normalized
  String password; // demo
  String displayName;
  UserRole role;

  bool isOnline = false;
  bool isBanned = false;
  String? banReason;
  DateTime createdAt;
  DateTime lastSeenAt = DateTime.now();

  bool isPremium = false;
  String premiumTier = 'none';

  int level = 1;
  int xpPool = 0;
  int totalXp = 0;
  String title = 'Çaylak';
  final List<String> badges = [];

  DateTime dayKey = _todayKey();
  int todayXp = 0;
  DateTime? lastXpChatAt;
  DateTime? lastMinuteTickAt;

  bool get isAdmin => role == UserRole.admin;
}

class NewsItem {
  NewsItem({
    required this.id,
    required this.title,
    required this.source,
    required this.excerpt,
    required this.publishedAt,
    this.imageSeed = 0,
    this.url = '',
    this.imageUrl = '',
  });

  final String id;
  final String title;
  final String source;
  final String excerpt;
  final DateTime publishedAt;
  final int imageSeed;
  final String url;
  final String imageUrl;
}

class ChatRoom {
  ChatRoom({required this.id, required this.name, required this.premiumOnly});
  final String id;
  final String name;
  final bool premiumOnly;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.roomId,
    required this.uid,
    required this.username,
    required this.text,
    required this.type,
    required this.createdAt,
  });

  final String id;
  final String roomId;
  final String uid;
  final String username;
  final String text;
  final MessageType type;
  final DateTime createdAt;

  bool deleted = false;
}

class ForumPost {
  ForumPost({
    required this.id,
    required this.uid,
    required this.username,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String uid;
  final String username;
  String title;
  String content;
  final DateTime createdAt;

  bool deleted = false;
  bool pinned = false;
}

class MuteRecord {
  MuteRecord({required this.uid, required this.until, required this.reason});
  final String uid;
  DateTime until;
  String reason;

  bool get isActive => DateTime.now().isBefore(until);
}

class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.premiumPriority = false,
  });

  final String id;
  final String title;
  final String body;
  final String type; // sistem/haber/duyuru
  final DateTime createdAt;
  final bool premiumPriority;
}

/* ==========================
   DEMO REPO (RAM)
   ========================== */

class DemoRepo {
  final Map<String, UserModel> usersByUid = {};
  final Map<String, String> uidByUsername = {};

  final List<NewsItem> news = [];

  final List<ChatRoom> rooms = [
    ChatRoom(id: 'global', name: 'Genel Arena', premiumOnly: false),
    ChatRoom(id: 'match', name: 'Maç Odası', premiumOnly: false),
    ChatRoom(id: 'elite', name: '$kPremiumCrown Elit Salon (Premium)', premiumOnly: true),
  ];

  final Map<String, List<ChatMessage>> messagesByRoom = {
    'global': [],
    'match': [],
    'elite': [],
  };

  final List<ForumPost> posts = [];
  final Map<String, MuteRecord> mutesByUid = {};
  final List<NotificationItem> notifications = [];
  final List<String> adminLogs = [];

  String newsApiKey = 'DEMO_KEY';

  void seed() {
    if (usersByUid.isNotEmpty) return;

    final admin = UserModel(
      uid: 'admin-1',
      username: 'admin',
      password: 'admin',
      displayName: 'Admin',
      role: UserRole.admin,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    )
      ..isPremium = true
      ..premiumTier = 'dark_gold'
      ..level = 15
      ..totalXp = 20000;

    admin.title = Titles.titleForLevel(admin.level, isPremium: true);
    admin.badges.addAll(['founder', 'moderator', 'premium']);

    final user = UserModel(
      uid: 'u-1',
      username: 'sbkaan',
      password: '1234',
      displayName: 'Kaan',
      role: UserRole.user,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    )
      ..level = 3
      ..totalXp = 900;

    user.title = Titles.titleForLevel(user.level, isPremium: false);
    user.badges.addAll(['newbie']);

    _addUser(admin);
    _addUser(user);

    _sysMsg('global', 'S&B ARENA’ya hoş geldin! 🏟️ Saygı çerçevesinde takılalım.');
    _sysMsg('match', 'Maç odası: Flood/spam yok. Keyifli tartışmalar!');
    _sysMsg('elite', '$kPremiumCrown Premium salonuna hoş geldin, $kPremiumTitleTR!');

    posts.addAll([
      ForumPost(
        id: 'p-1',
        uid: admin.uid,
        username: admin.username,
        title: '📌 Kurallar & Duyuru',
        content: '• Flood/spam yok\n• Saygılı iletişim\n• Küfür/nefret söylemi yok\n\nİyi eğlenceler!',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      )..pinned = true,
      ForumPost(
        id: 'p-2',
        uid: user.uid,
        username: user.username,
        title: 'Bugünkü maç yorumu',
        content: 'Bence orta saha harikaydı. Sizce kim yıldızlaştı?',
        createdAt: DateTime.now().subtract(const Duration(hours: 4)),
      ),
    ]);

    final now = DateTime.now();
    for (int i = 0; i < 12; i++) {
      news.add(
        NewsItem(
          id: 'n-$i',
          title: 'Spor Gündemi #${i + 1}: Kritik gelişmeler (DEMO)',
          source: i.isEven ? 'TR Spor' : 'Global Sport',
          excerpt: 'Bugün spor dünyasında dikkat çeken gelişmeler… (demo içerik)',
          publishedAt: now.subtract(Duration(hours: i * 3)),
          imageSeed: i % 5,
        ),
      );
    }

    pushNoti(title: 'Hoş geldin', body: 'Arena açıldı! Haberler, chat ve forum hazır.', type: 'sistem');
  }

  void _addUser(UserModel u) {
    usersByUid[u.uid] = u;
    uidByUsername[_norm(u.username)] = u.uid;
  }

  void _sysMsg(String roomId, String text) {
    messagesByRoom[roomId]!.add(
      ChatMessage(
        id: 'sys-${DateTime.now().microsecondsSinceEpoch}',
        roomId: roomId,
        uid: 'system',
        username: 'Sistem',
        text: text,
        type: MessageType.system,
        createdAt: DateTime.now(),
      ),
    );
  }

  void pushNoti({
    required String title,
    required String body,
    required String type,
    bool premiumPriority = false,
  }) {
    notifications.insert(
      0,
      NotificationItem(
        id: 'noti-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        body: body,
        type: type,
        createdAt: DateTime.now(),
        premiumPriority: premiumPriority,
      ),
    );
    if (notifications.length > 120) notifications.removeLast();
  }
}

/* ==========================
   SERVİSLER
   ========================== */

class Titles {
  static String titleForLevel(int level, {required bool isPremium}) {
    if (isPremium) return kPremiumTitleTR;
    if (level <= 5) return 'Çaylak';
    if (level <= 15) return 'Tribüncü';
    if (level <= 30) return 'Usta';
    if (level <= 50) return 'Kaptan';
    if (level <= 70) return 'Efsane';
    return 'ARENA İmparatoru';
  }
}

class XpService {
  int requiredXpForNextLevel(int level) => level * 300;

  void _rollDay(UserModel u) {
    final key = _todayKey();
    if (u.dayKey != key) {
      u.dayKey = key;
      u.todayXp = 0;
    }
  }

  int dailyCap(UserModel u) => u.isPremium ? kDailyXpCapPremium : kDailyXpCapUser;

  int addXp(UserModel u, int baseXp) {
    _rollDay(u);

    final cap = dailyCap(u);
    if (u.todayXp >= cap) return 0;

    final mult = u.isPremium ? kPremiumXpMultiplier : 1.0;
    final gained = max(0, (baseXp * mult).round());
    final allowed = min(gained, cap - u.todayXp);
    if (allowed <= 0) return 0;

    u.todayXp += allowed;
    u.xpPool += allowed;
    u.totalXp += allowed;

    while (u.level < kMaxLevel) {
      final need = requiredXpForNextLevel(u.level);
      if (u.xpPool >= need) {
        u.xpPool -= need;
        u.level += 1;
        u.title = Titles.titleForLevel(u.level, isPremium: u.isPremium);
        _award(u);
      } else {
        break;
      }
    }
    return allowed;
  }

  void _award(UserModel u) {
    void addOnce(String b) {
      if (!u.badges.contains(b)) u.badges.add(b);
    }

    if (u.level >= 5) addOnce('starter');
    if (u.level >= 15) addOnce('tribune');
    if (u.level >= 30) addOnce('veteran');
    if (u.level >= 50) addOnce('captain');
    if (u.level >= 70) addOnce('legend');
    if (u.isPremium) addOnce('premium');
  }
}

class AuthService {
  AuthService(this.repo);
  final DemoRepo repo;
  UserModel? currentUser;

  String? login(String username, String password) {
    final uid = repo.uidByUsername[_norm(username)];
    if (uid == null) return 'Kullanıcı bulunamadı.';
    final u = repo.usersByUid[uid]!;
    if (u.isBanned) return 'Bu hesap banlı: ${u.banReason ?? "Sebep belirtilmemiş."}';
    if (u.password != password) return 'Şifre hatalı.';
    currentUser = u;
    _online(true);
    return null;
  }

  String? register(String username, String password, String displayName) {
    final un = _norm(username);
    if (un.length < 3) return 'Kullanıcı adı en az 3 karakter olmalı.';
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) return 'Kullanıcı adı sadece harf, rakam ve "_" içermeli.';
    if (password.length < 4) return 'Şifre en az 4 karakter olmalı.';
    if (repo.uidByUsername.containsKey(un)) return 'Bu kullanıcı adı zaten alınmış.';

    final u = UserModel(
      uid: 'u-${DateTime.now().microsecondsSinceEpoch}',
      username: un,
      password: password,
      displayName: displayName.trim().isEmpty ? un : displayName.trim(),
      role: UserRole.user,
      createdAt: DateTime.now(),
    );

    u.title = Titles.titleForLevel(1, isPremium: false);
    u.badges.add('newbie');

    repo.usersByUid[u.uid] = u;
    repo.uidByUsername[un] = u.uid;

    currentUser = u;
    _online(true);
    return null;
  }

  void logout() {
    _online(false);
    currentUser = null;
  }

  void _online(bool v) {
    final u = currentUser;
    if (u == null) return;
    u.isOnline = v;
    u.lastSeenAt = DateTime.now();
  }
}

class ModerationService {
  ModerationService(this.repo);
  final DemoRepo repo;

  void ban(UserModel admin, UserModel target, String reason) {
    target.isBanned = true;
    target.banReason = reason;
    repo.adminLogs.add('[${DateTime.now()}] ${admin.username} banladı: ${target.username} ($reason)');
  }

  void unban(UserModel admin, UserModel target) {
    target.isBanned = false;
    target.banReason = null;
    repo.adminLogs.add('[${DateTime.now()}] ${admin.username} ban kaldırdı: ${target.username}');
  }

  void mute(UserModel admin, UserModel target, Duration dur, String reason) {
    repo.mutesByUid[target.uid] = MuteRecord(uid: target.uid, until: DateTime.now().add(dur), reason: reason);
    repo.adminLogs.add(
        '[${DateTime.now()}] ${admin.username} susturdu: ${target.username} (${dur.inMinutes}dk, $reason)');
  }

  void unmute(UserModel admin, UserModel target) {
    repo.mutesByUid.remove(target.uid);
    repo.adminLogs.add('[${DateTime.now()}] ${admin.username} susturma kaldırdı: ${target.username}');
  }

  MuteRecord? getMute(String uid) {
    final m = repo.mutesByUid[uid];
    if (m == null) return null;
    if (!m.isActive) {
      repo.mutesByUid.remove(uid);
      return null;
    }
    return m;
  }
}

class NewsService {
  NewsService(this.repo);
  final DemoRepo repo;

  Future<void> refreshDemo() async {
    await Future.delayed(const Duration(milliseconds: 350));
    final now = DateTime.now();
    repo.news.insert(
      0,
      NewsItem(
        id: 'n-${now.microsecondsSinceEpoch}',
        title: 'Yeni Haber: Arena gündemi güncellendi (DEMO)',
        source: 'S&B Feed',
        excerpt: 'Kaydır-yenile ile yeni demo haber eklendi.',
        publishedAt: now,
        imageSeed: now.second % 5,
      ),
    );
    if (repo.news.length > 25) repo.news.removeLast();
    repo.pushNoti(title: 'Yeni Haber', body: 'Haberler güncellendi (demo).', type: 'haber');
  }

  Future<List<NewsItem>> fetchFromNewsApi({required String apiKey}) async {
    final key = apiKey.trim();
    if (key.isEmpty || key == 'DEMO_KEY') return repo.news;

    final uri = Uri.https('newsapi.org', '/v2/everything', {
      'q':
          'football OR soccer OR basketball OR transfer OR champions league OR süper lig OR galatasaray OR fenerbahçe OR beşiktaş',
      'language': 'tr',
      'sortBy': 'publishedAt',
      'pageSize': '20',
      'apiKey': key,
    });

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('NewsAPI hata: ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final articles = (data['articles'] as List?) ?? const [];

    final items = <NewsItem>[];
    for (final a in articles) {
      final m = a as Map<String, dynamic>;
      final title = (m['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;

      final source = ((m['source'] as Map?)?['name'] ?? 'NewsAPI').toString();
      final desc = (m['description'] ?? m['content'] ?? '').toString();
      final url = (m['url'] ?? '').toString();
      final imageUrl = (m['urlToImage'] ?? '').toString();

      DateTime published = DateTime.now();
      final p = (m['publishedAt'] ?? '').toString();
      if (p.isNotEmpty) published = DateTime.tryParse(p) ?? DateTime.now();

      items.add(
        NewsItem(
          id: 'api-${published.microsecondsSinceEpoch}-${items.length}',
          title: title,
          source: source,
          excerpt: desc.isEmpty ? 'Detay için habere gir.' : desc,
          publishedAt: published.toLocal(),
          url: url,
          imageUrl: imageUrl,
          imageSeed: items.length % 5,
        ),
      );
    }

    return items.isEmpty ? repo.news : items;
  }
}

class ChatService {
  ChatService(this.repo, this.xp, this.moderation);
  final DemoRepo repo;
  final XpService xp;
  final ModerationService moderation;

  List<ChatMessage> messages(String roomId) => repo.messagesByRoom[roomId]!;

  bool canEnter(UserModel u, ChatRoom r) => !r.premiumOnly || u.isPremium || u.isAdmin;

  String? send(UserModel u, ChatRoom room, String text) {
    final mute = moderation.getMute(u.uid);
    if (mute != null) return 'Susturuldun: ${mute.reason} (bitiş: ${_hhmm(mute.until)})';

    final t = text.trim();
    if (t.isEmpty) return 'Boş mesaj gönderemezsin.';
    if (t.length > kChatMaxLen) return 'Mesaj çok uzun (max $kChatMaxLen).';

    // basit duplicate engeli
    final list = messages(room.id);
    for (int i = list.length - 1; i >= 0 && i >= list.length - 8; i--) {
      final m = list[i];
      if (m.uid == u.uid && !m.deleted && m.type == MessageType.user) {
        if (m.text.trim().toLowerCase() == t.toLowerCase()) return 'Aynı mesajı tekrar gönderemezsin.';
        break;
      }
    }

    list.add(
      ChatMessage(
        id: 'm-${DateTime.now().microsecondsSinceEpoch}',
        roomId: room.id,
        uid: u.uid,
        username: u.username,
        text: t,
        type: MessageType.user,
        createdAt: DateTime.now(),
      ),
    );

    final now = DateTime.now();
    if (u.lastXpChatAt == null || now.difference(u.lastXpChatAt!) >= kChatXpCooldown) {
      xp.addXp(u, kChatXp);
      u.lastXpChatAt = now;
    }

    u.lastSeenAt = now;
    return null;
  }

  void deleteMessage(UserModel admin, ChatMessage m) {
    m.deleted = true;
    repo.adminLogs.add('[${DateTime.now()}] ${admin.username} mesaj sildi: ${m.id} (${m.roomId})');
  }
}

class ForumService {
  ForumService(this.repo, this.xp);
  final DemoRepo repo;
  final XpService xp;

  List<ForumPost> listVisible() {
    final list = repo.posts.where((p) => !p.deleted).toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  String? create(UserModel u, String title, String content) {
    final t = title.trim();
    final c = content.trim();
    if (t.length < 4) return 'Başlık en az 4 karakter olmalı.';
    if (c.length < 10) return 'İçerik en az 10 karakter olmalı.';
    if (t.length > kForumTitleMax) return 'Başlık çok uzun (max $kForumTitleMax).';
    if (c.length > kForumContentMax) return 'İçerik çok uzun (max $kForumContentMax).';

    repo.posts.add(
      ForumPost(
        id: 'p-${DateTime.now().microsecondsSinceEpoch}',
        uid: u.uid,
        username: u.username,
        title: t,
        content: c,
        createdAt: DateTime.now(),
      ),
    );

    xp.addXp(u, kPostXp);
    u.lastSeenAt = DateTime.now();
    return null;
  }

  void delete(UserModel admin, ForumPost p) {
    p.deleted = true;
    repo.adminLogs.add('[${DateTime.now()}] ${admin.username} post sildi: ${p.id}');
  }

  void togglePin(UserModel actor, ForumPost p) {
    if (!(actor.isAdmin || actor.isPremium)) return;
    p.pinned = !p.pinned;
    repo.adminLogs.add('[${DateTime.now()}] ${actor.username} pin değiştirdi: ${p.id} => ${p.pinned}');
  }
}

class LeaderboardService {
  List<UserModel> global(DemoRepo repo) {
    final list = repo.usersByUid.values.toList();
    list.sort((a, b) => b.totalXp.compareTo(a.totalXp));
    return list;
  }

  List<_WeeklyEntry> weekly(DemoRepo repo) {
    final rng = Random(42);
    final list = repo.usersByUid.values.map((u) {
      final base = (u.totalXp / 20).round();
      final jitter = rng.nextInt(120);
      final gained = max(0, base + jitter);
      return _WeeklyEntry(u: u, gained: gained);
    }).toList();
    list.sort((a, b) => b.gained.compareTo(a.gained));
    return list;
  }
}

class _WeeklyEntry {
  _WeeklyEntry({required this.u, required this.gained});
  final UserModel u;
  final int gained;
}
/* ==========================
   NEWS SERVICE (V2) - TR + GLOBAL FUTBOL/SPOR (GÜNCEL)
   Not: PART 1'deki NewsService kullanılmayacak.
   AppState bu V2'yi kullanır.
   ========================== */

class NewsServiceV2 {
  NewsServiceV2(this.repo);
  final DemoRepo repo;

  Future<void> refreshDemo() async {
    await Future.delayed(const Duration(milliseconds: 350));
    final now = DateTime.now();
    repo.news.insert(
      0,
      NewsItem(
        id: 'n-${now.microsecondsSinceEpoch}',
        title: 'Yeni Haber: Arena gündemi güncellendi (DEMO)',
        source: 'S&B Feed',
        excerpt: 'Kaydır-yenile ile yeni demo haber eklendi.',
        publishedAt: now,
        imageSeed: now.second % 5,
      ),
    );
    if (repo.news.length > 25) repo.news.removeLast();
    repo.pushNoti(title: 'Yeni Haber', body: 'Haberler güncellendi (demo).', type: 'haber');
  }

  Future<List<NewsItem>> fetchFromNewsApi({required String apiKey}) async {
    final key = apiKey.trim();
    if (key.isEmpty || key == 'DEMO_KEY') return repo.news;

    // 1) TR Spor Top Headlines
    final trUri = Uri.https('newsapi.org', '/v2/top-headlines', {
      'country': 'tr',
      'category': 'sports',
      'pageSize': '20',
      'apiKey': key,
    });

    // 2) Global futbol/spor (EN)
    final globalUri = Uri.https('newsapi.org', '/v2/everything', {
      'q':
          '(football OR soccer OR basketball OR transfer OR "champions league" OR uefa OR fifa OR premier league OR la liga OR serie a OR bundesliga)',
      'language': 'en',
      'sortBy': 'publishedAt',
      'pageSize': '20',
      'apiKey': key,
    });

    final res = await Future.wait([http.get(trUri), http.get(globalUri)]);

    for (final r in res) {
      if (r.statusCode != 200) {
        throw Exception('NewsAPI hata: ${r.statusCode}');
      }
    }

    final trData = jsonDecode(res[0].body) as Map<String, dynamic>;
    final glData = jsonDecode(res[1].body) as Map<String, dynamic>;

    final trArticles = (trData['articles'] as List?) ?? const [];
    final glArticles = (glData['articles'] as List?) ?? const [];

    List<NewsItem> mapArticles(List arts, {required String fallbackSource}) {
      final out = <NewsItem>[];
      for (final a in arts) {
        final m = a as Map<String, dynamic>;
        final title = (m['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;

        final source = ((m['source'] as Map?)?['name'] ?? fallbackSource).toString();
        final desc = (m['description'] ?? m['content'] ?? '').toString();
        final url = (m['url'] ?? '').toString();
        final imageUrl = (m['urlToImage'] ?? '').toString();

        DateTime published = DateTime.now();
        final p = (m['publishedAt'] ?? '').toString();
        if (p.isNotEmpty) published = DateTime.tryParse(p) ?? DateTime.now();

        out.add(
          NewsItem(
            id: 'api-${published.microsecondsSinceEpoch}-${out.length}-${fallbackSource.hashCode}',
            title: title,
            source: source,
            excerpt: desc.isEmpty ? 'Detay için habere gir.' : desc,
            publishedAt: published.toLocal(),
            url: url,
            imageUrl: imageUrl,
            imageSeed: out.length % 5,
          ),
        );
      }
      return out;
    }

    final merged = <NewsItem>[
      ...mapArticles(trArticles, fallbackSource: 'TR Spor'),
      ...mapArticles(glArticles, fallbackSource: 'Global Sport'),
    ];

    // Başlığa göre basit duplicate temizliği
    final seen = <String>{};
    final unique = <NewsItem>[];
    for (final n in merged) {
      final k = _norm(n.title);
      if (seen.contains(k)) continue;
      seen.add(k);
      unique.add(n);
    }

    // Tarihe göre sırala (en yeni üstte)
    unique.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    return unique.isEmpty ? repo.news : unique;
  }
}

/* ==========================
   APP STATE
   ========================== */

class AppState extends ChangeNotifier {
  final repo = DemoRepo();

  late final auth = AuthService(repo);
  late final xp = XpService();
  late final moderation = ModerationService(repo);

  // V2 haber servisi (TR + Global futbol/spor)
  late final news = NewsServiceV2(repo);

  late final chat = ChatService(repo, xp, moderation);
  late final forum = ForumService(repo, xp);
  late final leader = LeaderboardService();

  UserModel? get me => auth.currentUser;

  int nav = 0;
  Timer? _minuteTimer;

  void bootstrap() {
    repo.seed();
    _minuteTimer?.cancel();
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) => _minuteTick());
  }

  void notifySoft() => notifyListeners();

  @override
  void dispose() {
    _minuteTimer?.cancel();
    super.dispose();
  }

  void setNav(int i) {
    nav = i;
    notifyListeners();
  }

  String? login(String u, String p) {
    final err = auth.login(u, p);
    if (err == null) {
      repo.pushNoti(
        title: 'Giriş Yapıldı',
        body: 'Hoş geldin, ${me!.displayName}!',
        type: 'sistem',
        premiumPriority: me!.isPremium,
      );
      notifyListeners();
    }
    return err;
  }

  String? register(String u, String p, String dn) {
    final err = auth.register(u, p, dn);
    if (err == null) {
      repo.pushNoti(title: 'Kayıt Oluşturuldu', body: 'Hesabın hazır: ${me!.username}', type: 'sistem');
      notifyListeners();
    }
    return err;
  }

  void logout() {
    final u = me;
    auth.logout();
    nav = 0;
    if (u != null) repo.pushNoti(title: 'Çıkış', body: '${u.username} çıkış yaptı.', type: 'sistem');
    notifyListeners();
  }

  void togglePremium() {
    final u = me;
    if (u == null) return;

    u.isPremium = !u.isPremium;
    u.premiumTier = u.isPremium ? 'dark_gold' : 'none';
    u.title = Titles.titleForLevel(u.level, isPremium: u.isPremium);
    if (u.isPremium && !u.badges.contains('premium')) u.badges.add('premium');

    repo.pushNoti(
      title: u.isPremium ? 'Premium Aktif' : 'Premium Kapatıldı',
      body: u.isPremium ? '$kPremiumTierName aktif edildi. Ünvan: $kPremiumTitleTR' : 'Premium devre dışı.',
      type: 'duyuru',
      premiumPriority: u.isPremium,
    );
    notifyListeners();
  }

  Future<void> refreshNews({required BuildContext context}) async {
    try {
      final apiKey = repo.newsApiKey;
      if (apiKey.trim().isNotEmpty && apiKey.trim() != 'DEMO_KEY') {
        final items = await news.fetchFromNewsApi(apiKey: apiKey);
        repo.news
          ..clear()
          ..addAll(items);
        repo.pushNoti(title: 'Yeni Haber', body: 'Güncel futbol/spor haberleri yüklendi.', type: 'haber');
      } else {
        await news.refreshDemo();
      }
      notifyListeners();
    } catch (e) {
      _toast(context, 'NewsAPI hata: $e');
    }
  }

  void _minuteTick() {
    final u = me;
    if (u == null) return;
    final now = DateTime.now();
    if (u.lastMinuteTickAt != null && now.difference(u.lastMinuteTickAt!) < const Duration(minutes: 1)) return;

    xp.addXp(u, kMinuteXp);
    u.lastMinuteTickAt = now;
    notifyListeners();
  }
}

/* ==========================
   THEME
   ========================== */

ThemeData _buildTheme({required bool gold}) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: gold ? const Color(0xFFD4AF37) : const Color(0xFF7C4DFF),
      brightness: Brightness.dark,
    ),
  );
  final cs = base.colorScheme;

  return base.copyWith(
    scaffoldBackgroundColor: cs.surface,
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
    ),
    cardTheme: CardTheme(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: cs.surfaceContainerHighest.withOpacity(0.55),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest.withOpacity(0.30),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
  );
}

/* ==========================
   ROOT APP
   ========================== */

class SBArenaApp extends StatefulWidget {
  const SBArenaApp({super.key});
  @override
  State<SBArenaApp> createState() => _SBArenaAppState();
}

class _SBArenaAppState extends State<SBArenaApp> {
  final app = AppState();

  @override
  void initState() {
    super.initState();
    app.bootstrap();
  }

  @override
  void dispose() {
    app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (_, __) {
        final theme = _buildTheme(gold: app.me?.isPremium == true);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: kAppName,
          theme: theme,
          home: app.me == null ? AuthShell(app: app) : HomeShell(app: app),
        );
      },
    );
  }
}

/* ==========================
   ORTAK UI WIDGETLAR (TEK KOPYA)
   ========================== */

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.primary.withOpacity(0.12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle, this.trailing});
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontWeight: FontWeight.w600)),
            ]),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _SoftFooterNote extends StatelessWidget {
  const _SoftFooterNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(text, style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w600)),
    );
  }
}

class _DemoCover extends StatelessWidget {
  const _DemoCover({required this.seed});
  final int seed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = [
      cs.primary.withOpacity(0.70),
      cs.tertiary.withOpacity(0.70),
      cs.secondary.withOpacity(0.70),
      cs.primaryContainer.withOpacity(0.70),
      cs.tertiaryContainer.withOpacity(0.70),
    ];
    final c = colors[seed % colors.length];

    return Container(
      height: 86,
      width: 86,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, cs.surfaceContainerHighest.withOpacity(0.10)],
        ),
      ),
      child: const Icon(Icons.sports, size: 34),
    );
  }
}

class _NewsCover extends StatelessWidget {
  const _NewsCover({required this.item});
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final url = item.imageUrl.trim();
    if (url.isEmpty) return _DemoCover(seed: item.imageSeed);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 86,
        height: 86,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _DemoCover(seed: item.imageSeed),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
        ),
      ),
    );
  }
}
/* =========================================================
  HOME SHELL + ALT NAV
========================================================= */

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final u = app.me!;
    final tabs = <Widget>[
      NewsTab(app: app),
      ChatTab(app: app),
      ForumTab(app: app),
      LeaderboardTab(app: app),
      ProfileTab(app: app),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(kAppName, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(width: 10),
            if (u.isAdmin) const _Pill(text: 'ADMIN', icon: Icons.shield),
            if (u.isPremium && !u.isAdmin) const _Pill(text: 'PREMIUM', icon: Icons.workspace_premium),
          ],
        ),
        actions: [
           if (app.nav == 2)
  IconButton(
    tooltip: 'Forumda Ara',
    icon: const Icon(Icons.search),
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ForumSearchScreen(app: app)),
    ),
  ),
          IconButton(
            tooltip: 'Bildirimler',
            icon: const Icon(Icons.notifications_none),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsScreen(app: app))),
          ),
          IconButton(
            tooltip: 'Çıkış',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirm(
              context,
              title: 'Çıkış',
              body: 'Hesaptan çıkılsın mı?',
              ok: () => app.logout(),
              okText: 'Çık',
            ),
          ),
        ],
      ),
      body: tabs[app.nav],
      floatingActionButton: _fab(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: app.nav,
        onDestinationSelected: app.setNav,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.newspaper_outlined), label: 'Haberler'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.forum_outlined), label: 'Forum'),
          NavigationDestination(icon: Icon(Icons.leaderboard_outlined), label: 'Lider'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }

  Widget? _fab(BuildContext context) {
    // Forumda yeni post
    if (app.nav == 2) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreatePostScreen(app: app))),
        icon: const Icon(Icons.edit),
        label: const Text('Post', style: TextStyle(fontWeight: FontWeight.w900)),
      );
    }
    // Haberlerde API key hızlı erişim
    if (app.nav == 0) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApiKeyScreen(app: app))),
        icon: const Icon(Icons.key),
        label: const Text('API Key', style: TextStyle(fontWeight: FontWeight.w900)),
      );
    }
    return null;
  }
}

/* =========================================================
  HABERLER TAB + DETAY + PULL TO REFRESH + AUTO LOAD
========================================================= */

class NewsTab extends StatefulWidget {
  const NewsTab({super.key, required this.app});
  final AppState app;

  @override
  State<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {
  bool loadedOnce = false;
  bool loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loadedOnce) {
      loadedOnce = true;
      // otomatik yükleme
      Future.microtask(() => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (loading) return;
    setState(() => loading = true);
    await widget.app.refreshNews(context: context);
    if (!mounted) return;
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final list = app.repo.news;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          _SectionHeader(
            title: 'Haberler',
            subtitle: app.repo.newsApiKey.trim() == 'DEMO_KEY'
                ? 'Demo feed • API key eklersen güncel futbol/spor gelir'
                : 'Güncel futbol & spor (TR + Global) • NewsAPI',
            trailing: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApiKeyScreen(app: app))),
              icon: const Icon(Icons.key),
              label: const Text('API Key', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(),
            ),
          for (final item in list)
            _NewsCard(
              item: item,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewsDetailScreen(app: app, item: item))),
            ),
          const SizedBox(height: 8),
          const _SoftFooterNote(
            text: 'Kaydır-yenile ile güncelleyebilirsin. Prod’da cache + pagination önerilir.',
          ),
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item, required this.onTap});
  final NewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _NewsCover(item: item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    item.excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface.withOpacity(0.75), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 16, color: cs.onSurface.withOpacity(0.6)),
                      const SizedBox(width: 6),
                      Text('${_ddmmyyyy(item.publishedAt)} • ${_hhmm(item.publishedAt)}',
                          style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontWeight: FontWeight.w700, fontSize: 12)),
                      const Spacer(),
                      Text(item.source,
                          style: TextStyle(color: cs.primary.withOpacity(0.9), fontWeight: FontWeight.w900, fontSize: 12)),
                    ],
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NewsDetailScreen extends StatelessWidget {
  const NewsDetailScreen({super.key, required this.app, required this.item});
  final AppState app;
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Haber Detayı')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(item.source, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    Text('${_ddmmyyyy(item.publishedAt)} • ${_hhmm(item.publishedAt)}',
                        style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 12),
                if (item.imageUrl.trim().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        item.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: cs.surfaceContainerHighest.withOpacity(0.25),
                          child: const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                const SizedBox(height: 12),
                Text(item.excerpt, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
                const SizedBox(height: 14),
                if (item.url.trim().isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => _toast(context, 'Demo: Tarayıcı açma eklenmedi (url: ${item.url})'),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Haberi Aç', style: TextStyle(fontWeight: FontWeight.w900)),
                  )
                else
                  const _SoftFooterNote(text: 'Not: Bu haberde url bilgisi yok.'),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================================================
  API KEY EKRANI (NewsAPI)
========================================================= */

class ApiKeyScreen extends StatefulWidget {
  const ApiKeyScreen({super.key, required this.app});
  final AppState app;

  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  late final TextEditingController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = TextEditingController(text: widget.app.repo.newsApiKey);
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void save() {
    final v = ctrl.text.trim();
    widget.app.repo.newsApiKey = v.isEmpty ? 'DEMO_KEY' : v;
    widget.app.repo.pushNoti(
      title: 'API Key',
      body: v.isEmpty ? 'Demo moda dönüldü.' : 'NewsAPI key kaydedildi.',
      type: 'sistem',
      premiumPriority: widget.app.me?.isPremium == true,
    );
    widget.app.notifySoft();
    Navigator.pop(context);
  }

  void useYourKey() {
    ctrl.text = 'cb4647d6e30049e28a03b65789295163';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NewsAPI Key'),
        actions: [
          TextButton(onPressed: save, child: const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.w900))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('API Key', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    hintText: 'NewsAPI key yapıştır...',
                    prefixIcon: Icon(Icons.key),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: useYourKey,
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Bu Key’i Kullan', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        ctrl.text = 'DEMO_KEY';
                        setState(() {});
                      },
                      icon: const Icon(Icons.undo),
                      label: const Text('Demo Mod'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Not: Key yoksa DEMO feed çalışır. Key varsa güncel futbol/spor haberleri (TR+Global) çekilir.',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================================================
  BİLDİRİMLER EKRANI (DEMO + ÖNCELİK)
========================================================= */

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final u = app.me!;
    final list = List<NotificationItem>.from(app.repo.notifications);

    // Premium öncelik mantığı: premiumPriority true olanlar üstte
    list.sort((a, b) {
      if (a.premiumPriority != b.premiumPriority) return a.premiumPriority ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Bildirimler')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          _SectionHeader(
            title: 'Bildirim Akışı',
            subtitle: u.isPremium ? 'Premium öncelik aktif' : 'Normal öncelik',
          ),
          if (list.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Bildirim yok.')))
          else
            for (final n in list)
              Card(
                child: ListTile(
                  leading: Icon(
                    n.type == 'haber'
                        ? Icons.newspaper
                        : n.type == 'duyuru'
                            ? Icons.campaign
                            : Icons.info_outline,
                  ),
                  title: Row(
                    children: [
                      if (n.premiumPriority) const Text('👑 '),
                      Expanded(child: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w900))),
                    ],
                  ),
                  subtitle: Text('${n.body}\n${_ddmmyyyy(n.createdAt)} • ${_hhmm(n.createdAt)}'),
                  isThreeLine: true,
                ),
              ),
        ],
      ),
    );
  }
}
/* =========================================================
  HOME SHELL + ALT NAV
========================================================= */

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final u = app.me!;
    final tabs = <Widget>[
      NewsTab(app: app),
      ChatTab(app: app),
      ForumTab(app: app),
      LeaderboardTab(app: app),
      ProfileTab(app: app),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(kAppName, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(width: 10),
            if (u.isAdmin) const _Pill(text: 'ADMIN', icon: Icons.shield),
            if (u.isPremium && !u.isAdmin) const _Pill(text: 'PREMIUM', icon: Icons.workspace_premium),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Bildirimler',
            icon: const Icon(Icons.notifications_none),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsScreen(app: app))),
          ),
          IconButton(
            tooltip: 'Çıkış',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirm(
              context,
              title: 'Çıkış',
              body: 'Hesaptan çıkılsın mı?',
              ok: () => app.logout(),
              okText: 'Çık',
            ),
          ),
        ],
      ),
      body: tabs[app.nav],
      floatingActionButton: _fab(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: app.nav,
        onDestinationSelected: app.setNav,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.newspaper_outlined), label: 'Haberler'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.forum_outlined), label: 'Forum'),
          NavigationDestination(icon: Icon(Icons.leaderboard_outlined), label: 'Lider'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profil'),
        ],
      ),
    );
  }

  Widget? _fab(BuildContext context) {
    // Forumda yeni post
    if (app.nav == 2) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreatePostScreen(app: app))),
        icon: const Icon(Icons.edit),
        label: const Text('Post', style: TextStyle(fontWeight: FontWeight.w900)),
      );
    }
    // Haberlerde API key hızlı erişim
    if (app.nav == 0) {
      return FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApiKeyScreen(app: app))),
        icon: const Icon(Icons.key),
        label: const Text('API Key', style: TextStyle(fontWeight: FontWeight.w900)),
      );
    }
    return null;
  }
}

/* =========================================================
  HABERLER TAB + DETAY + PULL TO REFRESH + AUTO LOAD
========================================================= */

class NewsTab extends StatefulWidget {
  const NewsTab({super.key, required this.app});
  final AppState app;

  @override
  State<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<NewsTab> {
  bool loadedOnce = false;
  bool loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loadedOnce) {
      loadedOnce = true;
      // otomatik yükleme
      Future.microtask(() => _refresh());
    }
  }

  Future<void> _refresh() async {
    if (loading) return;
    setState(() => loading = true);
    await widget.app.refreshNews(context: context);
    if (!mounted) return;
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final list = app.repo.news;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          _SectionHeader(
            title: 'Haberler',
            subtitle: app.repo.newsApiKey.trim() == 'DEMO_KEY'
                ? 'Demo feed • API key eklersen güncel futbol/spor gelir'
                : 'Güncel futbol & spor (TR + Global) • NewsAPI',
            trailing: TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApiKeyScreen(app: app))),
              icon: const Icon(Icons.key),
              label: const Text('API Key', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(),
            ),
          for (final item in list)
            _NewsCard(
              item: item,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewsDetailScreen(app: app, item: item))),
            ),
          const SizedBox(height: 8),
          const _SoftFooterNote(
            text: 'Kaydır-yenile ile güncelleyebilirsin. Prod’da cache + pagination önerilir.',
          ),
        ],
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item, required this.onTap});
  final NewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              _NewsCover(item: item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    item.excerpt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurface.withOpacity(0.75), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 16, color: cs.onSurface.withOpacity(0.6)),
                      const SizedBox(width: 6),
                      Text('${_ddmmyyyy(item.publishedAt)} • ${_hhmm(item.publishedAt)}',
                          style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontWeight: FontWeight.w700, fontSize: 12)),
                      const Spacer(),
                      Text(item.source,
                          style: TextStyle(color: cs.primary.withOpacity(0.9), fontWeight: FontWeight.w900, fontSize: 12)),
                    ],
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NewsDetailScreen extends StatelessWidget {
  const NewsDetailScreen({super.key, required this.app, required this.item});
  final AppState app;
  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Haber Detayı')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(item.source, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    Text('${_ddmmyyyy(item.publishedAt)} • ${_hhmm(item.publishedAt)}',
                        style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 12),
                if (item.imageUrl.trim().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        item.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: cs.surfaceContainerHighest.withOpacity(0.25),
                          child: const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                const SizedBox(height: 12),
                Text(item.excerpt, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
                const SizedBox(height: 14),
                if (item.url.trim().isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => _toast(context, 'Demo: Tarayıcı açma eklenmedi (url: ${item.url})'),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Haberi Aç', style: TextStyle(fontWeight: FontWeight.w900)),
                  )
                else
                  const _SoftFooterNote(text: 'Not: Bu haberde url bilgisi yok.'),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================================================
  API KEY EKRANI (NewsAPI)
========================================================= */

class ApiKeyScreen extends StatefulWidget {
  const ApiKeyScreen({super.key, required this.app});
  final AppState app;

  @override
  State<ApiKeyScreen> createState() => _ApiKeyScreenState();
}

class _ApiKeyScreenState extends State<ApiKeyScreen> {
  late final TextEditingController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = TextEditingController(text: widget.app.repo.newsApiKey);
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void save() {
    final v = ctrl.text.trim();
    widget.app.repo.newsApiKey = v.isEmpty ? 'DEMO_KEY' : v;
    widget.app.repo.pushNoti(
      title: 'API Key',
      body: v.isEmpty ? 'Demo moda dönüldü.' : 'NewsAPI key kaydedildi.',
      type: 'sistem',
      premiumPriority: widget.app.me?.isPremium == true,
    );
    widget.app.notifySoft();
    Navigator.pop(context);
  }

  void useYourKey() {
    ctrl.text = 'cb4647d6e30049e28a03b65789295163';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NewsAPI Key'),
        actions: [
          TextButton(onPressed: save, child: const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.w900))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('API Key', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    hintText: 'NewsAPI key yapıştır...',
                    prefixIcon: Icon(Icons.key),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: useYourKey,
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Bu Key’i Kullan', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        ctrl.text = 'DEMO_KEY';
                        setState(() {});
                      },
                      icon: const Icon(Icons.undo),
                      label: const Text('Demo Mod'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Not: Key yoksa DEMO feed çalışır. Key varsa güncel futbol/spor haberleri (TR+Global) çekilir.',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.7), fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================================================
  BİLDİRİMLER EKRANI (DEMO + ÖNCELİK)
========================================================= */

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final u = app.me!;
    final list = List<NotificationItem>.from(app.repo.notifications);

    // Premium öncelik mantığı: premiumPriority true olanlar üstte
    list.sort((a, b) {
      if (a.premiumPriority != b.premiumPriority) return a.premiumPriority ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Bildirimler')),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          _SectionHeader(
            title: 'Bildirim Akışı',
            subtitle: u.isPremium ? 'Premium öncelik aktif' : 'Normal öncelik',
          ),
          if (list.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Bildirim yok.')))
          else
            for (final n in list)
              Card(
                child: ListTile(
                  leading: Icon(
                    n.type == 'haber'
                        ? Icons.newspaper
                        : n.type == 'duyuru'
                            ? Icons.campaign
                            : Icons.info_outline,
                  ),
                  title: Row(
                    children: [
                      if (n.premiumPriority) const Text('👑 '),
                      Expanded(child: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w900))),
                    ],
                  ),
                  subtitle: Text('${n.body}\n${_ddmmyyyy(n.createdAt)} • ${_hhmm(n.createdAt)}'),
                  isThreeLine: true,
                ),
              ),
        ],
      ),
    );
  }
}
/* =========================================================
  CHAT TAB + ODALAR + ODA EKRANI (TAM)
========================================================= */

class ChatTab extends StatelessWidget {
  const ChatTab({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final u = app.me!;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        const _SectionHeader(
          title: 'Chat Odaları',
          subtitle: 'Canlı chat demo • Çoklu oda • Premium kilit',
        ),
        for (final room in app.repo.rooms)
          Card(
            child: ListTile(
              leading: Icon(room.premiumOnly ? Icons.lock : Icons.chat_bubble_outline),
              title: Row(
                children: [
                  if (room.premiumOnly) const Text('👑 '),
                  Expanded(child: Text(room.name, style: const TextStyle(fontWeight: FontWeight.w900))),
                ],
              ),
              subtitle: Text(room.premiumOnly ? 'Premium özel oda' : 'Herkese açık oda'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final can = app.chat.canEnter(u, room);
                if (!can) {
                  _toast(context, 'Bu oda sadece Premium içindir. Profil > Premium’dan aktif edebilirsin.');
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ChatRoomScreen(app: app, room: room)),
                );
              },
            ),
          ),
        const SizedBox(height: 10),
        const _SoftFooterNote(
          text: 'Not: Demo canlı chat. Prod’da Firestore/Socket ile gerçek zamanlı yapılabilir.',
        ),
      ],
    );
  }
}

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key, required this.app, required this.room});
  final AppState app;
  final ChatRoom room;

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _send() {
    final u = widget.app.me!;
    final err = widget.app.chat.send(u, widget.room, input.text);
    if (err != null) {
      _toast(context, err);
      return;
    }
    input.clear();
    widget.app.notifySoft();

    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final u = app.me!;
    final list = app.chat.messages(widget.room.id);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(widget.room.name, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(width: 8),
            if (widget.room.premiumOnly) const _Pill(text: 'Premium', icon: Icons.lock),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final m = list[i];
                final isMe = m.uid == u.uid;
                final isSystem = m.type == MessageType.system;

                if (isSystem) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.35),
                        ),
                        child: Text(m.text, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  );
                }

                final sender = app.repo.usersByUid[m.uid];
                final senderPremium = sender?.isPremium == true;

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isMe ? 'Sen' : '${senderPremium ? "👑 " : ""}${m.username}',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _hhmm(m.createdAt),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    fontSize: 12,
                                  ),
                                ),
                                if (u.isAdmin)
                                  IconButton(
                                    tooltip: 'Mesaj sil (admin)',
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    onPressed: () => _confirm(
                                      context,
                                      title: 'Mesaj sil',
                                      body: 'Bu mesaj silinsin mi?',
                                      ok: () {
                                        app.chat.deleteMessage(u, m);
                                        app.repo.pushNoti(
                                          title: 'Moderasyon',
                                          body: 'Admin bir mesaj sildi.',
                                          type: 'sistem',
                                          premiumPriority: true,
                                        );
                                        app.notifySoft();
                                        setState(() {});
                                      },
                                      okText: 'Sil',
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              m.deleted ? 'Bu mesaj silindi.' : m.text,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Mesaj yaz...',
                        prefixIcon: Icon(Icons.chat_bubble_outline),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _send,
                      icon: const Icon(Icons.send),
                      label: const Text('Gönder', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================================================
  FORUM TAB + POST LİSTESİ + DETAY + OLUŞTURMA (TAM)
========================================================= */

class ForumTab extends StatelessWidget {
  const ForumTab({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final u = app.me!;
    final posts = app.forum.listVisible();

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        const _SectionHeader(
          title: 'Forum',
          subtitle: 'Postlar • Moderasyon • Premium sabitleme (📌)',
        ),
        for (final p in posts) ...[
          Builder(builder: (context) {
            final author = app.repo.usersByUid[p.uid];
            final isPrem = author?.isPremium == true;

            return Card(
              child: ListTile(
                leading: Icon(p.pinned ? Icons.push_pin : Icons.article_outlined),
                title: Row(
                  children: [
                    if (isPrem) const Text('👑 '),
                    if (p.pinned) const Text('📌 '),
                    Expanded(child: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w900))),
                  ],
                ),
                subtitle: Text('@${p.username} • ${_ddmmyyyy(p.createdAt)} • ${_hhmm(p.createdAt)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => PostDetailScreen(app: app, post: p))),
              ),
            );
          }),
        ],
        const SizedBox(height: 10),
        const _SoftFooterNote(
          text: 'Premium ayrıcalık: Post sabitleme (📌). Admin ayrıca post silebilir.',
        ),
        if (u.isAdmin) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPanelScreen(app: app))),
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('Admin Panel', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ],
    );
  }
}

class PostDetailScreen extends StatelessWidget {
  const PostDetailScreen({super.key, required this.app, required this.post});
  final AppState app;
  final ForumPost post;

  @override
  Widget build(BuildContext context) {
    final u = app.me!;
    final canPin = u.isAdmin || u.isPremium;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post Detayı'),
        actions: [
          if (canPin)
            IconButton(
              tooltip: post.pinned ? 'Sabitlemeyi kaldır' : 'Sabitle (Premium)',
              icon: Icon(post.pinned ? Icons.push_pin : Icons.push_pin_outlined),
              onPressed: () {
                app.forum.togglePin(u, post);
                app.repo.pushNoti(
                  title: 'Forum',
                  body: post.pinned ? 'Bir post sabitlendi.' : 'Bir post sabitlemesi kaldırıldı.',
                  type: 'duyuru',
                  premiumPriority: u.isPremium,
                );
                app.notifySoft();
                Navigator.pop(context);
              },
            ),
          if (u.isAdmin)
            IconButton(
              tooltip: 'Post sil (admin)',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirm(
                context,
                title: 'Post sil',
                body: 'Bu post silinsin mi?',
                ok: () {
                  app.forum.delete(u, post);
                  app.repo.pushNoti(title: 'Moderasyon', body: 'Admin bir post sildi.', type: 'sistem', premiumPriority: true);
                  app.notifySoft();
                  Navigator.pop(context);
                },
                okText: 'Sil',
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (post.pinned) const Text('📌 ', style: TextStyle(fontSize: 18)),
                      Expanded(child: Text(post.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('@${post.username} • ${_ddmmyyyy(post.createdAt)} • ${_hhmm(post.createdAt)}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Text(post.content, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
                ],
              ),
            ),
          ),
          if (u.isPremium && !u.isAdmin)
            const _SoftFooterNote(text: 'Premium ayrıcalık: Post sabitleyebilirsin (📌).'),
        ],
      ),
    );
  }
}

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, required this.app});
  final AppState app;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final title = TextEditingController();
  final content = TextEditingController();

  @override
  void dispose() {
    title.dispose();
    content.dispose();
    super.dispose();
  }

  void _submit() {
    final u = widget.app.me!;
    final err = widget.app.forum.create(u, title.text, content.text);
    if (err != null) {
      _toast(context, err);
      return;
    }
    widget.app.repo.pushNoti(
      title: 'Forum',
      body: 'Yeni post paylaşıldı: ${u.username}',
      type: 'duyuru',
      premiumPriority: u.isPremium,
    );
    widget.app.notifySoft();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yeni Post'),
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text('Paylaş', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Başlık', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: title,
                    maxLength: kForumTitleMax,
                    decoration: const InputDecoration(hintText: 'Başlık yaz...'),
                  ),
                  const SizedBox(height: 10),
                  const Text('İçerik', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: content,
                    maxLines: 8,
                    maxLength: kForumContentMax,
                    decoration: const InputDecoration(hintText: 'İçeriği yaz...'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.send),
                      label: const Text('Paylaş', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _SoftFooterNote(text: 'Post atınca XP kazanırsın. Premium XP bonusu + günlük limit avantajı vardır.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
/* =========================================================
  LEADERBOARD TAB (GENEL + HAFTALIK)
========================================================= */

class LeaderboardTab extends StatefulWidget {
  const LeaderboardTab({super.key, required this.app});
  final AppState app;

  @override
  State<LeaderboardTab> createState() => _LeaderboardTabState();
}

class _LeaderboardTabState extends State<LeaderboardTab> with SingleTickerProviderStateMixin {
  late final TabController tab;

  @override
  void initState() {
    super.initState();
    tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final global = app.leader.global(app.repo);
    final weekly = app.leader.weekly(app.repo);

    return Column(
      children: [
        const _SectionHeader(
          title: 'Lider Tablosu',
          subtitle: 'XP’ye göre sıralama • Haftalık rekabet (demo)',
        ),
        TabBar(
          controller: tab,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900),
          tabs: const [
            Tab(text: 'Genel'),
            Tab(text: 'Haftalık'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: tab,
            children: [
              ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  for (int i = 0; i < global.length; i++)
                    _LeaderRow(
                      rank: i + 1,
                      u: global[i],
                      subtitle: 'Toplam XP: ${global[i].totalXp} • Seviye: ${global[i].level}',
                    ),
                  const SizedBox(height: 8),
                  const _SoftFooterNote(text: 'Not: Prod’da gerçek backend + anti-cheat gerekir.'),
                ],
              ),
              ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(
                      'Son $kWeeklyDays gün (demo hesap)',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  for (int i = 0; i < weekly.length; i++)
                    _LeaderRow(
                      rank: i + 1,
                      u: weekly[i].u,
                      subtitle: 'Haftalık XP: ${weekly[i].gained} • Seviye: ${weekly[i].u.level}',
                    ),
                  const SizedBox(height: 8),
                  const _SoftFooterNote(text: 'Haftalık tablo demo hesaplanır. Prod’da event bazlı tutulmalı.'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.rank, required this.u, required this.subtitle});
  final int rank;
  final UserModel u;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '$rank';

    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(u.isPremium ? '👑' : medal, style: const TextStyle(fontWeight: FontWeight.w900))),
        title: Row(
          children: [
            if (u.isAdmin) const Text('🛡️ '),
            if (u.isPremium) const Text('👑 '),
            Expanded(child: Text('@${u.username}', style: const TextStyle(fontWeight: FontWeight.w900))),
          ],
        ),
        subtitle: Text(subtitle),
        trailing: _Pill(text: u.title, icon: Icons.badge),
      ),
    );
  }
}

/* =========================================================
  PROFİL TAB
========================================================= */

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final u = app.me!;
    final cs = Theme.of(context).colorScheme;
    final cap = app.xp.dailyCap(u);

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        _SectionHeader(
          title: 'Profil',
          subtitle: 'Seviye • Rozet • Premium • Hesap',
          trailing: TextButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AccountDetailsScreen(app: app))),
            icon: const Icon(Icons.manage_accounts),
            label: const Text('Detay', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  child: Text(u.isPremium ? '👑' : '🙂', style: const TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(u.displayName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 4),
                    Text('@${u.username} • ${u.isOnline ? "Online" : "Offline"}',
                        style: TextStyle(color: cs.onSurface.withOpacity(0.75), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MiniChip(text: 'Seviye ${u.level}', icon: Icons.insights),
                        _MiniChip(text: u.title, icon: Icons.badge),
                        if (u.isPremium) _MiniChip(text: '$kPremiumTierName', icon: Icons.workspace_premium),
                        if (u.isAdmin) _MiniChip(text: 'ADMIN', icon: Icons.shield),
                      ],
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('İlerleme', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 10),
              Text('XP Havuzu: ${u.xpPool}  •  Toplam XP: ${u.totalXp}',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.85), fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Günlük XP: ${u.todayXp} / $cap',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.85), fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text('Rozetler', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: u.badges.isEmpty
                    ? [const _MiniChip(text: 'Henüz rozet yok', icon: Icons.hourglass_empty)]
                    : u.badges.map((b) => _MiniChip(text: b, icon: Icons.verified)).toList(),
              ),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Premium ($kPremiumTierName)', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 10),
              Text(
                u.isPremium
                    ? '✅ Premium aktif • Ünvan: $kPremiumTitleTR • XP bonus: ${(kPremiumXpMultiplier * 100).round()}% • Premium odalar açık'
                    : '❌ Premium kapalı • Güncel deneyim için premium alabilirsin',
                style: TextStyle(color: cs.onSurface.withOpacity(0.85), fontWeight: FontWeight.w600, height: 1.35),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PremiumScreen(app: app))),
                  icon: const Icon(Icons.workspace_premium),
                  label: Text(u.isPremium ? 'Premium Yönet' : 'Premium Satın Al', style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        ),
        if (u.isAdmin)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPanelScreen(app: app))),
              icon: const Icon(Icons.admin_panel_settings),
              label: const Text('Admin Panel', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
      ],
    );
  }
}
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        color: cs.surfaceContainerHighest.withOpacity(0.18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class AccountDetailsScreen extends StatelessWidget {
  const AccountDetailsScreen({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final u = app.me!;
    return Scaffold(
      appBar: AppBar(title: const Text('Hesap Detayı')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Bilgiler', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 10),
                Text('UID: ${u.uid}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Kullanıcı adı: ${u.username}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Görünen isim: ${u.displayName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Rol: ${u.isAdmin ? "Admin" : "Kullanıcı"}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Premium: ${u.isPremium ? "Evet" : "Hayır"}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Ünvan: ${u.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Oluşturma: ${_ddmmyyyy(u.createdAt)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Son görülme: ${_ddmmyyyy(u.lastSeenAt)} • ${_hhmm(u.lastSeenAt)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================================================
  PREMIUM EKRANI (DEMO SATIN ALMA)
========================================================= */

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final u = app.me!;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Premium')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$kPremiumCrown $kPremiumTierName', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                Text(
                  'Premium ile Arena deneyimin yükselir. (Demo satın alma)',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.8), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const _BenefitRow(icon: Icons.badge, text: 'Türkçe özel ünvan: KARA ALTIN ELİT'),
                _BenefitRow(icon: Icons.palette, text: 'Dark Gold tema'),
                _BenefitRow(icon: Icons.bolt, text: 'XP bonus: ${(kPremiumXpMultiplier * 100).round()}%'),
                _BenefitRow(icon: Icons.stacked_bar_chart, text: 'Günlük XP limiti: $kDailyXpCapPremium'),
                const _BenefitRow(icon: Icons.lock_open, text: 'Premium chat odaları'),
                const _BenefitRow(icon: Icons.push_pin, text: 'Forum post sabitleme (📌)'),
                const _BenefitRow(icon: Icons.priority_high, text: 'Bildirim önceliği'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: () => _confirm(
                      context,
                      title: u.isPremium ? 'Premium kapatılsın mı?' : 'Premium aktif edilsin mi?',
                      body: u.isPremium
                          ? 'Demo premium devre dışı bırakılacak.'
                          : 'Demo premium aktif olacak. Ünvanın "$kPremiumTitleTR" olacak.',
                      ok: () {
                        app.togglePremium();
                        app.notifySoft();
                        Navigator.pop(context);
                      },
                      okText: u.isPremium ? 'Kapat' : 'Aktif Et',
                    ),
                    icon: const Icon(Icons.workspace_premium),
                    label: Text(u.isPremium ? 'Premium Kapat (Demo)' : 'Premium Satın Al (Demo)',
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Prod notu: Gerçek ödeme için IAP / Stripe / backend doğrulama eklenebilir.',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
/* =========================================================
  AUTH UI - GİRİŞ / KAYIT (MODERN)
========================================================= */

class AuthShell extends StatefulWidget {
  const AuthShell({super.key, required this.app});
  final AppState app;

  @override
  State<AuthShell> createState() => _AuthShellState();
}

class _AuthShellState extends State<AuthShell> with SingleTickerProviderStateMixin {
  late final TabController tab;

  @override
  void initState() {
    super.initState();
    tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    cs.primary.withOpacity(0.28),
                    cs.surface.withOpacity(0.0),
                    cs.tertiary.withOpacity(0.16),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            height: 54,
                            width: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              gradient: LinearGradient(
                                colors: [
                                  cs.primary.withOpacity(0.90),
                                  cs.tertiary.withOpacity(0.80),
                                ],
                              ),
                            ),
                            child: const Icon(Icons.stadium_outlined, size: 28),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(kAppName, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                                Text('Güncel Spor Haberleri • Chat • Forum • Rekabet',
                                    style: TextStyle(color: cs.onSurface.withOpacity(0.70), fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _GlassCard(
                        child: Column(
                          children: [
                            TabBar(
                              controller: tab,
                              labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                              tabs: const [
                                Tab(text: 'Giriş Yap'),
                                Tab(text: 'Kayıt Ol'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 410,
                              child: TabBarView(
                                controller: tab,
                                children: [
                                  LoginPanel(app: widget.app),
                                  RegisterPanel(app: widget.app),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _HintChip(icon: Icons.shield, text: 'Admin: admin / admin', color: cs.primary),
                          _HintChip(icon: Icons.person, text: 'User: sbkaan / 1234', color: cs.secondary),
                          _HintChip(icon: Icons.workspace_premium, text: 'Premium: Profil > Premium', color: cs.tertiary),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        color: cs.surfaceContainerHighest.withOpacity(0.18),
      ),
      child: child,
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        color: color.withOpacity(0.10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class LoginPanel extends StatefulWidget {
  const LoginPanel({super.key, required this.app});
  final AppState app;

  @override
  State<LoginPanel> createState() => _LoginPanelState();
}

class _LoginPanelState extends State<LoginPanel> {
  final u = TextEditingController();
  final p = TextEditingController();
  bool loading = false;
  bool showPw = false;

  @override
  void dispose() {
    u.dispose();
    p.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => loading = true);
    await Future.delayed(const Duration(milliseconds: 180));
    final err = widget.app.login(u.text, p.text);
    setState(() => loading = false);
    if (!mounted) return;
    if (err != null) _toast(context, err);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FieldLabel('Kullanıcı Adı'),
        TextField(
          controller: u,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'örn: sbkaan',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: 10),
        _FieldLabel('Şifre'),
        TextField(
          controller: p,
          obscureText: !showPw,
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(
            hintText: '••••',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => showPw = !showPw),
              icon: Icon(showPw ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: loading ? null : submit,
            icon: loading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login),
            label: const Text('Giriş Yap', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 14),
        const _SoftInfo(icon: Icons.info_outline, text: 'Demo: admin/admin veya sbkaan/1234'),
      ],
    );
  }
}

class RegisterPanel extends StatefulWidget {
  const RegisterPanel({super.key, required this.app});
  final AppState app;

  @override
  State<RegisterPanel> createState() => _RegisterPanelState();
}

class _RegisterPanelState extends State<RegisterPanel> {
  final u = TextEditingController();
  final p = TextEditingController();
  final dn = TextEditingController();
  bool loading = false;
  bool showPw = false;

  @override
  void dispose() {
    u.dispose();
    p.dispose();
    dn.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => loading = true);
    await Future.delayed(const Duration(milliseconds: 180));
    final err = widget.app.register(u.text, p.text, dn.text);
    setState(() => loading = false);
    if (!mounted) return;
    if (err !=null) _toast(context, err);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _FieldLabel('Kullanıcı Adı'),
        TextField(
          controller: u,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'örn: sb_arena',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const SizedBox(height: 10),
        _FieldLabel('Şifre'),
        TextField(
          controller: p,
          obscureText: !showPw,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'en az 4 karakter',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => showPw = !showPw),
              icon: Icon(showPw ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _FieldLabel('Görünen İsim'),
        TextField(
          controller: dn,
          onSubmitted: (_) => submit(),
          decoration: const InputDecoration(
            hintText: 'örn: Sefa',
            prefixIcon: Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: loading ? null : submit,
            icon: loading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.person_add_alt_1),
            label: const Text('Kayıt Ol', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(height: 14),
        const _SoftInfo(icon: Icons.lock_outline, text: 'Demo kayıt: veriler RAM’de tutulur.'),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(text, style: TextStyle(color: cs.onSurface.withOpacity(0.75), fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _SoftInfo extends StatelessWidget {
  const _SoftInfo({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        color: cs.surfaceContainerHighest.withOpacity(0.16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: cs.onSurface.withOpacity(0.80), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
/* =========================================================
  ADMIN PANEL (ANA + KULLANICILAR)
========================================================= */

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key, required this.app});
  final AppState app;

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> with SingleTickerProviderStateMixin {
  late final TabController tab;

  @override
  void initState() {
    super.initState();
    tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final me = app.me!;
    if (!me.isAdmin) {
      return const Scaffold(body: Center(child: Text('Bu ekran sadece admin içindir.')));
    }

    final users = app.repo.usersByUid.values.toList()
      ..sort((a, b) => a.username.compareTo(b.username));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        bottom: TabBar(
          controller: tab,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900),
          tabs: const [
            Tab(text: 'Kullanıcılar'),
            Tab(text: 'İçerikler'),
            Tab(text: 'Loglar'),
          ],
        ),
      ),
      body: TabBarView(
        controller: tab,
        children: [
          _AdminUsersTab(app: app, users: users),
          _AdminContentTab(app: app),
          _AdminLogsTab(app: app),
        ],
      ),
    );
  }
}

class _AdminUsersTab extends StatelessWidget {
  const _AdminUsersTab({required this.app, required this.users});
  final AppState app;
  final List<UserModel> users;

  @override
  Widget build(BuildContext context) {
    final me = app.me!;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            'Toplam kullanıcı: ${users.length}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final u in users)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(u.isPremium ? '👑' : (u.isAdmin ? '🛡️' : '🙂'))),
              title: Row(
                children: [
                  Expanded(child: Text('@${u.username}', style: const TextStyle(fontWeight: FontWeight.w900))),
                  if (u.isBanned)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text('BANNED', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                ],
              ),
              subtitle: Text(
                'Seviye: ${u.level} • Ünvan: ${u.title} • XP: ${u.totalXp}\n'
                'Durum: ${u.isOnline ? "Online" : "Offline"}',
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (v) => _handle(context, me, u, v),
                itemBuilder: (_) => [
                  if (!u.isBanned) const PopupMenuItem(value: 'ban', child: Text('Banla')),
                  if (u.isBanned) const PopupMenuItem(value: 'unban', child: Text('Ban kaldır')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'mute', child: Text('Sustur')),
                  const PopupMenuItem(value: 'unmute', child: Text('Susturmayı kaldır')),
                ],
              ),
            ),
          ),
        const SizedBox(height: 10),
        const _SoftFooterNote(text: 'Not: Demo admin panel. Prod’da gerçek backend yetkilendirme şarttır.'),
      ],
    );
  }

  Future<void> _handle(BuildContext context, UserModel admin, UserModel target, String action) async {
    if (target.uid == admin.uid) {
      _toast(context, 'Kendine işlem yapamazsın.');
      return;
    }

    if (action == 'ban') {
      final reason = await _promptText(context, title: 'Ban sebebi', initial: 'Kurallara aykırı davranış');
      if (reason == null) return;
      app.moderation.ban(admin, target, reason);
      app.repo.pushNoti(title: 'Moderasyon', body: '@${target.username} banlandı.', type: 'sistem', premiumPriority: true);
      app.notifySoft();
      return;
    }

    if (action == 'unban') {
      app.moderation.unban(admin, target);
      app.repo.pushNoti(title: 'Moderasyon', body: '@${target.username} banı kaldırıldı.', type: 'sistem', premiumPriority: true);
      app.notifySoft();
      return;
    }

    if (action == 'mute') {
      final minutesStr = await _promptText(context, title: 'Süre (dakika)', initial: '10');
      if (minutesStr == null) return;
      final mins = int.tryParse(minutesStr.trim()) ?? 10;

      final reason = await _promptText(context, title: 'Susturma sebebi', initial: 'Flood / spam');
      if (reason == null) return;

      app.moderation.mute(admin, target, Duration(minutes: max(1, mins)), reason);
      app.repo.pushNoti(title: 'Moderasyon', body: '@${target.username} susturuldu.', type: 'sistem', premiumPriority: true);
      app.notifySoft();
      return;
    }

    if (action == 'unmute') {
      app.moderation.unmute(admin, target);
      app.repo.pushNoti(title: 'Moderasyon', body: '@${target.username} susturma kaldırıldı.', type: 'sistem', premiumPriority: true);
      app.notifySoft();
      return;
    }
  }

  Future<String?> _promptText(BuildContext context, {required String title, required String initial}) async {
    final ctrl = TextEditingController(text: initial);
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Yaz...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Tamam')),
        ],
      ),
    );
    return res;
  }
}
/* =========================================================
  ADMIN - İÇERİKLER (MESAJLAR + POSTLAR)
========================================================= */

class _AdminContentTab extends StatefulWidget {
  const _AdminContentTab({required this.app});
  final AppState app;

  @override
  State<_AdminContentTab> createState() => _AdminContentTabState();
}

class _AdminContentTabState extends State<_AdminContentTab> with SingleTickerProviderStateMixin {
  late final TabController tab;
  String roomId = 'global';

  @override
  void initState() {
    super.initState();
    tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final rooms = app.repo.rooms;

    return Column(
      children: [
        TabBar(
          controller: tab,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900),
          tabs: const [
            Tab(text: 'Mesajlar'),
            Tab(text: 'Postlar'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: tab,
            children: [
              ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        const Text('Oda:', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(width: 10),
                        DropdownButton<String>(
                          value: roomId,
                          items: [
                            for (final r in rooms) DropdownMenuItem(value: r.id, child: Text(r.name)),
                          ],
                          onChanged: (v) => setState(() => roomId = v ?? roomId),
                        ),
                      ],
                    ),
                  ),
                  ..._buildMessages(context, app, roomId),
                ],
              ),
              ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  ..._buildPosts(context, app),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildMessages(BuildContext context, AppState app, String roomId) {
    final admin = app.me!;
    final list = List<ChatMessage>.from(app.repo.messagesByRoom[roomId] ?? []);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (list.where((m) => m.type == MessageType.user).isEmpty) {
      return [const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Bu odada kullanıcı mesajı yok.')))];
    }

    return [
      for (final m in list)
        if (m.type == MessageType.user)
          Card(
            child: ListTile(
              title: Text(
                '${m.deleted ? "[SİLİNDİ] " : ""}${m.text}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('@${m.username} • ${_ddmmyyyy(m.createdAt)} • ${_hhmm(m.createdAt)}'),
              trailing: IconButton(
                tooltip: 'Mesaj sil',
                icon: const Icon(Icons.delete_outline),
                onPressed: m.deleted
                    ? null
                    : () => _confirm(
                          context,
                          title: 'Mesaj sil',
                          body: 'Bu mesaj silinsin mi?',
                          ok: () {
                            app.chat.deleteMessage(admin, m);
                            app.repo.pushNoti(title: 'Moderasyon', body: 'Admin bir mesaj sildi.', type: 'sistem', premiumPriority: true);
                            app.notifySoft();
                            setState(() {});
                          },
                          okText: 'Sil',
                        ),
              ),
            ),
          ),
    ];
  }

  List<Widget> _buildPosts(BuildContext context, AppState app) {
    final admin = app.me!;
    final list = app.repo.posts.where((p) => !p.deleted).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (list.isEmpty) {
      return [const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Post yok.')))];
    }

    return [
      for (final p in list)
        Card(
          child: ListTile(
            leading: Icon(p.pinned ? Icons.push_pin : Icons.article_outlined),
            title: Row(
              children: [
                if (p.pinned) const Text('📌 '),
                Expanded(child: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w900))),
              ],
            ),
            subtitle: Text('@${p.username} • ${_ddmmyyyy(p.createdAt)} • ${_hhmm(p.createdAt)}'),
            trailing: IconButton(
              tooltip: 'Post sil',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirm(
                context,
                title: 'Post sil',
                body: 'Bu post silinsin mi?',
                ok: () {
                  app.forum.delete(admin, p);
                  app.repo.pushNoti(title: 'Moderasyon', body: 'Admin bir post sildi.', type: 'sistem', premiumPriority: true);
                  app.notifySoft();
                  setState(() {});
                },
                okText: 'Sil',
              ),
            ),
          ),
        ),
    ];
  }
}

/* =========================================================
  ADMIN - LOGLAR
========================================================= */

class _AdminLogsTab extends StatelessWidget {
  const _AdminLogsTab({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final logs = List<String>.from(app.repo.adminLogs.reversed);

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        const _SectionHeader(
          title: 'Sistem Logları',
          subtitle: 'Admin işlemleri kayıtları (demo)',
        ),
        if (logs.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Log yok.')))
        else
          for (final l in logs)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
        const SizedBox(height: 10),
        const _SoftFooterNote(text: 'Prod’da loglar backend’de tutulmalı ve yetkilendirilmelidir.'),
      ],
    );
  }
}
/* =========================================================
  FORUM ARAMA (AYRI EKRAN) - MEVCUDU DEĞİŞTİRMEZ
========================================================= */

class ForumSearchScreen extends StatefulWidget {
  const ForumSearchScreen({super.key, required this.app});
  final AppState app;

  @override
  State<ForumSearchScreen> createState() => _ForumSearchScreenState();
}

class _ForumSearchScreenState extends State<ForumSearchScreen> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final postsAll = app.forum.listVisible();

    final posts = query.trim().isEmpty
        ? postsAll
        : postsAll.where((p) {
            final q = _norm(query);
            return _norm(p.title).contains(q) ||
                _norm(p.content).contains(q) ||
                _norm(p.username).contains(q);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Forumda Ara'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          const _SectionHeader(
            title: 'Arama',
            subtitle: 'Başlık • içerik • kullanıcı',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'örn: transfer, derbi, gs, fb...',
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          if (posts.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Sonuç bulunamadı.')))
          else
            for (final p in posts)
              Card(
                child: ListTile(
                  leading: Icon(p.pinned ? Icons.push_pin : Icons.article_outlined),
                  title: Row(
                    children: [
                      if (p.pinned) const Text('📌 '),
                      Expanded(child: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w900))),
                    ],
                  ),
                  subtitle: Text('@${p.username} • ${_ddmmyyyy(p.createdAt)} • ${_hhmm(p.createdAt)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PostDetailScreen(app: app, post: p)),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
