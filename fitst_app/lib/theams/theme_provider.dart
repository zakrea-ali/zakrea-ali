import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode {
    if (_themeMode == ThemeMode.system) {
      // نرجع القيمة الحالية للنظام، لكننا لا نستطيع هنا. سنتعامل معها في MaterialApp.
      // عادةً نستخدم MediaQuery أو نعتمد على المتغير. سنبسط: نعتبر system = light افتراضياً.
      // الأفضل إدارة هذا عبر State أو تمرير context. لكن للتبسيط:
      return false;
    }
    return _themeMode == ThemeMode.dark;
  }

  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
  }
}
