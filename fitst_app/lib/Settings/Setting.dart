import 'package:flutter/material.dart';
import 'package:fitst_app/screens/Login_Screen.dart';

class SettingPage extends StatelessWidget {
  const SettingPage({super.key, required Null Function() onLogout});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // قائمة عناصر الإعدادات (بدون الملف الشخصي)
    final List<SettingsItem> settingsItems = [
      SettingsItem(
        title: "الإشعارات",
        icon: Icons.notifications_none,
        color: Colors.orange,
        type: SettingsType.notifications,
      ),
      SettingsItem(
        title: "الخصوصية",
        icon: Icons.lock_outline,
        color: Colors.green,
        type: SettingsType.privacy,
      ),
      SettingsItem(
        title: "تسجيل الخروج",
        icon: Icons.logout,
        color: Colors.red,
        type: SettingsType.signOut,
      ),
    ];

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          "الإعدادات",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // تم إزالة بطاقة الملف الشخصي
          ...settingsItems.map(
            (item) => _buildSettingsCard(context, item, colorScheme, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(
    BuildContext context,
    SettingsItem item,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final isSignOut = item.type == SettingsType.signOut;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: item.color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(item.icon, color: item.color, size: 22),
        ),
        title: Text(
          item.title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isSignOut ? Colors.red : colorScheme.onSurface,
          ),
        ),
        trailing: Icon(
          isSignOut ? Icons.logout : Icons.arrow_forward_ios,
          size: 18,
          color: isSignOut ? Colors.red : colorScheme.onSurfaceVariant,
        ),
        onTap: () async {
          if (isSignOut) {
            await _showSignOutDialog(context);
          } else {
            _handleOtherOptions(context, item.type);
          }
        },
      ),
    );
  }

  Future<void> _showSignOutDialog(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: const Text("تسجيل الخروج"),
        content: const Text("هل أنت متأكد من رغبتك في تسجيل الخروج؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("إلغاء", style: TextStyle(color: colorScheme.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "تسجيل الخروج",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        // هنا يمكن استدعاء API لتحديث حالة المستخدم (غير متصل)
        // await BackendService.updateUserStatus(userId, isOnline: false);

        // مسح البيانات المحلية إذا لزم الأمر
        // await SharedPreferences.getInstance().then((prefs) => prefs.clear());

        if (context.mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("حدث خطأ أثناء تسجيل الخروج: $e")),
        );
      }
    }
  }

  void _handleOtherOptions(BuildContext context, SettingsType type) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("جاري تطوير ${_getTypeName(type)}..."),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _getTypeName(SettingsType type) {
    switch (type) {
      case SettingsType.notifications:
        return "الإشعارات";
      case SettingsType.privacy:
        return "الخصوصية";
      default:
        return "";
    }
  }
}

enum SettingsType { notifications, privacy, signOut }

class SettingsItem {
  final String title;
  final IconData icon;
  final Color color;
  final SettingsType type;

  SettingsItem({
    required this.title,
    required this.icon,
    required this.color,
    required this.type,
  });
}
