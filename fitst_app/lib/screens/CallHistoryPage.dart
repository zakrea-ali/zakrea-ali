import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:fitst_app/Model/ChatModel.dart';
import 'package:fitst_app/screens/IndividualPage.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';

class CallHistoryPage extends StatefulWidget {
  final String currentUserId;
  final String baseUrl;
  final IO.Socket? socket;

  const CallHistoryPage({
    Key? key,
    required this.currentUserId,
    required this.baseUrl,
    this.socket,
  }) : super(key: key);

  @override
  State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage> {
  List<Map<String, dynamic>> _callHistory = [];
  bool _isLoading = true;
  String? _error;
  Map<String, Map<String, String>> _userCache = {};

  @override
  void initState() {
    super.initState();
    _fetchCallHistory();
  }

  Future<void> _fetchCallHistory() async {
    try {
      final url = '${widget.baseUrl}/api/calls/history/${widget.currentUserId}';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _callHistory = List<Map<String, dynamic>>.from(data['history']);
            _isLoading = false;
          });
          _loadUserDetails();
          return;
        }
      }
      setState(() {
        _error = 'فشل تحميل سجل المكالمات';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'خطأ في الاتصال بالخادم';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUserDetails() async {
    final userIds = <String>{};
    for (var call in _callHistory) {
      final callerId = call['caller_id']?.toString();
      final receiverId = call['receiver_id']?.toString();
      if (callerId != null && callerId != widget.currentUserId) {
        userIds.add(callerId);
      }
      if (receiverId != null && receiverId != widget.currentUserId) {
        userIds.add(receiverId);
      }
    }

    for (final uid in userIds) {
      if (!_userCache.containsKey(uid)) {
        try {
          final response = await http.get(
            Uri.parse('${widget.baseUrl}/users/$uid'),
          );
          if (response.statusCode == 200) {
            final user = jsonDecode(response.body);
            _userCache[uid] = {
              'username': user['username'] ?? 'مستخدم',
              'job': user['job'] ?? '',
              'avatar_url': user['avatar_url'] ?? '',
              'id': uid,
            };
          } else {
            _userCache[uid] = {
              'username': 'مستخدم',
              'job': '',
              'avatar_url': '',
              'id': uid,
            };
          }
        } catch (e) {
          _userCache[uid] = {
            'username': 'مستخدم',
            'job': '',
            'avatar_url': '',
            'id': uid,
          };
        }
      }
    }
    if (mounted) setState(() {});
  }

  Map<String, String>? _getOtherUser(Map<String, dynamic> call) {
    final callerId = call['caller_id']?.toString();
    final receiverId = call['receiver_id']?.toString();
    final otherId = (callerId == widget.currentUserId) ? receiverId : callerId;
    if (otherId == null) return null;
    return _userCache[otherId];
  }

  String _getCallType(Map<String, dynamic> call) {
    final callerId = call['caller_id']?.toString();
    return (callerId == widget.currentUserId) ? 'outgoing' : 'incoming';
  }

  // 🔥 تحسين عرض النصوص حسب الحالة والنوع
  String _getStatusText(String status, String type) {
    if (type == 'outgoing') {
      switch (status) {
        case 'accepted':
          return 'مكالمة صادرة';
        case 'missed':
          return 'مكالمة صادرة (لم يجب)';
        case 'cancelled':
          return 'مكالمة ملغاة';
        case 'rejected':
          return 'المستخدم مشغول';
        case 'busy':
          return 'المستخدم مشغول';
        default:
          return 'مكالمة صادرة';
      }
    } else {
      switch (status) {
        case 'accepted':
          return 'مكالمة مستلمة';
        case 'missed':
          return 'مكالمة فائتة';
        case 'cancelled':
          return 'مكالمة فائتة';
        case 'rejected':
          return 'مكالمة مرفوضة';
        case 'busy':
          return 'المستخدم مشغول';
        default:
          return 'مكالمة واردة';
      }
    }
  }

  IconData _getIconForStatus(String status, String type) {
    if (type == 'outgoing') {
      switch (status) {
        case 'accepted':
          return Icons.call_made;
        case 'missed':
        case 'cancelled':
          return Icons.call_missed;
        case 'rejected':
        case 'busy':
          return Icons.phonelink_ring;
        default:
          return Icons.call;
      }
    } else {
      switch (status) {
        case 'accepted':
          return Icons.call_received;
        case 'missed':
        case 'cancelled':
          return Icons.call_missed;
        case 'rejected':
          return Icons.call_missed_outgoing;
        case 'busy':
          return Icons.phonelink_ring;
        default:
          return Icons.call;
      }
    }
  }

  Color _getColorForStatus(String status, String type) {
    if (type == 'outgoing') {
      switch (status) {
        case 'accepted':
          return Colors.blue.shade700;
        case 'missed':
        case 'cancelled':
          return Colors.red.shade700;
        case 'rejected':
        case 'busy':
          return Colors.deepOrange.shade700;
        default:
          return Colors.grey;
      }
    } else {
      switch (status) {
        case 'accepted':
          return Colors.green.shade700;
        case 'missed':
        case 'cancelled':
          return Colors.red.shade700;
        case 'rejected':
          return Colors.orange.shade700;
        case 'busy':
          return Colors.deepOrange.shade700;
        default:
          return Colors.grey;
      }
    }
  }

  String _formatTime(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    try {
      final dt = DateTime.parse(dateTimeStr).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return DateFormat('hh:mm a').format(dt);
      } else if (dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day - 1) {
        return 'أمس ${DateFormat('hh:mm a').format(dt)}';
      } else {
        return DateFormat('dd/MM/yyyy hh:mm a').format(dt);
      }
    } catch (e) {
      return dateTimeStr ?? '';
    }
  }

  String? _getFullImageUrl(String? url) {
    if (url == null || url.isEmpty || url == "null") return null;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    String cleanUrl = url.startsWith('/') ? url.substring(1) : url;
    if (cleanUrl.startsWith('uploads/') ||
        cleanUrl.startsWith('uploads_camera/') ||
        cleanUrl.startsWith('uploads_office/') ||
        cleanUrl.startsWith('uploads_reports/') ||
        cleanUrl.startsWith('uploads_tickets/')) {
      return '${widget.baseUrl}/$cleanUrl';
    }
    return '${widget.baseUrl}/uploads/$cleanUrl';
  }

  void _openChatWithUser(Map<String, String> user) {
    if (widget.socket == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Socket غير متصل، لا يمكن بدء المحادثة')),
      );
      return;
    }

    final chatModel = ChatModel(
      id: user['id']!,
      name: user['username']!,
      icon: user['avatar_url'] ?? '',
      isGroup: false,
      status: user['job'] ?? '',
      isOnline: false,
      lastSeen: '',
      createdBy: user['id']!,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => IndividualPage(
          chatmodel: chatModel,
          currentUserId: widget.currentUserId,
          existingSocket: widget.socket,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey[100],
      appBar: AppBar(
        title: const Text('سجل المكالمات'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 60, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchCallHistory,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : _callHistory.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.phone_missed,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'لا توجد مكالمات سابقة',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _callHistory.length,
                      itemBuilder: (context, index) {
                        final call = _callHistory[index];
                        final otherUser = _getOtherUser(call);
                        if (otherUser == null) return const SizedBox.shrink();

                        final type = _getCallType(call);
                        final status = call['status'] ?? 'missed';
                        final statusText = _getStatusText(status, type);
                        final icon = _getIconForStatus(status, type);
                        final color = _getColorForStatus(status, type);
                        final time = _formatTime(call['created_at']);

                        final displayName = otherUser['username'] ?? 'مستخدم';
                        final jobTitle = otherUser['job'] ?? '';
                        final nameWithJob = jobTitle.isNotEmpty
                            ? '$displayName ($jobTitle)'
                            : displayName;

                        final imageUrl =
                            _getFullImageUrl(otherUser['avatar_url']);

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: isDark ? Colors.grey[850] : Colors.white,
                          child: InkWell(
                            onTap: () => _openChatWithUser(otherUser),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundColor: Colors.grey[300],
                                    backgroundImage: imageUrl != null
                                        ? NetworkImage(imageUrl)
                                        : null,
                                    child: imageUrl == null
                                        ? Icon(
                                            Icons.person,
                                            size: 30,
                                            color: Colors.grey[600],
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nameWithJob,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              icon,
                                              size: 16,
                                              color: color,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              statusText,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: color,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    time,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
