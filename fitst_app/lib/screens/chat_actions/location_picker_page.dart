import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  LatLng? selectedLocation;
  final MapController _mapController = MapController();
  LatLng initialPosition = const LatLng(33.3152, 44.3661); // بغداد افتراضياً
  bool isLoadingLocation = false;

  // دالة جلب الموقع الحالي بدقة عالية
  Future<void> _getCurrentLocation() async {
    setState(() => isLoadingLocation = true);

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => isLoadingLocation = false);
      _showErrorSnackBar("خدمات الموقع معطلة. يرجى تفعيل الـ GPS");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => isLoadingLocation = false);
        _showErrorSnackBar("تم رفض إذن الوصول للموقع");
        return;
      }
    }

    // استخدام LocationAccuracy.high لضمان الموقع "بالضبط"
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    LatLng currentLatLng = LatLng(position.latitude, position.longitude);

    setState(() {
      selectedLocation = currentLatLng;
      isLoadingLocation = false;
    });

    _mapController.move(currentLatLng, 15);
  }

  // دالة موحدة لإرسال البيانات والعودة
  void _sendAndClose(LatLng location) {
    Navigator.pop(context, {
      "lat": location.latitude,
      "lng": location.longitude,
      "address":
          "https://www.google.com/maps/search/?api=1&query=${location.latitude},${location.longitude}",
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "إرسال الموقع",
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF075E54),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // جزء الخريطة
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: initialPosition,
                    initialZoom: 14,
                    onTap: (tapPosition, point) {
                      setState(() => selectedLocation = point);
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                      userAgentPackageName: "com.example.app",
                    ),
                    if (selectedLocation != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: selectedLocation!,
                            width: 50,
                            height: 50,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 45,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                // زر جلب الموقع الحالي العائم
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.white,
                    onPressed: _getCurrentLocation,
                    child: isLoadingLocation
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.my_location,
                            color: Color(0xFF075E54),
                          ),
                  ),
                ),
              ],
            ),
          ),
          // قائمة الخيارات في الأسفل
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.white,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // الخيار الأول: إرسال الموقع الحالي (GPS)
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF075E54),
                      child: Icon(
                        Icons.gps_fixed,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: const Text(
                      "إرسال موقعك الحالي",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF075E54),
                      ),
                    ),
                    subtitle: const Text("تحديد دقيق عبر الأقمار الصناعية"),
                    onTap: () async {
                      await _getCurrentLocation();
                      if (selectedLocation != null) {
                        _sendAndClose(selectedLocation!);
                      }
                    },
                  ),
                  const Divider(height: 1),

                  // الخيار الثاني: إرسال الموقع المختار يدوياً
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF25D366),
                      child: Icon(Icons.location_on, color: Colors.white),
                    ),
                    title: const Text(
                      "إرسال الموقع المختار",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      selectedLocation == null
                          ? "انقر على الخريطة لتحديد نقطة معينة"
                          : "إرسال الموقع المحدد باللون الأحمر",
                    ),
                    onTap: () {
                      if (selectedLocation != null) {
                        _sendAndClose(selectedLocation!);
                      } else {
                        _showErrorSnackBar("يرجى تحديد موقع على الخريطة أولاً");
                      }
                    },
                  ),
                  const Divider(height: 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
