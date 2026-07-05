import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart'; // ✅ إضافة الحزمة

class MaintenanceTicketPage extends StatefulWidget {
  final String baseUrl;
  final String currentUserId;

  const MaintenanceTicketPage({
    Key? key,
    required this.baseUrl,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<MaintenanceTicketPage> createState() => _MaintenanceTicketPageState();
}

class _MaintenanceTicketPageState extends State<MaintenanceTicketPage> {
  final _formKey = GlobalKey<FormState>();

  String _maintenanceType = "site";
  String? _selectedSiteIssue;
  final List<String> _siteIssues = [
    "صيانة منظومة الكهرباء - البورد الرئيسي",
    "صيانة منظومة الكهرباء - البورد الثانوي",
    "صيانة منظومة الكاميرات",
    "UPS صيانة",
    "صيانة اجهزة التبريد",
    "صيانة الوصلات المايكروية",
    "صيانة منضومة الارضي",
    "صيانة الكابل الضوئي",
    "TICKET SYSTEM صيانة منظومة",
    "صيانة الشبكة الداخلية",
    "صيانة الشاشات ومنظومة الصوت",
    "صيانة الاثاث",
    "صيانة نظم التهوية ومفرغات الهواء",
    "أخرى (يرجى التوضيح في الوصف)",
  ];

  final List<String> _deviceTypes = [
    "كمبيوتر",
    "قارئ البطاقة",
    "قارئ بصمة الاصابع",
    "الكاميرا",
    "الماسح الضوئي",
    "الكيباد",
    "طابعة الجوازات",
  ];
  String? _selectedDeviceType;
  String _serialNumber = "";
  String _deviceLocation = "";
  String _problemDescription = "";

  // ✅ تغيير نوع المرفقات إلى List<Uint8List> مع أسماء الملفات
  List<Uint8List> _attachedFileBytes = [];
  List<String> _fileNames = [];
  List<Uint8List> _filePreviews = [];

  bool _isSubmitting = false;

  String _governorate = "";
  String _workLocation = "";
  late String _currentDate;

  final List<String> _governorates = [
    "بغداد",
    "البصرة",
    "نينوى",
    "أربيل",
    "السليمانية",
    "دهوك",
    "كركوك",
    "صلاح الدين",
    "الأنبار",
    "بابل",
    "واسط",
    "ذي قار",
    "المثنى",
    "الديوانية",
    "ميسان",
    "كربلاء",
    "النجف",
    "ديالى",
  ];

  @override
  void initState() {
    super.initState();
    _currentDate = DateTime.now().toIso8601String().split('T').first;
  }

  // ✅ اختيار الملفات باستخدام file_picker
  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'mp4',
          'pdf',
          'doc',
          'docx',
          'txt'
        ],
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          for (var file in result.files) {
            // file.bytes يحتوي على البايتات
            if (file.bytes != null) {
              _attachedFileBytes.add(file.bytes!);
              _fileNames.add(file.name);
              _filePreviews.add(file.bytes!);
            }
          }
        });
      }
    } catch (e) {
      print("Error picking files: $e");
      _showSnackBar("حدث خطأ أثناء اختيار الملفات");
    }
  }

  void _removeFile(int index) {
    setState(() {
      _attachedFileBytes.removeAt(index);
      _fileNames.removeAt(index);
      _filePreviews.removeAt(index);
    });
  }

  // ✅ لم نعد نحتاج دالة _readFileAsBytes لأن البايتات موجودة مباشرة

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;

    if (_maintenanceType == "site" && _selectedSiteIssue == null) {
      _showSnackBar("الرجاء اختيار نوع عطل الموقع");
      return;
    }
    if (_maintenanceType == "device") {
      if (_selectedDeviceType == null) {
        _showSnackBar("الرجاء اختيار نوع الجهاز");
        return;
      }
      if (_serialNumber.trim().isEmpty) {
        _showSnackBar("الرجاء إدخال السيريال نمبر");
        return;
      }
    }
    if (_problemDescription.trim().isEmpty) {
      _showSnackBar("الرجاء كتابة وصف المشكلة");
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      var uri = Uri.parse("${widget.baseUrl}/api/tickets/create");
      var request = http.MultipartRequest("POST", uri);

      request.fields['userId'] = widget.currentUserId;
      request.fields['maintenanceType'] = _maintenanceType;
      request.fields['problemDescription'] = _problemDescription;
      request.fields['governorate'] = _governorate;
      request.fields['workLocation'] = _workLocation;
      request.fields['date'] = _currentDate;

      if (_maintenanceType == "site") {
        request.fields['siteIssue'] = _selectedSiteIssue!;
      } else {
        request.fields['deviceType'] = _selectedDeviceType!;
        request.fields['serialNumber'] = _serialNumber;
        request.fields['deviceLocation'] = _deviceLocation;
      }

      // ✅ إرفاق الملفات مباشرة من _attachedFileBytes
      for (int i = 0; i < _attachedFileBytes.length; i++) {
        final multipartFile = http.MultipartFile.fromBytes(
          'attachments',
          _attachedFileBytes[i],
          filename: _fileNames[i],
        );
        request.files.add(multipartFile);
      }

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      print("Response status: ${response.statusCode}");
      print("Response body: $responseBody");

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showSnackBar("تم إرسال تذكرة الصيانة بنجاح ✅", isError: false);
        Navigator.pop(context);
      } else {
        String errorMsg = "فشل الإرسال (${response.statusCode})";
        try {
          final Map<String, dynamic> errorJson = jsonDecode(responseBody);
          if (errorJson.containsKey('message'))
            errorMsg = errorJson['message'];
          else if (errorJson.containsKey('error'))
            errorMsg = errorJson['error'];
        } catch (_) {}
        _showSnackBar(errorMsg);
      }
    } catch (e) {
      print("Exception: $e");
      _showSnackBar("خطأ في الاتصال: ${e.toString()}");
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showSnackBar(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "تذكرة صيانة جديدة",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // بطاقة المحافظة وموقع العمل والتاريخ
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "معلومات الموقع والتاريخ",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'المحافظة *',
                        prefixIcon: Icon(
                          Icons.location_on,
                          color: colorScheme.primary,
                        ),
                        border: InputBorder.none,
                        labelStyle: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      value: _governorate.isEmpty ? null : _governorate,
                      hint: Text(
                        'اختر المحافظة',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      items: _governorates
                          .map(
                            (gov) =>
                                DropdownMenuItem(value: gov, child: Text(gov)),
                          )
                          .toList(),
                      onChanged: (val) => setState(() => _governorate = val!),
                      dropdownColor: colorScheme.surface,
                      style: TextStyle(color: colorScheme.onSurface),
                      validator: (v) =>
                          v == null ? 'الرجاء اختيار المحافظة' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      decoration: InputDecoration(
                        labelText: 'موقع العمل *',
                        prefixIcon: Icon(
                          Icons.business_center,
                          color: colorScheme.primary,
                        ),
                        border: InputBorder.none,
                        labelStyle: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                        hintStyle: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      style: TextStyle(color: colorScheme.onSurface),
                      onChanged: (v) => _workLocation = v,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'يرجى إدخال موقع العمل'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _currentDate,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'التاريخ (تلقائي)',
                        prefixIcon: Icon(
                          Icons.calendar_today,
                          color: colorScheme.primary,
                        ),
                        border: InputBorder.none,
                        labelStyle: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // بطاقة نوع الصيانة
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "نوع الصيانة",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMaintenanceTypeRadio(
                            '🏢 صيانة الموقع',
                            'site',
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMaintenanceTypeRadio(
                            '🖥️ صيانة الأجهزة',
                            'device',
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // بطاقة التفاصيل حسب النوع
            if (_maintenanceType == "site") ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "نوع عطل الموقع",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedSiteIssue,
                        hint: Text(
                          "اختر نوع العطل",
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        items: _siteIssues
                            .map(
                              (issue) => DropdownMenuItem(
                                value: issue,
                                child: Text(issue),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedSiteIssue = val),
                        dropdownColor: colorScheme.surface,
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: InputDecoration(border: InputBorder.none),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "بيانات الجهاز",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedDeviceType,
                        hint: Text(
                          "اختر نوع الجهاز",
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        items: _deviceTypes
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedDeviceType = val),
                        dropdownColor: colorScheme.surface,
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey[600]!
                                  : Colors.grey[300]!,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: colorScheme.primary,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor:
                              isDark ? Colors.grey[800] : Colors.grey[50],
                        ),
                        validator: (v) =>
                            v == null ? 'يرجى اختيار نوع الجهاز' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'السيريال نمبر *',
                        ),
                        style: TextStyle(color: colorScheme.onSurface),
                        onChanged: (v) => _serialNumber = v,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'يرجى إدخال السيريال نمبر'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'موقع الجهاز (اختياري)',
                        ),
                        style: TextStyle(color: colorScheme.onSurface),
                        onChanged: (v) => _deviceLocation = v,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // وصف المشكلة
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "وصف المشكلة",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      maxLines: 5,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: "اذكر تفاصيل الصيانة بالضبط...",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (v) => _problemDescription = v,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'يرجى كتابة وصف المشكلة'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // المرفقات
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "المرفقات (صور / فيديو / مستندات)",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _pickFiles,
                      icon: Icon(Icons.attach_file, color: colorScheme.primary),
                      label: Text(
                        "إضافة ملفات",
                        style: TextStyle(color: colorScheme.primary),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isDark ? Colors.grey[800] : Colors.grey[100],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_fileNames.isNotEmpty)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _fileNames.length,
                        itemBuilder: (context, index) {
                          bool isImage = _filePreviews[index].isNotEmpty &&
                              _fileNames[index].contains(
                                RegExp(r'\.(jpg|jpeg|png|gif)'),
                              );
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color:
                                  isDark ? Colors.grey[800] : Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              leading: isImage
                                  ? Image.memory(
                                      _filePreviews[index],
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                    )
                                  : Icon(
                                      Icons.insert_drive_file,
                                      color: colorScheme.primary,
                                    ),
                              title: Text(
                                _fileNames[index],
                                style: TextStyle(color: colorScheme.onSurface),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                ),
                                onPressed: () => _removeFile(index),
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // زر الإرسال
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitTicket,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.send, color: colorScheme.onPrimary),
                label: Text(
                  "إرسال التذكرة",
                  style: TextStyle(color: colorScheme.onPrimary),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMaintenanceTypeRadio(String label, String value, Color color) {
    final isSelected = _maintenanceType == value;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        setState(() {
          _maintenanceType = value;
          if (value == "site") {
            // إعادة تعيين حقول الأجهزة إذا لزم الأمر
          } else {
            _selectedSiteIssue = null;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withOpacity(0.1)
              : (isDark ? Colors.grey[800] : Colors.grey[50]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
            width: 1.5,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? color : colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
