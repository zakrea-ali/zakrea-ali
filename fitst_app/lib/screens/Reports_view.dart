import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:path_provider/path_provider.dart';

// ==================== صفحة عرض التبليغات ====================
class ViewReportsPage extends StatefulWidget {
  final String baseUrl;
  final String currentUserId;
  const ViewReportsPage({
    Key? key,
    required this.baseUrl,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<ViewReportsPage> createState() => _ViewReportsPageState();
}

class _ViewReportsPageState extends State<ViewReportsPage> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final response = await http.get(
        Uri.parse("${widget.baseUrl}/reports/all"),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final reportsList = List<Map<String, dynamic>>.from(data['reports']);
        for (var report in reportsList) {
          report['title'] = report['title'] ?? '';
          report['description'] = report['description'] ?? '';
          report['creator_name'] = report['creator_name'] ?? 'غير معروف';
          report['link'] = report['link'] ?? '';
          // معالجة المرفقات
          List<dynamic> rawAttachments = report['attachments'];
          if (rawAttachments is! List) {
            rawAttachments = [];
          }
          final cleaned = rawAttachments
              .map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
          report['attachments'] = cleaned;
        }
        setState(() => _reports = reportsList);
      } else {
        throw Exception(data['message'] ?? 'فشل تحميل البيانات');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteReport(String id, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف التبليغ'),
        content: const Text('هل أنت متأكد من حذف هذا التبليغ؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final response = await http.delete(
        Uri.parse("${widget.baseUrl}/reports/delete/$id"),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() => _reports.removeAt(index));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم الحذف بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception(data['message'] ?? 'فشل الحذف');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editReport(Map<String, dynamic> report, int index) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditReportPage(
          baseUrl: widget.baseUrl,
          report: report,
          currentUserId: widget.currentUserId,
          onReportUpdated: () => _fetchReports(),
        ),
      ),
    );
    if (result == true) await _fetchReports();
  }

  String _getFullUrl(String path) {
    if (path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    if (path.startsWith('/')) return '${widget.baseUrl}$path';
    return '${widget.baseUrl}/$path';
  }

  Future<void> _openFile(String url, String fileName) async {
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return;
      }
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$fileName';
      await Dio().download(url, filePath);
      await OpenFile.open(filePath);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يمكن فتح الملف: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  IconData _getIconForFile(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext))
      return Icons.image;
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) return Icons.video_library;
    if (['mp3', 'wav', 'aac', 'flac'].contains(ext)) return Icons.audiotrack;
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['doc', 'docx'].contains(ext)) return Icons.description;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow;
    return Icons.insert_drive_file;
  }

  Color _getIconColor(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext))
      return Colors.green;
    if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) return Colors.purple;
    if (['mp3', 'wav', 'aac', 'flac'].contains(ext)) return Colors.orange;
    if (['pdf'].contains(ext)) return Colors.red;
    if (['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'].contains(ext))
      return Colors.blue;
    return Colors.grey;
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('التبليغات'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchReports),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 60, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchReports,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : _reports.isEmpty
                  ? const Center(child: Text('لا توجد تبليغات حتى الآن'))
                  : ListView.builder(
                      itemCount: _reports.length,
                      itemBuilder: (ctx, i) {
                        final r = _reports[i];
                        final isCreator =
                            r['created_by'] == widget.currentUserId;
                        final attachments = (r['attachments'] as List?) ?? [];
                        final link = r['link'] ?? '';
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.blue,
                              child:
                                  Icon(Icons.announcement, color: Colors.white),
                            ),
                            title: Text(
                              r['title'] ?? '',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r['description'] ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.person,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      r['creator_name'] ?? 'غير معروف',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      size: 12,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _formatDate(r['created_at']),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                                if (link.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: () async {
                                      final url = _getFullUrl(link);
                                      if (await canLaunchUrl(Uri.parse(url))) {
                                        await launchUrl(
                                          Uri.parse(url),
                                          mode: LaunchMode.externalApplication,
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text('لا يمكن فتح الرابط'),
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.link,
                                            size: 14,
                                            color: Colors.blue,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            link,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.blue,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                if (attachments.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: attachments.map<Widget>((url) {
                                      final urlStr = url.toString();
                                      final fullUrl = _getFullUrl(urlStr);
                                      final fileName = urlStr.split('/').last;
                                      return GestureDetector(
                                        onTap: () =>
                                            _openFile(fullUrl, fileName),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withOpacity(0.2),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                _getIconForFile(fileName),
                                                size: 14,
                                                color: _getIconColor(fileName),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                fileName,
                                                style: const TextStyle(
                                                    fontSize: 11),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                            trailing: isCreator
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Colors.blue,
                                        ),
                                        onPressed: () => _editReport(r, i),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        onPressed: () =>
                                            _deleteReport(r['id'], i),
                                      ),
                                    ],
                                  )
                                : null,
                            onTap: () => _showReportDetails(r),
                          ),
                        );
                      },
                    ),
    );
  }

  void _showReportDetails(Map<String, dynamic> report) {
    final theme = Theme.of(context);
    final attachments = (report['attachments'] as List?) ?? [];
    final link = report['link'] ?? '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(report['title'] ?? ''),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الوصف:', style: theme.textTheme.titleSmall),
              Text(report['description'] ?? ''),
              const SizedBox(height: 8),
              Text('المنشئ: ${report['creator_name'] ?? 'غير معروف'}'),
              Text('تاريخ الإنشاء: ${_formatDate(report['created_at'])}'),
              if (link.isNotEmpty) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final url = _getFullUrl(link);
                    if (await canLaunchUrl(Uri.parse(url))) {
                      await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('لا يمكن فتح الرابط')),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link, size: 16, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(link, style: const TextStyle(color: Colors.blue)),
                      ],
                    ),
                  ),
                ),
              ],
              if (attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'المرفقات:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: attachments.map<Widget>((url) {
                    final urlStr = url.toString();
                    final fullUrl = _getFullUrl(urlStr);
                    final fileName = urlStr.split('/').last;
                    return GestureDetector(
                      onTap: () => _openFile(fullUrl, fileName),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getIconForFile(fileName),
                              size: 16,
                              color: _getIconColor(fileName),
                            ),
                            const SizedBox(width: 4),
                            Text(fileName),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

// ==================== صفحة تعديل التبليغ ====================
class EditReportPage extends StatefulWidget {
  final String baseUrl;
  final Map<String, dynamic> report;
  final String currentUserId;
  final VoidCallback onReportUpdated;
  const EditReportPage({
    Key? key,
    required this.baseUrl,
    required this.report,
    required this.currentUserId,
    required this.onReportUpdated,
  }) : super(key: key);

  @override
  State<EditReportPage> createState() => _EditReportPageState();
}

class _EditReportPageState extends State<EditReportPage> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _linkController;
  bool _isSaving = false;

  List<String> _existingAttachments = [];
  List<XFile> _newFiles = [];
  bool _isUploading = false;

  MediaType _getContentType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'gif':
        return MediaType('image', 'gif');
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'doc':
        return MediaType('application', 'msword');
      case 'docx':
        return MediaType(
          'application',
          'vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
      case 'xls':
        return MediaType('application', 'vnd.ms-excel');
      case 'xlsx':
        return MediaType(
          'application',
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      case 'txt':
        return MediaType('text', 'plain');
      default:
        return MediaType('application', 'octet-stream');
    }
  }

  Future<List<String>> _uploadNewFiles(List<XFile> files) async {
    if (files.isEmpty) return [];
    setState(() => _isUploading = true);
    List<String> uploadedUrls = [];
    try {
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        String fileName = file.name;
        if (fileName.isEmpty) {
          final path = file.path;
          if (path.isNotEmpty) {
            fileName = path.split('/').last.split('\\').last;
          } else {
            fileName =
                'uploaded_file_${DateTime.now().millisecondsSinceEpoch}_$i';
          }
        }
        Uint8List bytes;
        try {
          bytes = await file.readAsBytes();
        } catch (e) {
          print('⚠️ فشل قراءة الملف $fileName: $e');
          continue;
        }
        if (bytes.isEmpty) {
          print('⚠️ الملف $fileName فارغ، تخطي');
          continue;
        }
        final request = http.MultipartRequest(
          'POST',
          Uri.parse("${widget.baseUrl}/reports/upload"),
        );
        request.files.add(
          http.MultipartFile.fromBytes(
            'attachments',
            bytes,
            filename: fileName,
            contentType: _getContentType(fileName),
          ),
        );
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['files'] != null) {
            uploadedUrls.addAll(List<String>.from(data['files']));
          }
        }
      }
      return uploadedUrls;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل رفع الملفات: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return [];
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // استخدام الصيغة المتوافقة مع FilePicker الحديث بشكل مستقر وآمن
  Future<void> _pickFiles() async {
    try {
      // ✅ استدعاء مباشر متوافق مع الإصدارات الحديثة
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result != null) {
        final List<XFile> files = [];
        for (var f in result.files) {
          if (kIsWeb && f.bytes != null) {
            files.add(XFile.fromData(f.bytes!, name: f.name));
          } else if (f.path != null) {
            files.add(XFile(f.path!));
          }
        }
        setState(() => _newFiles.addAll(files));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في اختيار الملفات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => _newFiles.add(image));
  }

  void _removeExistingAttachment(int index) =>
      setState(() => _existingAttachments.removeAt(index));
  void _removeNewFile(int index) => setState(() => _newFiles.removeAt(index));

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final newUrls = await _uploadNewFiles(_newFiles);
      final allAttachments = [..._existingAttachments, ...newUrls];
      final link = _linkController.text.trim().isNotEmpty
          ? _linkController.text.trim()
          : null;
      final response = await http.put(
        Uri.parse("${widget.baseUrl}/reports/update/${widget.report['id']}"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': _titleController.text.trim(),
          'description': _descController.text.trim(),
          'attachments': allAttachments,
          'link': link,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم التحديث بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onReportUpdated();
        Navigator.pop(context, true);
      } else {
        throw Exception(data['message'] ?? 'فشل التحديث');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.report['title'] ?? '',
    );
    _descController = TextEditingController(
      text: widget.report['description'] ?? '',
    );
    _linkController = TextEditingController(text: widget.report['link'] ?? '');
    final attachments = widget.report['attachments'];
    if (attachments is List) {
      _existingAttachments = attachments
          .map((e) => e?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    } else {
      _existingAttachments = [];
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل التبليغ'),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save),
            onPressed: _isSaving ? null : _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'العنوان'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descController,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'الوصف'),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: TextFormField(
                    controller: _linkController,
                    decoration: InputDecoration(
                      labelText: 'رابط (اختياري)',
                      prefixIcon: const Icon(Icons.link),
                      hintText: 'https://...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_file, size: 20),
                      const SizedBox(width: 8),
                      const Text('المرفقات'),
                      const Spacer(),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.add),
                        onSelected: (value) =>
                            value == 'file' ? _pickFiles() : _pickImage(),
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'image',
                            child: Row(
                              children: [
                                Icon(Icons.image),
                                SizedBox(width: 8),
                                Text('صورة'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'file',
                            child: Row(
                              children: [
                                Icon(Icons.insert_drive_file),
                                SizedBox(width: 8),
                                Text('ملف'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_existingAttachments.isNotEmpty)
                  ..._existingAttachments.asMap().entries.map((entry) {
                    final index = entry.key;
                    final fileUrl = entry.value;
                    return ListTile(
                      leading: const Icon(
                        Icons.cloud_done,
                        color: Colors.green,
                      ),
                      title: Text(
                        fileUrl.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _removeExistingAttachment(index),
                      ),
                    );
                  }),
                if (_newFiles.isNotEmpty)
                  ..._newFiles.asMap().entries.map((entry) {
                    final index = entry.key;
                    final file = entry.value;
                    return ListTile(
                      leading: const Icon(
                        Icons.insert_drive_file,
                        color: Colors.blue,
                      ),
                      title: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.grey),
                        onPressed: () => _removeNewFile(index),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
