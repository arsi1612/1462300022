import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

// ─────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────
class AppColors {
  static const Color deepSpace = Color(0xFF0A0E1A);
  static const Color cosmicBlue = Color(0xFF1A2340);
  static const Color nebulaBlue = Color(0xFF2563EB);
  static const Color starWhite = Color(0xFFF0F4FF);
  static const Color moonGray = Color(0xFF8899BB);
  static const Color orbitCyan = Color(0xFF06B6D4);
  static const Color alertRed = Color(0xFFEF4444);
  static const Color successGreen = Color(0xFF22C55E);
}

// ─────────────────────────────────────────────
// MODEL DATA
// ─────────────────────────────────────────────
class ArticleModel {
  final int id;
  final String title;
  final String url;
  final String imageUrl;
  final String newsSite;
  final String summary;
  final String publishedAt;

  ArticleModel({
    required this.id,
    required this.title,
    required this.url,
    required this.imageUrl,
    required this.newsSite,
    required this.summary,
    required this.publishedAt,
  });

  factory ArticleModel.fromJson(Map<String, dynamic> json) {
    return ArticleModel(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      url: json['url'] ?? '',
      imageUrl: json['image_url'] ?? '',
      newsSite: json['news_site'] ?? '',
      summary: json['summary'] ?? '',
      publishedAt: json['published_at'] ?? '',
    );
  }
}

// ─────────────────────────────────────────────
// FIREBASE AUTH SERVICE
// ─────────────────────────────────────────────
class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _firestore = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;

  // Simpan session ke SharedPreferences
  static Future<void> _saveSession(bool isLoggedIn) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', isLoggedIn);
  }

  static Future<bool> checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  static Future<String?> register(
    String name,
    String email,
    String password,
    String instagram,
  ) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Simpan data user ke Firestore
      await _firestore.collection('users').doc(cred.user!.uid).set({
        'name': name,
        'email': email,
        'instagram': instagram.startsWith('@') ? instagram : '@$instagram',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _saveSession(true);
      return null; // null = sukses
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') return 'Email sudah terdaftar.';
      if (e.code == 'weak-password')
        return 'Password terlalu lemah (min 6 karakter).';
      if (e.code == 'invalid-email') return 'Format email tidak valid.';
      return e.message ?? 'Terjadi kesalahan.';
    }
  }

  static Future<String?> login(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      await _saveSession(true);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return 'Email tidak terdaftar.';
      if (e.code == 'wrong-password') return 'Password salah.';
      if (e.code == 'invalid-email') return 'Format email tidak valid.';
      return e.message ?? 'Terjadi kesalahan.';
    }
  }

  static Future<String?> sendResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return 'Email tidak terdaftar.';
      return e.message ?? 'Terjadi kesalahan.';
    }
  }

  static Future<void> logout() async {
    await _auth.signOut();
    await _saveSession(false);
  }

  // Ambil data profil dari Firestore
  static Future<Map<String, dynamic>?> getUserProfile() async {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }
}

// ─────────────────────────────────────────────
// FIRESTORE SERVICE
// ─────────────────────────────────────────────
class FirestoreService {
  static final _firestore = FirebaseFirestore.instance;

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  // Stream real-time favorites
  static Stream<QuerySnapshot> favoritesStream() {
    if (_uid == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('favorites')
        .snapshots();
  }

  static Future<void> addFavorite(int id, String title) async {
    if (_uid == null) return;
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('favorites')
        .doc(id.toString())
        .set({
          'id': id,
          'title': title,
          'savedAt': FieldValue.serverTimestamp(),
        });
  }

  static Future<void> removeFavorite(int id) async {
    if (_uid == null) return;
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('favorites')
        .doc(id.toString())
        .delete();
  }

  static Future<bool> isFavorite(int id) async {
    if (_uid == null) return false;
    final doc = await _firestore
        .collection('users')
        .doc(_uid)
        .collection('favorites')
        .doc(id.toString())
        .get();
    return doc.exists;
  }

  // Notifikasi statis
  static List<Map<String, dynamic>> get notifications => [
    {
      'title': 'Peluncuran Roket SpaceX',
      'body': 'Falcon 9 berhasil mendarat kembali',
      'time': '2 jam lalu',
    },
    {
      'title': 'Misi Artemis Update',
      'body': 'NASA umumkan jadwal terbaru misi ke Bulan',
      'time': '5 jam lalu',
    },
    {
      'title': 'Mars Rover Discovery',
      'body': 'Perseverance temukan mineral baru di Mars',
      'time': '1 hari lalu',
    },
    {
      'title': 'James Webb Telescope',
      'body': 'Gambar terbaru galaksi jauh dirilis',
      'time': '2 hari lalu',
    },
    {
      'title': 'Stasiun Luar Angkasa ISS',
      'body': 'Awak baru berhasil tiba di ISS',
      'time': '3 hari lalu',
    },
  ];
}

// ─────────────────────────────────────────────
// API SERVICE
// ─────────────────────────────────────────────
class NewsApiService {
  static const _base =
      'https://api.spaceflightnewsapi.net/v4/articles/?limit=20';

  static Future<List<ArticleModel>> fetchArticles() async {
    final resp = await http
        .get(Uri.parse(_base))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      final List rs = data['results'] ?? [];
      return rs.map((j) => ArticleModel.fromJson(j)).toList();
    }
    throw Exception('Gagal memuat berita (${resp.statusCode})');
  }
}

// ─────────────────────────────────────────────
// MAIN
// ─────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const SpaceNewsApp());
}

// ─────────────────────────────────────────────
// ROOT APP
// ─────────────────────────────────────────────
class SpaceNewsApp extends StatelessWidget {
  const SpaceNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpaceNews Core',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.deepSpace,
        colorScheme: ColorScheme.dark(
          primary: AppColors.nebulaBlue,
          secondary: AppColors.orbitCyan,
          surface: AppColors.cosmicBlue,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.cosmicBlue,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          labelStyle: const TextStyle(color: AppColors.moonGray),
          prefixIconColor: AppColors.moonGray,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.nebulaBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ─────────────────────────────────────────────
// 1. SPLASH SCREEN
// ─────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();

    // Delay tepat 3 detik lalu cek session
    Timer(const Duration(seconds: 3), () async {
      if (!mounted) return;
      final loggedIn = await AuthService.checkSession();
      final user = AuthService.currentUser;
      if (!mounted) return;
      if (loggedIn && user != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainShell()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RegisterPage()),
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSpace,
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.nebulaBlue.withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'SpaceNews Core',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.starWhite,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Advanced International News Portal',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.moonGray,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.orbitCyan),
                strokeWidth: 2.5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 2. HALAMAN DAFTAR
// ─────────────────────────────────────────────
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _igCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  Future<void> _register() async {
    final n = _nameCtrl.text.trim();
    final e = _emailCtrl.text.trim();
    final p = _passCtrl.text;
    final ig = _igCtrl.text.trim();
    if (n.isEmpty || e.isEmpty || p.isEmpty || ig.isEmpty) {
      setState(() => _error = 'Semua kolom wajib diisi.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await AuthService.register(n, e, p, ig);
    setState(() => _loading = false);
    if (!mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Akun berhasil dibuat!'),
          backgroundColor: AppColors.successGreen,
        ),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.nebulaBlue.withOpacity(0.4),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'SpaceNews Core',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.starWhite,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Buat akun baru',
                style: TextStyle(color: AppColors.moonGray),
              ),
              const SizedBox(height: 32),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.alertRed.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.alertRed,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.alertRed,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: AppColors.starWhite),
                decoration: const InputDecoration(
                  labelText: 'Nama Lengkap',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppColors.starWhite),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: const TextStyle(color: AppColors.starWhite),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.moonGray,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _igCtrl,
                style: const TextStyle(color: AppColors.starWhite),
                decoration: const InputDecoration(
                  labelText: 'Instagram (contoh: @username)',
                  prefixIcon: Icon(Icons.camera_alt_outlined),
                ),
              ),
              const SizedBox(height: 24),
              _loading
                  ? const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppColors.orbitCyan),
                    )
                  : ElevatedButton(
                      onPressed: _register,
                      child: const Text('Daftar'),
                    ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                ),
                child: const Text(
                  'Apakah sudah punya akun? Login',
                  style: TextStyle(
                    color: AppColors.orbitCyan,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 3. HALAMAN FORGOT PASSWORD
// ─────────────────────────────────────────────
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _msg;
  bool _isError = false;

  Future<void> _send() async {
    final e = _emailCtrl.text.trim();
    if (e.isEmpty) {
      setState(() {
        _msg = 'Masukkan email Anda.';
        _isError = true;
      });
      return;
    }
    setState(() {
      _loading = true;
      _msg = null;
    });
    final err = await AuthService.sendResetEmail(e);
    setState(() {
      _loading = false;
      _isError = err != null;
      _msg = err ?? 'Link reset berhasil dikirim ke $e. Cek inbox/spam kamu.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.deepSpace,
        foregroundColor: AppColors.starWhite,
        title: const Text(
          'Lupa Password',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reset Password',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.starWhite,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Masukkan email terdaftar, kami akan kirimkan link reset.',
              style: TextStyle(color: AppColors.moonGray, fontSize: 13),
            ),
            const SizedBox(height: 28),
            if (_msg != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      (_isError ? AppColors.alertRed : AppColors.successGreen)
                          .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _msg!,
                  style: TextStyle(
                    color: _isError
                        ? AppColors.alertRed
                        : AppColors.successGreen,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: AppColors.starWhite),
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 24),
            _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppColors.orbitCyan),
                    ),
                  )
                : ElevatedButton(
                    onPressed: _send,
                    child: const Text('Send to Email'),
                  ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 4. HALAMAN LOGIN
// ─────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    final e = _emailCtrl.text.trim();
    final p = _passCtrl.text;
    if (e.isEmpty || p.isEmpty) {
      setState(() => _error = 'Isi email dan password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await AuthService.login(e, p);
    setState(() => _loading = false);
    if (!mounted) return;
    if (err == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomePage()),
      );
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            children: [
              const SizedBox(height: 30),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.nebulaBlue.withOpacity(0.5),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'SpaceNews Core',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.starWhite,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Selamat datang kembali',
                style: TextStyle(color: AppColors.moonGray),
              ),
              const SizedBox(height: 36),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.alertRed.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.alertRed,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.alertRed,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: AppColors.starWhite),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: const TextStyle(color: AppColors.starWhite),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.moonGray,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ForgotPasswordPage(),
                    ),
                  ),
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(color: AppColors.orbitCyan),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _loading
                  ? const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppColors.orbitCyan),
                    )
                  : ElevatedButton(
                      onPressed: _login,
                      child: const Text('Login'),
                    ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const RegisterPage()),
                ),
                child: const Text(
                  'Belum punya akun? Daftar',
                  style: TextStyle(
                    color: AppColors.orbitCyan,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 5. WELCOME PAGE
// ─────────────────────────────────────────────
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  'https://images.unsplash.com/photo-1446776811953-b23d57bd21aa?w=600&fit=crop',
                  height: 240,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 240,
                    decoration: BoxDecoration(
                      color: AppColors.cosmicBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.newspaper_rounded,
                      size: 80,
                      color: AppColors.moonGray,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 36),
              const Text(
                'Welcome to SpaceNews Core Application',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.starWhite,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Portal berita antariksa internasional terdepan.\nJelajahi update terkini dari seluruh penjuru semesta.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.moonGray,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const MainShell()),
                ),
                child: const Text('Mulai Jelajahi'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 6. MAIN SHELL (BottomNavigationBar)
// ─────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _idx = 0;
  final _pages = const [
    HomePage(),
    FavoritePage(),
    NotificationPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.cosmicBlue,
          border: Border(
            top: BorderSide(
              color: AppColors.nebulaBlue.withOpacity(0.3),
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          indicatorColor: AppColors.nebulaBlue.withOpacity(0.25),
          selectedIndex: _idx,
          onDestinationSelected: (i) => setState(() => _idx = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(
                Icons.home_rounded,
                color: AppColors.orbitCyan,
              ),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite, color: AppColors.alertRed),
              label: 'Favorite',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_outlined),
              selectedIcon: Icon(
                Icons.notifications_rounded,
                color: AppColors.orbitCyan,
              ),
              label: 'Notifikasi',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(
                Icons.person_rounded,
                color: AppColors.orbitCyan,
              ),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// HOME PAGE
// ─────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<ArticleModel> _articles = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final data = await NewsApiService.fetchArticles();
      if (mounted)
        setState(() {
          _articles = data;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSpace,
      body: RefreshIndicator(
        color: AppColors.orbitCyan,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 70,
              backgroundColor: AppColors.deepSpace,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                title: Row(
                  children: const [
                    Icon(
                      Icons.rocket_launch_rounded,
                      color: AppColors.orbitCyan,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'SpaceNews Core',
                      style: TextStyle(
                        color: AppColors.starWhite,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_articles.isNotEmpty)
              SliverToBoxAdapter(
                child: _HeadlineBanner(article: _articles.first),
              ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'Berita Terkini',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.starWhite,
                  ),
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(AppColors.orbitCyan),
                  ),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.wifi_off_rounded,
                        color: AppColors.moonGray,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Gagal memuat berita',
                        style: TextStyle(color: AppColors.moonGray),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _load,
                        child: const Text(
                          'Coba Lagi',
                          style: TextStyle(color: AppColors.orbitCyan),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _ArticleCard(article: _articles[i]),
                    childCount: _articles.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HeadlineBanner extends StatelessWidget {
  final ArticleModel article;
  const _HeadlineBanner({required this.article});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetailPage(article: article)),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        height: 200,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: article.imageUrl.isNotEmpty
                  ? Image.network(
                      article.imageUrl,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          Container(color: AppColors.cosmicBlue),
                    )
                  : Container(
                      color: AppColors.cosmicBlue,
                      child: const Icon(
                        Icons.newspaper_rounded,
                        color: AppColors.moonGray,
                        size: 40,
                      ),
                    ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.nebulaBlue,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'HEADLINE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    article.newsSite,
                    style: const TextStyle(
                      color: AppColors.orbitCyan,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final ArticleModel article;
  const _ArticleCard({required this.article});

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetailPage(article: article)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cosmicBlue,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: article.imageUrl.isNotEmpty
                  ? Image.network(
                      article.imageUrl,
                      width: 88,
                      height: 74,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 88,
                        height: 74,
                        color: AppColors.deepSpace,
                      ),
                    )
                  : Container(
                      width: 88,
                      height: 74,
                      color: AppColors.deepSpace,
                      child: const Icon(
                        Icons.newspaper_rounded,
                        color: AppColors.moonGray,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    article.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.starWhite,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.source_outlined,
                        size: 11,
                        color: AppColors.moonGray,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        article.newsSite,
                        style: const TextStyle(
                          color: AppColors.orbitCyan,
                          fontSize: 11,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(article.publishedAt),
                        style: const TextStyle(
                          color: AppColors.moonGray,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 7. DETAIL PAGE
// ─────────────────────────────────────────────
class DetailPage extends StatefulWidget {
  final ArticleModel article;
  const DetailPage({super.key, required this.article});
  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  bool _isFav = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkFav();
  }

  Future<void> _checkFav() async {
    try {
      final fav = await FirestoreService.isFavorite(
        widget.article.id,
      ).timeout(const Duration(seconds: 5));
      if (mounted)
        setState(() {
          _isFav = fav;
          _loading = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _isFav = false;
          _loading = false;
        });
    }
  }

  Future<void> _toggleFav() async {
    if (_isFav) {
      await FirestoreService.removeFavorite(widget.article.id);
    } else {
      await FirestoreService.addFavorite(
        widget.article.id,
        widget.article.title,
      );
    }
    setState(() => _isFav = !_isFav);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isFav ? 'Ditambahkan ke Favorit' : 'Dihapus dari Favorit',
          ),
          backgroundColor: _isFav ? AppColors.successGreen : AppColors.moonGray,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Agu',
        'Sep',
        'Okt',
        'Nov',
        'Des',
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    return Scaffold(
      backgroundColor: AppColors.deepSpace,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            backgroundColor: AppColors.deepSpace,
            foregroundColor: AppColors.starWhite,
            pinned: true,
            actions: [
              _loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(
                            AppColors.orbitCyan,
                          ),
                        ),
                      ),
                    )
                  : IconButton(
                      icon: Icon(
                        _isFav ? Icons.favorite : Icons.favorite_border,
                        color: _isFav
                            ? AppColors.alertRed
                            : AppColors.starWhite,
                        size: 26,
                      ),
                      onPressed: _toggleFav,
                    ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  a.imageUrl.isNotEmpty
                      ? Image.network(
                          a.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: AppColors.cosmicBlue),
                        )
                      : Container(color: AppColors.cosmicBlue),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          AppColors.deepSpace,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.nebulaBlue.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.nebulaBlue.withOpacity(0.5),
                        ),
                      ),
                      child: Text(
                        a.newsSite,
                        style: const TextStyle(
                          color: AppColors.orbitCyan,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: AppColors.moonGray,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(a.publishedAt),
                      style: const TextStyle(
                        color: AppColors.moonGray,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  a.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.starWhite,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Divider(color: AppColors.cosmicBlue),
                const SizedBox(height: 16),
                const Text(
                  'Ringkasan',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.orbitCyan,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  a.summary.isNotEmpty
                      ? a.summary
                      : 'Tidak ada ringkasan tersedia.',
                  style: const TextStyle(
                    color: AppColors.starWhite,
                    fontSize: 14,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 28),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 8. HALAMAN FAVORITE (Real-time Firestore)
// ─────────────────────────────────────────────
class FavoritePage extends StatelessWidget {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepSpace,
      appBar: AppBar(
        backgroundColor: AppColors.deepSpace,
        title: const Text(
          'Favorit Saya',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.starWhite,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirestoreService.favoritesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.orbitCyan),
              ),
            );
          }
          if (snapshot.hasError ||
              !snapshot.hasData ||
              snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 64,
                    color: AppColors.moonGray,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Belum ada artikel favorit',
                    style: TextStyle(color: AppColors.moonGray, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Klik ikon hati di halaman detail\nuntuk menyimpan artikel',
                    style: TextStyle(color: AppColors.moonGray, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          final docs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final int id = data['id'] ?? 0;
              final String title = data['title'] ?? '';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cosmicBlue,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.alertRed.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.favorite,
                      color: AppColors.alertRed,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.starWhite,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppColors.moonGray,
                        size: 20,
                      ),
                      onPressed: () => FirestoreService.removeFavorite(id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 9. HALAMAN NOTIFIKASI
// ─────────────────────────────────────────────
class NotificationPage extends StatelessWidget {
  const NotificationPage({super.key});
  @override
  Widget build(BuildContext context) {
    final notifs = FirestoreService.notifications;
    return Scaffold(
      backgroundColor: AppColors.deepSpace,
      appBar: AppBar(
        backgroundColor: AppColors.deepSpace,
        title: const Text(
          'Notifikasi',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.starWhite,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: notifs.length,
        separatorBuilder: (_, __) =>
            Divider(color: AppColors.cosmicBlue.withOpacity(0.5), height: 1),
        itemBuilder: (_, i) {
          final n = notifs[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.nebulaBlue.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_rounded,
                    color: AppColors.orbitCyan,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n['title']!,
                        style: const TextStyle(
                          color: AppColors.starWhite,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        n['body']!,
                        style: const TextStyle(
                          color: AppColors.moonGray,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        n['time']!,
                        style: const TextStyle(
                          color: AppColors.nebulaBlue,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 10. HALAMAN PROFIL
// ─────────────────────────────────────────────
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await AuthService.getUserProfile().timeout(
        const Duration(seconds: 5),
      );
      if (mounted)
        setState(() {
          _profile = data;
          _loading = false;
        });
    } catch (_) {
      // Firestore timeout atau user belum login, tampilkan data dari Auth saja
      if (mounted)
        setState(() {
          _profile = null;
          _loading = false;
        });
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RegisterPage()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?['name'] ?? '';
    final email = _profile?['email'] ?? AuthService.currentUser?.email ?? '';
    final instagram = _profile?['instagram'] ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: AppColors.deepSpace,
      appBar: AppBar(
        backgroundColor: AppColors.deepSpace,
        title: const Text(
          'Profil',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.starWhite,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.orbitCyan),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.nebulaBlue, AppColors.orbitCyan],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.nebulaBlue.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.starWhite,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: const TextStyle(
                      color: AppColors.moonGray,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _InfoCard(
                    icon: Icons.person_rounded,
                    label: 'Nama Lengkap',
                    value: name,
                  ),
                  const SizedBox(height: 10),
                  _InfoCard(
                    icon: Icons.email_rounded,
                    label: 'Email',
                    value: email,
                  ),
                  const SizedBox(height: 10),
                  _InfoCard(
                    icon: Icons.camera_alt_rounded,
                    label: 'Instagram',
                    value: instagram,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Log Out'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.alertRed,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cosmicBlue,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.orbitCyan, size: 20),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppColors.moonGray, fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                value.isEmpty ? '-' : value,
                style: const TextStyle(
                  color: AppColors.starWhite,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
