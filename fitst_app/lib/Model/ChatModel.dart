class ChatModel {
  final String id;
  final String name;
  final String icon;
  final bool isGroup;
  final String time;
  final String currentMessage;
  final String status;
  final bool isOnline;
  final String lastSeen;
  final List<String> participants;
  final List<String> permissions;
  final String createdBy;
  final int unreadCount; // <-- الحقل الجديد

  const ChatModel({
    required this.id,
    required this.name,
    this.icon = "",
    this.isGroup = false,
    this.time = "",
    this.currentMessage = "",
    this.status = "",
    this.isOnline = false,
    this.lastSeen = "",
    this.participants = const [],
    this.permissions = const [],
    required this.createdBy,
    this.unreadCount = 0, // <-- هنا
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    return ChatModel(
      id: json['id']?.toString() ?? "",
      name: json['username'] ?? json['name'] ?? "Unknown",
      icon: json['icon'] ?? "",
      status: json['job'] ?? json['status'] ?? "",
      isOnline:
          json['is_online'] == true || json['is_online']?.toString() == "true",
      isGroup:
          json['is_group'] == true || json['is_group']?.toString() == "true",
      currentMessage: json['last_message'] ?? "",
      time: json['last_time']?.toString() ?? "",
      lastSeen: json['last_seen']?.toString() ?? "",
      participants: json['participants'] != null
          ? List<String>.from(json['participants'].map((e) => e.toString()))
          : [],
      permissions: json['permissions'] != null
          ? List<String>.from(json['permissions'].map((e) => e.toString()))
          : [],
      createdBy: json['created_by']?.toString() ?? "",
      unreadCount: json['unread_count'] ?? 0, // <-- استقبال العدد
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "name": name,
      "status": status,
      "is_online": isOnline,
      "is_group": isGroup,
      "last_seen": lastSeen,
      "permissions": permissions,
      "created_by": createdBy,
      "unread_count": unreadCount,
    };
  }

  ChatModel copyWith({
    String? id,
    String? name,
    String? icon,
    bool? isGroup,
    String? time,
    String? currentMessage,
    String? status,
    bool? isOnline,
    String? lastSeen,
    List<String>? participants,
    List<String>? permissions,
    String? createdBy,
    int? unreadCount,
  }) {
    return ChatModel(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      isGroup: isGroup ?? this.isGroup,
      time: time ?? this.time,
      currentMessage: currentMessage ?? this.currentMessage,
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      participants: participants ?? this.participants,
      permissions: permissions ?? this.permissions,
      createdBy: createdBy ?? this.createdBy,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}
