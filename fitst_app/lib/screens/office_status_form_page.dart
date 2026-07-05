import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fitst_app/Model/office_api_service.dart';
import 'package:fitst_app/Model/office_status.dart';

class OfficeStatusFormPage extends StatefulWidget {
  final String baseUrl;
  final String currentUserId;
  final OfficeStatus? existingOffice;
  final VoidCallback onSaved;

  const OfficeStatusFormPage({
    required this.baseUrl,
    required this.currentUserId,
    this.existingOffice,
    required this.onSaved,
    Key? key,
  }) : super(key: key);

  @override
  State<OfficeStatusFormPage> createState() => _OfficeStatusFormPageState();
}

class _OfficeStatusFormPageState extends State<OfficeStatusFormPage> {
  late OfficeApiService _api;
  final _formKey = GlobalKey<FormState>();
  final _officeNameController = TextEditingController();
  final _problemDetailsController = TextEditingController();

  String _selectedShift = 'morning';
  String _selectedStatus = 'working';
  List<String> _selectedProblems = [];
  Uint8List? _imageBytes;
  String? _existingImageUrl;
  bool _loading = false;
  bool _userHasExistingStatus = false;
  bool _checkingExistingStatus = true;

  final List<String> _problemOptions = [
    'الاستعلامات',
    'الاستلام',
    'دفع',
    'تبادل',
    'الطباعة',
    'الجودة',
    'التسليم',
  ];

  void _clearProblemDetails() {
    _selectedProblems.clear();
    _problemDetailsController.clear();
    _imageBytes = null;
    _existingImageUrl = null;
  }

  @override
  void initState() {
    super.initState();
    _api = OfficeApiService(widget.baseUrl);
    _checkIfUserHasExistingStatus();

    if (widget.existingOffice != null) {
      _officeNameController.text = widget.existingOffice!.officeName;
      _selectedShift = widget.existingOffice!.shift;
      _selectedStatus = widget.existingOffice!.status;
      if (widget.existingOffice!.problemType != null) {
        _selectedProblems = List.from(widget.existingOffice!.problemType!);
      }
      if (widget.existingOffice!.problemDetails != null) {
        _problemDetailsController.text = widget.existingOffice!.problemDetails!;
      }
      if (widget.existingOffice!.imageUrl != null) {
        _existingImageUrl = widget.existingOffice!.imageUrl;
      }
    }
  }

  Future<void> _checkIfUserHasExistingStatus() async {
    try {
      final allStatuses = await _api.fetchOfficeStatuses();
      final hasStatus = allStatuses.any(
        (status) => status.ownerId == widget.currentUserId,
      );
      setState(() {
        _userHasExistingStatus = hasStatus;
        _checkingExistingStatus = false;
      });
    } catch (e) {
      setState(() {
        _userHasExistingStatus = false;
        _checkingExistingStatus = false;
      });
    }
  }

  @override
  void dispose() {
    _officeNameController.dispose();
    _problemDetailsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _existingImageUrl = null;
      });
    }
  }

  void _removeImage() {
    setState(() {
      _imageBytes = null;
      _existingImageUrl = null;
    });
  }

  Future<void> _submit() async {
    final officeName = _officeNameController.text.trim();
    if (officeName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يرجى إدخال اسم المكتب'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStatus == 'problem' && _selectedProblems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('يرجى تحديد نوع المشكلة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (widget.existingOffice == null && _userHasExistingStatus) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا يمكنك إنشاء أكثر من حالة. قم بتعديل الحالة الموجودة.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await _api.saveOfficeStatus(
        officeName: officeName,
        shift: _selectedShift,
        status: _selectedStatus,
        problemType: _selectedStatus == 'problem' ? _selectedProblems : null,
        problemDetails: _problemDetailsController.text.trim().isEmpty
            ? null
            : _problemDetailsController.text.trim(),
        imageUrl: _existingImageUrl,
        userId: widget.currentUserId,
        imageBytes: _imageBytes,
      );
      widget.onSaved();
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingExistingStatus) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bool isCreationBlocked =
        (widget.existingOffice == null && _userHasExistingStatus);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingOffice == null
              ? 'إنشاء حالة مكتب'
              : 'تعديل حالة المكتب',
          style: const TextStyle(fontWeight: FontWeight.bold),
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
            // بطاقة اسم المكتب
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TextFormField(
                  controller: _officeNameController,
                  enabled: !isCreationBlocked,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: 'اسم المكتب',
                    hintText: 'مثال: مكتب الكاظمية',
                    prefixIcon: Icon(
                      Icons.business,
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
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'يرجى إدخال اسم المكتب'
                      : null,
                ),
              ),
            ),
            if (isCreationBlocked)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 12),
                child: Text(
                  '⚠️ لديك حالة مسبقة. لا يمكنك إنشاء حالة جديدة.',
                  style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),

            // بطاقة الشفت
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'الشفت',
                    prefixIcon: Icon(
                      Icons.access_time,
                      color: colorScheme.primary,
                    ),
                    border: InputBorder.none,
                    labelStyle: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  value: _selectedShift,
                  items: const [
                    DropdownMenuItem(
                      value: 'morning',
                      child: Text('الشفت الصباحي'),
                    ),
                    DropdownMenuItem(
                      value: 'evening',
                      child: Text('الشفت المسائي'),
                    ),
                  ],
                  onChanged: isCreationBlocked
                      ? null
                      : (val) {
                          if (val != null && val != _selectedShift) {
                            setState(() {
                              _selectedShift = val;
                              _selectedStatus = 'working';
                              _clearProblemDetails();
                            });
                          }
                        },
                  dropdownColor: colorScheme.surface,
                  style: TextStyle(color: colorScheme.onSurface),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // بطاقة حالة المكتب
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
                      'حالة المكتب',
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
                          child: _buildStatusRadio(
                            '🟢 شغال',
                            'working',
                            Colors.green,
                            enabled: !isCreationBlocked,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatusRadio(
                            '🔴 مشكلة',
                            'problem',
                            Colors.orange,
                            enabled: !isCreationBlocked,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatusRadio(
                            '⚫ مغلق',
                            'closed',
                            Colors.grey,
                            enabled: !isCreationBlocked,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // قسم المشكلة
            if (_selectedStatus == 'problem') ...[
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
                        'نوع المشكلة',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _problemOptions.map((opt) {
                          final isSelected = _selectedProblems.contains(opt);
                          return FilterChip(
                            label: Text(opt),
                            selected: isSelected,
                            onSelected: isCreationBlocked
                                ? null
                                : (selected) {
                                    setState(() {
                                      if (selected)
                                        _selectedProblems.add(opt);
                                      else
                                        _selectedProblems.remove(opt);
                                    });
                                  },
                            backgroundColor: isDark
                                ? Colors.grey[800]
                                : Colors.grey[100],
                            selectedColor: colorScheme.primary.withOpacity(0.2),
                            checkmarkColor: colorScheme.primary,
                            labelStyle: TextStyle(color: colorScheme.onSurface),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _problemDetailsController,
                        maxLines: 3,
                        enabled: !isCreationBlocked,
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: 'تفاصيل إضافية (اختياري)',
                          hintText: 'أدخل تفاصيل إضافية عن المشكلة...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          labelStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          hintStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'صورة مرفقة (اختياري)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_imageBytes != null || _existingImageUrl != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Stack(
                            alignment: Alignment.topRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _imageBytes != null
                                    ? Image.memory(
                                        _imageBytes!,
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                      )
                                    : _existingImageUrl != null
                                    ? Image.network(
                                        widget.baseUrl + _existingImageUrl!,
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                              Icons.broken_image,
                                              size: 120,
                                            ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              if (!isCreationBlocked)
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                  ),
                                  onPressed: _removeImage,
                                ),
                            ],
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: isCreationBlocked ? null : _pickImage,
                        icon: Icon(
                          Icons.photo_library,
                          color: colorScheme.primary,
                        ),
                        label: Text(
                          'اختيار صورة',
                          style: TextStyle(color: colorScheme.primary),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? Colors.grey[800]
                              : Colors.grey[100],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // زر الحفظ
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: (isCreationBlocked || _loading) ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.save, color: colorScheme.onPrimary),
                label: Text(
                  widget.existingOffice == null
                      ? 'إنشاء الحالة'
                      : 'تحديث الحالة',
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

  Widget _buildStatusRadio(
    String label,
    String value,
    Color color, {
    bool enabled = true,
  }) {
    final isSelected = _selectedStatus == value;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: enabled
          ? () {
              setState(() {
                if (_selectedStatus != value) {
                  _selectedStatus = value;
                  if (value != 'problem') _clearProblemDetails();
                }
              });
            }
          : null,
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
              color: enabled
                  ? (isSelected ? color : colorScheme.onSurface)
                  : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }
}
