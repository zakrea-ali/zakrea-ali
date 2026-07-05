import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fitst_app/Model/ChatModel.dart';
import 'package:fitst_app/screens/IndividualPage.dart';
import 'package:fitst_app/CustomUI/ProfilePage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fitst_app/main.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class Status extends StatefulWidget {
  final String currentUserId;
  final IO.Socket? socket;
  const Status({Key? key, required this.currentUserId, this.socket})
      : super(key: key);

  @override
  State<Status> createState() => _SelectStatus();
}

class _SelectStatus extends State<Status> {
  List<dynamic> users = [];
  List<dynamic> filteredUsers = [];
  bool isLoading = true;
  bool isMeActive = false;
  bool serverError = false;

  String get baseAddress => ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    try {
      final response = await http
          .get(Uri.parse("$baseAddress/users"))
          .timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final myData = data.firstWhere(
          (u) => u['id'].toString() == widget.currentUserId,
          orElse: () => null,
        );

        if (mounted) {
          setState(() {
            serverError = false;
            if (myData != null) isMeActive = myData['active'] ?? false;
            users = data
                .where((user) => user['id'].toString() != widget.currentUserId)
                .toList();
            filteredUsers = users;
            isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          serverError = true;
        });
      }
    }
  }

  Future<void> _toggleMyStatus(bool status) async {
    try {
      final response = await http.post(
        Uri.parse("$baseAddress/users/update_active"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": widget.currentUserId,
          "active_status": status,
        }),
      );

      if (response.statusCode == 200) {
        setState(() => isMeActive = status);
        _showSnackBar(
            status ? "تم التبديل إلى متوفر" : "تم التبديل إلى غير متوفر");
      } else {
        _showSnackBar("فشل تحديث الحالة (رمز ${response.statusCode})");
      }
    } catch (e) {
      _showSnackBar("خطأ في الاتصال: $e");
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _navigateToProfile(dynamic user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfilePage(userData: user, isReadOnly: true),
      ),
    );
  }

  void _navigateToChat(dynamic user) {
    // ✅ التحقق من وجود socket
    if (widget.socket == null) {
      _showSnackBar("لا يمكن الاتصال بالخادم حالياً");
      return;
    }

    // ✅ إنشاء ChatModel مع قيم افتراضية لتجنب null
    final chatModel = ChatModel(
      id: user['id']?.toString() ?? '',
      name: user['username'] ?? 'مستخدم',
      icon: user['avatar_url'] ??
          '', // إذا كان الحقل يقبل null، استخدم null بدلاً من ''، لكن الأفضل استخدام ''
      isGroup: false,
      status: user['job'] ?? '',
      createdBy: '',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IndividualPage(
          chatmodel: chatModel,
          currentUserId: widget.currentUserId,
          existingSocket: widget.socket!, // الآن مضمون أنه غير null
        ),
      ),
    );
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
        leadingWidth: 150,
        leading: Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: isMeActive,
                  activeColor: Colors.green,
                  onChanged: (value) => _toggleMyStatus(value),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isMeActive ? "متوفر" : "غير متوفر",
                    style: TextStyle(
                      color: isMeActive ? Colors.green : Colors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    "حالة العضو",
                    style: TextStyle(color: Colors.grey, fontSize: 8),
                  ),
                ],
              ),
            ],
          ),
        ),
        title: null,
        centerTitle: false,
        actions: [],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchUsers,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filteredUsers.length,
                itemBuilder: (context, index) {
                  final user = filteredUsers[index];
                  final bool isActive = user['active'] == true;

                  // ✅ تجنب null في رابط الصورة
                  final avatarUrl = user['avatar_url'];
                  final imageUrl = (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? "$baseAddress/uploads/$avatarUrl"
                      : null;

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isDark ? Colors.white12 : Colors.grey.shade200,
                      ),
                    ),
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 8,
                      ),
                      leading: GestureDetector(
                        onTap: () => _navigateToProfile(user),
                        child: CircleAvatar(
                          radius: 28,
                          backgroundColor: colorScheme.primary.withOpacity(0.1),
                          backgroundImage:
                              imageUrl != null ? NetworkImage(imageUrl) : null,
                          child: imageUrl == null
                              ? Text(
                                  (user['username'] ?? "U")[0].toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      title: Text(
                        user['username'] ?? "مستخدم",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          user['job'] ?? "لا توجد وظيفة",
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.grey[700],
                          ),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              isActive ? "متوفر" : "غير متوفر",
                              style: TextStyle(
                                color: isActive ? Colors.green : Colors.grey,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert,
                              size: 20,
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                            onSelected: (value) {
                              if (value == 'profile') _navigateToProfile(user);
                              if (value == 'message') _navigateToChat(user);
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'profile',
                                child: Text("عرض الملف الشخصي"),
                              ),
                              const PopupMenuItem(
                                value: 'message',
                                child: Text("إرسال رسالة"),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => _navigateToChat(user),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
