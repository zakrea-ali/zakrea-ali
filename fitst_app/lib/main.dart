import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fitst_app/screens/Auth.dart';
import 'package:fitst_app/Call/call_manager.dart';
import 'package:fitst_app/Call/incoming_call_overlay.dart';

// ==================== تكوين الاتصال ====================
class ApiConfig {
  // ✅ تم التعديل: استخدام رابط Render السحابي
  static const String baseUrl = 'https://zakrea-ali.onrender.com';
}

// ==================== InheritedWidget لنشر إعدادات الثيم ====================
class ThemeNotifier extends InheritedWidget {
  final ThemeMode themeMode;
  final VoidCallback toggleTheme;

  const ThemeNotifier({
    super.key,
    required this.themeMode,
    required this.toggleTheme,
    required super.child,
  });

  static ThemeNotifier? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeNotifier>();
  }

  @override
  bool updateShouldNotify(ThemeNotifier oldWidget) {
    return themeMode != oldWidget.themeMode;
  }
}

// ==================== التطبيق الرئيسي ====================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();

  static of(BuildContext context) {}
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  String? currentUserId;
  ThemeMode _themeMode = ThemeMode.system;

  // ==================== متغيرات المكالمات ====================
  OverlayEntry? _incomingOverlay;
  bool _isOverlayVisible = false;

  // مفتاح الـ Navigator للوصول إلى الـ Overlay
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserData();
    _loadThemeMode();

    // ربط مستمعي المكالمات بعد بناء الواجهة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupCallManagerListeners();
    });
  }

  // ==================== إعداد مستمعي المكالمات ====================
  void _setupCallManagerListeners() {
    // عند وصول مكالمة، نعرض الـ Overlay
    CallManager().onIncomingCall = (callData) {
      _showIncomingCallOverlay(callData);
    };

    // عند بدء المكالمة (قبول أو بدء)، نخفي الـ Overlay إذا كان ظاهراً
    CallManager().onCallStarted = (callService) {
      _hideIncomingCallOverlay();
    };
  }

  // ==================== عرض وإخفاء Overlay المكالمة الواردة ====================
  void _showIncomingCallOverlay(Map<String, dynamic> callData) {
    if (_isOverlayVisible) return;
    _isOverlayVisible = true;

    final callerId = callData['callerId'] ?? '';
    final isVideo = callData['isVideo'] ?? false;
    // يمكن تحسين اسم المتصل بجلبه من قاعدة البيانات
    final callerName = 'المستخدم';

    _incomingOverlay = OverlayEntry(
      builder: (context) => IncomingCallOverlay(
        callerName: callerName,
        isVideo: isVideo,
        onAccept: () {
          _hideIncomingCallOverlay();
          CallManager().acceptCall();
        },
        onReject: () {
          _hideIncomingCallOverlay();
          CallManager().rejectCall();
        },
      ),
    );

    // إضافة الـ Overlay إلى الـ Navigator الحالي
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.overlay?.insert(_incomingOverlay!);
    } else {
      // إذا لم يكن الـ Navigator جاهزاً، انتظر الإطار التالي
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = navigatorKey.currentState;
        if (nav != null) {
          nav.overlay?.insert(_incomingOverlay!);
        }
      });
    }
  }

  void _hideIncomingCallOverlay() {
    if (_incomingOverlay != null) {
      _incomingOverlay!.remove();
      _incomingOverlay = null;
      _isOverlayVisible = false;
    }
  }

  // ==================== تحميل بيانات المستخدم ====================
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserId = prefs.getString('user_id');
    });
    if (currentUserId != null) _updateOnlineStatus(true);
  }

  // ==================== تحميل وضع الثيم ====================
  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode');
    if (saved != null) {
      setState(() {
        _themeMode = saved == 'light'
            ? ThemeMode.light
            : saved == 'dark'
                ? ThemeMode.dark
                : ThemeMode.system;
      });
    }
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    String value;
    if (mode == ThemeMode.light)
      value = 'light';
    else if (mode == ThemeMode.dark)
      value = 'dark';
    else
      value = 'system';
    await prefs.setString('theme_mode', value);
  }

  void _toggleTheme() {
    setState(() {
      if (_themeMode == ThemeMode.light) {
        _themeMode = ThemeMode.dark;
      } else if (_themeMode == ThemeMode.dark) {
        _themeMode = ThemeMode.system;
      } else {
        _themeMode = ThemeMode.light;
      }
      _saveThemeMode(_themeMode);
    });
  }

  @override
  void dispose() {
    _updateOnlineStatus(false);
    WidgetsBinding.instance.removeObserver(this);
    _hideIncomingCallOverlay();
    // إزالة مستمعي المكالمات
    CallManager().onIncomingCall = null;
    CallManager().onCallStarted = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (currentUserId == null) return;
    if (state == AppLifecycleState.resumed) {
      _updateOnlineStatus(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _updateOnlineStatus(false);
    }
  }

  Future<void> _updateOnlineStatus(bool isOnline) async {
    if (currentUserId == null) return;
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/users/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': currentUserId, 'is_online': isOnline}),
      );
    } catch (e) {
      debugPrint("Error updating status: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemeNotifier(
      themeMode: _themeMode,
      toggleTheme: _toggleTheme,
      child: MaterialApp(
        navigatorKey: navigatorKey, // ربط المفتاح للوصول إلى الـ Navigator
        debugShowCheckedModeBanner: false,
        title: 'Scopesky',
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        themeMode: _themeMode,
        home: const SplashScreen(),
      ),
    );
  }

  // ==================== الثيم الفاتح المُحسَّن ====================
  ThemeData _buildLightTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: Brightness.light,
    );

    return ThemeData(
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 0.5,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF1E293B),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Color(0xFF64748B)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF3B82F6),
        foregroundColor: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Color(0xFF64748B)),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Color(0xFF1E293B)),
        bodyMedium: TextStyle(color: Color(0xFF334155)),
      ),
    );
  }

  // ==================== الثيم الداكن المُحسَّن ====================
  ThemeData _buildDarkTheme() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF3B82F6),
      brightness: Brightness.dark,
    );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      cardTheme: CardTheme(
        color: const Color(0xFF1E293B),
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white70),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF3B82F6),
        foregroundColor: Colors.white,
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
      ),
    );
  }
}