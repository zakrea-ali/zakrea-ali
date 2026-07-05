import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fitst_app/Users/Sign_up.dart';
import 'package:fitst_app/main.dart'; // ✅ استيراد ApiConfig

class UsersManagementPage extends StatefulWidget {
  const UsersManagementPage({Key? key}) : super(key: key);

  @override
  State<UsersManagementPage> createState() => _UsersManagementPageState();
}

class _UsersManagementPageState extends State<UsersManagementPage> {
  List<dynamic> allUsers = [];
  List<dynamic> filteredUsers = [];
  bool isLoading = true;
  bool isSearching = false;
  TextEditingController searchController = TextEditingController();

  // ✅ استخدام ApiConfig.baseUrl بدلاً من الـ IP الثابت
  String get baseUrl => ApiConfig.baseUrl;

  String? _getFullAvatarUrl(String? url) {
    if (url == null || url.isEmpty || url == "null") return null;
    if (url.startsWith('http')) return url;
    String path = url.startsWith('/') ? url : "/uploads/$url";
    return "$baseUrl$path";
  }

  @override
  void initState() {
    super.initState();
    fetchUsers();
  }

  Future<void> fetchUsers() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/users"));
      if (response.statusCode == 200) {
        setState(() {
          allUsers = jsonDecode(response.body);
          filteredUsers = allUsers;
          isLoading = false;
        });
      }
    } catch (e) {
      _showSnackBar("خطأ في جلب البيانات: $e");
    }
  }

  void _filterUsers(String query) {
    setState(() {
      filteredUsers = allUsers.where((user) {
        final name = user['username'].toString().toLowerCase();
        final email = user['email'].toString().toLowerCase();
        final job = (user['job'] ?? "").toString().toLowerCase();
        final searchLower = query.toLowerCase();
        return name.contains(searchLower) ||
            email.contains(searchLower) ||
            job.contains(searchLower);
      }).toList();
    });
  }

  Future<void> deleteUser(String id) async {
    if (id.isEmpty || id == "null") return;
    try {
      final response = await http.delete(Uri.parse("$baseUrl/users/$id"));
      if (response.statusCode == 200) {
        _showSnackBar("تم حذف المستخدم بنجاح");
        fetchUsers();
      }
    } catch (e) {
      _showSnackBar("خطأ في الحذف: $e");
    }
  }

  Future<void> updateUser(String id, Map<String, dynamic> data) async {
    if (id.isEmpty || id == "null") return;
    try {
      final response = await http.put(
        Uri.parse("$baseUrl/users/$id"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      );
      if (response.statusCode == 200) {
        _showSnackBar("تم التحديث بنجاح");
        fetchUsers();
      }
    } catch (e) {
      _showSnackBar("خطأ في التحديث: $e");
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: null,
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(
              isSearching ? Icons.close : Icons.search,
              color: colorScheme.primary,
            ),
            onPressed: () {
              setState(() {
                isSearching = !isSearching;
                if (!isSearching) {
                  searchController.clear();
                  filteredUsers = allUsers;
                } else {
                  Future.delayed(Duration.zero, () {
                    FocusScope.of(context).requestFocus(FocusNode());
                  });
                }
              });
            },
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SignUpPage()),
            ).then((_) => fetchUsers()),
            icon: Icon(Icons.person_add_alt_1, color: colorScheme.primary),
          ),
        ],
        bottom: isSearching
            ? PreferredSize(
                preferredSize: const Size.fromHeight(70),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: "ابحث عن اسم، وظيفة، أو إيميل...",
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[500],
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: colorScheme.primary.withOpacity(0.7),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                      style: TextStyle(color: colorScheme.onSurface),
                      onChanged: _filterUsers,
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : filteredUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_off,
                        size: 70,
                        color: isDark ? Colors.white30 : Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "لا يوجد مستخدمون مطابقون",
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: filteredUsers.length,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemBuilder: (context, index) {
                    final user = filteredUsers[index];
                    final String? fullImageUrl = _getFullAvatarUrl(
                      user['avatar_url'],
                    );
                    final bool isOnline = user['is_online'] == true;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        color: isDark ? Colors.grey[850] : Colors.white,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {},
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            child: Row(
                              children: [
                                // الصورة الرمزية مع حالة الاتصال
                                Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundColor:
                                          colorScheme.primary.withOpacity(0.1),
                                      backgroundImage: (fullImageUrl != null &&
                                              fullImageUrl.isNotEmpty)
                                          ? NetworkImage(fullImageUrl)
                                          : null,
                                      child: (fullImageUrl == null ||
                                              fullImageUrl.isEmpty)
                                          ? Text(
                                              (user['username'] ?? "U")[0]
                                                  .toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.primary,
                                              ),
                                            )
                                          : null,
                                    ),
                                    Positioned(
                                      bottom: 2,
                                      right: 2,
                                      child: Container(
                                        height: 14,
                                        width: 14,
                                        decoration: BoxDecoration(
                                          color: isOnline
                                              ? Colors.green
                                              : Colors.grey[400],
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isDark
                                                ? Colors.grey[850]!
                                                : Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                // المعلومات
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user['username'] ?? "بدون اسم",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "الوظيفة: ${user['job'] ?? 'غير محددة'}",
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark
                                              ? Colors.white60
                                              : Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "الإيميل: ${user['email']}",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.grey[500],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                // أزرار التعديل والحذف
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit_note,
                                        color: colorScheme.primary,
                                      ),
                                      onPressed: () => _showEditDialog(user),
                                      splashRadius: 24,
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_sweep,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () =>
                                          _confirmDelete(user['id'].toString()),
                                      splashRadius: 24,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  void _showEditDialog(dynamic user) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final nameCtrl = TextEditingController(text: user['username']);
    final emailCtrl = TextEditingController(text: user['email']);
    final phoneCtrl = TextEditingController(text: user['phone'] ?? "");
    final jobCtrl = TextEditingController(text: user['job'] ?? "");
    final passCtrl = TextEditingController();
    List<String> userPerms = List<String>.from(user['permissions'] ?? []);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: colorScheme.surface,
          title: Text(
            "تعديل بيانات المستخدم",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(
                  nameCtrl,
                  "اسم المستخدم",
                  Icons.person_outline,
                  colorScheme,
                  isDark,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  emailCtrl,
                  "البريد الإلكتروني",
                  Icons.email_outlined,
                  colorScheme,
                  isDark,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  phoneCtrl,
                  "رقم الهاتف",
                  Icons.phone_android,
                  colorScheme,
                  isDark,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  jobCtrl,
                  "الوظيفة",
                  Icons.badge_outlined,
                  colorScheme,
                  isDark,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  passCtrl,
                  "كلمة مرور جديدة (اختياري)",
                  Icons.lock_outline,
                  colorScheme,
                  isDark,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "الصلاحيات",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const Divider(),
                      ...[
                        "ادارة المستخدمين",
                        "رفع التبليغات",
                        "رفع التذاكر",
                        "عرض حالات صيانة الموقع",
                        "عرض حالات صيانة اجهزة الموقع",
                      ].map((p) {
                        return CheckboxListTile(
                          title: Text(
                            p,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: userPerms.contains(p),
                          onChanged: (bool? value) {
                            setDialogState(() {
                              value! ? userPerms.add(p) : userPerms.remove(p);
                            });
                          },
                          activeColor: colorScheme.primary,
                          checkboxShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(5),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "إلغاء",
                style: TextStyle(color: colorScheme.primary, fontSize: 16),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Map<String, dynamic> updateData = {
                  "username": nameCtrl.text.trim(),
                  "email": emailCtrl.text.trim(),
                  "phone": phoneCtrl.text.trim(),
                  "job": jobCtrl.text.trim(),
                  "permissions": userPerms,
                };
                if (passCtrl.text.isNotEmpty)
                  updateData["password"] = passCtrl.text;
                updateUser(user['id'].toString(), updateData);
                Navigator.pop(context);
              },
              child: const Text("حفظ التغييرات"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    IconData icon,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
        prefixIcon: Icon(icon, color: colorScheme.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        filled: true,
        fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 12,
        ),
      ),
      style: TextStyle(color: colorScheme.onSurface),
    );
  }

  void _confirmDelete(String id) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: colorScheme.surface,
        title: Text(
          "تأكيد الحذف",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        content: Text(
          "هل أنت متأكد أنك تريد حذف هذا المستخدم نهائياً؟",
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("إلغاء", style: TextStyle(color: colorScheme.primary)),
          ),
          TextButton(
            onPressed: () {
              deleteUser(id);
              Navigator.pop(context);
            },
            child: const Text(
              "حذف",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
