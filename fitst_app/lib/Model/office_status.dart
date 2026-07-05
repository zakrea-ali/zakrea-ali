class OfficeStatus {
  final String id;
  final String officeName;
  final String shift; // 'morning' or 'evening'
  final String ownerId;
  final String status; // 'working', 'problem', 'closed'
  final List<String>? problemType;
  final String? problemDetails;
  final String? imageUrl; // deprecated, kept for compatibility
  final List<String>? imageUrls; // new: list of image URLs
  final DateTime createdAt;
  final DateTime updatedAt;

  // الحقول الجديدة لاسم وصورة رافع الحالة
  final String? ownerName;
  final String? ownerAvatarUrl;

  OfficeStatus({
    required this.id,
    required this.officeName,
    required this.shift,
    required this.ownerId,
    required this.status,
    this.problemType,
    this.problemDetails,
    this.imageUrl,
    this.imageUrls,
    required this.createdAt,
    required this.updatedAt,
    this.ownerName,
    this.ownerAvatarUrl,
  });

  factory OfficeStatus.fromJson(Map<String, dynamic> json) {
    return OfficeStatus(
      id: json['id'],
      officeName: json['office_name'],
      shift: json['shift'] ?? 'morning',
      ownerId: json['owner_id'],
      status: json['status'],
      problemType: json['problem_type'] != null
          ? List<String>.from(json['problem_type'])
          : null,
      problemDetails: json['problem_details'],
      imageUrl: json['image_url'],
      imageUrls: json['image_urls'] != null
          ? List<String>.from(json['image_urls'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      ownerName: json['owner_name'], // قراءة اسم رافع الحالة
      ownerAvatarUrl: json['owner_image_url'], // قراءة صورة رافع الحالة
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'office_name': officeName,
    'shift': shift,
    'owner_id': ownerId,
    'status': status,
    'problem_type': problemType,
    'problem_details': problemDetails,
    'image_url': imageUrl,
    'image_urls': imageUrls,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'owner_name': ownerName,
    'owner_image_url': ownerAvatarUrl,
  };
}

class OfficeHistory {
  final String id;
  final String officeName;
  final String? shift;
  final String? ownerId;
  final String status;
  final List<String>? problemType;
  final String? problemDetails;
  final String? imageUrl; // kept for compatibility
  final List<String>? imageUrls;
  final String action; // 'create', 'update', 'delete', 'auto_close'
  final DateTime changedAt;
  final String? changedBy;

  OfficeHistory.fromJson(Map<String, dynamic> json)
    : id = json['id'],
      officeName = json['office_name'],
      shift = json['shift'],
      ownerId = json['owner_id'],
      status = json['status'],
      problemType = json['problem_type'] != null
          ? List<String>.from(json['problem_type'])
          : null,
      problemDetails = json['problem_details'],
      imageUrl = json['image_url'],
      imageUrls = json['image_urls'] != null
          ? List<String>.from(json['image_urls'])
          : null,
      action = json['action'],
      changedAt = DateTime.parse(json['changed_at']),
      changedBy = json['changed_by'];
}
