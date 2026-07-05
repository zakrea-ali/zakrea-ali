import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show File;
import 'package:fitst_app/main.dart'; // ✅ استيراد ApiConfig

class ProfilePage extends StatefulWidget {
  final Map<String, dynamic> userData;
  final bool isReadOnly;

  const ProfilePage({Key? key, required this.userData, this.isReadOnly = false})
      : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late String _userId;
  late String _username;
  late String _phone;
  late String _email;
  late String _job;
  late String? _avatarUrl;

  XFile? _pickedFile;
  bool _isImageDeleted = false;
  bool _isEditing = false;
  bool _isSaving = false;

  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  // ✅ استخدام ApiConfig.baseUrl بدلاً من الـ IP الثابت
  String get serverUrl => ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    _initControllers();
  }

  void _loadLocalData() {
    _userId = widget.userData['id'].toString();
    _username = widget.userData['username'] ?? "";
    _phone = widget.userData['phone'] ?? "";
    _email = widget.userData['email'] ?? "غير محدد";
    _job = widget.userData['job'] ?? "غير محدد";
    _avatarUrl = widget.userData['avatar_url'];
    _pickedFile = null;
    _isImageDeleted = false;
  }

  void _initControllers() {
    _nameController = TextEditingController(text: _username);
    _phoneController = TextEditingController(text: _phone);
  }

  void _updateControllers() {
    _nameController.text = _username;
    _phoneController.text = _phone;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _getFullImageUrl(String? url) {
    if (_isImageDeleted) return null;
    if (url == null || url.isEmpty || url == "null") return null;
    if (url.startsWith('http')) return url;
    String fileName = url.split('/').last;
    return "$serverUrl/uploads/$fileName?v=${DateTime.now().millisecondsSinceEpoch}";
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _pickedFile = image;
        _isImageDeleted = false;
      });
    }
  }

  void _removePhoto() {
    setState(() {
      _pickedFile = null;
      _avatarUrl = null;
      _isImageDeleted = true;
    });
  }

  Future<void> _updateProfile() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final url = Uri.parse("$serverUrl/users/update_profile");
      var request = http.MultipartRequest('POST', url);

      request.fields['id'] = _userId.trim();
      request.fields['username'] = _nameController.text.trim();
      request.fields['phone'] = _phoneController.text.trim();
      request.fields['job'] = _job.toString().trim();

      if (_pickedFile != null) {
        if (kIsWeb) {
          final bytes = await _pickedFile!.readAsBytes();
          request.files.add(
            http.MultipartFile.fromBytes(
              'avatar',
              bytes,
              filename: _pickedFile!.name,
            ),
          );
        } else {
          request.files.add(
            await http.MultipartFile.fromPath('avatar', _pickedFile!.path),
          );
        }
      } else if (_isImageDeleted) {
        request.fields['avatar_url'] = 'null';
      } else if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
        String fileName = _avatarUrl!.split('/').last;
        request.fields['avatar_url'] = fileName;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final updatedUser = responseData['user'] ?? responseData;

        setState(() {
          _username = updatedUser['username'] ?? _username;
          _phone = updatedUser['phone'] ?? _phone;
          _job = updatedUser['job'] ?? _job;
          _avatarUrl = updatedUser['avatar_url'] ?? updatedUser['user_file'];
          _pickedFile = null;
          _isImageDeleted = false;
          _isEditing = false;
          _updateControllers();
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("username", _username);
        await prefs.setString("phone", _phone);
        if (_avatarUrl != null && _avatarUrl!.isNotEmpty) {
          await prefs.setString("avatar_url", _avatarUrl!);
        } else {
          await prefs.remove("avatar_url");
        }

        widget.userData['username'] = _username;
        widget.userData['phone'] = _phone;
        widget.userData['job'] = _job;
        widget.userData['avatar_url'] = _avatarUrl;
        widget.userData['user_file'] = _avatarUrl;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("✅ تم تحديث البيانات بنجاح"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, widget.userData);
        }
      } else {
        String errorMsg = await _extractErrorMessage(response);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ $errorMsg"), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      print("Update error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("⚠️ خطأ في الاتصال: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String> _extractErrorMessage(http.Response response) async {
    try {
      final body = jsonDecode(response.body);
      return body['message'] ??
          body['error'] ??
          "فشل التحديث (${response.statusCode})";
    } catch (_) {
      return "فشل التحديث (${response.statusCode})";
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, widget.userData);
        return false;
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(colorScheme),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _buildInputField(
                      label: "الاسم الكامل",
                      controller: _nameController,
                      icon: Icons.person_rounded,
                      enabled: _isEditing && !widget.isReadOnly,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 15),
                    _buildInputField(
                      label: "رقم الهاتف",
                      controller: _phoneController,
                      icon: Icons.phone_android_rounded,
                      enabled: _isEditing && !widget.isReadOnly,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 15),
                    _buildReadOnlyField(
                      label: "البريد الإلكتروني",
                      value: _email,
                      icon: Icons.email_outlined,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 15),
                    _buildReadOnlyField(
                      label: "الوظيفة",
                      value: _job,
                      icon: Icons.work_outline_rounded,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(height: 30),
                    if (_isEditing && !widget.isReadOnly)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _isSaving ? null : _updateProfile,
                          child: _isSaving
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  "تحديث البيانات",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    String? displayImageUrl;
    if (_pickedFile == null &&
        !_isImageDeleted &&
        _avatarUrl != null &&
        _avatarUrl!.isNotEmpty) {
      displayImageUrl = _getFullImageUrl(_avatarUrl);
    }

    return Container(
      height: 320,
      child: Stack(
        children: [
          Container(
            height: 240,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary,
                  colorScheme.primary.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(50),
                bottomRight: Radius.circular(50),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context, widget.userData),
                  ),
                  Text(
                    _isEditing ? "تعديل الملف" : "الملف الشخصي",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  widget.isReadOnly
                      ? const SizedBox(width: 48)
                      : IconButton(
                          icon: Icon(
                            _isEditing ? Icons.close : Icons.edit_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () => setState(() {
                            _isEditing = !_isEditing;
                            if (!_isEditing) {
                              _loadLocalData();
                              _updateControllers();
                            }
                          }),
                        ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.surface, width: 5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: _buildAvatarImage(displayImageUrl, colorScheme),
                  ),
                  if (_isEditing && !widget.isReadOnly) ...[
                    Positioned(
                      bottom: 5,
                      right: 5,
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          backgroundColor: colorScheme.primary,
                          radius: 20,
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                    if ((_avatarUrl != null && !_isImageDeleted) ||
                        _pickedFile != null)
                      Positioned(
                        bottom: 5,
                        left: 5,
                        child: GestureDetector(
                          onTap: _removePhoto,
                          child: const CircleAvatar(
                            backgroundColor: Colors.redAccent,
                            radius: 20,
                            child: Icon(
                              Icons.delete_forever,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarImage(String? imageUrl, ColorScheme colorScheme) {
    if (_pickedFile != null) {
      if (kIsWeb) {
        return FutureBuilder<Uint8List>(
          future: _pickedFile!.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return CircleAvatar(
                radius: 70,
                backgroundImage: MemoryImage(snapshot.data!),
              );
            }
            return CircleAvatar(
              radius: 70,
              backgroundColor: colorScheme.surfaceContainerHighest,
              child: const CircularProgressIndicator(),
            );
          },
        );
      } else {
        return CircleAvatar(
          radius: 70,
          backgroundImage: FileImage(File(_pickedFile!.path)),
        );
      }
    }
    return CircleAvatar(
      radius: 70,
      backgroundColor: colorScheme.surfaceContainerHighest,
      backgroundImage: imageUrl != null && imageUrl.isNotEmpty
          ? NetworkImage(imageUrl)
          : null,
      child: (imageUrl == null || imageUrl.isEmpty)
          ? Icon(
              Icons.person,
              size: 80,
              color: colorScheme.onSurface.withOpacity(0.5),
            )
          : null,
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool enabled,
    required ColorScheme colorScheme,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: enabled
                  ? colorScheme.primary
                  : colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  enabled
                      ? TextField(
                          controller: controller,
                          style: TextStyle(color: colorScheme.onSurface),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        )
                      : Text(
                          controller.text,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color: colorScheme.onSurface.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
