import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Login_Screen.dart';
import 'Homescreen.dart';
import 'package:fitst_app/main.dart'; // 🟢 تأكد من عمل import لـ main لاستدعاء التحديث الكروي

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    checkAuth();
  }

  Future<void> checkAuth() async {
    // 1️⃣ تأخير بسيط لعرض شعار الترحيب والأنيميشن الخاص بك
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // 2️⃣ إجبار ملف main.dart على قراءة حالة الحساب وتحديث الذاكرة فوراً ليتزامن مع السيرفر
    await MyApp.of(context)?.refreshUser();

    final prefs = await SharedPreferences.getInstance();
    final String? storedId = prefs.getString('user_id');

    if (!mounted) return;

    // 3️⃣ الانتقال الآمن والنظيف بناءً على النتيجة
    if (storedId == null || storedId.isEmpty) {
      _navigateToLogin();
    } else {
      _navigateToHome(storedId);
    }
  }

  void _navigateToHome(String userId) {
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => Homescreen(currentUserId: userId),
        ),
        (route) => false, // يمسح الـ Splash تماماً من الذاكرة لمنع الرجوع إليها
      );
    }
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false, // يمسح الـ Splash تماماً من الذاكرة لمنع الرجوع إليها
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff667eea), Color(0xff764ba2)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.rocket_launch, size: 80, color: Colors.white),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                "Scopesky Chats",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
