import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/* ================= CONFIG ================= */
const String NEWS_API_KEY = "cb4647d6e30049e28a03b65789295163";

/* ================= MODELS ================= */
enum Role { user, admin }

class AppUser {
  String name;
  Role role;
  bool premium;
  bool banned;
  int level;
  int xp;

  AppUser({
    required this.name,
    this.role = Role.user,
    this.premium = false,
    this.banned = false,
    this.level = 1,
    this.xp = 0,
  });

  void gainXP(int v) {
    int gain = premium ? (v * 0.7).round() : v;
    if (xp + gain >= level * 300 && level < 99) {
      xp = 0;
      level++;
    } else {
      xp += gain;
    }
  }

  String get title {
    if (premium) return "👑 ARENA ELİT";
    if (level >= 50) return "Efsane";
    if (level >= 25) return "Usta";
    if (level >= 10) return "Tribüncü";
    return "Çaylak";
  }
}

AppUser currentUser = AppUser(name: "Misafir");

/* ================= THEMES ================= */
final darkTheme = ThemeData.dark().copyWith(
  scaffoldBackgroundColor: const Color(0xFF0E0E0E),
);

final premiumTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF0C0B08),
  primaryColor: const Color(0xFFD4AF37),
);

/* ================= MAIN ================= */
void main() {
  runApp(const SBArenaApp());
}

class SBArenaApp extends StatelessWidget {
  const SBArenaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: currentUser.premium ? premiumTheme : darkTheme,
      home: const LoginPage(),
    );
  }
}

/* ================= LOGIN ================= */
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TextEditingController();
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("S&B ARENA", style: TextStyle(fontSize: 32)),
              TextField(controller: c, decoration: const InputDecoration(labelText: "Kullanıcı adı")),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  currentUser = AppUser(
                    name: c.text,
                    role: c.text.toLowerCase() == "admin" ? Role.admin : Role.user,
                  );
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
                },
                child: const Text("Giriş Yap"),
              )
            ],
          ),
        ),
      ),
    );
  }
}

/* ================= HOME ================= */
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int i = 0;
  final pages = const [
    NewsPage(),
    ChatPage(),
    ForumPage(),
    LeaderboardPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("S&B ARENA")),
      body: pages[i],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: i,
        onTap: (v) => setState(() => i = v),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.newspaper), label: "Haber"),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: "Chat"),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: "Forum"),
          BottomNavigationBarItem(icon: Icon(Icons.emoji_events), label: "Lig"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profil"),
        ],
      ),
    );
  }
}

/* ================= NEWS ================= */
class NewsPage extends StatefulWidget {
  const NewsPage({super.key});
  @override State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  List articles = [];

  Future<void> load() async {
    try {
      final r = await http.get(Uri.parse(
          "https://newsapi.org/v2/top-headlines?category=sports&country=tr&apiKey=$NEWS_API_KEY"));
      final d = jsonDecode(r.body);
      setState(() => articles = d["articles"]);
    } catch (e) {
      // ignore errors for demo
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: load,
      child: ListView.builder(
        itemCount: articles.length,
        itemBuilder: (_, i) {
          final a = articles[i];
          return Card(
            margin: const EdgeInsets.all(8),
            child: Column(
              children: [
                if (a["urlToImage"] != null)
                  Image.network(a["urlToImage"], height: 180, fit: BoxFit.cover),
                ListTile(title: Text(a["title"] ?? "")),
              ],
            ),
          );
        },
      ),
    );
  }
}

/* ================= CHAT ================= */
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});
  @override
  Widget build(BuildContext context) {
    if (!currentUser.premium) {
      return const Center(child: Text("🔒 Premium chat odaları"));
    }
    return Center(child: Text("💬 Arena Chat (Demo)"));
  }
}

/* ================= FORUM ================= */
class ForumPage extends StatelessWidget {
  const ForumPage({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          title: const Text("⚽ En iyi forvet kim?"),
          trailing: IconButton(
            icon: const Icon(Icons.delete),
            onPressed: currentUser.role == Role.admin ? () {} : null,
          ),
        ),
      ],
    );
  }
}

/* ================= LEADERBOARD ================= */
class LeaderboardPage extends StatelessWidget {
  const LeaderboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(title: Text(currentUser.name), subtitle: Text("Seviye ${currentUser.level}")),
      ],
    );
  }
}

/* ================= PROFILE ================= */
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(currentUser.name, style: const TextStyle(fontSize: 22)),
        Text(currentUser.title),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => currentUser.premium = true,
          child: const Text("👑 Premium Ol"),
        ),
        if (currentUser.role == Role.admin)
          ElevatedButton(
            child: const Text("🛠 Admin Panel"),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPanel()));
            },
          )
      ],
    );
  }
}

/* ================= ADMIN ================= */
class AdminPanel extends StatelessWidget {
  const AdminPanel({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Panel")),
      body: ListTile(
        title: const Text("Kullanıcı Banla"),
        trailing: ElevatedButton(onPressed: () {}, child: const Text("Ban")),
      ),
    );
  }
}
