import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'models/health_record.dart';
import 'services/firebase_service.dart';
import 'services/firestore_service.dart';
import 'services/app_localizations.dart';
import 'services/database_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';
import 'services/offline_service.dart';
import 'services/exercise_service.dart';
import 'services/heart_rate_service.dart';
import 'services/translation_service.dart';
import 'bluetooth_scan_page.dart';
import 'doctor_appointment_page.dart';
import 'services/bluetooth_hr_service.dart';
import 'services/routing_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize timezones early for scheduled notifications
  tz.initializeTimeZones();
  try {
    await FirebaseService.initialize();
  } catch (_) {}
  // Initialize Supabase cloud database
  try {
    await Supabase.initialize(
      url: 'https://guomxsumdtkjcwipafdt.supabase.co',
      publishableKey: 'sb_publishable_i8q3Sy9oL7zbxGn7wk07GQ_gEciptus',
    );
    print('[Supabase] Initialized successfully');
  } catch (e) {
    print('[Supabase] Initialization error: $e');
  }
  runApp(const MedlyApp());
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------
class MedlyApp extends StatefulWidget {
  const MedlyApp({super.key});

  @override
  State<MedlyApp> createState() => _MedlyAppState();
}

class _MedlyAppState extends State<MedlyApp> {
  ThemeMode _themeMode = ThemeMode.light;
  bool _showSplash = true;
  bool _isLoggedIn = false;
  bool _needsOnboarding = false;
  bool _showCreateAccount = false;
  CaregiverProfile _currentAccount = CaregiverProfile.empty();
  final List<CaregiverProfile> _accounts = [];

  @override
  void initState() {
    super.initState();
    _checkExistingLogin();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  Future<void> _checkExistingLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('user_email');
    if (savedEmail != null && savedEmail.isNotEmpty) {
      // First check in-memory accounts
      var account = _accounts.firstWhere(
        (a) => a.email == savedEmail,
        orElse: () => CaregiverProfile.empty(),
      );
      // If not found, try SQLite database
      if (account.email.isEmpty) {
        try {
          final localAcct = await DatabaseService.getAccount(savedEmail);
          if (localAcct != null) {
            account = CaregiverProfile(
              name: localAcct['name'] ?? savedEmail,
              email: savedEmail,
              password: localAcct['password'] ?? '',
              role: localAcct['role'] ?? 'User',
              patients: [PatientProfile(name: localAcct['patient_name'] ?? 'Patient')],
              bloodGroup: localAcct['blood_group'],
              allergies: localAcct['allergies'],
              weight: localAcct['weight'],
              height: localAcct['height'],
            );
            print('[AutoLogin] Found account in local SQLite: $savedEmail');
          }
        } catch (_) {}
      }
      // Also try Firestore
      if (account.email.isEmpty) {
        try {
          final fs = FirestoreService();
          if (fs.isAvailable) {
            final snap = await fs.db.collection('users').doc(savedEmail).get();
            if (snap.exists) {
              final data = snap.data()!;
              account = CaregiverProfile(
                name: data['name'] ?? savedEmail,
                email: savedEmail,
                password: data['password'] ?? '',
                role: data['role'] ?? 'User',
                patients: [PatientProfile(name: data['patientName'] ?? 'Patient')],
                bloodGroup: data['bloodGroup'],
                allergies: data['allergies'],
                diseases: data['diseases'],
                weight: data['weight'],
                height: data['height'],
              );
            }
          }
        } catch (_) {}
      }
      // Also try Supabase
      if (account.email.isEmpty) {
        try {
          final docs = await SupabaseService.find('users',
            filter: {'email': savedEmail.toLowerCase()}, limit: 1);
          if (docs.isNotEmpty) {
            final data = docs.first;
            account = CaregiverProfile(
              name: data['name'] ?? savedEmail,
              email: savedEmail,
              password: data['password'] ?? '',
              role: data['role'] ?? 'User',
              patients: [PatientProfile(name: data['patientName'] ?? 'Patient')],
              bloodGroup: data['bloodGroup'],
              allergies: data['allergies'],
              diseases: data['diseases'],
              weight: data['weight'],
              height: data['height'],
            );
          }
        } catch (_) {}
      }
      if (account.email.isNotEmpty) {
        setState(() {
          _accounts.add(account);
          _currentAccount = account;
          _isLoggedIn = true;
        });
      }
    }
  }

  void _handleLogin(String email, String password) async {
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both email and password.')),
      );
      return;
    }

    final match = _accounts.firstWhere(
      (a) =>
          a.email.toLowerCase() == email.trim().toLowerCase() &&
          a.password == password.trim(),
      orElse: () => CaregiverProfile.empty(),
    );

    if (match.email.isEmpty) {
      // Try Firestore
      try {
        final fs = FirestoreService();
        if (fs.isAvailable) {
          final snap = await fs.db
              .collection('users')
              .where('email', isEqualTo: email.trim().toLowerCase())
              .limit(1)
              .get();
          if (snap.docs.isNotEmpty) {
            final data = snap.docs.first.data();
            if (data['password'] == password.trim()) {
              final profile = CaregiverProfile(
                name: data['name'] ?? email,
                email: email.trim(),
                password: password.trim(),
                role: data['role'] ?? 'User',
                patients: [
                  PatientProfile(name: data['patientName'] ?? 'Patient'),
                ],
                weight: data['weight'] ?? '',
                height: data['height'] ?? '',
              );
              setState(() {
                _accounts.add(profile);
                _currentAccount = profile;
                _isLoggedIn = true;
                _needsOnboarding = data['bloodGroup'] == null;
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('user_email', email.trim());
              return;
            }
          }
        }
      } catch (_) {}

      // Try Supabase as fallback
      try {
        final docs = await SupabaseService.find('users',
          filter: {'email': email.trim().toLowerCase()}, limit: 1);
        if (docs.isNotEmpty) {
          final data = docs.first;
          if (data['password'] == password.trim()) {
            final profile = CaregiverProfile(
              name: data['name'] ?? email,
              email: email.trim(),
              password: password.trim(),
              role: data['role'] ?? 'User',
              patients: [PatientProfile(name: data['patientName'] ?? 'Patient')],
              bloodGroup: data['bloodGroup'],
              allergies: data['allergies'],
              diseases: data['diseases'],
              weight: data['weight'],
              height: data['height'],
            );
            setState(() {
              _accounts.add(profile);
              _currentAccount = profile;
              _isLoggedIn = true;
              _needsOnboarding = data['bloodGroup'] == null;
            });
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_email', email.trim());
            return;
          }
        }
      } catch (_) {}

      // Try local SQLite account
      try {
        final localAccount = await DatabaseService.loginLocal(email.trim(), password.trim());
        if (localAccount != null) {
          final profile = CaregiverProfile(
            name: localAccount['name'] ?? email,
            email: email.trim(),
            password: password.trim(),
            role: localAccount['role'] ?? 'User',
            patients: [PatientProfile(name: localAccount['patient_name'] ?? 'Patient')],
            bloodGroup: localAccount['blood_group'],
            allergies: localAccount['allergies'],
            weight: localAccount['weight'],
            height: localAccount['height'],
          );
          setState(() {
            _accounts.add(profile);
            _currentAccount = profile;
            _isLoggedIn = true;
            _needsOnboarding = localAccount['blood_group'] == null;
          });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_email', email.trim());
          _cacheEmergencyData();
          print('[Login] Logged in via local SQLite: $email');
          return;
        }
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account not found. Please create one.'),
        ),
      );
      return;
    }

    // Log successful login to SQLite + Supabase
    await DatabaseService.logLogin(
      email: match.email,
      successful: true,
      role: match.role,
    );
    SupabaseService.syncLoginAudit(
      email: match.email,
      successful: true,
      role: match.role,
    );

    setState(() {
      _currentAccount = match;
      _isLoggedIn = true;
      _showCreateAccount = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_email', match.email);
    _cacheEmergencyData();
  }

  void _handleCreateAccountStart() {
    setState(() => _showCreateAccount = true);
  }

  void _handleSignOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_email');
    setState(() {
      _currentAccount = CaregiverProfile.empty();
      _isLoggedIn = false;
      _showCreateAccount = false;
      _needsOnboarding = false;
    });
  }

  void _handleAccountCreated(
    String name,
    String email,
    String password,
    String role,
    String patientName,
  ) {
    final newAccount = CaregiverProfile(
      name: name,
      email: email,
      password: password,
      role: role,
      patients: [PatientProfile(name: patientName)],
    );

    setState(() {
      _accounts.add(newAccount);
      _currentAccount = newAccount;
      _showCreateAccount = false;
      _isLoggedIn = true;
      _needsOnboarding = true;
    });

    _saveAccountToFirestore(newAccount);
    // Save locally to SQLite so user can always log back in
    DatabaseService.saveAccount(
      email: newAccount.email,
      name: newAccount.name,
      password: newAccount.password,
      role: newAccount.role,
      patientName: newAccount.patients.isNotEmpty ? newAccount.patients.first.name : null,
    );
    // Sync to Supabase
    SupabaseService.syncUser(
      name: newAccount.name,
      email: newAccount.email,
      role: newAccount.role,
      password: newAccount.password,
      patientName: newAccount.patients.isNotEmpty ? newAccount.patients.first.name : null,
    );
  }

  Future<void> _saveAccountToFirestore(CaregiverProfile profile) async {
    try {
      final fs = FirestoreService();
      if (fs.isAvailable) {
        await fs.db.collection('users').doc(profile.email).set({
          'name': profile.name,
          'email': profile.email,
          'password': profile.password,
          'role': profile.role,
          'patientName':
              profile.patients.isNotEmpty ? profile.patients.first.name : '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  void _handleOnboardingComplete(
    String bloodGroup,
    String allergies,
    String diseases,
    String weight,
    String height,
  ) {
    final updated = CaregiverProfile(
      name: _currentAccount.name,
      email: _currentAccount.email,
      password: _currentAccount.password,
      role: _currentAccount.role,
      patients: _currentAccount.patients,
      bloodGroup: bloodGroup,
      allergies: allergies,
      diseases: diseases,
      weight: weight,
      height: height,
    );
    setState(() {
      _currentAccount = updated;
      _needsOnboarding = false;
    });
    _saveOnboardingToFirestore(updated);
    _cacheEmergencyData();
    // Update local SQLite account with health data
    DatabaseService.updateAccount(updated.email, {
      'blood_group': updated.bloodGroup,
      'allergies': updated.allergies,
      'diseases': updated.diseases,
      'weight': updated.weight,
      'height': updated.height,
    });
  }

  Future<void> _cacheEmergencyData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('emergency_contacts_json');
      List<Map<String, String>> contacts = [];
      if (saved != null && saved.isNotEmpty) {
        contacts = saved.map((s) => Map<String, String>.from(jsonDecode(s))).toList();
      }
      await OfflineService.cacheEmergencyData(
        patientName: _currentAccount.patients.isNotEmpty ? _currentAccount.patients.first.name : 'Patient',
        bloodGroup: _currentAccount.bloodGroup ?? '',
        allergies: _currentAccount.allergies ?? '',
        diseases: _currentAccount.diseases ?? '',
        weight: _currentAccount.weight ?? '',
        height: _currentAccount.height ?? '',
        contacts: contacts,
      );
    } catch (_) {}
  }

  Future<void> _saveOnboardingToFirestore(CaregiverProfile profile) async {
    try {
      final fs = FirestoreService();
      if (fs.isAvailable) {
        await fs.db.collection('users').doc(profile.email).update({
          'bloodGroup': profile.bloodGroup,
          'allergies': profile.allergies,
      'diseases': profile.diseases,
          'weight': profile.weight,
          'height': profile.height,
        });
      }
    } catch (_) {}
    // Also sync to Supabase
    SupabaseService.upsert('users', {
      'email': profile.email.toLowerCase(),
      'blood_group': profile.bloodGroup,
      'allergies': profile.allergies,
      'diseases': profile.diseases,
      'weight': profile.weight,
      'height': profile.height,
    }, onConflict: 'email');
  }

  @override
  Widget build(BuildContext context) {
    final lightTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.redAccent,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF101827),
      cardTheme: const CardThemeData(color: Color(0xFF1B2432)),
    );

    if (_showSplash) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        home: const SplashAnimation(),
      );
    }

    if (_isLoggedIn && _needsOnboarding) {
      return MaterialApp(
        title: 'Medly',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: _themeMode,
        home: OnboardingScreen(
          onComplete: _handleOnboardingComplete,
          themeMode: _themeMode,
          onThemeChanged: (mode) => setState(() => _themeMode = mode),
        ),
      );
    }

    if (_isLoggedIn) {
      return MaterialApp(
        title: 'Medly',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: _themeMode,
        home: MedlyHomePage(
          themeMode: _themeMode,
          onThemeChanged: (mode) => setState(() => _themeMode = mode),
          caregiverName: _currentAccount.name,
          caregiverRole: _currentAccount.role,
          email: _currentAccount.email,
          patientName: _currentAccount.patients.isNotEmpty
              ? _currentAccount.patients.first.name
              : 'Patient',
          patients: _currentAccount.patients,
          onSignOut: _handleSignOut,
          bloodGroup: _currentAccount.bloodGroup,
          allergies: _currentAccount.allergies,
          diseases: _currentAccount.diseases,
          weight: _currentAccount.weight,
          height: _currentAccount.height,
          onProfileUpdate: (bg, al, dis, w, h) {
            _handleOnboardingComplete(bg, al, dis, w, h);
          },
        ),
      );
    }

    return MaterialApp(
      title: 'Medly',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      home: _showCreateAccount
          ? CreateAccountScreen(
              onCreateAccount: _handleAccountCreated,
              onBack: () => setState(() => _showCreateAccount = false),
              themeMode: _themeMode,
              onThemeChanged: (mode) => setState(() => _themeMode = mode),
            )
          : LoginScreen(
              onLogin: _handleLogin,
              onCreateAccount: _handleCreateAccountStart,
              onThemeChanged: (mode) => setState(() => _themeMode = mode),
              themeMode: _themeMode,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Splash screen with animation
// ---------------------------------------------------------------------------
class SplashAnimation extends StatefulWidget {
  const SplashAnimation({super.key});

  @override
  State<SplashAnimation> createState() => _SplashAnimationState();
}

class _SplashAnimationState extends State<SplashAnimation>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _pulseController;
  late AnimationController _ringController;
  late AnimationController _textController;
  late AnimationController _particleController;

  @override
  void initState() {
    super.initState();

    // Main logo animation (scale + fade)
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Pulse glow behind logo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Expanding ring effect
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Text fade-in (delayed)
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Particles
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Sequence: ring → logo → pulse → text → particles
    _ringController.forward().then((_) {
      _mainController.forward();
      _pulseController.repeat(reverse: true);
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      _textController.forward();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      _particleController.forward();
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
    _ringController.dispose();
    _textController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8E5E8),
              Color(0xFFF5F7FB),
              Color(0xFFEFF4F8),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Background particles
            AnimatedBuilder(
              animation: _particleController,
              builder: (ctx, _) => CustomPaint(
                size: size,
                painter: _SplashParticlesPainter(
                  progress: _particleController.value,
                ),
              ),
            ),

            // Center content
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Expanding ring + glow + logo stack
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Expanding ring
                        AnimatedBuilder(
                          animation: _ringController,
                          builder: (ctx, child) {
                            final ringSize = _ringController.value * 180;
                            final ringOpacity = (1.0 - _ringController.value).clamp(0.0, 1.0);
                            return Container(
                              width: ringSize,
                              height: ringSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: ringOpacity * 0.4),
                                  width: 2,
                                ),
                              ),
                            );
                          },
                        ),
                        // Pulsing glow
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (ctx, child) {
                            final glowSize = 120.0 + (_pulseController.value * 20);
                            final glowOpacity = 0.15 + (_pulseController.value * 0.1);
                            return Container(
                              width: glowSize,
                              height: glowSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: glowOpacity),
                                    blurRadius: 40,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        // Logo with scale + bounce
                        AnimatedBuilder(
                          animation: _mainController,
                          builder: (ctx, child) {
                            final scale = Curves.elasticOut.transform(_mainController.value);
                            final opacity = Curves.easeIn.transform(
                              (_mainController.value * 2).clamp(0.0, 1.0),
                            );
                            return Opacity(
                              opacity: opacity,
                              child: Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 110,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red.withValues(alpha: 0.15),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: Image.asset(
                                    'assets/medly_logo.png',
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // App name with letter-by-letter fade
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (ctx, child) {
                      return Opacity(
                        opacity: _textController.value,
                        child: Transform.translate(
                          offset: Offset(0, 20 * (1 - _textController.value)),
                          child: const Text(
                            'Medly',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFE53935),
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 8),

                  // Tagline with delayed fade
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (ctx, child) {
                      final taglineOpacity = (_textController.value * 1.5 - 0.5).clamp(0.0, 1.0);
                      return Opacity(
                        opacity: taglineOpacity,
                        child: Transform.translate(
                          offset: Offset(0, 15 * (1 - taglineOpacity)),
                          child: Text(
                            'CARE. CONNECT. SAVE LIVES.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade500,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 40),

                  // Loading dots
                  AnimatedBuilder(
                    animation: _textController,
                    builder: (ctx, child) {
                      if (_textController.value < 0.5) return const SizedBox();
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(3, (i) {
                          final dotOpacity = ((_textController.value - 0.5) * 2 - (i * 0.15)).clamp(0.0, 1.0);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: AnimatedOpacity(
                              opacity: dotOpacity,
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    },
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

// Particle painter for splash background
class _SplashParticlesPainter extends CustomPainter {
  final double progress;
  _SplashParticlesPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final random = math.Random(42);

    for (int i = 0; i < 25; i++) {
      final startX = random.nextDouble() * size.width;
      final startY = random.nextDouble() * size.height;
      final speed = 0.3 + random.nextDouble() * 0.7;
      final particleProgress = (progress * speed).clamp(0.0, 1.0);
      final radius = 1.0 + random.nextDouble() * 2.5;
      final opacity = (math.sin(particleProgress * math.pi) * 0.3).clamp(0.0, 0.3);

      final x = startX + math.sin(particleProgress * math.pi * 2 + i) * 30;
      final y = startY - particleProgress * 60;

      paint.color = i.isEven
          ? Colors.red.withValues(alpha: opacity)
          : Colors.pink.withValues(alpha: opacity * 0.7);

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashParticlesPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ---------------------------------------------------------------------------
// Login screen – no demo credentials
// ---------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onCreateAccount,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final void Function(String email, String password) onLogin;
  final VoidCallback onCreateAccount;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _acceptedTerms = false;

  void _submitLogin() {
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept Terms & Conditions to continue.')),
      );
      return;
    }
    widget.onLogin(_emailController.text.trim(), _passwordController.text.trim());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101827) : const Color(0xFFEFF4F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 430),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2432) : Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () {
                        widget.onThemeChanged(
                          widget.themeMode == ThemeMode.dark
                              ? ThemeMode.light
                              : ThemeMode.dark,
                        );
                      },
                      icon: Icon(
                        widget.themeMode == ThemeMode.dark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Image.asset(
                    'assets/medly_logo.png',
                    width: 80,
                    height: 80,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Welcome to Medly',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to manage health records and emergency care.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _acceptedTerms,
                        onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const TermsAndConditionsPage()),
                          ),
                          child: Text(
                            'I accept the Terms & Conditions',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black54,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _submitLogin,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Sign In'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: widget.onCreateAccount,
                      child: const Text('Create new account'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const TermsAndConditionsPage()),
                        );
                      },
                      child: Text(
                        'Terms & Conditions',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create Account screen
// ---------------------------------------------------------------------------
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({
    super.key,
    required this.onCreateAccount,
    required this.onBack,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final void Function(String, String, String, String, String) onCreateAccount;
  final VoidCallback onBack;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _patientController = TextEditingController();
  String _selectedRole = 'User';
  bool _acceptedTerms = false;

  static const _roles = [
    'User',
    'Doctor',
    'Ambulance Driver',
    'Family Member',
  ];

  bool get _needsPatientName => _selectedRole == 'User' || _selectedRole == 'Family Member';

  void _submitAccount() {
    if (!_acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept Terms & Conditions to continue.')),
      );
      return;
    }
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all details.')),
      );
      return;
    }
    if (_needsPatientName && _patientController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a patient name.')),
      );
      return;
    }
    widget.onCreateAccount(
      _nameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text.trim(),
      _selectedRole,
      _needsPatientName ? _patientController.text.trim() : _nameController.text.trim(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _patientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101827) : const Color(0xFFEFF4F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 450),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2432) : Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: widget.onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => widget.onThemeChanged(
                          widget.themeMode == ThemeMode.dark
                              ? ThemeMode.light
                              : ThemeMode.dark,
                        ),
                        icon: Icon(
                          widget.themeMode == ThemeMode.dark
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Create Account',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Set up your profile and link a patient.',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      prefixIcon: Icon(Icons.email_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      prefixIcon: Icon(Icons.work_rounded),
                      border: OutlineInputBorder(),
                    ),
                    items: _roles
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedRole = v);
                    },
                  ),
                  if (_needsPatientName) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _patientController,
                      decoration: const InputDecoration(
                        labelText: 'Patient name',
                        prefixIcon: Icon(Icons.medical_services_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: _acceptedTerms,
                        onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const TermsAndConditionsPage()),
                          ),
                          child: Text(
                            'I accept the Terms & Conditions',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black54,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _submitAccount,
                      icon: const Icon(Icons.person_add_rounded),
                      label: const Text('Create account'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding screen – blood type, allergies, weight, height
// ---------------------------------------------------------------------------
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final void Function(String bloodGroup, String allergies, String diseases, String weight, String height) onComplete;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  String _selectedBloodGroup = 'A+';
  final _allergiesController = TextEditingController();
  final _diseasesController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();

  static const _bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-', 'Unknown',
  ];

  @override
  void dispose() {
    _allergiesController.dispose();
    _diseasesController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_weightController.text.trim().isEmpty || _heightController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your weight and height.')),
      );
      return;
    }
    widget.onComplete(
      _selectedBloodGroup,
      _allergiesController.text.trim(),
      _diseasesController.text.trim(),
      _weightController.text.trim(),
      _heightController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101827) : const Color(0xFFEFF4F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 450),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2432) : Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      onPressed: () => widget.onThemeChanged(
                        widget.themeMode == ThemeMode.dark
                            ? ThemeMode.light
                            : ThemeMode.dark,
                      ),
                      icon: Icon(
                        widget.themeMode == ThemeMode.dark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Image.asset(
                    'assets/medly_logo.png',
                    width: 70,
                    height: 70,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Complete Your Profile',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your health information so Medly can assist you better in emergencies.',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                  ),
                  const SizedBox(height: 22),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedBloodGroup,
                    decoration: const InputDecoration(
                      labelText: 'Blood Group',
                      prefixIcon: Icon(Icons.bloodtype_rounded),
                      border: OutlineInputBorder(),
                    ),
                    items: _bloodGroups
                        .map((bg) => DropdownMenuItem(value: bg, child: Text(bg)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedBloodGroup = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _allergiesController,
                    decoration: const InputDecoration(
                      labelText: 'Allergies (optional, comma-separated)',
                      hintText: 'e.g. Peanuts, Penicillin (leave blank if none)',
                      prefixIcon: Icon(Icons.warning_amber_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _diseasesController,
                    decoration: const InputDecoration(
                      labelText: 'Diseases / Conditions (comma-separated)',
                      hintText: 'e.g. Diabetes, Asthma, Hypertension',
                      prefixIcon: Icon(Icons.sick_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _weightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Weight (kg)',
                      prefixIcon: Icon(Icons.monitor_weight_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _heightController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Height (cm)',
                      prefixIcon: Icon(Icons.height_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Continue'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main Home Page
// ---------------------------------------------------------------------------
class MedlyHomePage extends StatefulWidget {
  const MedlyHomePage({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.caregiverName,
    required this.caregiverRole,
    required this.email,
    required this.patientName,
    this.patients = const [],
    required this.onSignOut,
    this.bloodGroup,
    this.allergies,
    this.diseases,
    this.weight,
    this.height,
    this.onProfileUpdate,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final String caregiverName;
  final String caregiverRole;
  final String email;
  final String patientName;
  final List<PatientProfile> patients;
  final VoidCallback onSignOut;
  final String? bloodGroup;
  final String? allergies;
  final String? diseases;
  final String? weight;
  final String? height;
  final void Function(String, String, String, String, String)? onProfileUpdate;

  @override
  State<MedlyHomePage> createState() => _MedlyHomePageState();
}

class _MedlyHomePageState extends State<MedlyHomePage>
    with WidgetsBindingObserver {
  static const List<String> _languages = AppLocalizations.supportedLanguages;

  late String _selectedPatientName = widget.patientName;
  late List<PatientProfile> _patientProfiles = widget.patients.isEmpty
      ? [PatientProfile(name: widget.patientName)]
      : List<PatientProfile>.from(widget.patients);

  final FirestoreService _firestoreService = FirestoreService();
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  String _selectedLanguage = _languages.first;
  int _selectedIndex = 0;
  bool _isListening = false;
  String _currentContactName = '';
  double? _lastKnownLatitude;
  double? _lastKnownLongitude;

  // Medicine reminders – no defaults
  final List<MedicineReminder> _medicineReminders = [];
  final TextEditingController _medicineNameController = TextEditingController();
  final TextEditingController _medicineTimeController = TextEditingController();

  // Health metrics – empty, to be filled by user
  final List<HealthMetric> _healthMetrics = [
    HealthMetric(label: 'Blood Pressure', value: '--', unit: 'mmHg', color: Colors.blue),
    HealthMetric(label: 'Blood Sugar', value: '--', unit: 'mg/dL', color: Colors.teal),
    HealthMetric(label: 'Heart Rate', value: '--', unit: 'bpm', color: Colors.orange),
    HealthMetric(label: 'Sleep', value: '--', unit: 'hrs', color: Colors.purple),
  ];

  // Nearby services – loaded from Overpass API
  List<HealthcareService> _serviceList = [];
  bool _loadingServices = true;

  // Screen time tracking
  DateTime? _appOpenTime;
  int _screenTimeMinutesToday = 0;

  // Exercise checkbox selection
  final Set<String> _selectedExercises = {};

  // Profile photo
  String? _profilePhotoPath;
  String _todayDateKey = '';

  // Step counter — hardware pedometer + accelerometer fallback
  int _todaySteps = 0;
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  int _stepOffset = 0;
  int _lastSensorTotal = 0;
  bool _pedometerAvailable = false;
  // Accelerometer-based step detection
  double _lastAccelMagnitude = 0;
  int _accelStepCount = 0;
  static const double _stepThreshold = 12.0; // m/s² threshold for step detection
  static const int _stepCooldownMs = 350; // min ms between steps
  DateTime _lastStepTime = DateTime.fromMillisecondsSinceEpoch(0);

  String _t(String value) => AppLocalizations(_selectedLanguage).text(value);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appOpenTime = DateTime.now();
    _todayDateKey = _dateKey(DateTime.now());
    _loadSavedData();
    _fetchNearbyServices();
    _trackScreenTime();
    _initTts();
    _initNotifications();
    _initStepCounter();
  }

  Future<void> _initTts() async {
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setPitch(1.0);
    // Try to get natural-sounding voices
    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null && voices.isNotEmpty) {
        // Find the best natural voice for the current language
        final langVoices = voices.where((v) =>
          v['locale'].toString().startsWith(_getLanguageCode(_selectedLanguage))
        ).toList();
        if (langVoices.isNotEmpty) {
          await _flutterTts.setVoice({
            'name': langVoices.first['name'],
            'locale': langVoices.first['locale'],
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _initNotifications() async {
    await NotificationService.initialize();
    // Request notification permission (required on Android 13+)
    await NotificationService.requestPermission();
    // Handle notification taps — navigate to app
    NotificationService.onNotificationTapped = (payload) {
      if (payload != null && payload.startsWith('medicine_reminder:')) {
        final medicine = payload.replaceFirst('medicine_reminder:', '');
        print('[Notifications] Opening app for reminder: $medicine');
        setState(() => _selectedIndex = 2);
      } else if (payload == 'streak_reminder' || payload == 'morning_motivation') {
        // Switch to Health tab to show exercises
        setState(() => _selectedIndex = 2);
      }
    };
    // Reschedule all saved reminders — works even after app restart or reboot
    await NotificationService.rescheduleAllReminders();
    // Schedule daily streak reminders (8 PM) and morning motivation (7 AM)
    await NotificationService.scheduleStreakReminder();
    await NotificationService.scheduleMorningMotivation();
  }

  String _getLanguageCode(String lang) {
    switch (lang) {
      case 'Tamil': return 'ta';
      case 'Telugu': return 'te';
      case 'Kannada': return 'kn';
      case 'Malayalam': return 'ml';
      case 'Hindi': return 'hi';
      case 'Marathi': return 'mr';
      case 'Urdu': return 'ur';
      case 'French': return 'fr';
      case 'Japanese': return 'ja';
      default: return 'en';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stepCountSubscription?.cancel();
    _accelSubscription?.cancel();
    _bleHRSubscription?.cancel();
    _medicineNameController.dispose();
    _medicineTimeController.dispose();
    _speechToText.stop();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _recordScreenTime();
    } else if (state == AppLifecycleState.resumed) {
      _appOpenTime = DateTime.now();
      // One-time sensor read to capture steps taken while app was in background
      _readStepSensorOnce();
      // Also reload saved steps as fallback
      _loadSavedSteps();
      // Sync pending SOS events when back online
      _syncPendingSosEvents();
      // Refresh nearby services
      _fetchNearbyServices();
    }
  }

  void _recordScreenTime() {
    if (_appOpenTime != null) {
      final elapsed = DateTime.now().difference(_appOpenTime!).inMinutes;
      _screenTimeMinutesToday += elapsed;
      _appOpenTime = DateTime.now();
      _saveScreenTime();
      _saveStepCount(); // Save steps when app goes to background
    }
  }

  void _trackScreenTime() {
    // Called on init; screen time is tracked automatically via lifecycle observer.
    // Nothing extra needed here.
  }

  // ---- Step counter: pedometer + accelerometer fallback ----
  Future<void> _initStepCounter() async {
    final prefs = await SharedPreferences.getInstance();
    _stepOffset = prefs.getInt('step_offset_$_todayDateKey') ?? 0;
    _lastSensorTotal = prefs.getInt('last_sensor_total_$_todayDateKey') ?? 0;
    _todaySteps = prefs.getInt('today_steps_$_todayDateKey') ?? 0;
    if (_todaySteps > 0) setState(() {});

    // Try hardware pedometer first
    try {
      _stepCountSubscription = Pedometer.stepCountStream.listen(
        (StepCount event) {
          if (!mounted) return;
          _pedometerAvailable = true;
          _updateStepCount(event.steps);
        },
        onError: (error) {
          print('[StepCounter] Pedometer error: $error');
          _pedometerAvailable = false;
          _startAccelerometerFallback();
        },
        cancelOnError: false,
      );
      print('[StepCounter] Pedometer stream started');
    } catch (e) {
      print('[StepCounter] Pedometer init error: $e');
      _startAccelerometerFallback();
    }

    // If pedometer doesn't emit within 3 seconds, use accelerometer
    Future.delayed(const Duration(seconds: 3), () {
      if (!_pedometerAvailable && mounted) {
        print('[StepCounter] Pedometer not available, using accelerometer');
        _startAccelerometerFallback();
      }
    });
  }

  void _startAccelerometerFallback() {
    if (_accelSubscription != null) return; // Already started
    try {
      _accelSubscription = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
        (AccelerometerEvent event) {
          if (!mounted) return;
          _detectStepFromAccel(event);
        },
        onError: (e) {
          print('[StepCounter] Accelerometer error: $e');
        },
      );
      print('[StepCounter] Accelerometer fallback started');
    } catch (e) {
      print('[StepCounter] Accelerometer init error: $e');
    }
  }

  void _detectStepFromAccel(AccelerometerEvent event) {
    final magnitude = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    final now = DateTime.now();
    final timeSinceLastStep = now.difference(_lastStepTime).inMilliseconds;

    // Detect a step: magnitude spikes above threshold with cooldown
    if (magnitude > _stepThreshold &&
        _lastAccelMagnitude <= _stepThreshold &&
        timeSinceLastStep > _stepCooldownMs) {
      _accelStepCount++;
      _lastStepTime = now;
      // Update total steps (accel steps + any previously saved)
      final prefs = SharedPreferences.getInstance();
      prefs.then((p) {
        final savedAccelOffset = p.getInt('accel_offset_$_todayDateKey') ?? 0;
        if (savedAccelOffset == 0 && _accelStepCount == 1) {
          p.setInt('accel_offset_$_todayDateKey', 0);
        }
      });
      if (mounted) {
        setState(() => _todaySteps++);
        _saveStepCount();
      }
    }
    _lastAccelMagnitude = magnitude;
  }

  void _updateStepCount(int totalSteps) async {
    final prefs = await SharedPreferences.getInstance();

    // First reading ever today — set the offset
    if (_stepOffset == 0 && totalSteps > 0) {
      _stepOffset = totalSteps;
      await prefs.setInt('step_offset_$_todayDateKey', totalSteps);
    }

    // The sensor may give a HIGHER value than last time even while app was closed
    // because the hardware keeps counting. Compare and take the max.
    final sensorTodaySteps = (totalSteps - _stepOffset).clamp(0, 999999);
    final bestSteps = sensorTodaySteps > _todaySteps ? sensorTodaySteps : _todaySteps;

    if (bestSteps > _todaySteps || totalSteps > _lastSensorTotal) {
      setState(() => _todaySteps = bestSteps);
      await prefs.setInt('today_steps_$_todayDateKey', _todaySteps);
      await prefs.setInt('last_sensor_total_$_todayDateKey', totalSteps);
      _lastSensorTotal = totalSteps;
    }
  }

  /// One-time sensor read — captures steps taken while app was closed
  Future<void> _readStepSensorOnce() async {
    try {
      StreamSubscription? sub;
      final completer = Completer<void>();
      sub = Pedometer.stepCountStream.listen(
        (StepCount event) {
          _updateStepCount(event.steps);
          completer.complete();
          sub?.cancel();
        },
        onError: (_) {
          completer.complete();
          sub?.cancel();
        },
      );
      // Timeout after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.complete();
          sub?.cancel();
        }
      });
      await completer.future;
    } catch (e) {
      print('[StepCounter] One-time read error: $e');
    }
  }

  Future<void> _loadSavedSteps() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('today_steps_$_todayDateKey') ?? 0;
    if (saved > _todaySteps) {
      setState(() => _todaySteps = saved);
    }
  }

  Future<void> _saveStepCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('today_steps_$_todayDateKey', _todaySteps);
    await prefs.setInt('last_sensor_total_$_todayDateKey', _lastSensorTotal);
  }

  // ---- Pending SOS sync ----
  Future<void> _syncPendingSosEvents() async {
    try {
      final pending = await OfflineService.getPendingSyncCount();
      if (pending == 0) return;
      final isOnline = await OfflineService.isOnline();
      if (!isOnline) return;

      print('[Offline] Syncing $pending pending SOS events...');
      // Sync each queued SOS to Supabase
      final queue = (await SharedPreferences.getInstance()).getStringList('offline_sos_queue') ?? [];
      for (final item in queue) {
        final data = jsonDecode(item);
        SupabaseService.syncSosCall(
          patientName: data['patientName'] ?? '',
          contactName: data['contactName'] ?? '',
          contactPhone: data['contactPhone'] ?? '',
          latitude: data['latitude'],
          longitude: data['longitude'],
        );
      }
      await OfflineService.clearSyncQueue();
      print('[Offline] Sync complete');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synced $pending offline SOS event(s) to cloud.')),
        );
      }
    } catch (_) {}
  }

  String _dateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    // Load profile photo
    final photoPath = prefs.getString('profile_photo_${widget.email}');
    if (photoPath != null) setState(() => _profilePhotoPath = photoPath);
    final savedDate = prefs.getString('screen_time_date');
    setState(() {
      if (savedDate == _todayDateKey) {
        _screenTimeMinutesToday = prefs.getInt('screen_time_minutes') ?? 0;
      }
    });
    final savedReminders = prefs.getStringList('medicine_reminders');
    if (savedReminders != null && savedReminders.isNotEmpty) {
      setState(() {
        _medicineReminders
          ..clear()
          ..addAll(
            savedReminders.map((s) => MedicineReminder.fromMap(jsonDecode(s))),
          );
      });
    }
    // Load today's health snapshot from database
    try {
      final snapshots = await DatabaseService.getHealthSnapshots(_selectedPatientName);
      final today = snapshots.where((s) => s['date_key'] == _todayDateKey).toList();
      if (today.isNotEmpty) {
        final data = today.first;
        setState(() {
          if (data['blood_pressure'] != null && (data['blood_pressure'] as String).isNotEmpty) {
            _healthMetrics[0] = HealthMetric(label: 'Blood Pressure', value: data['blood_pressure'] as String, unit: 'mmHg', color: Colors.blue);
          }
          if (data['blood_sugar'] != null && (data['blood_sugar'] as String).isNotEmpty) {
            _healthMetrics[1] = HealthMetric(label: 'Blood Sugar', value: data['blood_sugar'] as String, unit: 'mg/dL', color: Colors.teal);
          }
          if (data['heart_rate'] != null && (data['heart_rate'] as String).isNotEmpty) {
            _healthMetrics[2] = HealthMetric(label: 'Heart Rate', value: data['heart_rate'] as String, unit: 'bpm', color: Colors.orange);
          }
          if (data['sleep_hours'] != null && (data['sleep_hours'] as String).isNotEmpty) {
            _healthMetrics[3] = HealthMetric(label: 'Sleep', value: data['sleep_hours'] as String, unit: 'hrs', color: Colors.purple);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveScreenTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('screen_time_date', _todayDateKey);
    await prefs.setInt('screen_time_minutes', _screenTimeMinutesToday);
  }

  Future<void> _saveMedicineReminders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'medicine_reminders',
      _medicineReminders.map((r) => jsonEncode(r.toMap())).toList(),
    );
  }

  // ------- Nearby services via Overpass API -------
  Future<void> _fetchNearbyServices() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _loadingServices = false);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        setState(() => _loadingServices = false);
        return;
      }

      // Try last known first (instant)
      double lat, lon;
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          lat = lastKnown.latitude;
          lon = lastKnown.longitude;
          _lastKnownLatitude = lat;
          _lastKnownLongitude = lon;
        } else {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
          );
          lat = pos.latitude;
          lon = pos.longitude;
          _lastKnownLatitude = lat;
          _lastKnownLongitude = lon;
        }
      } catch (_) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
        );
        lat = pos.latitude;
        lon = pos.longitude;
        _lastKnownLatitude = lat;
        _lastKnownLongitude = lon;
      }
      _lastKnownLatitude = lat;
      _lastKnownLongitude = lon;
      final radius = 15000; // 15 km radius for better coverage

      final query = '''
[out:json][timeout:30];
(
  node["amenity"="hospital"](around:$radius,$lat,$lon);
  way["amenity"="hospital"](around:$radius,$lat,$lon);
  relation["amenity"="hospital"](around:$radius,$lat,$lon);
  node["healthcare"="hospital"](around:$radius,$lat,$lon);
  way["healthcare"="hospital"](around:$radius,$lat,$lon);
  node["amenity"="pharmacy"](around:$radius,$lat,$lon);
  way["amenity"="pharmacy"](around:$radius,$lat,$lon);
  node["amenity"="chemist"](around:$radius,$lat,$lon);
  way["amenity"="chemist"](around:$radius,$lat,$lon);
  node["healthcare"="pharmacy"](around:$radius,$lat,$lon);
  node["healthcare"="ambulance"](around:$radius,$lat,$lon);
  node["emergency"="ambulance_station"](around:$radius,$lat,$lon);
  way["emergency"="ambulance_station"](around:$radius,$lat,$lon);
  node["healthcare"="clinic"](around:$radius,$lat,$lon);
  way["healthcare"="clinic"](around:$radius,$lat,$lon);
  node["amenity"="clinic"](around:$radius,$lat,$lon);
  way["amenity"="clinic"](around:$radius,$lat,$lon);
  node["healthcare"="doctor"](around:$radius,$lat,$lon);
);
out center 100;
''';

      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: {'data': query},
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final elements = data['elements'] as List? ?? [];
        final services = <HealthcareService>[];

        for (final el in elements) {
          final name = el['tags']?['name'] ?? el['tags']?['operator'] ?? 'Unknown';
          final amenity = el['tags']?['amenity'] ?? '';
          final healthcare = el['tags']?['healthcare'] ?? '';
          final emergency = el['tags']?['emergency'] ?? '';
          String type;
          if (amenity == 'hospital' || healthcare == 'hospital') {
            type = 'Hospital';
          } else if (amenity == 'pharmacy' || amenity == 'chemist' || healthcare == 'pharmacy') {
            type = 'Pharmacy';
          } else if (amenity == 'clinic' || healthcare == 'clinic') {
            type = 'Hospital';
          } else if (healthcare == 'doctor') {
            type = 'Hospital';
          } else if (healthcare == 'ambulance' || emergency == 'ambulance_station') {
            type = 'Ambulance';
          } else {
            type = 'Hospital';
          }
          final elLat = el['lat'] ?? el['center']?['lat'];
          final elLon = el['lon'] ?? el['center']?['lon'];
          if (elLat == null || elLon == null) continue;

          final dist = Geolocator.distanceBetween(lat, lon, elLat.toDouble(), elLon.toDouble());
          final distKm = (dist / 1000).toStringAsFixed(1);

          services.add(HealthcareService(
            name: name,
            type: type,
            distance: '$distKm km',
            status: 'Open',
            latitude: elLat.toDouble(),
            longitude: elLon.toDouble(),
          ));
        }

        services.sort((a, b) {
          final da = double.parse(a.distance.replaceAll(' km', ''));
          final db = double.parse(b.distance.replaceAll(' km', ''));
          return da.compareTo(db);
        });

        if (mounted) {
          setState(() {
            _serviceList = services.take(10).toList();
            _loadingServices = false;
          });
          // Cache for offline use
          OfflineService.cacheServices(
            services.take(10).map((s) => {
              'name': s.name, 'type': s.type, 'distance': s.distance,
              'latitude': s.latitude, 'longitude': s.longitude,
            }).toList(),
          );
        }
      } else {
        // Offline: try loading cached services
        final cached = await OfflineService.getCachedServices();
        if (mounted && cached.isNotEmpty) {
          setState(() {
            _serviceList = cached.map((c) => HealthcareService(
              name: c['name'] ?? 'Unknown',
              type: c['type'] ?? 'Hospital',
              distance: c['distance'] ?? '',
              status: 'Open',
              latitude: (c['latitude'] as num?)?.toDouble(),
              longitude: (c['longitude'] as num?)?.toDouble(),
            )).toList();
            _loadingServices = false;
          });
        } else if (mounted) {
          setState(() => _loadingServices = false);
        }
      }
    } catch (e) {
      print('[NearbyServices] Error: $e');
      // Try loading cached services on error
      final cached = await OfflineService.getCachedServices();
      if (mounted && cached.isNotEmpty) {
        setState(() {
          _serviceList = cached.map((c) => HealthcareService(
            name: c['name'] ?? 'Unknown',
            type: c['type'] ?? 'Hospital',
            distance: c['distance'] ?? '',
            status: 'Open',
            latitude: (c['latitude'] as num?)?.toDouble(),
            longitude: (c['longitude'] as num?)?.toDouble(),
          )).toList();
          _loadingServices = false;
        });
      } else if (mounted) {
        setState(() => _loadingServices = false);
      }
    }
  }

  // ------- SOS – call emergency contact (works offline) -------
  Future<void> _triggerEmergencySos() async {
    final isOnline = await OfflineService.isOnline();

    // Load contacts from memory, then try cache if offline
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('emergency_contacts_json');
    List<Map<String, String>> contacts = [];
    if (saved != null && saved.isNotEmpty) {
      contacts = saved.map((s) => Map<String, String>.from(jsonDecode(s))).toList();
    } else {
      // Fallback to legacy single contact
      final name = prefs.getString('emergency_contact_name') ?? '';
      final phone = prefs.getString('emergency_phone') ?? '';
      if (phone.isNotEmpty) contacts = [{'name': name, 'phone': phone, 'tier': '1'}];
    }
    // If still no contacts, try offline cache
    if (contacts.isEmpty) {
      contacts = await OfflineService.getCachedContacts();
    }

    if (contacts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add at least one emergency contact first.')),
        );
      }
      return;
    }

    // Cache contacts for offline use
    OfflineService.cacheEmergencyData(
      patientName: _selectedPatientName,
      bloodGroup: widget.bloodGroup ?? 'Unknown',
      allergies: widget.allergies ?? 'None',
      diseases: widget.diseases ?? 'None',
      weight: widget.weight ?? '',
      height: widget.height ?? '',
      contacts: contacts,
      lastLatitude: _lastKnownLatitude,
      lastLongitude: _lastKnownLongitude,
    );

    // Confirm SOS trigger
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trigger SOS?'),
        content: Text(
          isOnline
              ? 'Tier 1 contact will receive a phone call. '
                'Other tiers will receive a WhatsApp message. Continue?'
              : 'You are OFFLINE. Tier 1 will be called directly. '
                'Other tiers will receive an SMS message. Continue?'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('SEND SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Log SOS to local SQLite (always works)
    for (final c in contacts) {
      await DatabaseService.logSosCall(
        patientName: _selectedPatientName,
        contactName: c['name'],
        contactPhone: c['phone'],
        latitude: _lastKnownLatitude,
        longitude: _lastKnownLongitude,
      );
    }

    final sosLocation = _lastKnownLatitude != null && _lastKnownLongitude != null;
    if (sosLocation) {
      await DatabaseService.markSosLocation(
        latitude: _lastKnownLatitude!,
        longitude: _lastKnownLongitude!,
        patientName: _selectedPatientName,
      );
    }

    // If online, also sync to Supabase
    if (isOnline) {
      for (final c in contacts) {
        SupabaseService.syncSosCall(
          patientName: _selectedPatientName,
          contactName: c['name'],
          contactPhone: c['phone'],
          latitude: _lastKnownLatitude,
          longitude: _lastKnownLongitude,
        );
      }
      if (sosLocation) {
        SupabaseService.syncSosLocation(
          latitude: _lastKnownLatitude!,
          longitude: _lastKnownLongitude!,
          patientName: _selectedPatientName,
        );
      }
    } else {
      // Queue for sync when back online
      for (final c in contacts) {
        await OfflineService.queueSosSync(
          patientName: _selectedPatientName,
          contactName: c['name'] ?? '',
          contactPhone: c['phone'] ?? '',
          latitude: _lastKnownLatitude,
          longitude: _lastKnownLongitude,
        );
      }
    }

    // Tier 1: direct phone call (works offline!)
    final tier1 = contacts.firstWhere(
      (c) => c['tier'] == '1',
      orElse: () => contacts.first,
    );
    final callUri = Uri(scheme: 'tel', path: tier1['phone']);
    if (await canLaunchUrl(callUri)) {
      await launchUrl(callUri);
    }

    // Build SOS message with patient info
    final patientInfo = await OfflineService.getCachedPatientInfo();
    final sosMessageBody = 'EMERGENCY SOS from Medly!\n'
        '${_selectedPatientName} is in danger!\n'
        'Blood group: ${patientInfo["bloodGroup"] ?? "Unknown"}\n'
        'Allergies: ${patientInfo["allergies"] ?? "None"}\n'
        'Diseases: ${patientInfo["diseases"] ?? "None"}';
    final locationPart = sosLocation
        ? '\nLocation: https://maps.google.com/?q=${_lastKnownLatitude},${_lastKnownLongitude}'
        : '';
    final fullMessage = sosMessageBody + locationPart;

    // Tiers 2-5: WhatsApp if online, SMS if offline
    for (final c in contacts) {
      if (c['tier'] != '1') {
        final phone = c['phone']?.replaceAll(RegExp(r'[^0-9+]'), '') ?? '';
        if (phone.isEmpty) continue;

        if (isOnline) {
          // Try WhatsApp
          final sosMessage = Uri.encodeComponent(fullMessage);
          final whatsappUri = Uri.parse('https://wa.me/$phone?text=$sosMessage');
          try {
            if (await canLaunchUrl(whatsappUri)) {
              await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
            }
          } catch (_) {}
        } else {
          // Offline: send SMS (works without internet!)
          final smsUri = Uri(scheme: 'sms', path: phone, queryParameters: {'body': fullMessage});
          try {
            if (await canLaunchUrl(smsUri)) {
              await launchUrl(smsUri);
            }
          } catch (_) {}
        }
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SOS sent! Calling ${tier1['name']}, messaging ${contacts.length - 1} contact(s) via WhatsApp.')),
      );
    }
  }

  // ------- Emergency Broadcast — send SMS to ALL contacts at once -------
  Future<void> _triggerEmergencyBroadcast() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('emergency_contacts_json');
    List<Map<String, String>> contacts = [];
    if (saved != null && saved.isNotEmpty) {
      contacts = saved.map((s) => Map<String, String>.from(jsonDecode(s))).toList();
    } else {
      final name = prefs.getString('emergency_contact_name') ?? '';
      final phone = prefs.getString('emergency_phone') ?? '';
      if (phone.isNotEmpty) contacts = [{'name': name, 'phone': phone, 'tier': '1'}];
    }
    if (contacts.isEmpty) {
      contacts = await OfflineService.getCachedContacts();
    }

    if (contacts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add at least one emergency contact first.')),
        );
      }
      return;
    }

    // Confirm broadcast
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🚨 Emergency Broadcast?'),
        content: Text(
          'This will send an SMS to ALL ${contacts.length} emergency contacts simultaneously. '
          'Each contact will receive your name, blood group, allergies, and live GPS location. Continue?'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('BROADCAST NOW'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Log broadcast to SQLite
    for (final c in contacts) {
      await DatabaseService.logSosCall(
        patientName: _selectedPatientName,
        contactName: c['name'] ?? 'Broadcast',
        contactPhone: c['phone'],
        latitude: _lastKnownLatitude,
        longitude: _lastKnownLongitude,
      );
    }

    final hasLocation = _lastKnownLatitude != null && _lastKnownLongitude != null;
    if (hasLocation) {
      await DatabaseService.markSosLocation(
        latitude: _lastKnownLatitude!,
        longitude: _lastKnownLongitude!,
        patientName: 'BROADCAST: $_selectedPatientName',
      );
    }

    // Sync to Supabase
    for (final c in contacts) {
      SupabaseService.syncSosCall(
        patientName: 'BROADCAST: $_selectedPatientName',
        contactName: c['name'] ?? 'Broadcast',
        contactPhone: c['phone'],
        latitude: _lastKnownLatitude,
        longitude: _lastKnownLongitude,
      );
    }

    // Build the emergency SMS message
    final patientInfo = await OfflineService.getCachedPatientInfo();
    final sosMessage = '🚨 EMERGENCY BROADCAST from Medly!\n'
        '${_selectedPatientName} needs urgent help!\n'
        'Blood group: ${patientInfo["bloodGroup"] ?? "Unknown"}\n'
        'Allergies: ${patientInfo["allergies"] ?? "None"}\n'
        'Diseases: ${patientInfo["diseases"] ?? "None"}\n'
        'Weight: ${patientInfo["weight"] ?? "Unknown"} kg'
        'Height: ${patientInfo["height"] ?? "Unknown"} cm';
    final locationPart = hasLocation
        ? '\n📍 Location: https://maps.google.com/?q=${_lastKnownLatitude},${_lastKnownLongitude}'
        : '';
    final fullMessage = sosMessage + locationPart;

    // Send SMS to ALL contacts simultaneously
    int smsCount = 0;
    for (final c in contacts) {
      final phone = c['phone']?.replaceAll(RegExp(r'[^0-9+]'), '') ?? '';
      if (phone.isEmpty) continue;

      final smsUri = Uri(scheme: 'sms', path: phone, queryParameters: {'body': fullMessage});
      try {
        if (await canLaunchUrl(smsUri)) {
          // Each contact gets its own SMS intent
          await launchUrl(smsUri, mode: LaunchMode.externalApplication);
          smsCount++;
        }
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🚨 Broadcast sent! SMS opened for $smsCount contact(s).'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ------- Global voice input -------
  void _startGlobalVoiceInput() async {
    final available = await _speechToText.initialize();
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice input not available on this device.')),
        );
      }
      return;
    }

    setState(() => _isListening = true);
    await _speechToText.listen(
      onResult: (result) {
        if (result.finalResult) {
          setState(() => _isListening = false);
          final text = result.recognizedWords.trim();
          if (text.isNotEmpty) {
            _handleVoiceCommand(text);
          }
        }
      },
      localeId: _getLocaleId(_selectedLanguage),
      listenFor: const Duration(seconds: 15),
    );
  }

  void _handleVoiceCommand(String command) {
    final lower = command.toLowerCase();

    // Navigation commands
    if (lower.contains('home') || lower.contains('go home')) {
      setState(() => _selectedIndex = 0);
      return;
    }
    if (lower.contains('sos') || lower.contains('emergency')) {
      setState(() => _selectedIndex = 1);
      return;
    }
    if (lower.contains('health') || lower.contains('medicine')) {
      setState(() => _selectedIndex = 2);
      return;
    }

    // SOS trigger
    if (lower.contains('call') && (lower.contains('emergency') || lower.contains('contact') || lower.contains('help'))) {
      _triggerEmergencySos();
      return;
    }

    // Default: open AI assistant with the voice text
    _openAiSheetWithText(command);
  }

  void _openAiSheetWithText(String initialText) {
    _openAiSheet(initialText: initialText);
  }

  // ------- AI assistant (floating) -------
  void _openAiSheet({String initialText = ''}) {
    final symptomController = TextEditingController(text: initialText);
    final localCtx = context;

    showModalBottomSheet(
      context: localCtx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.smart_toy_rounded, color: Colors.indigo),
                      const SizedBox(width: 8),
                      Text(
                        _t('AI Health Assistant'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  // Language indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.language, size: 14, color: Colors.indigo),
                        const SizedBox(width: 6),
                        Text(
                          'Responding in: $_selectedLanguage',
                          style: const TextStyle(fontSize: 12, color: Colors.indigo),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: symptomController,
                    maxLines: 3,
                    onSubmitted: (_) async {
                      final text = symptomController.text.trim();
                      if (text.isEmpty) return;
                      showDialog(
                        context: localCtx,
                        builder: (_) => AlertDialog(
                          content: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              CircularProgressIndicator(),
                              SizedBox(width: 20),
                              Text('Analyzing...'),
                            ],
                          ),
                        ),
                      );
                      final guidance = await _generateAiGuidance(text);
                      if (localCtx.mounted) Navigator.pop(localCtx);
                      await _flutterTts.setLanguage(_getLocaleId(_selectedLanguage));
                      await _flutterTts.setSpeechRate(0.45);
                      await _flutterTts.setPitch(1.0);
                      _flutterTts.speak(guidance);
                      if (localCtx.mounted) {
                        showDialog(
                          context: localCtx,
                          builder: (_) => AlertDialog(
                            title: Text(_t('Guidance summary')),
                            content: SingleChildScrollView(child: Text(guidance)),
                            actions: [TextButton(onPressed: () => Navigator.pop(localCtx), child: const Text('OK'))],
                          ),
                        );
                      }
                    },
                    decoration: InputDecoration(
                      hintText: _t('Describe your symptoms or ask for first aid guidance'),
                      suffixIcon: const Icon(Icons.keyboard_return, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final text = symptomController.text.trim();
                            if (text.isEmpty) return;
                            showDialog(
                              context: localCtx,
                              builder: (_) => AlertDialog(
                                content: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    CircularProgressIndicator(),
                                    SizedBox(width: 20),
                                    Text('Analyzing...'),
                                  ],
                                ),
                              ),
                            );
                            final guidance = await _generateAiGuidance(text);
                            if (localCtx.mounted) Navigator.pop(localCtx);
                            await _flutterTts.setLanguage(_getLocaleId(_selectedLanguage));
                            await _flutterTts.setSpeechRate(0.45);
                            await _flutterTts.setPitch(1.0);
                            _flutterTts.speak(guidance);
                            if (localCtx.mounted) {
                              showDialog(
                                context: localCtx,
                                builder: (_) => AlertDialog(
                                  title: Text(_t('Guidance summary')),
                                  content: SingleChildScrollView(
                                    child: Text(guidance),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(localCtx),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.auto_awesome),
                          label: Text(_t('Get guidance')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: () async {
                          final available = await _speechToText.initialize();
                          if (!available) {
                            ScaffoldMessenger.of(localCtx).showSnackBar(
                              const SnackBar(content: Text('Voice input not available.')),
                            );
                            return;
                          }
                          await _speechToText.listen(
                            onResult: (result) {
                              setSheetState(() {
                                symptomController.text = result.recognizedWords;
                              });
                            },
                            localeId: _getLocaleId(_selectedLanguage),
                            listenFor: const Duration(seconds: 12),
                          );
                        },
                        icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Guidance button
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: localCtx,
                        builder: (_) => AlertDialog(
                          title: const Text('How to use AI Assistant'),
                          content: SingleChildScrollView(
                            child: Text(
                              '1. Type or speak your symptoms or health question\n\n'
                              '2. Press Enter key or tap "Get guidance" for analysis\n\n'
                              '3. The AI responds in your selected language: $_selectedLanguage\n\n'
                              '4. Supported languages:\n'
                              '   English, Tamil, Hindi, Telugu, Kannada,\n'
                              '   Malayalam, Marathi, Urdu, French, Japanese\n\n'
                              '5. Tap the mic button to speak in your language\n\n'
                              '6. The response is read aloud in your language\n\n'
                              '7. Change language from the app settings to\n'
                              '   get responses in a different language\n\n'
                              'Supported topics: fever, cold, injuries, allergies,\n'
                              'diabetes, blood pressure, mental health, and more.',
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(localCtx), child: const Text('Got it')),],
                        ),
                      );
                    },
                    icon: const Icon(Icons.help_outline_rounded, size: 16),
                    label: const Text('How to use', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _getLocaleId(String lang) {
    switch (lang) {
      case 'Tamil':
        return 'ta_IN';
      case 'Hindi':
        return 'hi_IN';
      case 'Telugu':
        return 'te_IN';
      case 'Kannada':
        return 'kn_IN';
      case 'Malayalam':
        return 'ml_IN';
      case 'Japanese':
        return 'ja_JP';
      case 'Marathi':
        return 'mr_IN';
      case 'Urdu':
        return 'ur_PK';
      case 'French':
        return 'fr_FR';
      default:
        return 'en_US';
    }
  }

  Future<String> _generateAiGuidance(String symptoms) async {
    // Determine target language for response
    final targetLang = _selectedLanguage;
    final langCode = TranslationService.getLanguageCode(targetLang);

    // Gemini API (key bundled in app, not visible to users)
    const geminiApiKey = 'AIzaSyDummyReplaceMe'; // Replace with real key
    try {
      if (geminiApiKey.isNotEmpty && !geminiApiKey.startsWith('AIzaSyDummy')) {
        final response = await http.post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$geminiApiKey'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [{
              'parts': [{
                'text': 'You are Medly, a smart healthcare assistant. The user describes: "$symptoms". IMPORTANT: Respond entirely in ${_selectedLanguage} language (language code: $langCode). Provide helpful health guidance including: 1) What this could indicate, 2) Urgency level (low/moderate/high/emergency), 3) First aid steps if applicable, 4) When to see a doctor. Be concise but thorough. Include disclaimer that this is not a substitute for professional medical advice. Use simple, clear ${_selectedLanguage} that anyone can understand.'
              }]
            }],
            'generationConfig': {
              'temperature': 0.7,
              'maxOutputTokens': 500,
            }
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
          if (text != null && text.isNotEmpty) return text;
        }
      }
    } catch (_) {}

    // Fallback to enhanced local knowledge — translate to user's language
    String guidance = _getLocalGuidance(symptoms);
    if (targetLang != 'English') {
      guidance = await TranslationService.translate(
        text: guidance,
        targetLanguage: targetLang,
      );
    }
    return guidance;
  }

  /// Local knowledge base fallback (English)
  String _getLocalGuidance(String symptoms) {
    final lowered = symptoms.toLowerCase();

    if (lowered.contains('chest pain') || lowered.contains('difficulty breathing') || lowered.contains('severe bleeding') || lowered.contains('faint') || lowered.contains('unconscious') || lowered.contains('heart attack')) {
      return '🚨 EMERGENCY: This may be a life-threatening condition.\n\n1. Call emergency services (108/112) IMMEDIATELY\n2. If chest pain: Have the person sit upright, loosen tight clothing\n3. If breathing difficulty: Help them sit upright, stay calm\n4. If bleeding: Apply firm pressure with clean cloth\n5. If unconscious: Check breathing, begin CPR if needed\n6. Do NOT give food or water to someone with chest pain\n\n⚠️ This is AI guidance only. Seek immediate professional medical help.';
    }

    if (lowered.contains('fever') && (lowered.contains('high') || lowered.contains('103') || lowered.contains('104') || lowered.contains('severe'))) {
      return '🟡 HIGH FEVER - Urgent attention needed:\n\n1. Take paracetamol (500mg) as per dosage\n2. Apply cold compress on forehead\n3. Drink plenty of fluids - water, ORS, coconut water\n4. Wear light cotton clothing\n5. Rest in a cool, ventilated room\n6. If fever exceeds 103°F or lasts more than 2 days, see a doctor\n7. Watch for: stiff neck, rash, confusion, difficulty breathing\n\n⚠️ High fever in children under 5 or elderly requires immediate medical attention.';
    }

    if (lowered.contains('fever') || lowered.contains('cold') || lowered.contains('cough') || lowered.contains('flu') || lowered.contains('sore throat')) {
      return '🟢 Likely Common Cold/Flu:\n\n1. Rest well - your body needs energy to fight infection\n2. Stay hydrated - warm water, herbal tea, soups\n3. For cough: Honey with warm water, steam inhalation\n4. For sore throat: Salt water gargle (1/2 tsp salt in warm water)\n5. Take paracetamol for fever/headache\n6. Monitor temperature every 4-6 hours\n7. Eat light, nutritious food\n\n⚠️ See a doctor if: fever >101°F for 3+ days, breathing difficulty, chest pain, or symptoms worsen after initial improvement.';
    }

    if (lowered.contains('headache') || lowered.contains('migraine') || lowered.contains('dizziness')) {
      return '🟢 Likely Headache/Migraine:\n\n1. Rest in a dark, quiet room\n2. Apply cold compress on forehead or warm compress on neck\n3. Stay hydrated - drink water regularly\n4. Avoid screens and bright lights\n5. For migraine: Try pressing temples gently in circular motion\n6. Take paracetamol if needed\n\n⚠️ SEEK URGENT CARE if: Sudden severe "worst headache of life", headache with fever + stiff neck, headache after head injury, vision changes, or weakness on one side.';
    }

    if (lowered.contains('stomach') || lowered.contains('abdomen') || lowered.contains('belly') || lowered.contains('vomit') || lowered.contains('diarrhea') || lowered.contains('nausea')) {
      return '🟢 Likely Stomach/GI Issue:\n\n1. Drink ORS or electrolyte solution to prevent dehydration\n2. Eat small, bland meals - rice, bananas, toast (BRAT diet)\n3. Avoid spicy, fatty, or dairy foods\n4. Sip warm water or ginger tea for nausea\n5. Rest your stomach - avoid eating if vomiting\n6. Reintroduce food gradually once vomiting stops\n\n⚠️ See a doctor if: Blood in vomit/stool, severe abdominal pain, signs of dehydration (dark urine, dizziness), fever >101°F, symptoms last >48 hours.';
    }

    if (lowered.contains('allergic') || lowered.contains('allergy') || lowered.contains('rash') || lowered.contains('swelling') || lowered.contains('hives') || lowered.contains('itch')) {
      return '🟡 Possible Allergic Reaction:\n\n1. Remove the suspected trigger if identifiable\n2. For mild rash/itching: Apply calamine lotion or antihistamine cream\n3. Take an antihistamine (cetirizine 10mg or loratadine 10mg)\n4. Apply cold compress to affected area\n5. Avoid scratching to prevent infection\n\n🚨 SEEK EMERGENCY CARE IMMEDIATELY if: Swelling of face/lips/throat, difficulty breathing, dizziness, rapid heartbeat. This could be anaphylaxis and requires immediate treatment.';
    }

    if (lowered.contains('diabetes') || lowered.contains('sugar') || lowered.contains('insulin') || lowered.contains('hypoglycemia') || lowered.contains('hypoglycemic')) {
      return '🟡 Diabetes Management Guidance:\n\nFor LOW blood sugar (<70 mg/dL):\n1. Take 15g fast-acting carbs (3-4 glucose tablets, or 1 tbsp sugar in water, or half cup fruit juice)\n2. Wait 15 minutes, recheck\n3. Repeat if still low\n4. Once stable, eat a balanced snack\n\nFor HIGH blood sugar (>250 mg/dL):\n1. Drink plenty of water\n2. Take prescribed medication as directed\n3. Light walking may help\n4. Monitor every 1-2 hours\n\n⚠️ If blood sugar >300 mg/dL or symptoms of DKA (nausea, fruity breath, rapid breathing), seek emergency care.';
    }

    if (lowered.contains('blood pressure') || lowered.contains('bp') || lowered.contains('hypertension') || lowered.contains('hypotension')) {
      return '🟡 Blood Pressure Guidance:\n\nHIGH BP (>140/90):\n1. Sit quietly for 5 minutes, then re-measure\n2. Reduce salt intake immediately\n3. Avoid caffeine and alcohol\n4. Practice deep breathing\n5. If >180/120, this is a hypertensive crisis - seek emergency care\n\nLOW BP (<90/60):\n1. Stand up slowly\n2. Drink plenty of fluids\n3. Increase salt intake slightly\n4. Wear compression stockings\n5. Eat small, frequent meals\n\n⚠️ Regular monitoring is essential. Consult your doctor for medication adjustments.';
    }

    if (lowered.contains('sleep') || lowered.contains('insomnia') || lowered.contains('sleeping') || lowered.contains('tired') || lowered.contains('fatigue') || lowered.contains('exhaustion')) {
      return '🟢 Sleep/Fatigue Guidance:\n\n1. Maintain a consistent sleep schedule (same time daily)\n2. Avoid screens 1 hour before bed\n3. Keep bedroom cool, dark, and quiet\n4. Avoid caffeine after 2 PM\n5. Try warm milk or chamomile tea before bed\n6. Exercise regularly (but not close to bedtime)\n7. Practice relaxation: deep breathing, meditation\n\nFor daytime fatigue: Take a 20-min power nap (not longer), stay hydrated, get sunlight exposure in the morning.\n\n⚠️ If fatigue persists >2 weeks despite good sleep hygiene, consult a doctor for possible thyroid, anemia, or other causes.';
    }

    if (lowered.contains('injury') || lowered.contains('wound') || lowered.contains('cut') || lowered.contains('bruise') || lowered.contains('sprain') || lowered.contains('swollen')) {
      return '🟢 First Aid for Injuries:\n\nFor Cuts/Wounds:\n1. Wash hands before treating\n2. Rinse wound under clean running water\n3. Apply gentle pressure with clean cloth to stop bleeding\n4. Apply antibiotic ointment if available\n5. Cover with sterile bandage\n\nFor Sprains (RICE method):\n1. Rest - avoid using the injured area\n2. Ice - apply for 15-20 min every 2 hours\n3. Compression - wrap with elastic bandage\n4. Elevation - keep above heart level\n\n⚠️ Seek care if: Deep wound, cannot bear weight, visible bone/deformity, signs of infection (redness, warmth, pus), or bleeding does not stop after 15 min.';
    }

    if (lowered.contains('medicine') || lowered.contains('medication') || lowered.contains('drug') || lowered.contains('dosage') || lowered.contains('side effect')) {
      return '💊 Medication Guidance:\n\n1. ALWAYS take medicines as prescribed by your doctor\n2. Never skip doses without consulting your doctor\n3. Take medicines at the same time each day for consistency\n4. Read the label for dosage instructions\n5. Store medicines in a cool, dry place\n6. Check expiry dates regularly\n\nCommon Side Effects to Watch:\n- Stomach upset: Take with food\n- Drowsiness: Avoid driving\n- Dizziness: Stand up slowly\n\n🚨 Emergency: If you accidentally overdose, call poison control immediately. Bring the medicine container to the hospital.\n\n⚠️ Never share prescription medicines. Always consult your doctor before starting or stopping any medication.';
    }

    if (lowered.contains('2+2') || lowered.contains('what is') || lowered.contains('hello') || lowered.contains('hi ') || lowered.contains('who are you') || lowered.contains('tell me about')) {
      return "You can ask me about any health topic:\n\n- Symptom assessment & first aid\n- Medication guidance\n- Diabetes, BP, asthma management\n- Injury & wound care\n- Sleep, nutrition, exercise advice\n- Mental health support\n\nJust describe what you need help with.";
    }

    if (lowered.contains('asthma') || lowered.contains('breathing') || lowered.contains('wheez') || lowered.contains('bronchitis')) {
      return '🫁 Respiratory/Asthma Guidance:\n\n1. Sit upright - do not lie down\n2. Use your prescribed inhaler (blue reliever) as directed\n3. Take slow, deep breaths through pursed lips\n4. Remove yourself from triggers (dust, smoke, cold air)\n5. Stay calm - anxiety can worsen breathing difficulty\n6. Keep rescue medication accessible at all times\n\nFor Asthma Attack:\n- Use reliever inhaler (2-6 puffs)\n- Sit upright and breathe slowly\n- If no improvement in 10 min, call emergency services\n\n⚠️ Seek emergency care if: Lips turning blue, cannot speak in full sentences, reliever not helping, peak flow below 50% of normal.';
    }

    if (lowered.contains('heart') || lowered.contains('palpitation') || lowered.contains('heartbeat') || lowered.contains('arrhythmia')) {
      return '❤️ Heart Health Guidance:\n\nFor Palpitations/Skipped Beats:\n1. Sit down and rest\n2. Take slow deep breaths\n3. Splash cold water on face\n4. Avoid caffeine, alcohol, nicotine\n5. Stay hydrated\n6. Monitor pulse for 1-2 minutes\n\nFor Chest Discomfort:\n1. Stop all activity immediately\n2. Sit or lie in comfortable position\n3. Chew aspirin (325mg) if not allergic\n4. Call emergency services if pain persists >5 min\n\n🚨 EMERGENCY: Call 108/112 if you experience crushing chest pain, pain spreading to arm/jaw, sudden shortness of breath, or loss of consciousness.';
    }

    if (lowered.contains('eye') || lowered.contains('vision') || lowered.contains('blur') || lowered.contains('red eye') || lowered.contains('eye pain')) {
      return '👁️ Eye Health Guidance:\n\nFor Red/Watery Eyes:\n1. Wash hands before touching face\n2. Rinse eyes with clean water or saline\n3. Avoid rubbing eyes\n4. Use artificial tears for dryness\n5. Apply cold compress for swelling\n6. Rest eyes from screens (20-20-20 rule: every 20 min, look at something 20 feet away for 20 sec)\n\nFor Sudden Vision Loss:\n🚨 EMERGENCY - Seek immediate medical care\n\n⚠️ See an eye doctor if: Persistent redness, pain, discharge, light sensitivity, or vision changes lasting >24 hours.';
    }

    if (lowered.contains('skin') || lowered.contains('acne') || lowered.contains('eczema') || lowered.contains('psoriasis') || lowered.contains('dry skin') || lowered.contains('oily')) {
      return '🧴 Skin Care Guidance:\n\nFor General Skin Issues:\n1. Cleanse gently with mild, fragrance-free cleanser\n2. Moisturize daily (apply on damp skin)\n3. Use sunscreen SPF 30+ daily\n4. Avoid hot water showers - use lukewarm\n5. Wear breathable cotton fabrics\n6. Stay hydrated and eat omega-3 rich foods\n\nFor Acne:\n- Wash face 2x daily with salicylic acid cleanser\n- Do not pop pimples\n- Use non-comedogenic moisturizer\n- Benzoyl peroxide 2.5% for spot treatment\n\n⚠️ See a dermatologist for persistent or severe skin conditions.';
    }

    if (lowered.contains('bone') || lowered.contains('fracture') || lowered.contains('back pain') || lowered.contains('neck pain') || lowered.contains('joint') || lowered.contains('arthritis')) {
      return '🦴 Bone & Joint Guidance:\n\nFor Back/Neck Pain:\n1. Apply ice pack for first 48 hours, then warm compress\n2. Rest but avoid prolonged bed rest\n3. Take paracetamol or ibuprofen for pain\n4. Maintain good posture\n5. Gentle stretching when pain allows\n6. Sleep on your side with pillow between knees\n\nFor Suspected Fracture:\n1. Immobilize the area - do not move\n2. Apply ice wrapped in cloth\n3. Elevate if possible\n4. Seek immediate medical care\n\n⚠️ See a doctor for: Pain lasting >1 week, numbness/tingling, loss of movement, visible deformity.';
    }

    if (lowered.contains('pregnant') || lowered.contains('pregnancy') || lowered.contains('morning sickness') || lowered.contains('baby')) {
      return '🤰 Pregnancy Guidance:\n\nFor Morning Sickness:\n1. Eat small, frequent meals (every 2-3 hours)\n2. Keep crackers by bedside - eat before getting up\n3. Avoid strong smells and spicy foods\n4. Ginger tea or ginger candies help\n5. Stay hydrated - sip water throughout the day\n6. Get plenty of rest\n\nGeneral Pregnancy Wellness:\n- Take prenatal vitamins (folic acid, iron, calcium)\n- Stay active with gentle walking\n- Attend regular prenatal checkups\n- Avoid alcohol, smoking, raw/undercooked foods\n\n🚨 Seek immediate care for: Severe headache, vision changes, heavy bleeding, severe abdominal pain, fever >101°F, reduced fetal movement.';
    }

    if (lowered.contains('mental health') || lowered.contains('anxiety') || lowered.contains('depression') || lowered.contains('stress') || lowered.contains('panic') || lowered.contains('sad') || lowered.contains('worry')) {
      return '🧠 Mental Health Guidance:\n\nFor Anxiety/Stress:\n1. Practice 4-7-8 breathing: inhale 4 sec, hold 7, exhale 8\n2. Ground yourself: name 5 things you see, 4 you hear, 3 you touch\n3. Limit caffeine and screen time\n4. Take a walk in nature\n5. Talk to someone you trust\n6. Journal your thoughts\n7. Progressive muscle relaxation\n\nFor Panic Attack:\n1. Remind yourself: this will pass\n2. Focus on slow, deep breathing\n3. Hold an ice cube or splash cold water\n4. Name objects around you\n5. Do not fight the feelings - let them flow\n\n⚠️ If you are having thoughts of self-harm, please reach out:\n- iCall: 9152987821\n- Vandrevala Foundation: 1860-2662-345\n- Crisis Helpline: 999 (UK) or 988 (US)\nYou are not alone. Professional help is available.';
    }

    if (lowered.contains('nutrition') || lowered.contains('diet') || lowered.contains('food') || lowered.contains('weight loss') || lowered.contains('obesity') || lowered.contains('vitamin')) {
      return '🥗 Nutrition Guidance:\n\nBalanced Diet Basics:\n- Half plate: vegetables and fruits\n- Quarter plate: whole grains (rice, roti, oats)\n- Quarter plate: protein (dal, fish, chicken, eggs, paneer)\n- Add healthy fats (nuts, seeds, olive oil)\n\nHealthy Eating Tips:\n1. Eat 5 servings of fruits/vegetables daily\n2. Choose whole grains over refined\n3. Limit sugar to <25g/day\n4. Limit salt to <5g/day\n5. Drink 8-10 glasses of water\n6. Eat slowly and mindfully\n7. Do not skip breakfast\n\nFor Weight Management:\n- Focus on sustainable changes, not crash diets\n- Aim for 0.5-1kg loss per week\n- Combine diet changes with regular exercise\n\n⚠️ Consult a dietitian for personalized nutrition plans.';
    }

    if (lowered.contains('exercise') || lowered.contains('workout') || lowered.contains('fitness') || lowered.contains('walking') || lowered.contains('yoga')) {
      return '🏃 Exercise & Fitness Guidance:\n\nDaily Exercise Goals (WHO Recommendations):\n- Adults: 150 min moderate activity per week\n- Children: 60 min daily\n- Include strength training 2x per week\n\nSafe Exercise Tips:\n1. Always warm up 5-10 minutes before exercise\n2. Start slowly and gradually increase intensity\n3. Stay hydrated before, during, and after\n4. Stop if you feel pain, dizziness, or chest discomfort\n5. Cool down and stretch after exercise\n6. Rest days are important for recovery\n\nBest Exercises by Condition:\n- Heart disease: Walking, gentle cycling\n- Diabetes: Walking after meals\n- Asthma: Swimming, yoga\n- Back pain: Swimming, core exercises\n\n⚠️ Consult your doctor before starting a new exercise program, especially with chronic conditions.';
    }

    if (lowered.contains('covid') || lowered.contains('corona') || lowered.contains('pandemic') || lowered.contains('quarantine') || lowered.contains('isolation')) {
      return '🦠 COVID-19 Guidance:\n\nIf You Test Positive:\n1. Isolate for at least 5 days from symptom onset\n2. Rest and stay hydrated\n3. Monitor temperature every 4-6 hours\n4. Take paracetamol for fever/body aches\n5. Use a pulse oximeter if available (normal: >95%)\n6. Continue isolation until fever-free for 24 hours\n\nWhen to Seek Emergency Care:\n- Oxygen saturation below 94\n- Persistent chest pain or pressure\n- Difficulty breathing at rest\n- Confusion or inability to stay awake\n- Bluish lips or face\n\nPrevention:\n- Stay up to date with vaccinations\n- Wear masks in crowded indoor spaces\n- Wash hands frequently\n- Maintain good ventilation\n\n⚠️ Long COVID symptoms (fatigue, brain fog, breathlessness) may persist - consult your doctor if they continue.';
    }

    if (lowered.contains('dental') || lowered.contains('tooth') || lowered.contains('teeth') || lowered.contains('gum') || lowered.contains('toothache')) {
      return '🦷 Dental Health Guidance:\n\nFor Toothache:\n1. Rinse mouth with warm salt water\n2. Floss gently to remove trapped food\n3. Take ibuprofen for pain (if not contraindicated)\n4. Apply clove oil to the affected area\n5. Use cold compress on cheek outside\n6. Avoid very hot or cold foods\n\nDental Hygiene:\n- Brush 2x daily for 2 minutes\n- Floss once daily\n- Use fluoride toothpaste\n- Replace toothbrush every 3 months\n- Visit dentist every 6 months\n\n⚠️ See a dentist immediately if: Severe swelling, fever with toothache, pus discharge, difficulty swallowing, or broken tooth.';
    }

    if (lowered.contains('urin') || lowered.contains('kidney') || lowered.contains('bladder') || lowered.contains('uti') || lowered.contains('burning')) {
      return '💧 Urinary Health Guidance:\n\nFor UTI Symptoms (burning, frequency, urgency):\n1. Drink plenty of water (2-3 liters/day)\n2. Do not hold urine - go when needed\n3. Urinate after sexual activity\n4. Wipe front to back\n5. Avoid irritants (caffeine, alcohol, spicy food)\n6. Cranberry juice may help\n\nFor Kidney Stone Pain:\n1. Drink water frequently\n2. Take prescribed pain medication\n3. Strain urine to catch the stone\n4. Apply heat to affected area\n\n⚠️ Seek medical care if: Fever with UTI symptoms, blood in urine, severe flank pain, inability to urinate, or persistent symptoms >48 hours. UTIs require antibiotics.';
    }

    return '📋 Health Guidance:\n\nI understand you are asking about: "${symptoms.substring(0, math.min(50, symptoms.length))}"\n\nHere is what I can suggest:\n1. Monitor your symptoms closely\n2. Stay hydrated - drink 8-10 glasses of water daily\n3. Get adequate rest (7-8 hours of sleep)\n4. Eat balanced, nutritious meals\n5. Avoid self-medication - consult a doctor for proper diagnosis\n\n⚠️ If symptoms are severe, persistent (>3 days), or worsening, please visit a healthcare professional.\n\nFor emergencies, call 108 (India) or your local emergency number.\n\nYou can describe more specific symptoms for detailed guidance.';
  }

  // ------- Health data collection -------
  Future<void> _showHealthDataDialog() async {
    final bpController = TextEditingController();
    final bsController = TextEditingController();
    final hrController = TextEditingController();
    final slController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Today\'s health snapshot')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: bpController, decoration: InputDecoration(labelText: '${_t('Blood Pressure')} (e.g. 120/80)')),
            const SizedBox(height: 8),
            TextField(controller: bsController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${_t('Blood Sugar')} (mg/dL)')),
            const SizedBox(height: 8),
            TextField(controller: hrController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${_t('Heart Rate')} (bpm)')),
            const SizedBox(height: 8),
            TextField(controller: slController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: '${_t('Sleep')} (hrs)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, {
              'bp': bpController.text.trim(),
              'bs': bsController.text.trim(),
              'hr': hrController.text.trim(),
              'sl': slController.text.trim(),
            }),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        if (result['bp']!.isNotEmpty) _healthMetrics[0] = HealthMetric(label: 'Blood Pressure', value: result['bp']!, unit: 'mmHg', color: Colors.blue);
        if (result['bs']!.isNotEmpty) _healthMetrics[1] = HealthMetric(label: 'Blood Sugar', value: result['bs']!, unit: 'mg/dL', color: Colors.teal);
        if (result['hr']!.isNotEmpty) _healthMetrics[2] = HealthMetric(label: 'Heart Rate', value: result['hr']!, unit: 'bpm', color: Colors.orange);
        if (result['sl']!.isNotEmpty) _healthMetrics[3] = HealthMetric(label: 'Sleep', value: result['sl']!, unit: 'hrs', color: Colors.purple);
      });

      // Store in Firestore
      try {
        if (_firestoreService.isAvailable) {
          await _firestoreService.db.collection('daily_health').add({
            'patientName': _selectedPatientName,
            'date': _todayDateKey,
            'bloodPressure': result['bp'],
            'bloodSugar': result['bs'],
            'heartRate': result['hr'],
            'sleep': result['sl'],
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {}

      // Save to SQLite database
      await DatabaseService.saveHealthSnapshot(
        patientName: _selectedPatientName,
        dateKey: _todayDateKey,
        bloodPressure: result['bp'],
        bloodSugar: result['bs'],
        heartRate: result['hr'],
        sleepHours: result['sl'],
        steps: _todaySteps,
      );
      // Sync to Supabase
      SupabaseService.syncHealthSnapshot(
        patientName: _selectedPatientName,
        dateKey: _todayDateKey,
        bloodPressure: result['bp'],
        bloodSugar: result['bs'],
        heartRate: result['hr'],
        sleepHours: result['sl'],
        steps: _todaySteps,
      );

      // Also save locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('health_$_todayDateKey', jsonEncode(result));
    }
  }

  // ------- Medicine reminder -------
  Future<void> _submitMedicineReminder() async {
    final name = _medicineNameController.text.trim();
    final time = _medicineTimeController.text.trim();
    if (name.isEmpty || time.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('Enter medicine and time'))),
      );
      return;
    }
    setState(() {
      _medicineReminders.add(MedicineReminder(name: name, time: time, taken: false));
    });
    await _saveMedicineReminders();
    // Save to SQLite database
    await DatabaseService.saveMedicineReminder(email: widget.email, name: name, time: time);
    // Sync to Supabase
    SupabaseService.syncMedicineReminder(email: widget.email, name: name, time: time);
    // Schedule notification
    final notifId = NotificationService.generateId(name, time);
    await NotificationService.scheduleMedicineReminder(
      id: notifId,
      medicineName: name,
      timeString: time,
    );
    _medicineNameController.clear();
    _medicineTimeController.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('Reminder saved'))),
      );
    }
  }

  Future<void> _removeMedicineReminder(MedicineReminder item) async {
    // Cancel the notification
    final notifId = NotificationService.generateId(item.name, item.time);
    await NotificationService.cancelReminder(notifId);
    setState(() => _medicineReminders.remove(item));
    await _saveMedicineReminders();
  }

  // ------- Pages -------
  Widget _buildOverviewPage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emergency status banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1F2937), const Color(0xFF111827)]
                    : [const Color(0xFFF8E5E8), const Color(0xFFF4DDE1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.favorite_rounded, color: Colors.red),
                    ),
                    const SizedBox(width: 10),
                    Text(_t('Emergency status'), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 18),
                Text(_t('Stable'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  _t('Vitals are within range. Keep your emergency contact and record ready.'),
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _triggerEmergencySos,
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: Text(_t('Emergency SOS')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Quick info pills
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _infoPill(_t('Blood group'), widget.bloodGroup ?? _t('Not set')),
              _infoPill(_t('Allergies'), (widget.allergies?.isNotEmpty ?? false) ? widget.allergies! : _t('None')),
              _infoPill(_t('Diseases'), (widget.diseases?.isNotEmpty ?? false) ? widget.diseases! : _t('None')),
              _infoPill(_t('Weight'), (widget.weight?.isNotEmpty ?? false) ? '${widget.weight} kg' : _t('Not set')),
              _infoPill(_t('Height'), (widget.height?.isNotEmpty ?? false) ? '${widget.height} cm' : _t('Not set')),
              _buildBmiPill(),
            ],
          ),
          const SizedBox(height: 20),

          // Step Counter Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF0D9488), const Color(0xFF0F766E)]
                    : [const Color(0xFFCCFBF1), const Color(0xFF99F6E4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.directions_walk_rounded, color: Colors.teal, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_t('Today\'s steps'), style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.teal.shade900,
                      )),
                      const SizedBox(height: 4),
                      Text(
                        '$_todaySteps',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.teal.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: (_todaySteps / 10000).clamp(0.0, 1.0),
                        backgroundColor: Colors.teal.withValues(alpha: 0.2),
                        color: _todaySteps >= 10000 ? Colors.green : Colors.teal,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _todaySteps >= 10000
                            ? _t('Goal reached! 🎉')
                            : '${10000 - _todaySteps} ${_t('steps to goal')}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white70 : Colors.teal.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                // Calories estimate (rough: 1 step ≈ 0.04 kcal)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: isDark ? 0.2 : 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.local_fire_department_rounded, color: Colors.orange.shade700, size: 18),
                      const SizedBox(height: 2),
                      Text(
                        '${(_todaySteps * 0.04).toInt()}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                      ),
                      Text('kcal', style: TextStyle(fontSize: 9, color: isDark ? Colors.white60 : Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Health snapshot
          Row(
            children: [
              Flexible(
                child: Text(_t('Today\'s health snapshot'), style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _showHealthDataDialog,
                icon: const Icon(Icons.edit, size: 14),
                label: Text(_t('Enter data'), style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: _healthMetrics.map((metric) {
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: metric.color.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.monitor_heart_rounded, color: metric.color, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_t(metric.label), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${metric.value} ${_t(metric.unit)}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Nearby care - Map-based
          Text(_t('Nearby Healthcare'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Find hospitals, pharmacies & clinics near you using your live location',
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ClinicMapPage(
                      language: _selectedLanguage,
                      initialServices: _serviceList,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.map_rounded, size: 20),
              label: const Text('Open Live Map — Find Hospitals & Pharmacies', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 20),

          // Screen time
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2937) : Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t('Screen time today'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text('${(_screenTimeMinutesToday / 60).toStringAsFixed(1)} ${_t('hours')}'),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: (_screenTimeMinutesToday / 480).clamp(0.0, 1.0),
                  backgroundColor: Colors.grey.shade200,
                  color: _screenTimeMinutesToday > 240 ? Colors.red : Colors.teal,
                ),
                if (_screenTimeMinutesToday > 240)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _t('Consider taking a screen break.'),
                      style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF2D1B1B)
                : const Color(0xFFE8EEF5),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.emergency, size: 70, color: Colors.red.shade700),
                  const SizedBox(height: 12),
                  Text(_t('Smart SOS'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    _t('Share your live location, blood group, allergies, and emergency contacts in one tap.'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _triggerEmergencySos,
                    icon: const Icon(Icons.phone_rounded),
                    label: Text(_t('Call Emergency Contact')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _triggerEmergencyBroadcast,
                      icon: const Icon(Icons.broadcast_on_personal_rounded),
                      label: const Text('Broadcast SMS to All'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepOrange,
                        side: const BorderSide(color: Colors.deepOrange),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Emergency contact section
          Text(_t('Emergency contact'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          EmergencyContactCard(
            language: _selectedLanguage,
            onContactSaved: () => setState(() {}),
          ),
          const SizedBox(height: 18),

          // Emergency profile
          Text(_t('Emergency profile'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.bloodtype_rounded),
            title: Text(_t('Blood group')),
            subtitle: Text(widget.bloodGroup ?? 'Not provided'),
          ),
          ListTile(
            leading: const Icon(Icons.medical_services_rounded),
            title: Text(_t('Allergies')),
            subtitle: Text(
              (widget.allergies?.isNotEmpty ?? false) ? widget.allergies! : 'No known allergies',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.sick_rounded),
            title: Text(_t('Diseases')),
            subtitle: Text(
              (widget.diseases?.isNotEmpty ?? false) ? widget.diseases! : 'No known diseases',
            ),
          ),
          const SizedBox(height: 18),

          // SOS Call Log
          Text(_t('SOS call log'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: DatabaseService.getSosLog(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final logs = snapshot.data!;
              if (logs.isEmpty) return const Text('No SOS calls recorded yet.');
              return Column(
                children: logs.take(5).map((log) => Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.phone_rounded, color: Colors.red, size: 20),
                    title: Text(log['contact_name'] ?? 'Emergency', style: const TextStyle(fontSize: 13)),
                    subtitle: Text('${log['contact_phone'] ?? ''} \u2022 ${log['timestamp']?.toString().substring(0, 16) ?? ''}', style: const TextStyle(fontSize: 11)),
                  ),
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHealthPage() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(_t('Medicine reminder'), style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),

        // Clock widget for medicine times
        if (_medicineReminders.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F2937) : Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: MedicineClockWidget(reminders: _medicineReminders),
          ),
        const SizedBox(height: 16),

        // Add reminder form
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _medicineNameController,
                  decoration: InputDecoration(
                    labelText: _t('Medicine name'),
                    prefixIcon: const Icon(Icons.medication_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _medicineTimeController,
                  keyboardType: TextInputType.datetime,
                  decoration: InputDecoration(
                    labelText: _t('Time'),
                    hintText: '08:00 AM',
                    prefixIcon: const Icon(Icons.schedule_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitMedicineReminder,
                    icon: const Icon(Icons.add_task_rounded),
                    label: Text(_t('Submit reminder')),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Reminder list
        ..._medicineReminders.map(
          (item) => CheckboxListTile(
            value: item.taken,
            onChanged: (v) async {
              final taken = v ?? false;
              setState(() => item.taken = taken);
              if (taken) {
                // Cancel notification when marked as taken
                final notifId = NotificationService.generateId(item.name, item.time);
                await NotificationService.cancelReminder(notifId);
              } else {
                // Re-schedule when unmarked
                final notifId = NotificationService.generateId(item.name, item.time);
                await NotificationService.scheduleMedicineReminder(
                  id: notifId,
                  medicineName: item.name,
                  timeString: item.time,
                );
              }
              await _saveMedicineReminders();
            },
            title: Text(item.name),
            subtitle: Text(item.time),
            controlAffinity: ListTileControlAffinity.trailing,
            secondary: IconButton(
              tooltip: _t('Delete reminder'),
              onPressed: () => _removeMedicineReminder(item),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Connect Smartwatch button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final connected = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const BluetoothScanPage()),
              );
              if (connected == true && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Smartwatch connected! Heart rate will stream automatically.'),
                    backgroundColor: Colors.green,
                  ),
                );
                // Start listening to heart rate from watch
                _startBluetoothHR();
              }
            },
            icon: const Icon(Icons.watch_rounded, size: 18),
            label: const Text('Connect Smartwatch', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF6C63FF),
              side: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Nearby care - Map button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ClinicMapPage(
                    language: _selectedLanguage,
                    initialServices: _serviceList,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map_rounded, size: 18),
            label: const Text('Find Hospitals & Pharmacies Near You', style: TextStyle(fontSize: 13)),
          ),
        ),

        const SizedBox(height: 24),

        // Daily Exercises
        Text(_t('Daily Exercises'), style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(_t('Based on your conditions'), style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        const SizedBox(height: 12),
        _buildExerciseSection(),
        const SizedBox(height: 16),
        _buildStreakSection(),
        const SizedBox(height: 16),
        _buildBadgeCollection(),
      ],
    );
  }

  Widget _buildStreakSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<Map<String, dynamic>?>(
      future: DatabaseService.getStreak(widget.email),
      builder: (ctx, snap) {
        final streak = snap.data;
        final current = streak?['current_streak'] ?? 0;
        final longest = streak?['longest_streak'] ?? 0;
        final badges = streak?['total_badges'] ?? 0;
        final badge = ExerciseService.getBadgeForWeek(current);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF7C3AED), const Color(0xFF5B21B6)]
                  : [const Color(0xFFEDE9FE), const Color(0xFFDDD6FE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Text(badge['emoji'] ?? '⭐', style: const TextStyle(fontSize: 40)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_t('Exercise Streak'), style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.purple.shade900)),
                    const SizedBox(height: 4),
                    Text(
                      '$current ${_t('day streak')} • $longest ${_t('best')}',
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.purple.shade700, fontSize: 13),
                    ),
                    Text(
                      '$badges ${_t('badges earned')} • ${badge['name']}',
                      style: TextStyle(color: isDark ? Colors.white60 : Colors.purple.shade600, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: isDark ? 0.3 : 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$current🔥',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.purple.shade900),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBadgeCollection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<Map<String, dynamic>?>(
      future: DatabaseService.getStreak(widget.email),
      builder: (ctx, snap) {
        final badges = (snap.data?['total_badges'] ?? 0) as int;
        final weeks = badges.clamp(0, 364);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F2937) : Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('🏷️', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Text(_t('Badge Collection'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  Text('$weeks/364', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 12),
              if (weeks == 0)
                Text(_t('Complete exercises to earn badges!'), style: TextStyle(color: Colors.grey.shade500, fontSize: 13))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(weeks.clamp(0, 30), (i) {
                    final badge = ExerciseService.getBadgeForWeek(i + 1);
                    return Tooltip(
                      message: 'Week ${i + 1}: ${badge['name']}',
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: Text(badge['emoji'] ?? '⭐', style: const TextStyle(fontSize: 22))),
                      ),
                    );
                  }),
                ),
              if (weeks > 30)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '+${weeks - 30} more badges earned!',
                    style: TextStyle(color: Colors.purple.shade400, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExerciseSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final diseases = widget.diseases ?? '';
    final exercises = ExerciseService.getExercisesForDiseases(diseases);
    final todayKey = _todayDateKey;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseService.getExerciseCompletions(widget.email, todayKey),
      builder: (ctx, snap) {
        final completions = snap.data ?? [];
        final completedNames = completions.map((c) => c['exercise_name'] as String).toSet();

        // Check streak and send reminder if needed
        DatabaseService.getStreak(widget.email).then((streakData) {
          final currentStreak = (streakData?['current_streak'] as int?) ?? 0;
          NotificationService.checkAndNotifyStreak(
            email: widget.email,
            currentStreak: currentStreak,
            exercisesCompleted: completedNames.length,
            totalExercises: exercises.length,
          );
        });

        // Motivational streak header
        return FutureBuilder<Map<String, dynamic>?>(
          future: DatabaseService.getStreak(widget.email),
          builder: (ctx, streakSnap) {
            final streakData = streakSnap.data;
            final currentStreak = (streakData?['current_streak'] as int?) ?? 0;
            final completed = completedNames.length;
            final total = exercises.length;
            final allDone = completed >= total;

            String streakEmoji;
            String streakMessage;
            Color streakColor;
            if (allDone) {
              streakEmoji = '🎉';
              streakMessage = 'All exercises done today! Keep the streak alive tomorrow!';
              streakColor = Colors.green;
            } else if (currentStreak >= 30) {
              streakEmoji = '👑';
              streakMessage = "$currentStreak-day streak! Champions don't quit!";
              streakColor = Colors.amber.shade700;
            } else if (currentStreak >= 7) {
              streakEmoji = '🔥';
              streakMessage = "$currentStreak days strong! Don't break the chain!";
              streakColor = Colors.deepOrange;
            } else if (currentStreak >= 3) {
              streakEmoji = '💪';
              streakMessage = "$currentStreak days! Almost a week - keep pushing!";
              streakColor = Colors.orange;
            } else if (currentStreak >= 1) {
              streakEmoji = '⭐';
              streakMessage = '$currentStreak day streak started! Build the habit!';
              streakColor = Colors.blue;
            } else {
              streakEmoji = '🌟';
              streakMessage = '$completed/$total done today. Start your streak now!';
              streakColor = Colors.purple;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Motivational banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        streakColor.withOpacity(0.15),
                        streakColor.withOpacity(0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: streakColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Text(streakEmoji, style: const TextStyle(fontSize: 32)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Streak: $currentStreak day${currentStreak == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: streakColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              streakMessage,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Progress ring
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CircularProgressIndicator(
                              value: total > 0 ? completed / total : 0,
                              strokeWidth: 4,
                              backgroundColor: streakColor.withOpacity(0.15),
                              valueColor: AlwaysStoppedAnimation(streakColor),
                            ),
                            Center(
                              child: Text(
                                '$completed/$total',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: streakColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Exercise cards with checkboxes
                ...exercises.map((ex) {
                  final isDone = completedNames.contains(ex['name']);
                  final isSelected = _selectedExercises.contains(ex['name']);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: isDone
                        ? (isDark ? const Color(0xFF1A3A2A) : const Color(0xFFE8F5E9))
                        : (isSelected ? (isDark ? const Color(0xFF1A2A4A) : const Color(0xFFE8EAF6)) : null),
                    child: ListTile(
                      leading: Text(ex['icon'] ?? '🏃', style: const TextStyle(fontSize: 28)),
                      title: Text(
                        ex['name'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                          color: isDone ? Colors.green : null,
                        ),
                      ),
                      subtitle: Text('${ex['duration']} • ${ex['desc']}'),
                      trailing: isDone
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 28)
                          : Checkbox(
                              value: isSelected,
                              activeColor: const Color(0xFF6C63FF),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedExercises.add(ex['name']!);
                                  } else {
                                    _selectedExercises.remove(ex['name']!);
                                  }
                                });
                              },
                            ),
                    ),
                  );
                }),
                // Submit button
                const SizedBox(height: 12),
                if (!allDone && _selectedExercises.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        // Save only checked exercises
                        for (final ex in exercises) {
                          if (_selectedExercises.contains(ex['name']) && !completedNames.contains(ex['name'])) {
                            await DatabaseService.saveExerciseCompletion(
                              email: widget.email,
                              exerciseName: ex['name']!,
                              dateKey: todayKey,
                            );
                          }
                        }
                        await DatabaseService.updateStreak(
                          email: widget.email,
                          todayKey: todayKey,
                        );
                        final count = _selectedExercises.length;
                        _selectedExercises.clear();
                        setState(() {});
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_t('$count exercise(s) submitted! Streak updated 🔥')),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.done_all_rounded, color: Colors.white),
                      label: Text(
                        _t('Submit ${_selectedExercises.length} Exercise(s)'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 2,
                      ),
                    ),
                  ),
                if (!allDone && _selectedExercises.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _t('Check the exercises you completed, then tap Submit'),
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (allDone)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3A2A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('✅', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 8),
                        Text(
                          _t('All exercises completed for today!'),
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _openMapForService(HealthcareService service) async {
    final lat = service.latitude;
    final lon = service.longitude;
    if (lat != null && lon != null) {
      final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon');
      if (await canLaunchUrl(url)) {
        await launchUrl(url);
      }
    }
  }

  StreamSubscription<int>? _bleHRSubscription;
  void _startBluetoothHR() {
    final bleService = BluetoothHRService();
    _bleHRSubscription?.cancel();
    _bleHRSubscription = bleService.heartRateStream.listen((hr) {
      if (mounted && hr > 0) {
        setState(() {
          _healthMetrics[2] = HealthMetric(
            label: 'Heart Rate',
            value: '$hr',
            unit: 'bpm',
            color: Colors.orange,
          );
        });
        // Auto-save to health snapshot every reading
        DatabaseService.saveHealthSnapshot(
          patientName: _selectedPatientName,
          dateKey: _todayDateKey,
          bloodPressure: '',
          bloodSugar: '',
          heartRate: '$hr',
          sleepHours: '',
          steps: _todaySteps,
        );
      }
    });
  }

  Widget _infoPill(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildBmiPill() {
    final bmiData = HeartRateService.calculateBMI(
      widget.weight ?? '',
      widget.height ?? '',
    );
    final bmi = bmiData['bmi'] as double;
    final category = bmiData['category'] as String;
    final color = bmiData['color'] as Color;
    final advice = bmiData['advice'] as String;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Simple status label
    String statusEmoji;
    String statusText;
    if (bmi <= 0) {
      statusEmoji = '❓';
      statusText = 'No Data';
    } else if (bmi < 18.5) {
      statusEmoji = '🦴';
      statusText = 'Skinny';
    } else if (bmi < 25) {
      statusEmoji = '✅';
      statusText = 'Healthy';
    } else if (bmi < 30) {
      statusEmoji = '⚠️';
      statusText = 'Overweight';
    } else if (bmi < 35) {
      statusEmoji = '🔴';
      statusText = 'Obese';
    } else {
      statusEmoji = '🚨';
      statusText = 'Severely Obese';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(statusEmoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'BMI: ${bmi > 0 ? bmi.toStringAsFixed(1) : '--'}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
                ),
              ),
            ],
          ),
          if (bmi > 0) ...[
            const SizedBox(height: 8),
            // BMI gauge bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (bmi / 40).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$category — $advice',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black45, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pages = [
      _buildOverviewPage(),
      _buildEmergencyPage(),
      _buildHealthPage(),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1F2937) : const Color(0xFFE8D9DA),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Medly', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            Text(
              '${widget.caregiverRole} \u2022 ${_selectedPatientName.length > 12 ? _selectedPatientName.substring(0, 12) + '...' : _selectedPatientName}',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black54),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          // Language selector
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLanguage,
                  isDense: true,
                  dropdownColor: isDark ? const Color(0xFF1F2937) : Colors.white,
                  items: _languages
                      .map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 11))))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedLanguage = v);
                  },
                ),
              ),
            ),
          ),
          // Live Map button
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ClinicMapPage(
                    language: _selectedLanguage,
                    initialServices: _serviceList,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map_rounded),
            tooltip: 'Live Map',
          ),
          // Theme toggle
          IconButton(
            onPressed: () => widget.onThemeChanged(
              widget.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
            ),
            icon: Icon(widget.themeMode == ThemeMode.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
          ),
          // Profile menu with online/offline dot
          FutureBuilder<bool>(
            future: OfflineService.isOnline(),
            builder: (ctx, snap) {
              final online = snap.data ?? true;
              return PopupMenuButton<String>(
                icon: Stack(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: const Color(0xFF6C63FF).withOpacity(0.15),
                      backgroundImage: _profilePhotoPath != null ? FileImage(File(_profilePhotoPath!)) : null,
                      child: _profilePhotoPath == null
                          ? Text(
                              widget.patientName.isNotEmpty ? widget.patientName[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF6C63FF)),
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: online ? Colors.green : Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE8D9DA), width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
            onSelected: (value) {
              if (value == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CaregiverSettingsPage(
                      caregiverName: widget.caregiverName,
                      caregiverRole: widget.caregiverRole,
                      caregiverEmail: widget.email,
                      patients: _patientProfiles,
                      selectedPatientName: _selectedPatientName,
                      onPatientSelected: (name) => setState(() => _selectedPatientName = name),
                      onSignOut: widget.onSignOut,
                    ),
                  ),
                );
              } else if (value == 'blood_donation') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BloodDonationPage(language: _selectedLanguage)),
                );
              } else if (value == 'edit_profile') {
                _showEditProfileDialog();
              } else if (value == 'family_dashboard') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FamilyHealthDashboardPage(
                      caregiverEmail: widget.email,
                      caregiverName: widget.caregiverName,
                    ),
                  ),
                );
              } else if (value == 'live_map') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ClinicMapPage(
                      language: _selectedLanguage,
                      initialServices: _serviceList,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
              const PopupMenuItem(value: 'family_dashboard', child: Text('Family Dashboard')),
              const PopupMenuItem(value: 'live_map', child: Text('Live Map')),
              const PopupMenuItem(value: 'edit_profile', child: Text('Edit profile')),
              const PopupMenuItem(value: 'blood_donation', child: Text('Blood Donation')),
            ],
          );
            },
          ),
        ],
      ),
      body: pages[_selectedIndex],
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: FloatingActionButton(
          onPressed: _openAiSheet,
          backgroundColor: Colors.indigo,
          mini: true,
          tooltip: _t('AI Health Assistant'),
          child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 22),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.only(left: 10, right: 10, bottom: 6, top: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111827) : const Color(0xFFF5F0F1),
          border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12, width: 1)),
        ),
        child: NavigationBar(
          height: 72,
          elevation: 0,
          backgroundColor: Colors.transparent,
          indicatorColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) {
            if (i == 3) {
              // Map tab → open full-screen live map
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ClinicMapPage(
                    language: _selectedLanguage,
                    initialServices: _serviceList,
                  ),
                ),
              );
            } else {
              setState(() => _selectedIndex = i);
            }
          },
          destinations: [
            NavigationDestination(icon: const Icon(Icons.home_rounded), label: _t('Home')),
            NavigationDestination(icon: const Icon(Icons.sos_rounded), label: _t('SOS')),
            NavigationDestination(icon: const Icon(Icons.monitor_heart_rounded), label: _t('Health')),
            NavigationDestination(icon: const Icon(Icons.map_rounded), label: _t('Map')),
          ],
        ),
      ),
    );
  }

  void _showEditProfileDialog() {
    final bgController = TextEditingController(text: widget.bloodGroup ?? '');
    final allergiesController = TextEditingController(text: widget.allergies ?? '');
    final diseasesController = TextEditingController(text: widget.diseases ?? '');
    final weightController = TextEditingController(text: widget.weight ?? '');
    final heightController = TextEditingController(text: widget.height ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Health Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: bgController, decoration: const InputDecoration(labelText: 'Blood Group')),
              const SizedBox(height: 8),
              TextField(controller: allergiesController, decoration: const InputDecoration(labelText: 'Allergies')),
              const SizedBox(height: 8),
              TextField(controller: diseasesController, decoration: const InputDecoration(labelText: 'Diseases / Conditions')),
              const SizedBox(height: 8),
              TextField(controller: weightController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Weight (kg)')),
              const SizedBox(height: 8),
              TextField(controller: heightController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height (cm)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              widget.onProfileUpdate?.call(
                bgController.text.trim(),
                allergiesController.text.trim(),
                diseasesController.text.trim(),
                weightController.text.trim(),
                heightController.text.trim(),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Emergency Contact Card (editable)
// ---------------------------------------------------------------------------
class EmergencyContactCard extends StatefulWidget {
  const EmergencyContactCard({
    super.key,
    required this.language,
    required this.onContactSaved,
  });

  final String language;
  final VoidCallback onContactSaved;

  @override
  State<EmergencyContactCard> createState() => _EmergencyContactCardState();
}

class _EmergencyContactCardState extends State<EmergencyContactCard> {
  List<Map<String, String>> _contacts = [];

  static const List<String> _tiers = ['Tier 1 (Call)', 'Tier 2', 'Tier 3', 'Tier 4', 'Tier 5'];
  static const List<Color> _tierColors = [
    Colors.red, Colors.orange, Colors.amber, Colors.blue, Colors.teal,
  ];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('emergency_contacts_json');
    if (saved != null && saved.isNotEmpty) {
      setState(() {
        _contacts = saved.map((s) => Map<String, String>.from(jsonDecode(s))).toList();
      });
    } else {
      // Migrate from old single-contact format
      final name = prefs.getString('emergency_contact_name');
      final phone = prefs.getString('emergency_phone');
      if (name != null && phone != null && name.isNotEmpty && phone.isNotEmpty) {
        setState(() {
          _contacts = [{'name': name, 'phone': phone, 'tier': '1'}];
        });
        _saveContacts();
      }
    }
  }

  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('emergency_contacts_json',
      _contacts.map((c) => jsonEncode(c)).toList());
    // Also save legacy format for backward compatibility
    if (_contacts.isNotEmpty) {
      final tier1 = _contacts.firstWhere((c) => c['tier'] == '1', orElse: () => _contacts.first);
      await prefs.setString('emergency_contact_name', tier1['name'] ?? '');
      await prefs.setString('emergency_phone', tier1['phone'] ?? '');
    }
    widget.onContactSaved();
  }

  void _addOrEditContact({int? index}) {
    final isEdit = index != null;
    final nameCtrl = TextEditingController(text: isEdit ? _contacts[index]['name'] : '');
    final phoneCtrl = TextEditingController(text: isEdit ? _contacts[index]['phone'] : '');
    String selectedTier = isEdit ? _contacts[index]['tier']! : (_contacts.length + 1).clamp(1, 5).toString();
    final usedTiers = _contacts.where((c) => isEdit ? c['tier'] != selectedTier : true).map((c) => c['tier']).toSet();
    final availableTiers = ['1','2','3','4','5'].where((t) => !usedTiers.contains(t) || (isEdit && t == selectedTier)).toList();
    if (!availableTiers.contains(selectedTier) && availableTiers.isNotEmpty) {
      selectedTier = availableTiers.first;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Contact' : 'Add Emergency Contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedTier,
                decoration: const InputDecoration(labelText: 'Priority Tier', border: OutlineInputBorder()),
                items: availableTiers.map((t) {
                  final idx = int.parse(t) - 1;
                  return DropdownMenuItem(
                    value: t,
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: _tierColors[idx], shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Text(_tiers[idx]),
                    ]),
                  );
                }).toList(),
                onChanged: (v) => setDialogState(() => selectedTier = v ?? selectedTier),
              ),
              const SizedBox(height: 8),
              Text(
                selectedTier == '1' ? 'Tier 1: Will receive a direct phone call during SOS'
                    : 'Tier ${selectedTier}: Will receive WhatsApp message during SOS',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            if (isEdit)
              TextButton(
                onPressed: () {
                  setState(() => _contacts.removeAt(index));
                  _saveContacts();
                  Navigator.pop(ctx);
                },
                child: const Text('Remove', style: TextStyle(color: Colors.red)),
              ),
            ElevatedButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || phoneCtrl.text.trim().isEmpty) return;
                final contact = {'name': nameCtrl.text.trim(), 'phone': phoneCtrl.text.trim(), 'tier': selectedTier};
                setState(() {
                  if (isEdit) {
                    _contacts[index] = contact;
                  } else {
                    _contacts.add(contact);
                  }
                });
                _saveContacts();
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ...List.generate(_contacts.length, (i) {
          final c = _contacts[i];
          final tier = int.tryParse(c['tier'] ?? '1') ?? 1;
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _tierColors[tier - 1].withOpacity(0.15),
                child: Text('T$tier', style: TextStyle(color: _tierColors[tier - 1], fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              title: Text(c['name'] ?? ''),
              subtitle: Text('${c['phone']} \u2022 ${_tiers[tier - 1]}'),
              trailing: IconButton(
                icon: const Icon(Icons.edit_rounded, size: 20),
                onPressed: () => _addOrEditContact(index: i),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        if (_contacts.length < 5)
          OutlinedButton.icon(
            onPressed: () => _addOrEditContact(),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
            label: const Text('Add contact'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Medicine Clock Widget
// ---------------------------------------------------------------------------
class MedicineClockWidget extends StatelessWidget {
  const MedicineClockWidget({super.key, required this.reminders});

  final List<MedicineReminder> reminders;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      width: 200,
      child: CustomPaint(
        painter: MedicineClockPainter(reminders: reminders),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.access_time_rounded, size: 28, color: Colors.red),
              const SizedBox(height: 4),
              Text(
                '${reminders.where((r) => r.taken).length}/${reminders.length}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Text('taken', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class MedicineClockPainter extends CustomPainter {
  MedicineClockPainter({required this.reminders});

  final List<MedicineReminder> reminders;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    // Clock face
    final facePaint = Paint()
      ..color = Colors.grey.shade100
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, facePaint);

    // Border
    final borderPaint = Paint()
      ..color = Colors.red.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, borderPaint);

    // Hour markers
    final markerPaint = Paint()..color = Colors.grey.shade400;
    for (int i = 0; i < 12; i++) {
      final angle = (i * 30 - 90) * math.pi / 180;
      final outer = Offset(
        center.dx + radius * 0.88 * math.cos(angle),
        center.dy + radius * 0.88 * math.sin(angle),
      );
      final inner = Offset(
        center.dx + radius * 0.78 * math.cos(angle),
        center.dy + radius * 0.78 * math.sin(angle),
      );
      canvas.drawLine(inner, outer, markerPaint..strokeWidth = 2);
    }

    // Draw medicine times as dots
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < reminders.length; i++) {
      final angle = (i * (360 / reminders.length) - 90) * math.pi / 180;
      final dotCenter = Offset(
        center.dx + radius * 0.6 * math.cos(angle),
        center.dy + radius * 0.6 * math.sin(angle),
      );
      dotPaint.color = reminders[i].taken ? Colors.green : Colors.red;
      canvas.drawCircle(dotCenter, 8, dotPaint);

      // Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: reminders[i].name.substring(0, math.min(3, reminders[i].name.length)),
          style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(dotCenter.dx - textPainter.width / 2, dotCenter.dy - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant MedicineClockPainter oldDelegate) =>
      oldDelegate.reminders != reminders;
}

// ---------------------------------------------------------------------------
// Blood Donation Page
// ---------------------------------------------------------------------------
class BloodDonationPage extends StatefulWidget {
  const BloodDonationPage({super.key, required this.language});

  final String language;

  @override
  State<BloodDonationPage> createState() => _BloodDonationPageState();
}

class _BloodDonationPageState extends State<BloodDonationPage> {
  String _t(String v) => AppLocalizations(widget.language).text(v);
  List<Map<String, dynamic>> _donors = [];
  bool _loading = true;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedBloodGroup = 'O+';

  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

  @override
  void initState() {
    super.initState();
    _loadDonors();
  }

  Future<void> _loadDonors() async {
    try {
      final fs = FirestoreService();
      if (fs.isAvailable) {
        final snap = await fs.db.collection('blood_donors').orderBy('createdAt', descending: true).get();
        setState(() {
          _donors = snap.docs.map((d) => d.data()).toList();
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    // Load from local storage
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('blood_donors') ?? [];
    setState(() {
      _donors = saved.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
      _loading = false;
    });
  }

  Future<void> _registerDonor() async {
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter name and phone.')),
      );
      return;
    }

    final donor = {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'bloodGroup': _selectedBloodGroup,
      'createdAt': DateTime.now().toIso8601String(),
    };

    try {
      final fs = FirestoreService();
      if (fs.isAvailable) {
        await fs.db.collection('blood_donors').add({
          ...donor,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}

    // Also save locally
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('blood_donors') ?? [];
    list.add(jsonEncode(donor));
    await prefs.setStringList('blood_donors', list);

    setState(() => _donors.insert(0, donor));
    _nameController.clear();
    _phoneController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registered as blood donor!')),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('Blood Donation'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Register section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t('Register as Donor'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_rounded))),
                  const SizedBox(height: 8),
                  TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_rounded))),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedBloodGroup,
                    decoration: const InputDecoration(labelText: 'Blood Group', prefixIcon: Icon(Icons.bloodtype_rounded)),
                    items: _bloodGroups.map((bg) => DropdownMenuItem(value: bg, child: Text(bg))).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedBloodGroup = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _registerDonor,
                      icon: const Icon(Icons.bloodtype_rounded),
                      label: Text(_t('Register')),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Donor list
          Text(_t('Available Donors'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_donors.isEmpty)
            const Text('No donors registered yet.')
          else
            ..._donors.map(
              (donor) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red.shade50,
                    child: Text(
                      donor['bloodGroup'] ?? '?',
                      style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  title: Text(donor['name'] ?? 'Unknown'),
                  subtitle: Text(donor['phone'] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.phone_rounded, color: Colors.green),
                    onPressed: () async {
                      final phone = donor['phone'];
                      if (phone != null) {
                        final uri = Uri(scheme: 'tel', path: phone);
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      }
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Caregiver Settings
// ---------------------------------------------------------------------------
class CaregiverSettingsPage extends StatefulWidget {
  const CaregiverSettingsPage({
    super.key,
    required this.caregiverName,
    required this.caregiverRole,
    required this.caregiverEmail,
    required this.patients,
    required this.selectedPatientName,
    required this.onPatientSelected,
    required this.onSignOut,
  });

  final String caregiverName;
  final String caregiverRole;
  final String caregiverEmail;
  final List<PatientProfile> patients;
  final String selectedPatientName;
  final ValueChanged<String> onPatientSelected;
  final VoidCallback onSignOut;

  @override
  State<CaregiverSettingsPage> createState() => _CaregiverSettingsPageState();
}

class _CaregiverSettingsPageState extends State<CaregiverSettingsPage> {
  late String _selectedPatientName = widget.selectedPatientName;
  String? _profilePhotoPath;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfilePhoto();
  }

  Future<void> _loadProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('profile_photo_${widget.caregiverEmail}');
    if (mounted) setState(() => _profilePhotoPath = path);
  }

  Future<void> _pickProfilePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final XFile? image = await _picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (image == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_photo_${widget.caregiverEmail}', image.path);
    if (mounted) setState(() => _profilePhotoPath = image.path);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F2937) : Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _pickProfilePhoto,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: const Color(0xFF6C63FF).withOpacity(0.15),
                          backgroundImage: _profilePhotoPath != null ? FileImage(File(_profilePhotoPath!)) : null,
                          child: _profilePhotoPath == null
                              ? Text(
                                  widget.caregiverName.isNotEmpty ? widget.caregiverName[0].toUpperCase() : '?',
                                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Color(0xFF6C63FF)),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFF6C63FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Account', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(widget.caregiverName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Role: ${widget.caregiverRole}'),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFF6C63FF)),
                    onPressed: _pickProfilePhoto,
                    tooltip: 'Change photo',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (widget.patients.isNotEmpty) ...[
              const Text('Linked patients', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...widget.patients.map((patient) {
                final isSelected = _selectedPatientName == patient.name;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? Colors.green.shade100 : Colors.grey.shade100,
                      child: Icon(Icons.person_rounded, color: isSelected ? Colors.green : Colors.grey),
                    ),
                    title: Text(patient.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    subtitle: isSelected ? const Text('Currently selected', style: TextStyle(fontSize: 12, color: Colors.green)) : null,
                    trailing: isSelected
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(12)),
                            child: const Text('Active', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                          )
                        : const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    onTap: () {
                      setState(() => _selectedPatientName = patient.name);
                      widget.onPatientSelected(patient.name);
                      Navigator.pop(context);
                    },
                  ),
                );
              }),
            ],
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.smart_toy_rounded),
              title: const Text('AI Assistant'),
              subtitle: const Text('Powered by Gemini AI (built-in)'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('AI is ready! Tap the robot icon on the Home tab to use it.')),
                );
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.description_rounded),
              title: const Text('Terms & Conditions'),
              subtitle: const Text('View app terms and privacy policy'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TermsAndConditionsPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('SOS Call Log'),
              subtitle: const Text('View emergency call history'),
              onTap: () async {
                final logs = await DatabaseService.getSosLog();
                if (!context.mounted) return;
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('SOS Call Log'),
                    content: SizedBox(
                      width: 300,
                      height: 400,
                      child: logs.isEmpty
                          ? const Center(child: Text('No SOS calls recorded yet.'))
                          : ListView.builder(
                              itemCount: logs.length,
                              itemBuilder: (_, i) => Card(
                                child: ListTile(
                                  leading: const Icon(Icons.phone_rounded, color: Colors.red),
                                  title: Text(logs[i]['contact_name'] ?? 'Unknown'),
                                  subtitle: Text('${logs[i]['contact_phone']}\n${logs[i]['timestamp']?.toString().substring(0, 19) ?? ''}'),
                                ),
                              ),
                            ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.storage_rounded),
              title: const Text('Database Viewer'),
              subtitle: const Text('View all stored data'),
              onTap: () async {
                final hasAccess = await DatabaseService.hasDbAccess(widget.caregiverEmail);
                if (!context.mounted) return;
                if (hasAccess) {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DatabaseViewerPage(
                      isAdmin: DatabaseService.isOwner(widget.caregiverEmail),
                      currentUserEmail: widget.caregiverEmail,
                    )),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Access denied. Only authorized accounts can view the database.')),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.family_restroom_rounded, color: Colors.indigo),
              title: const Text('Family Health Dashboard'),
              subtitle: const Text("Monitor family members' health"),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FamilyHealthDashboardPage(
                      caregiverEmail: widget.caregiverEmail,
                      caregiverName: widget.caregiverName,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.local_hospital_rounded, color: Colors.red),
              title: const Text('Doctor Appointments'),
              subtitle: const Text('Find doctors nearby & video call'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DoctorAppointmentPage()),
                );
              },
            ),
            const SizedBox(height: 12),
            // MongoDB connection test
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Testing MongoDB connection...')),
                  );
                  final connected = await SupabaseService.testConnection();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(connected
                            ? 'Supabase connected successfully!' : 'Supabase connection failed. Check API key.'),
                        backgroundColor: connected ? Colors.green : Colors.red,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.cloud_rounded),
                label: const Text('Test Supabase Connection'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  widget.onSignOut();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Database Viewer page
// ---------------------------------------------------------------------------
class DatabaseViewerPage extends StatefulWidget {
  const DatabaseViewerPage({super.key, required this.isAdmin, required this.currentUserEmail});

  final bool isAdmin;
  final String currentUserEmail;

  @override
  State<DatabaseViewerPage> createState() => _DatabaseViewerPageState();
}

class _DatabaseViewerPageState extends State<DatabaseViewerPage> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = ['Login Audit', 'Health Snapshots', 'SOS Log', 'SOS Locations', 'Medicine Reminders'];
    if (widget.isAdmin) tabs.add('Access Control');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Viewer'),
        actions: [
          if (widget.isAdmin)
            IconButton(
              onPressed: () => _showAddUserDialog(),
              icon: const Icon(Icons.person_add_rounded),
              tooltip: 'Add authorized user',
            ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(tabs.length, (i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: ChoiceChip(
                  label: Text(tabs[i], style: const TextStyle(fontSize: 12)),
                  selected: _selectedTab == i,
                  onSelected: (_) => setState(() => _selectedTab = i),
                ),
              )),
            ),
          ),
          Expanded(
            child: _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0: return _buildLoginAudit();
      case 1: return _buildHealthSnapshots();
      case 2: return _buildSosLog();
      case 3: return _buildSosLocations();
      case 4: return _buildMedicineReminders();
      case 5: return _buildAccessControl();
      default: return const SizedBox();
    }
  }

  void _showAddUserDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Authorized User'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Gmail address',
            hintText: 'user@gmail.com',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final email = controller.text.trim();
              if (email.isEmpty || !email.contains('@')) return;
              final success = await DatabaseService.grantAccess(email, widget.currentUserEmail);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(success ? 'Access granted to $email' : 'User already authorized')),
                );
                setState(() {});
              }
            },
            child: const Text('Grant Access'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessControl() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseService.getAuthorizedUsers(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final users = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.shield_rounded, color: Colors.indigo),
                  const SizedBox(width: 8),
                  Text('${users.length} authorized user(s)', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _showAddUserDialog,
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('Add', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (_, i) {
                  final user = users[i];
                  final isOwner = DatabaseService.isOwner(user['email']);
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        isOwner ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                        color: isOwner ? Colors.amber : Colors.blue,
                      ),
                      title: Text(user['email'], style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        '${isOwner ? 'Owner' : 'Granted by: ${user['granted_by']}'}\n${user['granted_at']?.toString().substring(0, 19) ?? ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: isOwner
                          ? const Chip(label: Text('Owner', style: TextStyle(fontSize: 10)))
                          : IconButton(
                              icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.red, size: 20),
                              onPressed: () async {
                                await DatabaseService.revokeAccess(user['email']);
                                setState(() {});
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Access revoked for ${user['email']}')),
                                  );
                                }
                              },
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoginAudit() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseService.getLoginAudit(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.isEmpty) return const Center(child: Text('No login records yet.'));
        return ListView.builder(
          itemCount: snap.data!.length,
          itemBuilder: (_, i) {
            final row = snap.data![i];
            return Card(
              child: ListTile(
                leading: Icon(
                  row['successful'] == 1 ? Icons.check_circle : Icons.cancel,
                  color: row['successful'] == 1 ? Colors.green : Colors.red,
                ),
                title: Text(row['email'] ?? '', style: const TextStyle(fontSize: 13)),
                subtitle: Text('${row['role'] ?? ''} \u2022 ${row['timestamp']?.toString().substring(0, 19) ?? ''}', style: const TextStyle(fontSize: 11)),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHealthSnapshots() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseService.getHealthSnapshots(''),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.isEmpty) return const Center(child: Text('No health snapshots yet.'));
        return ListView.builder(
          itemCount: snap.data!.length,
          itemBuilder: (_, i) {
            final row = snap.data![i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.monitor_heart_rounded, color: Colors.blue),
                title: Text('${row['date_key']} - ${row['patient_name']}', style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  'BP: ${row['blood_pressure'] ?? '--'} | Sugar: ${row['blood_sugar'] ?? '--'} | HR: ${row['heart_rate'] ?? '--'} | Sleep: ${row['sleep_hours'] ?? '--'}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSosLog() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseService.getSosLog(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.isEmpty) return const Center(child: Text('No SOS calls yet.'));
        return ListView.builder(
          itemCount: snap.data!.length,
          itemBuilder: (_, i) {
            final row = snap.data![i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.phone_rounded, color: Colors.red),
                title: Text('${row['contact_name'] ?? 'Unknown'} - ${row['contact_phone'] ?? ''}', style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  '${row['latitude'] != null ? '${row['latitude']}, ${row['longitude']}' : 'No location'} \u2022 ${row['timestamp']?.toString().substring(0, 19) ?? ''}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSosLocations() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseService.getActiveSosLocations(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.isEmpty) return const Center(child: Text('No active SOS locations.'));
        return ListView.builder(
          itemCount: snap.data!.length,
          itemBuilder: (_, i) {
            final row = snap.data![i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.location_on_rounded, color: Colors.orange),
                title: Text('${row['patient_name'] ?? 'Unknown'}', style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  '${row['latitude']}, ${row['longitude']}\nExpires: ${row['expires_at']?.toString().substring(0, 19) ?? ''}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMedicineReminders() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: DatabaseService.getMedicineReminders(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.isEmpty) return const Center(child: Text('No medicine reminders yet.'));
        return ListView.builder(
          itemCount: snap.data!.length,
          itemBuilder: (_, i) {
            final row = snap.data![i];
            return Card(
              child: ListTile(
                leading: Icon(
                  row['taken'] == 1 ? Icons.check_circle : Icons.medication_rounded,
                  color: row['taken'] == 1 ? Colors.green : Colors.blue,
                ),
                title: Text('${row['name']}', style: const TextStyle(fontSize: 13)),
                subtitle: Text('${row['time']} \u2022 ${row['taken'] == 1 ? 'Taken' : 'Pending'}', style: const TextStyle(fontSize: 11)),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Family Health Dashboard
// ---------------------------------------------------------------------------
class FamilyHealthDashboardPage extends StatefulWidget {
  const FamilyHealthDashboardPage({
    super.key,
    required this.caregiverEmail,
    required this.caregiverName,
  });

  final String caregiverEmail;
  final String caregiverName;

  @override
  State<FamilyHealthDashboardPage> createState() => _FamilyHealthDashboardPageState();
}

class _FamilyHealthDashboardPageState extends State<FamilyHealthDashboardPage> {
  List<Map<String, dynamic>> _familyMembers = [];
  bool _loading = true;

  final List<Color> _cardColors = [
    const Color(0xFF6366F1),
    const Color(0xFFEC4899),
    const Color(0xFF14B8A6),
    const Color(0xFFF59E0B),
    const Color(0xFF3B82F6),
    const Color(0xFF10B981),
  ];

  @override
  void initState() {
    super.initState();
    _loadFamilyMembers();
  }

  Future<void> _loadFamilyMembers() async {
    setState(() => _loading = true);
    try {
      final members = await DatabaseService.getFamilyMembers(widget.caregiverEmail);
      setState(() {
        _familyMembers = members;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101827) : const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Family Health Dashboard'),
        backgroundColor: isDark ? const Color(0xFF1F2937) : const Color(0xFFE8D9DA),
        actions: [
          IconButton(
            onPressed: _showAddFamilyMemberDialog,
            icon: const Icon(Icons.person_add_rounded),
            tooltip: 'Add family member',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _familyMembers.isEmpty
              ? _buildEmptyState()
              : _buildMemberList(),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.family_restroom_rounded, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('No family members yet', style: TextStyle(fontSize: 20, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Add family members to monitor their health', style: TextStyle(color: Colors.grey.shade500)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showAddFamilyMemberDialog,
            icon: const Icon(Icons.person_add_rounded),
            label: const Text('Add Family Member'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              minimumSize: const Size(240, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _familyMembers.length,
      itemBuilder: (context, index) {
        final member = _familyMembers[index];
        final color = _cardColors[index % _cardColors.length];
        return _buildMemberCard(member, color, isDark);
      },
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> member, Color color, bool isDark) {
    final name = member['patient_name'] ?? 'Unknown';
    final relationship = member['relationship'] ?? 'Family';
    final bloodGroup = member['blood_group'] ?? 'Unknown';
    final allergies = member['allergies'] ?? 'None';
    final age = member['age'] ?? '--';
    final phone = member['phone'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with name and relationship
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: color.withValues(alpha: 0.2),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(relationship, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 6),
                          Text('Age: $age', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _showEditFamilyMemberDialog(member);
                    if (v == 'add_health') _showAddHealthDataDialog(member);
                    if (v == 'delete') _deleteFamilyMember(member);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 18), SizedBox(width: 8), Text('Edit')])),
                    const PopupMenuItem(value: 'add_health', child: Row(children: [Icon(Icons.monitor_heart_rounded, size: 18), SizedBox(width: 8), Text('Add Health Data')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_rounded, size: 18, color: Colors.red), SizedBox(width: 8), Text('Remove', style: TextStyle(color: Colors.red))])),
                  ],
                ),
              ],
            ),
          ),
          // Health info pills
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Health Info', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _healthPill('🩸 Blood', bloodGroup, isDark),
                    const SizedBox(width: 8),
                    _healthPill('⚠️ Allergies', allergies, isDark),
                  ],
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _healthPill('📞 Phone', phone, isDark),
                ],
                const SizedBox(height: 12),
                // Latest health snapshot
                FutureBuilder<Map<String, dynamic>?> (
                  future: DatabaseService.getLatestFamilyHealthSnapshot(member['id']),
                  builder: (ctx, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                    }
                    final snapshot = snap.data;
                    if (snapshot == null) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 18, color: Colors.grey.shade500),
                            const SizedBox(width: 8),
                            Text('No health data yet. Tap menu to add.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ],
                        ),
                      );
                    }
                    return _buildLatestHealthCard(snapshot, color, isDark);
                  },
                ),
                const SizedBox(height: 8),
                // View full history button
                TextButton.icon(
                  onPressed: () => _showHealthHistory(member),
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text('View Health History'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthPill(String label, String value, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.black54)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildLatestHealthCard(Map<String, dynamic> snapshot, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_rounded, size: 16, color: color),
              const SizedBox(width: 6),
              Text('Latest: ${snapshot['date_key'] ?? ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniMetric('BP', snapshot['blood_pressure'] ?? '--', isDark),
              _miniMetric('Sugar', snapshot['blood_sugar'] ?? '--', isDark),
              _miniMetric('HR', snapshot['heart_rate'] ?? '--', isDark),
              _miniMetric('Sleep', snapshot['sleep_hours'] ?? '--', isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniMetric(String label, String value, bool isDark) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
          Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  void _showAddFamilyMemberDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final ageController = TextEditingController();
    final phoneController = TextEditingController();
    final bloodGroupController = TextEditingController();
    final allergiesController = TextEditingController();
    final weightController = TextEditingController();
    final heightController = TextEditingController();
    String selectedRelationship = 'Family';
    final relationships = ['Family', 'Spouse', 'Parent', 'Child', 'Sibling', 'Grandparent', 'Friend', 'Other'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Family Member'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
                  textCapitalization: TextCapitalization.words),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRelationship,
                  decoration: const InputDecoration(labelText: 'Relationship', border: OutlineInputBorder()),
                  items: relationships.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) { if (v != null) setDialogState(() => selectedRelationship = v); },
                ),
                const SizedBox(height: 12),
                TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email (optional)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 12),
                TextField(controller: ageController, decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
                  keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextField(controller: bloodGroupController, decoration: const InputDecoration(labelText: 'Blood Group', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: allergiesController, decoration: const InputDecoration(labelText: 'Allergies', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: weightController, decoration: const InputDecoration(labelText: 'Weight (kg)', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: heightController, decoration: const InputDecoration(labelText: 'Height (cm)', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
                  return;
                }
                final id = await DatabaseService.addFamilyMember(
                  caregiverEmail: widget.caregiverEmail,
                  patientName: nameController.text.trim(),
                  patientEmail: emailController.text.trim().isNotEmpty ? emailController.text.trim() : null,
                  relationship: selectedRelationship,
                  bloodGroup: bloodGroupController.text.trim().isNotEmpty ? bloodGroupController.text.trim() : null,
                  allergies: allergiesController.text.trim().isNotEmpty ? allergiesController.text.trim() : null,
                  weight: weightController.text.trim().isNotEmpty ? weightController.text.trim() : null,
                  height: heightController.text.trim().isNotEmpty ? heightController.text.trim() : null,
                  age: ageController.text.trim().isNotEmpty ? ageController.text.trim() : null,
                  phone: phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : null,
                );
                // Sync to Supabase
                SupabaseService.syncFamilyMember(
                  caregiverEmail: widget.caregiverEmail,
                  patientName: nameController.text.trim(),
                  patientEmail: emailController.text.trim().isNotEmpty ? emailController.text.trim() : null,
                  relationship: selectedRelationship,
                  bloodGroup: bloodGroupController.text.trim().isNotEmpty ? bloodGroupController.text.trim() : null,
                  allergies: allergiesController.text.trim().isNotEmpty ? allergiesController.text.trim() : null,
                  weight: weightController.text.trim().isNotEmpty ? weightController.text.trim() : null,
                  height: heightController.text.trim().isNotEmpty ? heightController.text.trim() : null,
                  age: ageController.text.trim().isNotEmpty ? ageController.text.trim() : null,
                  phone: phoneController.text.trim().isNotEmpty ? phoneController.text.trim() : null,
                );
                Navigator.pop(ctx);
                _loadFamilyMembers();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${nameController.text.trim()} added to family')),
                  );
                }
              },
              child: const Text('Add Member'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditFamilyMemberDialog(Map<String, dynamic> member) {
    final nameController = TextEditingController(text: member['patient_name'] ?? '');
    final emailController = TextEditingController(text: member['patient_email'] ?? '');
    final ageController = TextEditingController(text: member['age'] ?? '');
    final phoneController = TextEditingController(text: member['phone'] ?? '');
    final bloodGroupController = TextEditingController(text: member['blood_group'] ?? '');
    final allergiesController = TextEditingController(text: member['allergies'] ?? '');
    String selectedRelationship = member['relationship'] ?? 'Family';
    final relationships = ['Family', 'Spouse', 'Parent', 'Child', 'Sibling', 'Grandparent', 'Friend', 'Other'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit ${member['patient_name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRelationship,
                  decoration: const InputDecoration(labelText: 'Relationship', border: OutlineInputBorder()),
                  items: relationships.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) { if (v != null) setDialogState(() => selectedRelationship = v); },
                ),
                const SizedBox(height: 12),
                TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: ageController, decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()), keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()), keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                TextField(controller: bloodGroupController, decoration: const InputDecoration(labelText: 'Blood Group', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: allergiesController, decoration: const InputDecoration(labelText: 'Allergies', border: OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await DatabaseService.updateFamilyMember(member['id'], {
                  'patient_name': nameController.text.trim(),
                  'patient_email': emailController.text.trim(),
                  'relationship': selectedRelationship,
                  'age': ageController.text.trim(),
                  'phone': phoneController.text.trim(),
                  'blood_group': bloodGroupController.text.trim(),
                  'allergies': allergiesController.text.trim(),
                });
                Navigator.pop(ctx);
                _loadFamilyMembers();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddHealthDataDialog(Map<String, dynamic> member) {
    final bpController = TextEditingController();
    final sugarController = TextEditingController();
    final hrController = TextEditingController();
    final sleepController = TextEditingController();
    final notesController = TextEditingController();
    final todayKey = '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Health Data for ${member['patient_name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Date: $todayKey', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              TextField(controller: bpController, decoration: const InputDecoration(labelText: 'Blood Pressure (e.g. 120/80)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: sugarController, decoration: const InputDecoration(labelText: 'Blood Sugar (mg/dL)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: hrController, decoration: const InputDecoration(labelText: 'Heart Rate (bpm)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: sleepController, decoration: const InputDecoration(labelText: 'Sleep (hours)', border: OutlineInputBorder()), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              TextField(controller: notesController, decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder()), maxLines: 2),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await DatabaseService.saveFamilyHealthSnapshot(
                familyMemberId: member['id'],
                caregiverEmail: widget.caregiverEmail,
                dateKey: todayKey,
                bloodPressure: bpController.text.trim().isNotEmpty ? bpController.text.trim() : null,
                bloodSugar: sugarController.text.trim().isNotEmpty ? sugarController.text.trim() : null,
                heartRate: hrController.text.trim().isNotEmpty ? hrController.text.trim() : null,
                sleepHours: sleepController.text.trim().isNotEmpty ? sleepController.text.trim() : null,
                notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
              );
              // Sync to Supabase
              SupabaseService.syncFamilyHealthSnapshot(
                caregiverEmail: widget.caregiverEmail,
                patientName: member['patient_name'],
                dateKey: todayKey,
                bloodPressure: bpController.text.trim().isNotEmpty ? bpController.text.trim() : null,
                bloodSugar: sugarController.text.trim().isNotEmpty ? sugarController.text.trim() : null,
                heartRate: hrController.text.trim().isNotEmpty ? hrController.text.trim() : null,
                sleepHours: sleepController.text.trim().isNotEmpty ? sleepController.text.trim() : null,
                notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
              );
              Navigator.pop(ctx);
              _loadFamilyMembers();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Health data saved')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showHealthHistory(Map<String, dynamic> member) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FamilyHealthHistoryPage(
          memberName: member['patient_name'] ?? 'Unknown',
          memberId: member['id'],
        ),
      ),
    );
  }

  void _deleteFamilyMember(Map<String, dynamic> member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Family Member'),
        content: Text('Remove ${member['patient_name']} and all their health data?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await DatabaseService.deleteFamilyMember(member['id']);
              Navigator.pop(ctx);
              _loadFamilyMembers();
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Family Health History Page
// ---------------------------------------------------------------------------
class FamilyHealthHistoryPage extends StatelessWidget {
  const FamilyHealthHistoryPage({
    super.key,
    required this.memberName,
    required this.memberId,
  });

  final String memberName;
  final int memberId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: Text('$memberName - Health History')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseService.getFamilyHealthSnapshots(memberId),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final snapshots = snap.data ?? [];
          if (snapshots.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded, size: 60, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('No health records yet', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Add health data from the dashboard', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshots.length,
            itemBuilder: (context, i) {
              final s = snapshots[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today_rounded, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text('${s['date_key']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const Spacer(),
                          Text('${s['timestamp']?.toString().substring(0, 10) ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ],
                      ),
                      const Divider(),
                      Row(
                        children: [
                          _historyMetric('BP', s['blood_pressure'] ?? '--'),
                          _historyMetric('Sugar', s['blood_sugar'] ?? '--'),
                          _historyMetric('Heart Rate', s['heart_rate'] ?? '--'),
                          _historyMetric('Sleep', s['sleep_hours'] ?? '--'),
                        ],
                      ),
                      if (s['notes'] != null && s['notes'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('📝 ${s['notes']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _historyMetric(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Terms and Conditions page
// ---------------------------------------------------------------------------
class TermsAndConditionsPage extends StatelessWidget {
  const TermsAndConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Medly - Terms & Conditions', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text('Last updated: August 2026', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            _section('1. Acceptance of Terms',
              'By using Medly, you agree to these Terms & Conditions. If you do not agree, please do not use the app.'),
            _section('2. Medical Disclaimer',
              'Medly provides general health information and AI-powered guidance. This is NOT a substitute for professional medical advice, diagnosis, or treatment. Always consult a qualified healthcare provider for medical concerns. In emergencies, call your local emergency number (108/112) immediately.'),
            _section('3. Data Collection & Privacy',
              'Medly collects the following data to provide its services:\n\n• Login information (email, name, role)\n• Health records (blood group, allergies, weight, height)\n• Daily health snapshots (blood pressure, sugar, heart rate, sleep)\n• Medicine reminders\n• SOS call logs and location data\n• Screen time usage\n\nThis data is stored locally on your device using SQLite database. If you choose to enable Firebase sync, data may also be stored in the cloud.'),
            _section('4. SOS Feature',
              'The SOS feature initiates a phone call to your designated emergency contact. Medly may also log your GPS location during SOS events. SOS locations are marked on the map for 4 hours for emergency reference. Medly cannot guarantee connection to emergency services.'),
            _section('5. Location Services',
              'Medly uses your device location to find nearby hospitals, pharmacies, and healthcare services using OpenStreetMap data. Location data is processed in real-time and is not stored permanently unless associated with an SOS event.'),
            _section('6. AI Health Assistant',
              'The AI assistant provides general health guidance based on symptom descriptions. Responses may be generated by a local knowledge base or an external AI API (Google Gemini). Always verify AI guidance with a healthcare professional.'),
            _section('7. Blood Donation Feature',
              'The blood donation registry allows voluntary donors to register their information. Doctors and ambulance drivers can view this information to connect donors with patients in need. Registration is voluntary and you may remove your information at any time.'),
            _section('8. User Responsibilities',
              'You are responsible for:\n\n• Keeping your login credentials secure\n• Providing accurate health information\n• Maintaining updated emergency contacts\n• Using the app responsibly and not relying solely on AI guidance\n• Seeking professional medical help when needed'),
            _section('9. Limitation of Liability',
              'Medly and its developers are not liable for any consequences arising from reliance on the app\'s health guidance. The app is provided "as is" without warranties of any kind.'),
            _section('10. Changes to Terms',
              'We reserve the right to update these terms at any time. Continued use of the app after changes constitutes acceptance of the new terms.'),
            _section('11. Contact',
              'For questions about these terms, please contact us through the app support channel.'),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text(content, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Live Map Page – Nearby Hospitals, Pharmacies, SOS X markers
// ---------------------------------------------------------------------------
class ClinicMapPage extends StatefulWidget {
  const ClinicMapPage({super.key, required this.language, this.initialServices});

  final String language;
  final List<HealthcareService>? initialServices;

  @override
  State<ClinicMapPage> createState() => _ClinicMapPageState();
}

class _ClinicMapPageState extends State<ClinicMapPage> with SingleTickerProviderStateMixin {
  LatLng? _center; // null until real GPS obtained
  bool _loadingLocation = true;
  String _locationError = '';
  bool _loadingServices = false;
  List<HealthcareService> _services = [];
  List<Map<String, dynamic>> _sosLocations = [];
  final MapController _mapController = MapController();
  bool _mapReady = false;
  String _selectedFilter = 'All';
  int _selectedZoom = 14;
  late AnimationController _pulseController;

  // Route state
  List<LatLng> _routePoints = [];
  RouteInfo? _currentRoute;
  bool _loadingRoute = false;
  HealthcareService? _selectedService;
  bool _isNavigating = false;
  StreamSubscription<Position>? _navigationSub;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    if (widget.initialServices != null && widget.initialServices!.isNotEmpty) {
      _services = List.from(widget.initialServices!);
    }
    _findLocation();
    _loadSosLocations();
  }

  @override
  void dispose() {
    _navigationSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _findLocation() async {
    try {
      // Step 1: Check if location services are enabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        // Try to open location settings
        if (mounted) {
          setState(() {
            _loadingLocation = false;
            _locationError = 'GPS is turned OFF. Please enable Location/GPS in your phone settings.';
          });
        }
        // Try to open location settings
        try { await Geolocator.openLocationSettings(); } catch (_) {}
        return;
      }

      // Step 2: Check/request permission
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _loadingLocation = false;
            _locationError = 'Location permission denied. Please allow it in App Settings.';
          });
        }
        try { await Geolocator.openAppSettings(); } catch (_) {}
        return;
      }

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        if (mounted) {
          setState(() {
            _loadingLocation = false;
            _locationError = 'Location permission required. Please allow location access.';
          });
        }
        return;
      }

      // Step 3: Try last known position FIRST (instant, no waiting)
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
        if (position != null) {
          print('[Map] Got last known position: ${position.latitude}, ${position.longitude}');
          if (mounted) {
            final loc = LatLng(position.latitude, position.longitude);
            setState(() {
              _center = loc;
              _loadingLocation = false;
              _locationError = '';
              _mapReady = true;
            });
            if (_services.isEmpty) {
              _fetchServices(lat: position.latitude, lon: position.longitude);
            }
            _mapController.move(loc, 14);
          }
        }
      } catch (e) {
        print('[Map] lastKnownPosition error: $e');
      }

      // Step 4: Get fresh high-accuracy position (may take a few seconds)
      try {
        final freshPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );

        if (mounted) {
          final realLocation = LatLng(freshPosition.latitude, freshPosition.longitude);
          setState(() {
            _center = realLocation;
            _loadingLocation = false;
            _locationError = '';
            _mapReady = true;
          });
          // Re-fetch hospitals with accurate location
          _fetchServices(lat: freshPosition.latitude, lon: freshPosition.longitude);
          _mapController.move(realLocation, 14);
        }
      } catch (e) {
        print('[Map] getCurrentPosition error: $e');
        // If we already have lastKnownPosition, that's fine
        if (_center != null) return;
        // No position at all
        if (mounted) {
          setState(() {
            _loadingLocation = false;
            _locationError = 'Could not get GPS location. Make sure you are outdoors or near a window. Tap retry to try again.';
          });
        }
      }
    } catch (e) {
      print('[Map] Location error: $e');
      if (mounted) {
        setState(() {
          _loadingLocation = false;
          _locationError = 'Location error: $e. Tap retry to try again.';
        });
      }
    }
  }

  Future<void> _loadSosLocations() async {
    await DatabaseService.cleanupExpiredSosLocations();
    final locations = await DatabaseService.getActiveSosLocations();
    if (mounted) setState(() => _sosLocations = locations);
  }

  Future<void> _fetchServices({double? lat, double? lon}) async {
    setState(() => _loadingServices = true);
    try {
      // Use passed coordinates or get fresh GPS
      double searchLat, searchLon;
      if (lat != null && lon != null) {
        searchLat = lat;
        searchLon = lon;
      } else {
        if (!await Geolocator.isLocationServiceEnabled()) {
          if (mounted) setState(() => _loadingServices = false);
          return;
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission != LocationPermission.always &&
            permission != LocationPermission.whileInUse) {
          if (mounted) setState(() => _loadingServices = false);
          return;
        }
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
        );
        searchLat = position.latitude;
        searchLon = position.longitude;
      }
      final finalLat = searchLat;
      final finalLon = searchLon;
      setState(() {
        _center = LatLng(finalLat, finalLon);
        _loadingLocation = false;
      });

      final radius = 15000; // 15 km radius
      final query = '''[out:json][timeout:30];
(
  node["amenity"="hospital"](around:$radius,$finalLat,$finalLon);
  way["amenity"="hospital"](around:$radius,$finalLat,$finalLon);
  relation["amenity"="hospital"](around:$radius,$finalLat,$finalLon);
  node["healthcare"="hospital"](around:$radius,$finalLat,$finalLon);
  way["healthcare"="hospital"](around:$radius,$finalLat,$finalLon);
  node["amenity"="pharmacy"](around:$radius,$finalLat,$finalLon);
  way["amenity"="pharmacy"](around:$radius,$finalLat,$finalLon);
  node["amenity"="chemist"](around:$radius,$finalLat,$finalLon);
  way["amenity"="chemist"](around:$radius,$finalLat,$finalLon);
  node["healthcare"="pharmacy"](around:$radius,$finalLat,$finalLon);
  node["healthcare"="ambulance"](around:$radius,$finalLat,$finalLon);
  node["emergency"="ambulance_station"](around:$radius,$finalLat,$finalLon);
  way["emergency"="ambulance_station"](around:$radius,$finalLat,$finalLon);
  node["healthcare"="clinic"](around:$radius,$finalLat,$finalLon);
  way["healthcare"="clinic"](around:$radius,$finalLat,$finalLon);
  node["amenity"="clinic"](around:$radius,$finalLat,$finalLon);
  way["amenity"="clinic"](around:$radius,$finalLat,$finalLon);
  node["healthcare"="doctor"](around:$radius,$finalLat,$finalLon);
);
out center 100;
''';

      // Try primary server, fallback to backup
      http.Response? response;
      final servers = [
        'https://overpass-api.de/api/interpreter',
        'https://overpass.kumi.systems/api/interpreter',
        'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
      ];
      for (final server in servers) {
        try {
          response = await http.post(
            Uri.parse(server),
            body: {'data': query},
          ).timeout(const Duration(seconds: 25));
          if (response.statusCode == 200) break;
        } catch (_) {
          continue;
        }
      }
      if (response == null || response.statusCode != 200) {
        if (mounted) setState(() {_loadingServices = false; _services = [];});
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final elements = data['elements'] as List? ?? [];
        final services = <HealthcareService>[];

        for (final el in elements) {
          final name = el['tags']?['name'] ?? el['tags']?['operator'] ?? 'Unknown';
          final amenity = el['tags']?['amenity'] ?? '';
          final healthcare = el['tags']?['healthcare'] ?? '';
          final emergency = el['tags']?['emergency'] ?? '';
          String type;
          if (amenity == 'hospital' || healthcare == 'hospital') {
            type = 'Hospital';
          } else if (amenity == 'pharmacy' || amenity == 'chemist' || healthcare == 'pharmacy') {
            type = 'Pharmacy';
          } else if (amenity == 'clinic' || healthcare == 'clinic') {
            type = 'Hospital';
          } else if (healthcare == 'doctor') {
            type = 'Hospital';
          } else if (healthcare == 'ambulance' || emergency == 'ambulance_station') {
            type = 'Ambulance';
          } else {
            type = 'Hospital';
          }
          final elLat = el['lat'] ?? el['center']?['lat'];
          final elLon = el['lon'] ?? el['center']?['lon'];
          if (elLat == null || elLon == null) continue;

          final dist = Geolocator.distanceBetween(finalLat, finalLon, elLat.toDouble(), elLon.toDouble());
          final distKm = (dist / 1000).toStringAsFixed(1);

          services.add(HealthcareService(
            name: name,
            type: type,
            distance: '$distKm km',
            status: 'Open',
            latitude: elLat.toDouble(),
            longitude: elLon.toDouble(),
          ));
        }

        services.sort((a, b) {
          final da = double.parse(a.distance.replaceAll(' km', ''));
          final db = double.parse(b.distance.replaceAll(' km', ''));
          return da.compareTo(db);
        });

        if (mounted) {
          setState(() {
            _services = services;
            _loadingServices = false;
          });
          // Cache for offline use
          OfflineService.cacheServices(
            services.map((s) => {
              'name': s.name, 'type': s.type, 'distance': s.distance,
              'latitude': s.latitude, 'longitude': s.longitude,
            }).toList(),
          );
        }
      } else {
        // Try cached
        final cached = await OfflineService.getCachedServices();
        if (mounted && cached.isNotEmpty) {
          setState(() {
            _services = cached.map((c) => HealthcareService(
              name: c['name'] ?? 'Unknown', type: c['type'] ?? 'Hospital',
              distance: c['distance'] ?? '', status: 'Open',
              latitude: (c['latitude'] as num?)?.toDouble(),
              longitude: (c['longitude'] as num?)?.toDouble(),
            )).toList();
            _loadingServices = false;
          });
        } else if (mounted) {
          setState(() => _loadingServices = false);
        }
      }
    } catch (e) {
      print('[LiveMap] Error: $e');
      final cached = await OfflineService.getCachedServices();
      if (mounted && cached.isNotEmpty) {
        setState(() {
          _services = cached.map((c) => HealthcareService(
            name: c['name'] ?? 'Unknown', type: c['type'] ?? 'Hospital',
            distance: c['distance'] ?? '', status: 'Open',
            latitude: (c['latitude'] as num?)?.toDouble(),
            longitude: (c['longitude'] as num?)?.toDouble(),
          )).toList();
          _loadingServices = false;
        });
      } else if (mounted) {
        setState(() => _loadingServices = false);
      }
    }
  }

  List<HealthcareService> get _filteredServices {
    if (_selectedFilter == 'All') return _services;
    return _services.where((s) => s.type == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mapCenter = _center ?? const LatLng(20.5937, 78.9629); // India center if no GPS
    final markers = <Marker>[
      // User location (blue pulsing dot) - only show if we have real GPS
      if (_center != null)
      Marker(
        point: _center!,
        width: 44,
        height: 44,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.my_location, color: Colors.blue, size: 28),
        ),
      ),
      // SOS locations (pulsing X marks)
      ..._sosLocations.map((loc) {
        final name = loc['patient_name'] ?? 'Unknown';
        final ts = loc['timestamp']?.toString().substring(0, 16) ?? '';
        final expiresAt = loc['expires_at']?.toString().substring(0, 16) ?? '';
        return Marker(
          point: LatLng(loc['latitude'], loc['longitude']),
          width: 56,
          height: 56,
          child: Tooltip(
            message: '🚨 SOS: $name\nTime: $ts\nExpires: $expiresAt',
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 1.0 + (_pulseController.value * 0.15);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.3 + _pulseController.value * 0.4),
                          blurRadius: 12 + _pulseController.value * 8,
                          spreadRadius: _pulseController.value * 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 32),
                  ),
                );
              },
            ),
          ),
        );
      }),
      // Hospital/Pharmacy/Ambulance markers
      ..._filteredServices.where((s) => s.latitude != null && s.longitude != null).map((service) => Marker(
        point: LatLng(service.latitude!, service.longitude!),
        width: 42,
        height: 52,
        child: GestureDetector(
          onTap: () => _showServiceSheet(service),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                service.type == 'Hospital'
                    ? Icons.local_hospital_rounded
                    : service.type == 'Pharmacy'
                        ? Icons.local_pharmacy_rounded
                        : Icons.emergency_rounded,
                color: service.type == 'Hospital'
                    ? Colors.red.shade700
                    : service.type == 'Pharmacy'
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                size: 28,
              ),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      )),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations(widget.language).text('Find nearby care')),
        actions: [
          if (_loadingServices)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          IconButton(
            onPressed: () {
              setState(() {
                _loadingLocation = true;
                _loadingServices = true;
                _locationError = '';
              });
              _findLocation();
              _loadSosLocations();
            },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh location',
          ),
          IconButton(
            onPressed: () {
              if (_mapReady) {
                _mapController.move(_center ?? mapCenter, _selectedZoom.toDouble());
              }
            },
            icon: const Icon(Icons.my_location_rounded),
            tooltip: 'Center on me',
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: _selectedZoom.toDouble(),
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) {
                  _selectedZoom = pos.zoom.round();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.medly',
              ),
              // Route polyline
              if (_routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: const Color(0xFF6C63FF),
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
              RichAttributionWidget(
                attributions: [TextSourceAttribution('OpenStreetMap contributors')],
              ),
            ],
          ),
          if (_loadingLocation)
            const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator()),
          // Location error banner
          if (_locationError.isNotEmpty && !_loadingLocation)
            Positioned(
              top: 50,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_off, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_locationError, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _loadingLocation = true;
                            _locationError = '';
                          });
                          _findLocation();
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry — Get My Location'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Loading overlay while getting location
          if (_loadingLocation && _center == null)
            Positioned(
              top: 60,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black87 : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8)],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Getting your GPS location...', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    SizedBox(height: 4),
                    Text('Please wait while we find where you are', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          // Filter chips at top
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black87 : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _filterChip('All', Icons.all_inclusive_rounded, Colors.blue),
                    _filterChip('Hospital', Icons.local_hospital_rounded, Colors.red),
                    _filterChip('Pharmacy', Icons.local_pharmacy_rounded, Colors.green),
                    _filterChip('Ambulance', Icons.emergency_rounded, Colors.orange),
                  ],
                ),
              ),
            ),
          ),
          // Legend at bottom
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.black87 : Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 6),
                      Text(
                        '${_filteredServices.length} places found',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                      ),
                      if (_sosLocations.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.close, size: 12, color: Colors.red),
                              const SizedBox(width: 3),
                              Text('${_sosLocations.length} SOS', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _legendItem(Icons.local_hospital_rounded, 'Hospital', Colors.red.shade700),
                      const SizedBox(width: 12),
                      _legendItem(Icons.local_pharmacy_rounded, 'Pharmacy', Colors.green.shade700),
                      const SizedBox(width: 12),
                      _legendItem(Icons.emergency_rounded, 'Ambulance', Colors.orange.shade700),
                      const SizedBox(width: 12),
                      _legendItem(Icons.close, 'SOS', Colors.red),
                      const SizedBox(width: 12),
                      _legendItem(Icons.my_location, 'You', Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Route info panel
          if (_currentRoute != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1F2937) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _isNavigating ? Colors.green.withOpacity(0.1) : const Color(0xFF6C63FF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _isNavigating ? Icons.navigation_rounded : Icons.route_rounded,
                            color: _isNavigating ? Colors.green : const Color(0xFF6C63FF),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedService?.name ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_isNavigating)
                                const Text(
                                  'Following your location...', 
                                  style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w500),
                                ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _clearRoute,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 16, color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _routeInfoTile(Icons.straighten, 'Distance', _currentRoute!.distanceText),
                        _routeInfoTile(Icons.schedule, 'ETA', _currentRoute!.durationText),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _startNavigation();
                            },
                            icon: const Icon(Icons.navigation_rounded, size: 16),
                            label: Text(_isNavigating ? 'Stop Navigation' : 'Start Navigation'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isNavigating ? Colors.red : Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          // Loading route indicator
          if (_loadingRoute)
            const Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Calculating route...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          // Zoom controls on right side
          Positioned(
            right: 12,
            bottom: _currentRoute != null ? 180 : 140,
            child: Column(
              children: [
                _zoomButton(Icons.add_rounded, () {
              _selectedZoom = (_selectedZoom + 1).clamp(1, 19);
              if (_mapReady) _mapController.move(_mapController.camera.center, _selectedZoom.toDouble());
            }),
                const SizedBox(height: 4),
                _zoomButton(Icons.remove_rounded, () {
              _selectedZoom = (_selectedZoom - 1).clamp(1, 19);
              if (_mapReady) _mapController.move(_mapController.camera.center, _selectedZoom.toDouble());
            }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, IconData icon, Color color) {
    final selected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        onTap: () => setState(() => _selectedFilter = label),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: selected ? color : Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal, color: selected ? color : Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _routeInfoTile(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF6C63FF), size: 22),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? Colors.black87 : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
        ),
        child: Icon(icon, size: 22),
      ),
    );
  }

  // ---- Route drawing ----
  Future<void> _showRoute(HealthcareService service) async {
    if (_center == null || service.latitude == null || service.longitude == null) return;
    setState(() {
      _loadingRoute = true;
      _selectedService = service;
    });

    final route = await RoutingService.getRoute(
      _center!,
      LatLng(service.latitude!, service.longitude!),
    );

    if (mounted && route != null) {
      setState(() {
        _routePoints = route.points;
        _currentRoute = route;
        _loadingRoute = false;
      });
      // Fit map to show entire route
      if (route.points.length >= 2 && _mapReady) {
        final bounds = LatLngBounds.fromPoints(route.points);
        _mapController.fitCamera(CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(60),
        ));
      }
    } else if (mounted) {
      setState(() {
        _loadingRoute = false;
        _selectedService = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not find route. Try Google Maps instead.'), backgroundColor: Colors.orange),
      );
    }
  }

  void _clearRoute() {
    _stopNavigation();
    setState(() {
      _routePoints = [];
      _currentRoute = null;
      _selectedService = null;
    });
  }

  void _startNavigation() {
    if (_isNavigating) {
      _stopNavigation();
      return;
    }
    if (_center == null || _selectedService == null) return;

    setState(() => _isNavigating = true);

    // Follow user location in real-time
    _navigationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    ).listen((pos) {
      if (!mounted || !_isNavigating) return;
      final userLatLng = LatLng(pos.latitude, pos.longitude);
      setState(() => _center = userLatLng);
      _mapController.move(userLatLng, 17);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Navigation started! Map follows your location.'),
        backgroundColor: Color(0xFF6C63FF),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _stopNavigation() {
    _navigationSub?.cancel();
    _navigationSub = null;
    if (_isNavigating) {
      setState(() => _isNavigating = false);
    }
  }

  void _showServiceSheet(HealthcareService service) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (service.type == 'Hospital' ? Colors.red : service.type == 'Pharmacy' ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    service.type == 'Hospital' ? Icons.local_hospital_rounded : service.type == 'Pharmacy' ? Icons.local_pharmacy_rounded : Icons.emergency_rounded,
                    color: service.type == 'Hospital' ? Colors.red.shade700 : service.type == 'Pharmacy' ? Colors.green.shade700 : Colors.orange.shade700,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('${service.type} • ${service.distance}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Route button - shows route on map
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showRoute(service);
                },
                icon: const Icon(Icons.route_rounded, size: 18),
                label: const Text('Show Route on Map'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showRoute(service);
                    },
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: const Text('Start Navigation'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (service.latitude != null && service.longitude != null && _mapReady) {
                        Navigator.pop(ctx);
                        _mapController.move(LatLng(service.latitude!, service.longitude!), 16);
                      }
                    },
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text('Show on Map'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Healthcare service model (extended)
// ---------------------------------------------------------------------------
class HealthcareService {
  final String name;
  final String type;
  final String distance;
  final String status;
  final double? latitude;
  final double? longitude;

  HealthcareService({
    required this.name,
    required this.type,
    required this.distance,
    required this.status,
    this.latitude,
    this.longitude,
  });
}

// ---------------------------------------------------------------------------
// Caregiver Profile model (extended)
// ---------------------------------------------------------------------------
class CaregiverProfile {
  final String name;
  final String email;
  final String password;
  final String role;
  final List<PatientProfile> patients;
  final String? bloodGroup;
  final String? allergies;
  final String? diseases;
  final String? weight;
  final String? height;

  CaregiverProfile({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    required this.patients,
    this.bloodGroup,
    this.allergies,
    this.diseases,
    this.weight,
    this.height,
  });

  factory CaregiverProfile.empty() {
    return CaregiverProfile(
      name: '',
      email: '',
      password: '',
      role: '',
      patients: const [],
    );
  }
}

class PatientProfile {
  final String name;
  PatientProfile({required this.name});
}

// ---------------------------------------------------------------------------
// Medicine Reminder model
// ---------------------------------------------------------------------------
class MedicineReminder {
  final String name;
  final String time;
  bool taken;

  MedicineReminder({required this.name, required this.time, required this.taken});

  Map<String, dynamic> toMap() => {'name': name, 'time': time, 'taken': taken};

  factory MedicineReminder.fromMap(Map<String, dynamic> map) {
    return MedicineReminder(
      name: map['name'] as String? ?? '',
      time: map['time'] as String? ?? '',
      taken: map['taken'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// Health Metric model
// ---------------------------------------------------------------------------
class HealthMetric {
  final String label;
  final String value;
  final String unit;
  final Color color;

  HealthMetric({required this.label, required this.value, required this.unit, required this.color});
}

// ---------------------------------------------------------------------------
// Health Task model
// ---------------------------------------------------------------------------
class HealthTask {
  final String id;
  final String title;
  final String detail;
  final IconData icon;

  const HealthTask({required this.id, required this.title, required this.detail, required this.icon});
}
