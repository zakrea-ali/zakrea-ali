import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:fitst_app/Model/ChatModel.dart';
import 'package:fitst_app/screens/IndividualPage.dart';
import 'package:fitst_app/screens/CreateGroupPage.dart';
import 'package:fitst_app/screens/SelectMembers.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:fitst_app/main.dart';

class ChatPage extends StatefulWidget {
  final String currentUserId;
  final IO.Socket socket;
  final bool showAppBar;
  final String initialSearchQuery;

  const ChatPage({
    Key? key,
    required this.currentUserId,
    required this.socket,
    this.showAppBar = true,
    this.initialSearchQuery = '',
  }) : super(key: key);

  @override
  ChatPageState createState() => ChatPageState();
}

class ChatPageState extends State<ChatPage> {
  List<ChatModel> _allChats = [];
  List<ChatModel> _filteredChats = [];
  bool isLoading = true;
  String _searchQuery = '';

  String get baseUrl => ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.initialSearchQuery;
    _fetchChats();
    _listenToSocketEvents();
  }

  void _listenToSocketEvents() {
    widget.socket.on("message", (data) => _fetchChats());
    widget.socket.on("group_message", (data) => _fetchChats());
  }

  Future<void> _fetchChats() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      // جلب المحادثات الفردية
      final individualUrl = Uri.parse("$baseUrl/chats/${widget.currentUserId}");
      final individualResponse =
          await http.get(individualUrl).timeout(const Duration(seconds: 10));
      List<ChatModel> individualChats = [];
      if (individualResponse.statusCode == 200) {
        final List<dynamic> data = jsonDecode(individualResponse.body);
        individualChats = data.map((item) => ChatModel.fromJson(item)).toList();
      }

      // جلب المجموعات
      final groupsUrl =
          Uri.parse("$baseUrl/groups?user_id=${widget.currentUserId}");
      final groupsResponse =
          await http.get(groupsUrl).timeout(const Duration(seconds: 10));
      List<ChatModel> groupChats = [];
      if (groupsResponse.statusCode == 200) {
        final List<dynamic> data = jsonDecode(groupsResponse.body);
        groupChats = data.map((item) => ChatModel.fromJson(item)).toList();
      }

      // ترتيب تنازلي حسب وقت آخر رسالة (الأحدث أولاً)
      groupChats.sort((a, b) => b.time!.compareTo(a.time!));
      individualChats.sort((a, b) => b.time!.compareTo(a.time!));

      _allChats = [...groupChats, ...individualChats];
      _applyFilter();

      if (mounted) setState(() => isLoading = false);
    } catch (e) {
      _showError("فشل الاتصال بالسيرفر");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // دالة لتحديث عدد غير المقروء بعد فتح المحادثة
  Future<void> _markAsRead(String chatId, bool isGroup) async {
    try {
      final url = isGroup
          ? "$baseUrl/groups/$chatId/read?user_id=${widget.currentUserId}"
          : "$baseUrl/chats/$chatId/read?user_id=${widget.currentUserId}";
      await http.post(Uri.parse(url)).timeout(const Duration(seconds: 5));
      // بعد التحديث، نعيد جلب المحادثات لتحديث العدد
      _fetchChats();
    } catch (e) {
      debugPrint("فشل تحديث حالة القراءة: $e");
    }
  }

  void refreshChats() => _fetchChats();

  void updateSearchQuery(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilter();
    });
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredChats = List.from(_allChats);
    } else {
      _filteredChats = _allChats.where((chat) {
        return chat.name.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return "";
    try {
      final dt = DateTime.parse(timeStr).toLocal();
      return DateFormat('hh:mm a').format(dt);
    } catch (e) {
      return "";
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return "?";
    return name.trim()[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text("Scope Chats"),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _fetchChats,
                ),
              ],
            )
          : null,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredChats.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  itemCount: _filteredChats.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, thickness: 0.5, indent: 70),
                  itemBuilder: (context, index) {
                    final chat = _filteredChats[index];
                    final bool isGroup = chat.isGroup == true;
                    String? fullImageUrl;
                    if (chat.icon != null &&
                        chat.icon!.isNotEmpty &&
                        chat.icon != "null") {
                      fullImageUrl = chat.icon!.startsWith('http')
                          ? chat.icon
                          : "$baseUrl/uploads/${chat.icon}";
                    }

                    return ListTile(
                      onTap: () {
                        // قبل الانتقال، نُعلم الخادم بأن المستخدم قرأ الرسائل
                        _markAsRead(chat.id, isGroup);
                        _navigateToChat(chat);
                      },
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: const Color(0xFFEDE7F6),
                            backgroundImage: fullImageUrl != null
                                ? NetworkImage(fullImageUrl)
                                : null,
                            child: (fullImageUrl == null)
                                ? (isGroup
                                    ? const Icon(
                                        Icons.groups_rounded,
                                        color: Color(0xFF673AB7),
                                        size: 30,
                                      )
                                    : Text(
                                        _getInitials(chat.name),
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF673AB7),
                                        ),
                                      ))
                                : null,
                          ),
                          if (!isGroup && chat.isOnline == true)
                            Positioned(
                              bottom: 2,
                              right: 2,
                              child: Container(
                                height: 13,
                                width: 13,
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          // عرض عدد الرسائل غير المقروءة
                          if (chat.unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              constraints: const BoxConstraints(minWidth: 20),
                              child: Text(
                                chat.unreadCount > 99
                                    ? '99+'
                                    : chat.unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (isGroup) const SizedBox(width: 6),
                          if (isGroup)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "${chat.participants.length}",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                            )
                          else if (chat.isOnline == true)
                            const Text(
                              "online",
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        chat.currentMessage ?? "لا توجد رسائل",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(_formatTime(chat.time)),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    final message = _searchQuery.isEmpty
        ? "لا توجد محادثات أو مجموعات"
        : "لا توجد نتائج لـ '$_searchQuery'";
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchQuery.isEmpty ? Icons.chat_bubble_outline : Icons.search_off,
            size: 70,
            color: Colors.grey,
          ),
          const SizedBox(height: 10),
          Text(message),
          if (_searchQuery.isNotEmpty)
            TextButton(
              onPressed: () => updateSearchQuery(''),
              child: const Text("مسح البحث"),
            ),
          if (_searchQuery.isEmpty)
            TextButton(onPressed: _fetchChats, child: const Text("تحديث")),
        ],
      ),
    );
  }

  void _navigateToChat(ChatModel chat) {
    if (chat.isGroup == true) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CreateGroupPage(
            chatmodel: chat,
            currentUserId: widget.currentUserId,
            baseUrl: baseUrl,
          ),
        ),
      ).then((_) => _fetchChats());
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IndividualPage(
            chatmodel: chat,
            currentUserId: widget.currentUserId,
            existingSocket: widget.socket,
          ),
        ),
      ).then((_) => _fetchChats());
    }
  }
}
