import 'package:flutter/material.dart';
import 'package:fitst_app/Model/office_api_service.dart';
import 'package:fitst_app/Model/office_status.dart';
import 'office_status_form_page.dart';
import 'office_history_page.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class UserDetails {
  final String id;
  final String username;
  final String? avatarUrl;

  UserDetails({required this.id, required this.username, this.avatarUrl});

  factory UserDetails.fromJson(Map<String, dynamic> json) {
    return UserDetails(
      id: json['id'],
      username: json['username'] ?? 'مستخدم',
      avatarUrl: json['avatar_url'],
    );
  }
}

class OfficeStatusListPage extends StatefulWidget {
  final String baseUrl;
  final String currentUserId;

  const OfficeStatusListPage({
    required this.baseUrl,
    required this.currentUserId,
    Key? key,
  }) : super(key: key);

  @override
  State<OfficeStatusListPage> createState() => _OfficeStatusListPageState();
}

class _OfficeStatusListPageState extends State<OfficeStatusListPage> {
  late OfficeApiService _api;
  List<OfficeStatus> _statuses = [];
  bool _loading = true;
  Map<String, UserDetails> _userDetailsMap = {};

  String? _getFullImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return null;
    if (imagePath.startsWith('http')) return imagePath;
    return '${widget.baseUrl}/uploads/$imagePath';
  }

  @override
  void initState() {
    super.initState();
    _api = OfficeApiService(widget.baseUrl);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await _api.fetchOfficeStatuses();
      setState(() => _statuses = data);
      await _fetchUsersDetails();
      setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _fetchUsersDetails() async {
    final Set<String> uniqueUserIds = {};
    for (var office in _statuses) {
      if (office.ownerId.isNotEmpty &&
          !_userDetailsMap.containsKey(office.ownerId)) {
        uniqueUserIds.add(office.ownerId);
      }
    }
    for (String userId in uniqueUserIds) {
      await _fetchUserDetail(userId);
    }
  }

  Future<void> _fetchUserDetail(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/users/$userId'),
      );
      if (response.statusCode == 200) {
        final user = UserDetails.fromJson(json.decode(response.body));
        setState(() => _userDetailsMap[userId] = user);
      } else {
        setState(
          () => _userDetailsMap[userId] = UserDetails(
            id: userId,
            username: 'مستخدم غير معروف',
          ),
        );
      }
    } catch (e) {
      setState(
        () => _userDetailsMap[userId] = UserDetails(
          id: userId,
          username: 'مستخدم',
        ),
      );
    }
  }

  Future<void> _deleteOffice(OfficeStatus office) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المكتب'),
        content: Text(
          'هل تريد حذف المكتب "${office.officeName}" (${office.shift == 'morning' ? 'صباحي' : 'مسائي'}) نهائياً؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _api.deleteOfficeStatus(
          office.officeName,
          office.shift,
          widget.currentUserId,
        );
        _loadData();
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'working':
        return '🟢 شغال';
      case 'problem':
        return '🔴 توجد مشكلة';
      case 'closed':
        return '⚫ مغلق';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'working':
        return Colors.green;
      case 'problem':
        return Colors.red;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getShiftText(String shift) => shift == 'morning' ? 'صباحي' : 'مسائي';

  void _showFullImageDialog(
    BuildContext context,
    List<String> imageUrls,
    String baseUrl,
  ) {
    final fullUrls = imageUrls
        .map((url) => url.startsWith('http') ? url : baseUrl + url)
        .toList();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Container(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.7,
          child: fullUrls.length == 1
              ? InteractiveViewer(
                  child: Image.network(
                    fullUrls.first,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image, size: 100),
                  ),
                )
              : PageView.builder(
                  itemCount: fullUrls.length,
                  itemBuilder: (ctx, idx) => InteractiveViewer(
                    child: Image.network(
                      fullUrls[idx],
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, size: 100),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildImageIcon(List<String> imageUrls) {
    if (imageUrls.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _showFullImageDialog(context, imageUrls, widget.baseUrl),
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 8, right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image, size: 18, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              imageUrls.length == 1 ? 'صورة' : '${imageUrls.length} صور',
              style: TextStyle(fontSize: 12, color: colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  String _formatIraqTime(DateTime dt) {
    final iraqTime = dt.add(const Duration(hours: 3));
    final hour12 = iraqTime.hour % 12 == 0 ? 12 : iraqTime.hour % 12;
    final period = iraqTime.hour >= 12 ? 'م' : 'ص';
    return '${iraqTime.year}-${iraqTime.month}-${iraqTime.day} $hour12:${iraqTime.minute.toString().padLeft(2, '0')} $period';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('حالة المكاتب'),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        actions: [
          IconButton(
            icon: Icon(Icons.history, color: colorScheme.primary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => OfficeHistoryPage(api: _api)),
            ),
          ),
          IconButton(
            icon: Icon(Icons.add, color: colorScheme.primary),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OfficeStatusFormPage(
                    baseUrl: widget.baseUrl,
                    currentUserId: widget.currentUserId,
                    onSaved: () => _loadData(),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: colorScheme.primary),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _statuses.isEmpty
          ? Center(
              child: Text(
                'لا توجد مكاتب مسجلة',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            )
          : ListView.builder(
              itemCount: _statuses.length,
              itemBuilder: (ctx, i) {
                final office = _statuses[i];
                final isOwner = office.ownerId == widget.currentUserId;
                final userDetails = _userDetailsMap[office.ownerId];
                final String displayName =
                    userDetails?.username ?? 'جاري التحميل...';
                final String? fullAvatarUrl = _getFullImageUrl(
                  userDetails?.avatarUrl,
                );

                final List<String> images = [];
                if (office.imageUrls != null && office.imageUrls!.isNotEmpty) {
                  images.addAll(office.imageUrls!);
                } else if (office.imageUrl != null &&
                    office.imageUrl!.isNotEmpty) {
                  images.add(office.imageUrl!);
                }

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  color: colorScheme.surface,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getStatusColor(
                            office.status,
                          ).withOpacity(0.2),
                          child: Icon(
                            Icons.business,
                            color: _getStatusColor(office.status),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                office.officeName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _getShiftText(office.shift),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_getStatusText(office.status)),
                            if (office.status == 'problem' &&
                                office.problemType != null)
                              Wrap(
                                spacing: 4,
                                children: office.problemType!
                                    .map(
                                      (p) => Chip(
                                        label: Text(p),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        backgroundColor:
                                            colorScheme.surfaceContainerHighest,
                                        labelStyle: TextStyle(
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            if (office.problemDetails != null &&
                                office.problemDetails!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'التفاصيل: ${office.problemDetails}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurface.withOpacity(
                                      0.8,
                                    ),
                                  ),
                                ),
                              ),
                            Text(
                              'آخر تحديث: ${_formatIraqTime(office.updatedAt)}',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            const SizedBox(height: 4),
                            // عرض صورة واسم المستخدم
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor:
                                      colorScheme.surfaceContainerHighest,
                                  backgroundImage: fullAvatarUrl != null
                                      ? NetworkImage(fullAvatarUrl)
                                      : null,
                                  child: fullAvatarUrl == null
                                      ? Icon(
                                          Icons.person,
                                          size: 12,
                                          color: colorScheme.onSurface,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurface.withOpacity(
                                        0.8,
                                      ),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: isOwner
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.edit,
                                      color: colorScheme.primary,
                                    ),
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => OfficeStatusFormPage(
                                            baseUrl: widget.baseUrl,
                                            currentUserId: widget.currentUserId,
                                            existingOffice: office,
                                            onSaved: () => _loadData(),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _deleteOffice(office),
                                  ),
                                ],
                              )
                            : null,
                      ),
                      if (images.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: _buildImageIcon(images),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
