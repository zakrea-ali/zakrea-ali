// lib/screens/chat_actions/call_manager.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// دالة عامة للاتصال المباشر – يمكن استدعاؤها من أي صفحة
Future<void> makeDirectCall({
  required String userId,
  required String baseUrl,
  required BuildContext context,
}) async {
  try {
    final response = await http.get(Uri.parse("$baseUrl/users"));
    if (response.statusCode != 200) {
      _showError(context, "فشل جلب بيانات المستخدم");
      return;
    }

    final List users = jsonDecode(response.body);
    final user = users.firstWhere(
      (u) => u['id'].toString() == userId.toString(),
      orElse: () => null,
    );

    if (user == null) {
      _showError(context, "المستخدم غير موجود");
      return;
    }

    final String phone = user['phone']?.toString() ?? "";
    if (phone.isEmpty) {
      _showError(context, "رقم الهاتف غير متوفر");
      return;
    }

    final Uri telUri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(telUri)) {
      await launchUrl(telUri);
    } else {
      _showError(context, "لا يمكن إجراء المكالمة");
    }
  } catch (e) {
    _showError(context, "خطأ: ${e.toString()}");
  }
}

void _showError(BuildContext context, String msg) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
}
