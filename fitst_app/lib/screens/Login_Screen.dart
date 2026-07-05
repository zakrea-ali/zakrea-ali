import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fitst_app/screens/Homescreen.dart';
import 'package:fitst_app/main.dart'; // لاستخدام ApiConfig و ThemeNotifier و MyApp

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoggingIn = false;
  bool isPasswordHidden = true;
  String? userId;

  String get serverBaseUrl => ApiConfig.baseUrl;

  String get loginUrl => "$serverBaseUrl/users/login";
  String get healthUrl => "$serverBaseUrl/health";
  String get statusUrl => "$serverBaseUrl/users/update_status";

  // ==================== اختبار الاتصال بالخادم ====================
  Future<bool> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse(healthUrl))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['status'] == "ok";
      }
      return false;
    } catch (e) {
      debugPrint("❌ فشل اختبار الاتصال: $e");
      return false;
    }
  }

  // ==================== دالة تسجيل الدخول ====================
  Future<void> login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoggingIn = true);

    final connected = await testConnection();
    if (!connected) {
      _showSnackBar("⚠️ تعذر الاتصال بالسيرفر، تأكد من تشغيل Node.js");
      setState(() => isLoggingIn = false);
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse(loginUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "email": emailController.text.trim(),
              "password": passwordController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['user'] != null) {
          final user = data['user'];
          userId = user['id'].toString();

          // ==================== حفظ بيانات المستخدم محلياً ====================
          final prefs = await SharedPreferences.getInstance();

          await prefs.setString('user_id', userId!);
          await prefs.setString(
            'username',
            user['username']?.toString() ?? "User",
          );
          await prefs.setString('email', user['email']?.toString() ?? "");
          await prefs.setString(
            'avatar_url',
            user['avatar_url']?.toString() ?? "",
          );
          await prefs.setString('job', user['job']?.toString() ?? "");
          await prefs.setString('phone', user['phone']?.toString() ?? "");

          // حفظ الصلاحيات
          if (user['permissions'] != null) {
            List<String> perms = (user['permissions'] as List)
                .map((item) => item.toString())
                .toList();
            await prefs.setStringList('permissions', perms);
          }

          // حفظ الدور
          if (user['role'] != null) {
            await prefs.setString('role', user['role'].toString());
          } else {
            await prefs.setString('role', 'user');
          }

          _showSnackBar("✅ تم تسجيل الدخول بنجاح");

          // 🟢 1. تحديث حالة التطبيق الكبرى والسيرفر بالخلفية
          if (mounted) {
            await MyApp.of(context)?.refreshUser();
          }

          // 🟢 2. أمر النقل الفعلي والصريح إلى صفحة الهوم ومسح الـ Stack تماماً
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => Homescreen(currentUserId: userId!),
              ),
              (route) => false,
            );
          }
        } else {
          _showSnackBar("❌ بيانات المستخدم غير موجودة");
        }
      } else if (response.statusCode == 401) {
        _showSnackBar("❌ البريد الإلكتروني أو كلمة المرور غير صحيحة");
      } else if (response.statusCode == 500) {
        _showSnackBar("❌ خطأ داخلي في السيرفر (500)");
      } else {
        _showSnackBar("❌ فشل تسجيل الدخول: ${response.statusCode}");
      }
    } catch (e) {
      _showSnackBar("❌ خطأ في الاتصال: ${e.toString()}");
      debugPrint("❌ خطأ في تسجيل الدخول: $e");
    } finally {
      if (mounted) setState(() => isLoggingIn = false);
    }
  }

  // ==================== تحديث حالة الاتصال ====================
  Future<void> updateStatus(bool isOnline) async {
    if (userId == null) return;
    try {
      await http
          .post(
            Uri.parse(statusUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"user_id": userId, "is_online": isOnline}),
          )
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint("⚠️ Error updating status: $e");
    }
  }

  // ==================== عرض رسائل ====================
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ==================== تصميم الحقول ====================
  InputDecoration inputStyle(
    String hint,
    IconData icon,
    ColorScheme colorScheme,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: colorScheme.primary),
      filled: true,
      fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
      contentPadding: const EdgeInsets.symmetric(vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      hintStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600]),
    );
  }

  // ==================== واجهة المستخدم ====================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "تسجيل الدخول",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: Colors.white,
            ),
            onPressed: () {
              final notifier = ThemeNotifier.of(context);
              notifier?.toggleTheme();
            },
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.primary, colorScheme.primary.withOpacity(0.7)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Icon(
                    Icons.lock_person_rounded,
                    size: 90,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 30),
                  Container(
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // ===== حقل البريد الإلكتروني =====
                          TextFormField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: inputStyle(
                              "البريد الإلكتروني",
                              Icons.email,
                              colorScheme,
                            ),
                            style: TextStyle(color: colorScheme.onSurface),
                            validator: (v) => v!.isEmpty
                                ? "يرجى إدخال البريد الإلكتروني"
                                : null,
                          ),
                          const SizedBox(height: 15),

                          // ===== حقل كلمة المرور =====
                          TextFormField(
                            controller: passwordController,
                            obscureText: isPasswordHidden,
                            decoration: inputStyle(
                              "كلمة المرور",
                              Icons.lock,
                              colorScheme,
                            ).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  isPasswordHidden
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: colorScheme.primary,
                                ),
                                onPressed: () => setState(
                                  () => isPasswordHidden = !isPasswordHidden,
                                ),
                              ),
                            ),
                            style: TextStyle(color: colorScheme.onSurface),
                            validator: (v) =>
                                v!.isEmpty ? "يرجى إدخال كلمة المرور" : null,
                          ),
                          const SizedBox(height: 30),

                          // ===== زر تسجيل الدخول =====
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                elevation: 5,
                              ),
                              onPressed: isLoggingIn ? null : login,
                              child: isLoggingIn
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : const Text(
                                      "دخول",
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
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
