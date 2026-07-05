import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fitst_app/main.dart'; // ✅ استيراد ApiConfig

class IncomingCallOverlay extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final String callerName;
  final String? callerAvatar;
  final bool isVideo;
  final String? serverUrl; // ✅ لإكمال الروابط النسبية

  const IncomingCallOverlay({
    Key? key,
    required this.onAccept,
    required this.onReject,
    required this.callerName,
    this.callerAvatar,
    required this.isVideo,
    this.serverUrl,
  }) : super(key: key);

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  // ✅ دالة مساعدة لتحويل الرابط إلى رابط كامل
  String? _getFullImageUrl(String? url) {
    if (url == null || url.isEmpty || url == "null") return null;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    // ✅ استخدام ApiConfig.baseUrl كقيمة افتراضية
    final baseUrl = widget.serverUrl ?? ApiConfig.baseUrl;
    String cleanUrl = url.startsWith('/') ? url.substring(1) : url;

    // التعامل مع المجلدات المختلفة
    if (cleanUrl.startsWith('uploads/') ||
        cleanUrl.startsWith('uploads_camera/') ||
        cleanUrl.startsWith('uploads_office/') ||
        cleanUrl.startsWith('uploads_reports/') ||
        cleanUrl.startsWith('uploads_tickets/')) {
      return '$baseUrl/$cleanUrl';
    }

    if (cleanUrl.startsWith('camera-') ||
        cleanUrl.startsWith('voice_') ||
        cleanUrl.startsWith('profile_') ||
        cleanUrl.startsWith('office_') ||
        cleanUrl.startsWith('report_') ||
        cleanUrl.startsWith('ticket_')) {
      if (cleanUrl.startsWith('camera-')) {
        return '$baseUrl/uploads_camera/$cleanUrl';
      } else if (cleanUrl.startsWith('office_')) {
        return '$baseUrl/uploads_office/$cleanUrl';
      } else if (cleanUrl.startsWith('report_')) {
        return '$baseUrl/uploads_reports/$cleanUrl';
      } else if (cleanUrl.startsWith('ticket_')) {
        return '$baseUrl/uploads_tickets/$cleanUrl';
      } else {
        return '$baseUrl/uploads/$cleanUrl';
      }
    }

    return '$baseUrl/uploads/$cleanUrl';
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();

    // منع الخروج بالضغط على زر الرجوع (للحفاظ على التجربة)
    SystemChannels.platform.invokeMethod('SystemNavigator.setEnabled', false);
  }

  @override
  void dispose() {
    _controller.dispose();
    // إعادة تفعيل زر الرجوع بعد الإغلاق
    SystemChannels.platform.invokeMethod('SystemNavigator.setEnabled', true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fullImageUrl = _getFullImageUrl(widget.callerAvatar);

    return WillPopScope(
      onWillPop: () async => false, // منع إغلاق الـ Overlay بالرجوع
      child: Material(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Card(
              elevation: 24,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              color: Theme.of(context).cardColor,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ✅ صورة المتصل (دائرية) أو أيقونة افتراضية
                    ClipOval(
                      child: fullImageUrl != null && fullImageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: fullImageUrl,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                width: 90,
                                height: 90,
                                color: Colors.grey[300],
                                child: const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.grey,
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                width: 90,
                                height: 90,
                                color: Colors.grey[300],
                                child: const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : CircleAvatar(
                              radius: 45,
                              backgroundColor: Colors.grey[300],
                              child: Icon(
                                widget.isVideo ? Icons.videocam : Icons.phone,
                                size: 40,
                                color: Colors.grey[600],
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),
                    // اسم المتصل
                    Text(
                      widget.callerName,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    // نوع المكالمة
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.isVideo ? Icons.videocam : Icons.phone,
                          color: widget.isVideo ? Colors.blue : Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isVideo
                              ? 'مكالمة فيديو واردة'
                              : 'مكالمة صوتية واردة',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // أزرار القبول والرفض
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // ❌ زر رفض
                        _buildActionButton(
                          icon: Icons.call_end,
                          label: 'رفض',
                          color: Colors.red,
                          onPressed: widget.onReject,
                        ),
                        // ✅ زر قبول
                        _buildActionButton(
                          icon: Icons.call,
                          label: 'قبول',
                          color: Colors.green,
                          onPressed: widget.onAccept,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        FloatingActionButton(
          heroTag: label,
          onPressed: onPressed,
          backgroundColor: color,
          elevation: 4,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[700],
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
