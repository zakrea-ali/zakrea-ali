import 'package:flutter/material.dart';
import 'package:fitst_app/Model/office_api_service.dart';
import 'package:fitst_app/Model/office_status.dart';
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

class OfficeHistoryPage extends StatefulWidget {
  final OfficeApiService api;
  const OfficeHistoryPage({required this.api, Key? key}) : super(key: key);

  @override
  State<OfficeHistoryPage> createState() => _OfficeHistoryPageState();
}

class _OfficeHistoryPageState extends State<OfficeHistoryPage> {
  List<OfficeHistory> _allHistory = [];
  List<OfficeHistory> _filteredHistory = [];
  bool _loading = true;

  String? _filterShift;
  String? _filterStatus;
  DateTime? _filterDate;
  String? _filterOfficeName;

  Map<String, UserDetails> _userDetailsMap = {};

  final List<String> _officeOptions = [
    'الكل',
    'مكتب الكاظمية',
    'مكتب الحلة',
    'مكتب الديوانية',
    'مكتب اربيل',
  ];

  String? _getFullImageUrl(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return null;
    if (imagePath.startsWith('http')) return imagePath;
    return '${widget.api.baseUrl}/uploads/$imagePath';
  }

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    try {
      final data = await widget.api.fetchHistory(shift: _filterShift);
      setState(() {
        _allHistory = data;
      });
      await _fetchUsersDetails();
      _applyFilters();
      setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _applyFilters() {
    List<OfficeHistory> temp = List.from(_allHistory);
    temp = temp.where((h) => h.action != 'delete').toList();

    if (_filterStatus != null) {
      temp = temp.where((h) => h.status == _filterStatus).toList();
    }

    if (_filterDate != null) {
      temp = temp.where((h) {
        return h.changedAt.year == _filterDate!.year &&
            h.changedAt.month == _filterDate!.month &&
            h.changedAt.day == _filterDate!.day;
      }).toList();
    }

    if (_filterOfficeName != null && _filterOfficeName != 'الكل') {
      temp = temp.where((h) => h.officeName == _filterOfficeName).toList();
    }

    setState(() {
      _filteredHistory = temp;
    });
  }

  Future<void> _fetchUsersDetails() async {
    final Set<String> uniqueUserIds = {};
    for (var history in _allHistory) {
      final userId = history.changedBy;
      if (userId != null &&
          userId.isNotEmpty &&
          !_userDetailsMap.containsKey(userId)) {
        uniqueUserIds.add(userId);
      }
    }
    for (String userId in uniqueUserIds) {
      await _fetchUserDetail(userId);
    }
  }

  Future<void> _fetchUserDetail(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('${widget.api.baseUrl}/users/$userId'),
      );
      if (response.statusCode == 200) {
        final user = UserDetails.fromJson(json.decode(response.body));
        setState(() {
          _userDetailsMap[userId] = user;
        });
      } else {
        setState(() {
          _userDetailsMap[userId] = UserDetails(
            id: userId,
            username: 'مستخدم غير معروف',
          );
        });
      }
    } catch (e) {
      setState(() {
        _userDetailsMap[userId] = UserDetails(id: userId, username: 'مستخدم');
      });
    }
  }

  String _actionText(String action) {
    switch (action) {
      case 'create':
        return 'إنشاء';
      case 'update':
        return 'تحديث';
      case 'delete':
        return 'حذف';
      case 'auto_close':
        return 'إغلاق تلقائي';
      default:
        return action;
    }
  }

  String _shiftText(String? shift) {
    if (shift == null) return 'غير محدد';
    return shift == 'morning' ? 'صباحي' : 'مسائي';
  }

  String _statusText(String status) {
    switch (status) {
      case 'working':
        return 'شغال';
      case 'problem':
        return 'مشكلة';
      case 'closed':
        return 'مغلق';
      default:
        return status;
    }
  }

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
      onTap: () => _showFullImageDialog(context, imageUrls, widget.api.baseUrl),
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _openFilterSheet() {
    DateTime? tempDate = _filterDate;
    String? tempOfficeName = _filterOfficeName;
    String? tempShift = _filterShift;
    String? tempStatus = _filterStatus;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateSheet) {
            return Dialog(
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                width: MediaQuery.of(ctx).size.width * 0.9,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.filter_alt,
                            color: Theme.of(ctx).colorScheme.primary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'فلتر السجل',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(ctx).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. التاريخ (بدون نص، فقط أيقونة وحقل)
                            _buildFilterSectionWithoutLabel(
                              icon: Icons.calendar_today,
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: tempDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setStateSheet(() => tempDate = picked);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                      width: 1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.date_range,
                                        color: Theme.of(
                                          ctx,
                                        ).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          tempDate == null
                                              ? 'اختر التاريخ'
                                              : _formatDate(tempDate!),
                                          style: TextStyle(
                                            color: tempDate == null
                                                ? Colors.grey.shade600
                                                : Theme.of(
                                                    ctx,
                                                  ).colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      if (tempDate != null)
                                        GestureDetector(
                                          onTap: () => setStateSheet(
                                            () => tempDate = null,
                                          ),
                                          child: const Icon(
                                            Icons.clear,
                                            size: 20,
                                            color: Colors.red,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 2. المكتب
                            _buildFilterSection(
                              icon: Icons.business,
                              label: 'المكتب',
                              child: DropdownButtonFormField<String?>(
                                value: tempOfficeName,
                                isExpanded: true,
                                decoration: _inputDecoration(),
                                items: _officeOptions.map((office) {
                                  return DropdownMenuItem<String?>(
                                    value: office == 'الكل' ? null : office,
                                    child: Text(office),
                                  );
                                }).toList(),
                                onChanged: (val) =>
                                    setStateSheet(() => tempOfficeName = val),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 3. الشفت
                            _buildFilterSection(
                              icon: Icons.access_time,
                              label: 'الشفت',
                              child: DropdownButtonFormField<String?>(
                                value: tempShift,
                                isExpanded: true,
                                decoration: _inputDecoration(),
                                items: const [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text('الكل'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'morning',
                                    child: Text('صباحي'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'evening',
                                    child: Text('مسائي'),
                                  ),
                                ],
                                onChanged: (val) =>
                                    setStateSheet(() => tempShift = val),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 4. الحالة
                            _buildFilterSection(
                              icon: Icons.info_outline,
                              label: 'الحالة',
                              child: DropdownButtonFormField<String?>(
                                value: tempStatus,
                                isExpanded: true,
                                decoration: _inputDecoration(),
                                items: const [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text('الكل'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'working',
                                    child: Text('شغال'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'problem',
                                    child: Text('مشكلة'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'closed',
                                    child: Text('مغلق'),
                                  ),
                                ],
                                onChanged: (val) =>
                                    setStateSheet(() => tempStatus = val),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _filterDate = tempDate;
                            _filterOfficeName = tempOfficeName;
                            _filterShift = tempShift;
                            _filterStatus = tempStatus;
                          });
                          _loadHistory();
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'تطبيق الفلتر',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // قسم بدون نص (للتاريخ فقط)
  Widget _buildFilterSectionWithoutLabel({
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  // قسم عادي (أيقونة + نص)
  Widget _buildFilterSection({
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل حالة المكاتب'),
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.filter_list, color: colorScheme.primary),
            onPressed: _openFilterSheet,
            tooltip: 'فلتر متقدم',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filteredHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'لا يوجد سجل',
                        style: TextStyle(
                          fontSize: 18,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredHistory.length,
                  itemBuilder: (ctx, i) {
                    final h = _filteredHistory[i];
                    final List<String> images = [];
                    if (h.imageUrls != null && h.imageUrls!.isNotEmpty) {
                      images.addAll(h.imageUrls!);
                    } else if (h.imageUrl != null && h.imageUrl!.isNotEmpty) {
                      images.add(h.imageUrl!);
                    }

                    final userId = h.changedBy;
                    final userDetails =
                        userId != null ? _userDetailsMap[userId] : null;
                    final String displayName =
                        userDetails?.username ?? (userId ?? 'غير معروف');
                    final String? fullAvatarUrl = _getFullImageUrl(
                      userDetails?.avatarUrl,
                    );

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      color: colorScheme.surface,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Icon(
                                Icons.history,
                                color: colorScheme.primary,
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${h.officeName} - ${_actionText(h.action)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHighest
                                        .withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _shiftText(h.shift),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.7),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.label_outline,
                                      size: 14,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.7),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'الحالة: ${_statusText(h.status)}',
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                                if (h.problemType != null &&
                                    h.problemType!.isNotEmpty)
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: h.problemType!
                                        .map(
                                          (p) => Chip(
                                            label: Text(p),
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            backgroundColor: colorScheme
                                                .surfaceContainerHighest,
                                            labelStyle: TextStyle(
                                              color: colorScheme.onSurface,
                                              fontSize: 12,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                if (h.problemDetails != null &&
                                    h.problemDetails!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'التفاصيل: ${h.problemDetails}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color:
                                            colorScheme.onSurface.withOpacity(
                                          0.8,
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 14,
                                      color: colorScheme.onSurface
                                          .withOpacity(0.6),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatIraqTime(h.changedAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            colorScheme.onSurface.withOpacity(
                                          0.6,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor:
                                          colorScheme.surfaceContainerHighest,
                                      backgroundImage: fullAvatarUrl != null
                                          ? NetworkImage(fullAvatarUrl)
                                          : null,
                                      child: fullAvatarUrl == null
                                          ? Icon(
                                              Icons.person,
                                              size: 14,
                                              color: colorScheme.onSurface,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        displayName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              colorScheme.onSurface.withOpacity(
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
                            isThreeLine: true,
                          ),
                          if (images.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 16,
                                right: 16,
                                bottom: 12,
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: _buildImageIcon(images),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
