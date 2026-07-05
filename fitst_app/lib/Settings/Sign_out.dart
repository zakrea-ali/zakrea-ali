import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fitst_app/screens/Login_Screen.dart';
import 'package:fitst_app/main.dart'; // 🟢 مهم جداً لاستدعاء MyApp

class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: Colors.blue[300],
      ),
      body: Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: const Text("Sign Out"),
          onPressed: () async {
            try {
              // ✅ 1. مسح جميع البيانات المخزنة محلياً (SharedPreferences)
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear(); // يمسح كل المفاتيح المخزنة بما فيها user_id

              // ✅ 2. تصفير الحساب وإعلام ملف main.dart فوراً بالتغيير
              if (context.mounted) {
                // استدعاء دالة refreshUser المضافة في main.dart لتصفير المعرف القديم من الذاكرة
                await MyApp.of(context)?.refreshUser();
              }

              // ✅ 3. الانتقال إلى LoginPage وإزالة كل الصفحات السابقة
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false, // يزيل كل الصفحات من الـ stack لمنع الرجوع
                );
              }
            } catch (e) {
              debugPrint("فشل تسجيل الخروج: $e");
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("فشل تسجيل الخروج")),
                );
              }
            }
          },
        ),
      ),
    );
  }
}
