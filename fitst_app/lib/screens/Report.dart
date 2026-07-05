import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fitst_app/screens/Reports_view.dart';

class CreateReportPage extends StatefulWidget {
  final String baseUrl;
  final String currentUserId;
  const CreateReportPage({
    Key? key,
    required this.baseUrl,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<CreateReportPage> createState() => _CreateReportPageState();
}

class _CreateReportPageState extends State<CreateReportPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _linkController =
      TextEditingController(); // ✅ رابط اختياري
  bool _isSubmitting = false;

  List<XFile> _selectedFiles = [];
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

  Future<List<String>> _uploadFiles(List<XFile> files) async {
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
        print('📤 رفع ملف $fileName - استجابة: ${response.statusCode}');
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['files'] != null) {
            uploadedUrls.addAll(List<String>.from(data['files']));
            print('✅ تم رفع $fileName -> ${data['files']}');
          } else {
            print('❌ فشل رفع $fileName: ${data['message']}');
          }
        } else {
          print(
            '❌ فشل رفع $fileName: HTTP ${response.statusCode} - ${response.body}',
          );
        }
      }
      return uploadedUrls;
    } catch (e) {
      print('🔥 خطأ أثناء رفع الملفات: $e');
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

  // ✅ تم التعديل هنا ليتوافق مع الإصدارات الحديثة والمستقرة لـ FilePicker
  Future<void> _pickFiles() async {
    try {
      // ✅ الإصدارات الحديثة: استدعاء مباشر من FilePicker بدون platform
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
        setState(() => _selectedFiles.addAll(files));
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
    if (image != null) setState(() => _selectedFiles.add(image));
  }

  void _removeFile(int index) {
    setState(() => _selectedFiles.removeAt(index));
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final uploadedUrls = await _uploadFiles(_selectedFiles);
      print('📦 الملفات المرفوعة بنجاح: $uploadedUrls');

      final link = _linkController.text.trim().isNotEmpty
          ? _linkController.text.trim()
          : null;

      final url = Uri.parse("${widget.baseUrl}/reports/create");
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': _titleController.text.trim(),
          'description': _descController.text.trim(),
          'created_by': widget.currentUserId,
          'attachments': uploadedUrls,
          'link': link, // ✅ إرسال الرابط
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم إرسال التبليغ بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ViewReportsPage(
              baseUrl: widget.baseUrl,
              currentUserId: widget.currentUserId,
            ),
          ),
        );
      } else {
        throw Exception(data['message'] ?? 'فشل الإرسال');
      }
    } catch (e) {
      print('❌ خطأ في إرسال التبليغ: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('إنشاء تبليغ جديد'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // عنوان التبليغ
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'العنوان',
                prefixIcon: const Icon(Icons.title),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'الرجاء إدخال عنوان' : null,
            ),
            const SizedBox(height: 16),
            // الوصف
            TextFormField(
              controller: _descController,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'الوصف',
                prefixIcon: const Icon(Icons.description),
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'الرجاء كتابة وصف' : null,
            ),
            const SizedBox(height: 16),
            // حقل الرابط (اختياري)
            TextFormField(
              controller: _linkController,
              decoration: InputDecoration(
                labelText: 'رابط (اختياري)',
                prefixIcon: const Icon(Icons.link),
                hintText: 'https://example.com',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.url,
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                final uri = Uri.tryParse(value.trim());
                if (uri == null || !uri.hasScheme) {
                  return 'الرجاء إدخال رابط صحيح (مثل https://...)';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // المرفقات (اختياري)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.attach_file, size: 20),
                        const SizedBox(width: 8),
                        const Text('المرفقات (اختياري)'),
                        const Spacer(),
                        if (!_isUploading)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.add),
                            onSelected: (value) {
                              if (value == 'file')
                                _pickFiles();
                              else if (value == 'image') _pickImage();
                            },
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
                        if (_isUploading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                  if (_selectedFiles.isNotEmpty)
                    Container(
                      height: 100,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _selectedFiles.length,
                        itemBuilder: (ctx, i) {
                          final file = _selectedFiles[i];
                          final isImage =
                              file.name.toLowerCase().contains('.jpg') ||
                                  file.name.toLowerCase().contains('.jpeg') ||
                                  file.name.toLowerCase().contains('.png') ||
                                  file.name.toLowerCase().contains('.gif');
                          return Stack(
                            children: [
                              Container(
                                width: 80,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: isImage
                                    ? (kIsWeb
                                        ? Image.network(
                                            file.path,
                                            fit: BoxFit.cover,
                                          )
                                        : Image.file(
                                            File(file.path),
                                            fit: BoxFit.cover,
                                          ))
                                    : Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(
                                              Icons.insert_drive_file,
                                              size: 40,
                                              color: Colors.blue,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              file.name
                                                  .split('.')
                                                  .last
                                                  .toUpperCase(),
                                              style: const TextStyle(
                                                fontSize: 10,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.cancel,
                                    size: 20,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _removeFile(i),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: (_isSubmitting || _isUploading) ? null : _submitReport,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: (_isSubmitting || _isUploading)
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('إرسال التبليغ', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
