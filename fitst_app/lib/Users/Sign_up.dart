import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:fitst_app/main.dart'; // ✅ استيراد ApiConfig و ThemeNotifier

class SignUpPage extends StatefulWidget {
  final int? currentUserId;
  const SignUpPage({Key? key, this.currentUserId}) : super(key: key);

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String? selectedJob;
  String? userId;

  final List<String> availablePermissions = [
    "بدون صلاحيات",
    "ادارة المستخدمين",
    "رفع التبليغات",
    "رفع التذاكر",
    "رفع مشاكل المكتب",
    "المنسق",
  ];

  List<String> selectedPermissions = [];

  final List<String> jobsMenu = [
    "مدير عام",
    "محاسب",
    "مهندس تقني",
    "موظف مبيعات",
    "عامل مكتب",
    "سائق",
  ];

  bool isRegistering = false;
  bool isPasswordHidden = true;
  bool isConfirmPasswordHidden = true;

  // ✅ استخدام ApiConfig.baseUrl بدلاً من الـ IP الثابت
  String get serverBaseUrl => ApiConfig.baseUrl;

  String get signupUrl => "$serverBaseUrl/users/signup";
  String get healthUrl => "$serverBaseUrl/health";

  Future<bool> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse(healthUrl))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> signUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (selectedPermissions.isEmpty) {
      _showSnackBar("يرجى اختيار صلاحية واحدة على الأقل");
      return;
    }

    setState(() => isRegistering = true);
    final connected = await testConnection();
    if (!connected) {
      _showSnackBar("لا يمكن الاتصال بالسيرفر");
      setState(() => isRegistering = false);
      return;
    }

    try {
      final response = await http.post(
        Uri.parse(signupUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": nameController.text.trim(),
          "email": emailController.text.trim(),
          "phone": phoneController.text.trim(),
          "job": selectedJob,
          "password": passwordController.text.trim(),
          "permissions": selectedPermissions,
        }),
      );

      if (response.statusCode == 200) {
        _showSnackBar("✅ تم إنشاء الحساب بنجاح");
        _formKey.currentState!.reset();
        setState(() {
          selectedJob = null;
          selectedPermissions = [];
        });
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      _showSnackBar("❌ خطأ: ${e.toString()}");
    } finally {
      setState(() => isRegistering = false);
    }
  }

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
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      hintStyle: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600]),
    );
  }

  void _showMultiSelect() async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            return AlertDialog(
              title: Text(
                "اختر الصلاحيات",
                style: TextStyle(color: colorScheme.primary),
              ),
              backgroundColor: colorScheme.surface,
              content: SingleChildScrollView(
                child: ListBody(
                  children: availablePermissions.map((perm) {
                    bool hasGeneralPermission =
                        selectedPermissions.contains("بدون صلاحيات") ||
                            selectedPermissions.contains("صلاحيات كاملة");
                    bool isThisPermGeneral =
                        (perm == "بدون صلاحيات" || perm == "صلاحيات كاملة");
                    bool isDisabled = false;
                    if (hasGeneralPermission &&
                        !selectedPermissions.contains(perm)) {
                      isDisabled = true;
                    } else if (!isThisPermGeneral && hasGeneralPermission) {
                      isDisabled = true;
                    } else if (isThisPermGeneral &&
                        selectedPermissions.isNotEmpty &&
                        !selectedPermissions.contains(perm)) {
                      isDisabled = true;
                    }

                    return CheckboxListTile(
                      value: selectedPermissions.contains(perm),
                      title: Text(
                        perm,
                        style: TextStyle(
                          color:
                              isDisabled ? Colors.grey : colorScheme.onSurface,
                        ),
                      ),
                      activeColor: colorScheme.primary,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: isDisabled
                          ? null
                          : (checked) {
                              setDialogState(() {
                                if (checked!) {
                                  selectedPermissions.add(perm);
                                } else {
                                  selectedPermissions.remove(perm);
                                }
                              });
                              setState(() {});
                            },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    "موافق",
                    style: TextStyle(color: colorScheme.primary),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "إنشاء حساب جديد",
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
                  Icon(
                    Icons.person_add_rounded,
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
                          // ===== الاسم الكامل =====
                          TextFormField(
                            controller: nameController,
                            decoration: inputStyle(
                              "الاسم الكامل",
                              Icons.person,
                              colorScheme,
                            ),
                            style: TextStyle(color: colorScheme.onSurface),
                            validator: (v) =>
                                v!.isEmpty ? "يرجى إدخال الاسم الكامل" : null,
                          ),
                          const SizedBox(height: 15),

                          // ===== المسمى الوظيفي =====
                          DropdownButtonFormField<String>(
                            value: selectedJob,
                            decoration: inputStyle(
                              "المسمى الوظيفي",
                              Icons.work,
                              colorScheme,
                            ),
                            dropdownColor:
                                isDark ? Colors.grey[800] : Colors.white,
                            style: TextStyle(color: colorScheme.onSurface),
                            items: jobsMenu
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) =>
                                setState(() => selectedJob = val),
                            validator: (v) =>
                                v == null ? "يرجى اختيار المسمى الوظيفي" : null,
                          ),
                          const SizedBox(height: 15),

                          // ===== الصلاحيات =====
                          GestureDetector(
                            onTap: _showMultiSelect,
                            child: InputDecorator(
                              decoration: inputStyle(
                                "صلاحيات المستخدم",
                                Icons.add_circle_outline,
                                colorScheme,
                              ),
                              child: Text(
                                selectedPermissions.isEmpty
                                    ? "اضغط لإضافة الصلاحيات"
                                    : selectedPermissions.join(" , "),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),

                          // ===== البريد الإلكتروني =====
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

                          // ===== رقم الهاتف =====
                          TextFormField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: inputStyle(
                              "رقم الهاتف",
                              Icons.phone,
                              colorScheme,
                            ),
                            style: TextStyle(color: colorScheme.onSurface),
                            validator: (v) =>
                                v!.isEmpty ? "يرجى إدخال رقم الهاتف" : null,
                          ),
                          const SizedBox(height: 15),

                          // ===== كلمة المرور =====
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
                          const SizedBox(height: 15),

                          // ===== تأكيد كلمة المرور =====
                          TextFormField(
                            controller: confirmPasswordController,
                            obscureText: isConfirmPasswordHidden,
                            decoration: inputStyle(
                              "تأكيد كلمة المرور",
                              Icons.lock_outline,
                              colorScheme,
                            ).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  isConfirmPasswordHidden
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  color: colorScheme.primary,
                                ),
                                onPressed: () => setState(
                                  () => isConfirmPasswordHidden =
                                      !isConfirmPasswordHidden,
                                ),
                              ),
                            ),
                            style: TextStyle(color: colorScheme.onSurface),
                            validator: (v) => v != passwordController.text
                                ? "كلمات المرور غير متطابقة"
                                : null,
                          ),
                          const SizedBox(height: 30),

                          // ===== زر إنشاء الحساب =====
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
                              onPressed: isRegistering ? null : signUp,
                              child: isRegistering
                                  ? const CircularProgressIndicator(
                                      color: Colors.white,
                                    )
                                  : const Text(
                                      "إنشاء الحساب",
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
