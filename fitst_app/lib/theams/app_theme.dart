import 'package:flutter/material.dart';

class AppColors {
  // الألوان للوضع الفاتح
  static const Color primaryLight = Color(0xFF075E54);
  static const Color secondaryLight = Color(0xFF25D366);
  static const Color backgroundLight = Color(0xFFE5DDD5);
  static const Color myMessageLight = Color(0xFFDCF8C6);
  static const Color otherMessageLight = Colors.white;
  static const Color inputBgLight = Colors.white;
  static const Color textLight = Color(0xFF000000);

  // الألوان للوضع الداكن
  static const Color primaryDark = Color(0xFF1F2C25);
  static const Color secondaryDark = Color(0xFF00A884);
  static const Color backgroundDark = Color(0xFF0A0A0A);
  static const Color myMessageDark = Color(0xFF1F2C25);
  static const Color otherMessageDark = Color(0xFF262626);
  static const Color inputBgDark = Color(0xFF1E1E1E);
  static const Color textDark = Color(0xFFFFFFFF);
}

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: AppColors.primaryLight,
    scaffoldBackgroundColor: AppColors.backgroundLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primaryLight,
      elevation: 0,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 20),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.inputBgLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: BorderSide.none,
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: AppColors.primaryDark,
    scaffoldBackgroundColor: AppColors.backgroundDark,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      elevation: 0,
      titleTextStyle: TextStyle(color: Colors.white, fontSize: 20),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.inputBgDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(25),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
