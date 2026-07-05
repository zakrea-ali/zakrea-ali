import 'package:flutter/material.dart';
import 'package:fitst_app/main.dart'; // للوصول إلى الثيم والتبديل

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "عن التطبيق",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: colorScheme.primary,
            ),
            onPressed: () {
              final notifier = ThemeNotifier.of(context);
              notifier?.toggleTheme();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ===== الشعار =====
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primary,
                    colorScheme.primary.withOpacity(0.7)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                size: 50,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Chats Office",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "تطبيق تواصل اجتماعي متكامل",
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 30),
            Divider(
              color: isDark ? Colors.grey[700] : Colors.grey[300],
              thickness: 1,
            ),
            const SizedBox(height: 25),

            // ===== معلومات المطور =====
            const Text(
              "المطور",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            CircleAvatar(
              radius: 50,
              backgroundColor: colorScheme.primary.withOpacity(0.1),
              child: const Icon(
                Icons.person,
                size: 60,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "زكريا علي راشد",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Zakaria Ali Rashid",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSocialIcon(Icons.email, "zakrea.ali@gmail.com"),
                const SizedBox(width: 20),
                _buildSocialIcon(Icons.code, "GitHub"),
              ],
            ),
            const SizedBox(height: 30),
            Divider(
              color: isDark ? Colors.grey[700] : Colors.grey[300],
              thickness: 1,
            ),
            const SizedBox(height: 25),

            // ===== ميزات التطبيق =====
            const Text(
              "✨ الميزات الرئيسية",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            _buildFeatureItem(
              icon: Icons.chat,
              title: "الدردشة الفورية",
              description: "تواصل مع أصدقائك وزملائك في الوقت الفعلي",
              isDark: isDark,
            ),
            _buildFeatureItem(
              icon: Icons.call,
              title: "المكالمات الصوتية والفيديو",
              description: "مكالمات عالية الجودة عبر الإنترنت",
              isDark: isDark,
            ),
            _buildFeatureItem(
              icon: Icons.group,
              title: "المجموعات",
              description: "أنشئ مجموعات وتواصل مع فريقك",
              isDark: isDark,
            ),
            _buildFeatureItem(
              icon: Icons.assignment,
              title: "التقارير والتذاكر",
              description: "إدارة التقارير وتذاكر الصيانة بسهولة",
              isDark: isDark,
            ),
            _buildFeatureItem(
              icon: Icons.business,
              title: "إدارة المكاتب",
              description: "متابعة حالة المكاتب والورديات",
              isDark: isDark,
            ),
            const SizedBox(height: 30),
            Divider(
              color: isDark ? Colors.grey[700] : Colors.grey[300],
              thickness: 1,
            ),
            const SizedBox(height: 25),

            // ===== معلومات إضافية =====
            const Text(
              "📱 معلومات التطبيق",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            _buildInfoRow(
              title: "الإصدار",
              value: "1.0.0",
              isDark: isDark,
            ),
            _buildInfoRow(
              title: "النظام الأساسي",
              value: "Flutter (Android / iOS / Web)",
              isDark: isDark,
            ),
            _buildInfoRow(
              title: "التقنيات المستخدمة",
              value: "Node.js, PostgreSQL, Socket.io",
              isDark: isDark,
            ),
            _buildInfoRow(
              title: "تاريخ الإصدار",
              value: "2026",
              isDark: isDark,
            ),
            const SizedBox(height: 30),
            Divider(
              color: isDark ? Colors.grey[700] : Colors.grey[300],
              thickness: 1,
            ),
            const SizedBox(height: 20),

            // ===== شعار المطور =====
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: colorScheme.primary.withOpacity(0.05),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    "💻 Built with ❤️",
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "© 2025 Zakaria Ali Rashid",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[500] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ===== عنصر الميزات =====
  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF3B82F6), size: 22),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===== عنصر المعلومات =====
  Widget _buildInfoRow({
    required String title,
    required String value,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // ===== أيقونات التواصل =====
  Widget _buildSocialIcon(IconData icon, String label) {
    return InkWell(
      onTap: () {
        // يمكن إضافة روابط هنا
        // مثلاً: فتح البريد الإلكتروني أو رابط GitHub
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
