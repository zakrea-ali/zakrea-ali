import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:fitst_app/Model/ChatModel.dart';
import 'package:fitst_app/screens/SelectMembers.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:fitst_app/screens/IndividualPage.dart';
import 'package:fitst_app/screens/CreateGroupPage.dart';
import 'package:fitst_app/main.dart'; // ✅ استيراد ApiConfig

class ChatPageForForward extends StatefulWidget {
  final String currentUserId;
  final IO.Socket socket;
  final bool showAppBar;
  final String initialSearchQuery;
  final Map<String, dynamic> messageToForward;
  final Function(bool success, String? targetChatName, String? targetChatId)
      onForwardComplete;

  const ChatPageForForward({
    Key? key,
    required this.currentUserId,
    required this.socket,
    this.showAppBar = true,
    this.initialSearchQuery = '',
    required this.messageToForward,
    required this.onForwardComplete,
  }) : super(key: key);

  @override
  State<ChatPageForForward> createState() => _ChatPageForForwardState();
}

class _ChatPageForForwardState extends State<ChatPageForForward> {
  List<ChatModel> _allChats = [];
  List<ChatModel> _filteredChats = [];
  bool isLoading = true;
  String _searchQuery = '';
  bool _isForwarding = false;

  // ✅ استخدام ApiConfig.baseUrl بدلاً من الـ IP الثابت
  String get baseUrl => ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.initialSearchQuery;
    _fetchChats();
    print(
      "🔍 [DIAGNOSTIC] ChatPageForForward opened. Socket connected: ${widget.socket.connected}",
    );
  }

  Future<void> _fetchChats() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final individualUrl = Uri.parse("$baseUrl/chats/${widget.currentUserId}");
      final individualResponse =
          await http.get(individualUrl).timeout(const Duration(seconds: 10));
      List<ChatModel> individualChats = [];
      if (individualResponse.statusCode == 200) {
        final List<dynamic> data = jsonDecode(individualResponse.body);
        individualChats = data.map((item) => ChatModel.fromJson(item)).toList();
      }

      final groupsUrl = Uri.parse(
        "$baseUrl/groups?user_id=${widget.currentUserId}",
      );
      final groupsResponse =
          await http.get(groupsUrl).timeout(const Duration(seconds: 10));
      List<ChatModel> groupChats = [];
      if (groupsResponse.statusCode == 200) {
        final List<dynamic> data = jsonDecode(groupsResponse.body);
        groupChats = data.map((item) => ChatModel.fromJson(item)).toList();
      }

      groupChats.sort((a, b) => b.time.compareTo(a.time));
      individualChats.sort((a, b) => b.time.compareTo(a.time));

      _allChats = [...groupChats, ...individualChats];
      _applyFilter();

      if (mounted) setState(() => isLoading = false);
    } catch (e) {
      print("❌ Error fetching chats: $e");
      if (mounted) setState(() => isLoading = false);
    }
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

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return "";
    try {
      final dt = DateTime.parse(timeStr).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final messageDate = DateTime(dt.year, dt.month, dt.day);

      if (messageDate == today) {
        return DateFormat('hh:mm a').format(dt);
      } else if (messageDate == yesterday) {
        return "أمس";
      } else {
        return DateFormat('dd/MM/yyyy').format(dt);
      }
    } catch (e) {
      return "";
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return "?";
    return name.trim()[0].toUpperCase();
  }

  // ✅ دالة جديدة: فتح المحادثة المستهدفة مع تمرير الرسالة
  Future<void> _openTargetChat(ChatModel chat) async {
    if (_isForwarding) return;
    setState(() => _isForwarding = true);

    final originalMessage = widget.messageToForward;
    final targetChatName = chat.name;

    // إغلاق صفحة الاختيار الحالية
    Navigator.pop(context);

    // فتح صفحة المحادثة المناسبة
    if (chat.isGroup == true) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CreateGroupPage(
            currentUserId: widget.currentUserId,
            baseUrl: baseUrl,
            chatmodel: chat,
            forwardingMessage: originalMessage,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IndividualPage(
            chatmodel: chat,
            currentUserId: widget.currentUserId,
            existingSocket: widget.socket,
            forwardingMessage: originalMessage, // ✅ تم إضافة المعامل
          ),
        ),
      );
    }

    // بعد العودة من صفحة المحادثة
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم فتح محادثة $targetChatName لتأكيد الإرسال')),
      );
    }

    setState(() => _isForwarding = false);
  }

  Future<void> _openNewChat() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SelectMembers(
          currentUserId: widget.currentUserId,
          multiSelect: false,
        ),
      ),
    );

    if (result != null && result is ChatModel) {
      await _openTargetChat(result);
    }
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
        title: Text(
          "إعادة توجيه إلى...",
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
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
                autofocus: true,
                decoration: InputDecoration(
                  hintText: "ابحث عن شخص أو مجموعة...",
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
                  setState(() {
                    _searchQuery = value;
                    _applyFilter();
                  });
                },
              ),
            ),
          ),
        ),
      ),
      body: _isForwarding
          ? const Center(child: CircularProgressIndicator())
          : isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        "جاري تحميل المحادثات...",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (_searchQuery.isEmpty)
                      Container(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color:
                                  isDark ? Colors.white12 : Colors.grey[200]!,
                            ),
                          ),
                        ),
                        child: ListTile(
                          onTap: _openNewChat,
                          leading: CircleAvatar(
                            backgroundColor:
                                colorScheme.primary.withOpacity(0.2),
                            child:
                                Icon(Icons.message, color: colorScheme.primary),
                          ),
                          title: Text(
                            "محادثة جديدة",
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _filteredChats.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _searchQuery.isNotEmpty
                                        ? Icons.search_off
                                        : Icons.chat_bubble_outline,
                                    size: 70,
                                    color: isDark
                                        ? Colors.white30
                                        : Colors.grey[400],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? "لا توجد نتائج لـ '$_searchQuery'"
                                        : "لا توجد محادثات",
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _filteredChats.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                thickness: 0.5,
                                indent: 70,
                                color:
                                    isDark ? Colors.white12 : Colors.grey[200],
                              ),
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
                                  onTap: () => _openTargetChat(chat),
                                  leading: Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 25,
                                        backgroundColor: colorScheme.primary
                                            .withOpacity(0.1),
                                        backgroundImage: fullImageUrl != null
                                            ? NetworkImage(fullImageUrl)
                                            : null,
                                        child: (fullImageUrl == null)
                                            ? (isGroup
                                                ? Icon(
                                                    Icons.groups_rounded,
                                                    color: colorScheme.primary,
                                                    size: 30,
                                                  )
                                                : Text(
                                                    _getInitials(chat.name),
                                                    style: TextStyle(
                                                      fontSize: 22,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          colorScheme.primary,
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
                                    chat.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  subtitle: Text(
                                    chat.currentMessage?.isNotEmpty == true
                                        ? chat.currentMessage!
                                        : (isGroup
                                            ? "${chat.participants.length} عضو"
                                            : "اضغط لتحديد"),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[600],
                                      fontSize: 13,
                                    ),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _formatTime(chat.time),
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.grey[500],
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (isGroup)
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                colorScheme.primary.withOpacity(
                                              0.15,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            "مجموعة",
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: colorScheme.primary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
