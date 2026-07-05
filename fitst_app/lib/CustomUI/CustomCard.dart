import 'package:flutter/material.dart';
import 'package:fitst_app/Model/ChatModel.dart';
import 'package:fitst_app/screens/IndividualPage.dart';
import 'package:fitst_app/main.dart'; // ✅ استيراد ApiConfig

class CustomCard extends StatelessWidget {
  final ChatModel chatmodel;
  final String myUserId;
  final Future<Map<String, dynamic>> Function(String userId)? fetchUserData;

  const CustomCard({
    Key? key,
    required this.chatmodel,
    required this.myUserId,
    this.fetchUserData,
  }) : super(key: key);

  String _getInitials(String name) {
    if (name.isEmpty) return "?";
    return name.trim()[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryPurple = Color(0xff764ba2);
    const Color accentBlue = Color(0xff667eea);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ استخدام ApiConfig.baseUrl بدلاً من الـ IP الثابت
    final String serverUrl = ApiConfig.baseUrl;

    String otherUserId = chatmodel.participants.firstWhere(
      (id) => id.toString() != myUserId.toString(),
      orElse: () => "",
    );

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                IndividualPage(chatmodel: chatmodel, currentUserId: myUserId),
          ),
        );
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: fetchUserData != null && otherUserId.isNotEmpty
            ? fetchUserData!(otherUserId)
            : Future.value({}),
        builder: (context, snapshot) {
          String displayName = chatmodel.name;
          String jobTitle = "";
          bool isOnline = false;
          String? avatarUrl;

          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            final data = snapshot.data!;
            displayName = data['username'] ?? chatmodel.name;
            jobTitle = data['job'] ?? "";
            isOnline = data['is_online'] ?? false;
            avatarUrl = data['avatar_url'];
          }

          String? fullImageUrl;
          if (avatarUrl != null &&
              avatarUrl.isNotEmpty &&
              avatarUrl != "null") {
            fullImageUrl = avatarUrl.startsWith('http')
                ? avatarUrl
                : "$serverUrl/uploads/${avatarUrl.split('/').last}";
          }

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.white.withOpacity(0.05) : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              leading: Stack(
                children: [
                  Container(
                    width: 55,
                    height: 55,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [accentBlue, primaryPurple],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      image: fullImageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(fullImageUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: fullImageUrl == null
                        ? Center(
                            child: Text(
                              _getInitials(displayName),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : null,
                  ),
                  if (!chatmodel.isGroup)
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? Colors.greenAccent
                              : Colors.grey.shade400,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                isDark ? const Color(0xFF0F172A) : Colors.white,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                jobTitle.isNotEmpty ? "$displayName [$jobTitle]" : displayName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Row(
                children: [
                  Icon(
                    Icons.done_all_rounded,
                    size: 16,
                    color: isOnline ? accentBlue : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      chatmodel.currentMessage,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    chatmodel.time,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                  ),
                  if (isOnline)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        "متصل",
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
