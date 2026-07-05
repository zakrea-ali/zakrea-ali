import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fitst_app/Model/ChatModel.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:fitst_app/main.dart'; // ✅ استيراد ApiConfig

class SelectMembers extends StatefulWidget {
  final String currentUserId;
  final bool multiSelect;
  final Function(List<String>)? onSelectionDone;

  const SelectMembers({
    Key? key,
    required this.currentUserId,
    this.multiSelect = false,
    this.onSelectionDone,
  }) : super(key: key);

  @override
  State<SelectMembers> createState() => _SelectMembersState();
}

class _SelectMembersState extends State<SelectMembers> {
  List<ChatModel> users = [];
  List<ChatModel> filteredUsers = [];
  List<String> selectedIds = [];
  bool isLoading = true;
  String _searchQuery = '';

  // ✅ استخدام ApiConfig.baseUrl بدلاً من التعبير الثلاثي
  String get baseAddress => ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  void _filterUsers() {
    setState(() {
      if (_searchQuery.isEmpty) {
        filteredUsers = List.from(users);
      } else {
        filteredUsers = users.where((user) {
          return user.name.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();
      }
    });
  }

  String _formatLastSeen(String? lastSeenStr) {
    if (lastSeenStr == null || lastSeenStr.isEmpty || lastSeenStr == "null") {
      return "غير متاح";
    }
    try {
      DateTime lastSeen = DateTime.parse(lastSeenStr).toLocal();
      DateTime now = DateTime.now();
      if (lastSeen.day == now.day &&
          lastSeen.month == now.month &&
          lastSeen.year == now.year) {
        return DateFormat('hh:mm a').format(lastSeen);
      } else {
        return DateFormat('yyyy/MM/dd').format(lastSeen);
      }
    } catch (e) {
      return "منذ فترة";
    }
  }

  String? _getFullAvatarUrl(String? url) {
    if (url == null || url.isEmpty || url == "null") return null;
    if (url.startsWith('http')) return url;
    String path = url.startsWith('/') ? url : "/uploads/$url";
    return "$baseAddress$path";
  }

  String _getInitials(String name) {
    if (name.isEmpty) return "?";
    return name.trim()[0].toUpperCase();
  }

  Future<void> _fetchUsers() async {
    try {
      final response = await http.get(Uri.parse("$baseAddress/users"));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        setState(() {
          users = data
              .where((user) => user['id'].toString() != widget.currentUserId)
              .map<ChatModel>(
                (user) => ChatModel(
                  id: user['id']?.toString() ?? '',
                  name: user['username'] ?? 'بدون اسم',
                  icon: user['avatar_url']?.toString() ?? '',
                  status: user['job'] ?? 'لا توجد وظيفة',
                  isOnline: user['is_online'] ?? false,
                  lastSeen: user['last_seen']?.toString() ?? '',
                  permissions: List<String>.from(user['permissions'] ?? []),
                  isGroup: false,
                  participants: [],
                  createdBy: '',
                  time: '',
                  currentMessage: '',
                ),
              )
              .toList();
          filteredUsers = List.from(users);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (selectedIds.contains(userId)) {
        selectedIds.remove(userId);
      } else {
        selectedIds.add(userId);
      }
    });
  }

  void _confirmSelection() {
    if (selectedIds.isEmpty) return;
    widget.onSelectionDone?.call(selectedIds);
    Navigator.pop(context, selectedIds);
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
        title: widget.multiSelect
            ? Text(
                "اختر الأعضاء (${selectedIds.length})",
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
        centerTitle: widget.multiSelect ? true : false,
        actions: widget.multiSelect
            ? [
                TextButton(
                  onPressed: selectedIds.isEmpty ? null : _confirmSelection,
                  child: Text(
                    "تم",
                    style: TextStyle(
                      color: selectedIds.isEmpty
                          ? colorScheme.onSurface.withOpacity(0.3)
                          : colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ]
            : null,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: "بحث...",
                  prefixIcon: Icon(
                    Icons.search,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white54 : Colors.grey[500],
                  ),
                ),
                style: TextStyle(color: colorScheme.onSurface),
                onChanged: (value) {
                  _searchQuery = value;
                  _filterUsers();
                },
              ),
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
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
                      const SizedBox(height: 10),
                      Text(
                        _searchQuery.isEmpty
                            ? "لا توجد جهات اتصال متاحة"
                            : "لا توجد نتائج لـ '$_searchQuery'",
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  itemCount: filteredUsers.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    indent: 70,
                    color: isDark ? Colors.white12 : Colors.grey[200],
                  ),
                  itemBuilder: (context, index) {
                    final user = filteredUsers[index];
                    final bool isOnline = user.isOnline;
                    final String? fullImageUrl = _getFullAvatarUrl(user.icon);
                    final bool isSelected = selectedIds.contains(user.id);

                    if (widget.multiSelect) {
                      return ListTile(
                        onTap: () => _toggleSelection(user.id),
                        leading: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 25,
                              backgroundColor:
                                  colorScheme.primary.withOpacity(0.1),
                              backgroundImage: (fullImageUrl != null &&
                                      fullImageUrl.isNotEmpty)
                                  ? NetworkImage(fullImageUrl)
                                  : null,
                              child:
                                  (fullImageUrl == null || fullImageUrl.isEmpty)
                                      ? Text(
                                          _getInitials(user.name),
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
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOnline
                                      ? Colors.green
                                      : Colors.grey[400],
                                  border: Border.all(
                                    color: colorScheme.surface,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          user.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          user.status,
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.grey[600],
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isOnline)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  "متصل",
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "آخر ظهور",
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.grey[400],
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatLastSeen(user.lastSeen),
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[600],
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(width: 8),
                            Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(user.id),
                              activeColor: colorScheme.primary,
                              checkColor: colorScheme.onPrimary,
                            ),
                          ],
                        ),
                      );
                    } else {
                      return ListTile(
                        onTap: () => Navigator.pop(context, user),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 25,
                              backgroundColor:
                                  colorScheme.primary.withOpacity(0.1),
                              backgroundImage: (fullImageUrl != null &&
                                      fullImageUrl.isNotEmpty)
                                  ? NetworkImage(fullImageUrl)
                                  : null,
                              child:
                                  (fullImageUrl == null || fullImageUrl.isEmpty)
                                      ? Text(
                                          _getInitials(user.name),
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
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOnline
                                      ? Colors.green
                                      : Colors.grey[400],
                                  border: Border.all(
                                    color: colorScheme.surface,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        title: Text(
                          user.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          user.status,
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.grey[600],
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isOnline
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  "متصل",
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "آخر ظهور",
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.grey[400],
                                      fontSize: 10,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatLastSeen(user.lastSeen),
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[600],
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                      );
                    }
                  },
                ),
    );
  }
}
