import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fitst_app/Model/ChatModel.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fitst_app/main.dart'; // ✅ استيراد ApiConfig

class MembersCard extends StatelessWidget {
  final ChatModel members;
  final String? serverUrl; // ✅ أصبح اختيارياً بدون قيمة افتراضية

  const MembersCard({
    Key? key,
    required this.members,
    this.serverUrl, // ✅ لا قيمة افتراضية
  }) : super(key: key);

  // ✅ دالة مساعدة للحصول على الرابط الصحيح
  String get _baseUrl => serverUrl ?? ApiConfig.baseUrl;

  Future<Map<String, dynamic>> fetchMemberData(String memberId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/getUser?id=$memberId'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {};
      }
    } catch (e) {
      debugPrint("Error fetching member data: $e");
      return {};
    }
  }

  String _getInitials(String name) {
    if (name.isEmpty) return "?";
    return name.trim()[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: fetchMemberData(members.id),
      builder: (context, snapshot) {
        String displayName = members.name;
        String status = members.status;
        bool isOnline = false;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          displayName = snapshot.data!['name'] ?? members.name;
          status = snapshot.data!['job'] ?? members.status;
          isOnline = snapshot.data!['isOnline'] ?? false;
        }

        return InkWell(
          onTap: () {},
          child: ListTile(
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: Colors.blueGrey[200],
                  child: SvgPicture.asset(
                    "assets/person.svg",
                    color: Colors.white,
                    height: 30,
                    width: 30,
                    placeholderBuilder: (context) => Text(
                      _getInitials(displayName),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (isOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              displayName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(status, style: const TextStyle(fontSize: 13)),
          ),
        );
      },
    );
  }
}
