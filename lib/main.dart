import 'package:flutter/material.dart';
import 'dart:async';

/* ================= USER MODEL ================= */

class AppUser {
  String name;
  bool online;
  int level;
  int xp;
  int posts;
  int messages;
  Duration timeSpent;
  List<String> badges;

  AppUser({
    required this.name,
    this.online = true,
    this.level = 1,
    this.xp = 0,
    this.posts = 0,
    this.messages = 0,
    Duration? timeSpent,
    List<String>? badges,
  })  : timeSpent = timeSpent ?? Duration.zero,
        badges = badges ?? [];

  void gainXP(int value) {
    if (level >= 99) return;
    xp += value;
    if (xp >= level * 100) {
      xp = 0;
      level++;
      checkBadges();
    }
  }

  void checkBadges() {
    if (level >= 5) add("⭐ Yükselen");
    if (level >= 10) add("🔥 Tecrübeli");
    if (level >= 25) add("💎 Elit");
    if (level >= 50) add("👑 Efsane");
    if (level >= 99) add("🏆 ARENA LİDERİ");
    if (posts >= 5) add("📝 İlk Post");
    if (messages >= 10) add("💬 Sohbetçi");
    if (timeSpent.inMinutes >= 30) add("⏱ Sadık Üye");
  }

  void add(String badge) {
    if (!badges.contains(badge)) badges.add(badge);
  }

  String get title {
    if (level >= 90) return "Ölümsüz";
    if (level >= 70) return "İkon";
    if (level >= 50) return "Efsane";
    if (level >= 30) return "Usta";
    if (level >= 15) return "Analist";
    if (level >= 5) return "Tribüncü";
    return "Çaylak";
  }
}

AppUser user = AppUser(name: "S&B Kullanıcı");

/* ================= APP ================= */

void main() {
  runApp(const SBArenaApp());
}

class SBArenaApp extends StatelessWidget {
  const SBArenaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E0E0E),
        primaryColor: Colors.amber,
      ),
      home: const SplashScreen(),
    );
  }
}

/* ================= SPLASH ================= */

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController c;

  @override
  void initState() {
    super.initState();
    c = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..forward();

    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ScaleTransition(
          scale: CurvedAnimation(parent: c, curve: Curves.easeOutBack),
          child: Image.asset(
            "assets/logo.png", // 👈 LOGOYU SEN KOYACAKSIN
            width: 180,
          ),
        ),
      ),
    );
  }
}

/* ================= HOME ================= */

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;
  Timer? timer;

  final pages = const [
    NewsPage(),
    ChatPage(),
    ForumPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      setState(() {
        user.timeSpent += const Duration(seconds: 10);
        user.gainXP(2);
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset("assets/logo.png", width: 28),
            const SizedBox(width: 8),
            const Text("S&B ARENA"),
          ],
        ),
        actions: [
          Icon(Icons.circle,
              size: 12, color: user.online ? Colors.green : Colors.grey),
          const SizedBox(width: 16),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        selectedItemColor: Colors.amber,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Haberler"),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: "Chat"),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: "Forum"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profil"),
        ],
      ),
    );
  }
}

/* ================= HABERLER ================= */

class NewsPage extends StatelessWidget {
  const NewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        newsCard("Derbi Gecesi!", Icons.sports_soccer),
        newsCard("NBA Final Heyecanı", Icons.sports_basketball),
        newsCard("Formula 1 Gündemi", Icons.sports_motorsports),
      ],
    );
  }

  Widget newsCard(String title, IconData icon) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, size: 32, color: Colors.amber),
        title: Text(title),
        subtitle: const Text("Detaylar için tıkla"),
        onTap: () => user.gainXP(5),
      ),
    );
  }
}

/* ================= CHAT ================= */

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Expanded(
          child: ListTile(
            title: Text("Arena Chat"),
            subtitle: Text("Canlı sohbet (demo)"),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: ElevatedButton(
            onPressed: () {
              user.messages++;
              user.gainXP(10);
            },
            child: const Text("Mesaj Gönder"),
          ),
        )
      ],
    );
  }
}

/* ================= FORUM ================= */

class ForumPage extends StatelessWidget {
  const ForumPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        forumPost("⚽ En iyi forvet kim?"),
        forumPost("🏀 NBA MVP tahminleri"),
        forumPost("🏎 F1 sezon analizi"),
      ],
    );
  }

  Widget forumPost(String title) {
    return ListTile(
      title: Text(title),
      trailing: IconButton(
        icon: const Icon(Icons.add_comment),
        onPressed: () {
          user.posts++;
          user.gainXP(15);
        },
      ),
    );
  }
}

/* ================= PROFILE ================= */

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const CircleAvatar(
          radius: 40,
          backgroundColor: Colors.amber,
          child: Icon(Icons.person, size: 40, color: Colors.black),
        ),
        const SizedBox(height: 12),
        Center(
            child:
                Text(user.name, style: const TextStyle(fontSize: 22))),
        Center(child: Text(user.title)),
        const SizedBox(height: 12),
        Text("Seviye: ${user.level}"),
        LinearProgressIndicator(
          value: user.xp / (user.level * 100),
          color: Colors.amber,
        ),
        const SizedBox(height: 16),
        const Text("Rozetler", style: TextStyle(fontSize: 18)),
        Wrap(
          spacing: 8,
          children: user.badges.map((b) => Chip(label: Text(b))).toList(),
        ),
      ],
    );
  }
}
