import 'package:flutter/material.dart';
import 'package:fitst_app/Pages/ChatPage.dart';
import 'package:fitst_app/Settings/Setting.dart';
import 'package:fitst_app/CustomUI/ProfilePage.dart';
import 'package:fitst_app/screens/Report.dart';
import 'package:fitst_app/screens/Reports_view.dart';
import 'package:fitst_app/screens/CreateGroupPage.dart';
import 'package:fitst_app/Model/ChatModel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fitst_app/Users/Manager_users.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:fitst_app/main.dart';
import 'package:fitst_app/screens/SelectMembers.dart';
import 'package:fitst_app/screens/IndividualPage.dart';
import 'package:fitst_app/CustomUI/Status.dart';
import 'package:fitst_app/screens/office_status_list_page.dart';
import 'package:fitst_app/screens/office_status_form_page.dart';
import 'package:fitst_app/screens/MaintenanceTicketPage.dart';
import 'package:fitst_app/screens/ViewSiteTicketsPage.dart' as SiteTickets;
import 'package:fitst_app/screens/ViewDeviceTicketsPage.dart' as DeviceTickets;
import 'package:fitst_app/screens/CallHistoryPage.dart';
import 'package:fitst_app/screens/AboutPage.dart'; // ✅ استيراد صفحة About

class Homescreen extends StatefulWidget {
  final String currentUserId;
  const Homescreen({Key? key, required this.currentUserId}) : super(key: key);

  @override
  State<Homescreen> createState() => _HomescreenState();
}

class _HomescreenState extends State<Homescreen> {
  // ✅ تغيير القيمة الابتدائية إلى 2 لتظهر المحادثات أولاً
  int _selectedIndex = 2;

  String role = "user";
  bool isLoading = true;
  late String currentUserId;
  String username = "";
  String email = "";
  String? avatarUrl;
  String? job;
  String? phone;
  List<String> permissions = [];

  IO.Socket? socket;
  bool isSocketConnecting = true;

  final GlobalKey<ChatPageState> _chatPageKey = GlobalKey<ChatPageState>();
  String _searchQuery = '';

  late final String serverUrl;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    serverUrl = ApiConfig.baseUrl;
    currentUserId = widget.currentUserId;
    _loadUserData();
    _initializeSocket();
  }

  void _initializeSocket() {
    try {
      socket = IO.io(
        serverUrl,
        IO.OptionBuilder().setTransports(['websocket']).build(),
      );

      socket!.onConnect((_) {
        debugPrint("✅ Socket متصل بنجاح");
        socket!.emit("signin", widget.currentUserId);
        setState(() => isSocketConnecting = false);
      });

      socket!.onConnectError((error) {
        debugPrint("❌ خطأ في اتصال Socket: $error");
        setState(() => isSocketConnecting = false);
      });

      socket!.onDisconnect((_) {
        debugPrint("⚠️ تم قطع اتصال Socket");
      });

      socket!.connect();
    } catch (e) {
      debugPrint("❌ فشل تهيئة Socket: $e");
      setState(() => isSocketConnecting = false);
    }
  }

  String? _getFullAvatarUrl(String? url) {
    if (url == null || url.isEmpty || url == "null") return null;
    if (url.startsWith('http')) return url;
    String path = url.startsWith('/') ? url : "/uploads/$url";
    return "$serverUrl$path?v=${DateTime.now().millisecondsSinceEpoch}";
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserId = widget.currentUserId.isNotEmpty
          ? widget.currentUserId
          : prefs.getString("user_id") ?? "";

      role = prefs.getString("role") ?? "user";
      username = prefs.getString("username") ?? "User";
      email = prefs.getString("email") ?? "";
      avatarUrl = prefs.getString("avatar_url");
      job = prefs.getString("job");
      phone = prefs.getString("phone");
      permissions = prefs.getStringList("permissions") ?? [];
      isLoading = false;
    });

    // الترتيب الأصلي: المستخدمين، المكاتب، المحادثات، المكالمات
    _pages = [
      Status(currentUserId: currentUserId, socket: socket),
      OfficeStatusListPage(baseUrl: serverUrl, currentUserId: currentUserId),
      ChatPage(
        key: _chatPageKey,
        currentUserId: currentUserId,
        socket: socket!,
        showAppBar: false,
        initialSearchQuery: _searchQuery,
      ),
      CallHistoryPage(
        currentUserId: currentUserId,
        baseUrl: serverUrl,
        socket: socket,
      ),
    ];
  }

  Future<void> _createNewGroup() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            CreateGroupPage(currentUserId: currentUserId, baseUrl: serverUrl),
      ),
    );
    if (result != null && result is ChatModel && mounted) {
      _chatPageKey.currentState?.refreshChats();
    }
  }

  void handleMenu(String value) async {
    switch (value) {
      case "Profile":
        final updatedData = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfilePage(
              userData: {
                "id": currentUserId,
                "username": username,
                "email": email,
                "avatar_url": avatarUrl,
                "job": job,
                "phone": phone,
              },
            ),
          ),
        );
        if (updatedData != null) {
          final prefs = await SharedPreferences.getInstance();
          setState(() {
            username = updatedData['username'] ?? username;
            avatarUrl = updatedData['avatar_url'];
            job = updatedData['job'] ?? job;
            phone = updatedData['phone'] ?? phone;
          });
          await prefs.setString("username", username);
          await prefs.setString("phone", phone ?? "");
          if (avatarUrl != null && avatarUrl!.isNotEmpty) {
            await prefs.setString("avatar_url", avatarUrl!);
          } else {
            await prefs.remove("avatar_url");
          }
          if (job != null) await prefs.setString("job", job!);
        }
        break;

      case "Settings":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SettingPage(
              onLogout: () {
                socket?.emit("logout", widget.currentUserId);
                socket?.disconnect();
                socket = null;
              },
            ),
          ),
        );
        break;

      case "UsersManagementPage":
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const UsersManagementPage()),
        );
        break;

      case "CreateReport":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateReportPage(
              baseUrl: serverUrl,
              currentUserId: currentUserId,
            ),
          ),
        );
        break;

      case "ViewReports":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ViewReportsPage(
              baseUrl: serverUrl,
              currentUserId: currentUserId,
            ),
          ),
        );
        break;

      case "SubmitOfficeStatus":
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OfficeStatusFormPage(
              baseUrl: serverUrl,
              currentUserId: currentUserId,
              onSaved: () {
                if (_pages.length > 1 && _pages[1] is OfficeStatusListPage) {
                  setState(() {
                    _pages[1] = OfficeStatusListPage(
                      baseUrl: serverUrl,
                      currentUserId: currentUserId,
                    );
                  });
                }
              },
            ),
          ),
        );
        break;

      case "CreateGroup":
        _createNewGroup();
        break;

      case "Submit Ticket":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MaintenanceTicketPage(
              baseUrl: serverUrl,
              currentUserId: currentUserId,
            ),
          ),
        );
        break;

      case "View Site Tickets":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SiteTickets.ViewSiteTicketsPage(
              baseUrl: serverUrl,
              currentUserId: currentUserId,
            ),
          ),
        );
        break;

      case "View Device Tickets":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DeviceTickets.ViewDeviceTicketsPage(
              baseUrl: serverUrl,
              currentUserId: currentUserId,
            ),
          ),
        );
        break;

      // ✅ إضافة حالة About
      case "About":
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AboutPage(),
          ),
        );
        break;

      default:
        break;
    }
  }

  PopupMenuItem<String> _buildPopupItem(
    String value,
    IconData icon,
    String title,
  ) {
    final theme = Theme.of(context);
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 22, color: theme.iconTheme.color),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startNewChat() async {
    final selectedUser = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SelectMembers(currentUserId: currentUserId, multiSelect: false),
      ),
    );
    if (selectedUser != null && selectedUser is ChatModel && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IndividualPage(
            chatmodel: selectedUser,
            currentUserId: currentUserId,
            existingSocket: socket!,
          ),
        ),
      );
      _chatPageKey.currentState?.refreshChats();
    }
  }

  @override
  void dispose() {
    if (socket != null) {
      socket!.emit("logout", widget.currentUserId);
      socket!.disconnect();
      socket = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || isSocketConnecting || _pages.length < 4) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    String? fullImage = _getFullAvatarUrl(avatarUrl);
    bool isManager = (role == "manager");
    bool canManageUsers = isManager || permissions.contains("ادارة المستخدمين");
    bool canReport = isManager || permissions.contains("رفع التبليغات");
    bool canTicket = permissions.contains("رفع التذاكر");
    bool canViewSiteTickets =
        isManager || permissions.contains("عرض حالات صيانة الموقع");
    bool canViewDeviceTickets =
        isManager || permissions.contains("عرض حالات صيانة اجهزة الموقع");

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: AppBar(
          elevation: 0,
          backgroundColor: colorScheme.surface,
          title: null,
          actions: [
            IconButton(
              icon: Icon(
                isDark ? Icons.light_mode : Icons.dark_mode,
                color: colorScheme.primary,
              ),
              onPressed: () {
                final notifier = ThemeNotifier.of(context);
                notifier?.toggleTheme();
              },
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: colorScheme.primary),
              onSelected: handleMenu,
              color: colorScheme.surface,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: "Profile",
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: colorScheme.primary.withOpacity(0.1),
                        backgroundImage:
                            fullImage != null ? NetworkImage(fullImage) : null,
                        child: fullImage == null
                            ? Icon(Icons.person,
                                size: 20, color: colorScheme.primary)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            username,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                          Text(
                            "ملفي الشخصي",
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                _buildPopupItem(
                    "CreateGroup", Icons.group_add, "إنشاء مجموعة جديدة"),
                _buildPopupItem(
                    "Settings", Icons.settings_outlined, "الإعدادات"),
                _buildPopupItem(
                    "ViewReports", Icons.analytics_outlined, "عرض التبليغ"),
                if (canManageUsers)
                  _buildPopupItem(
                    "UsersManagementPage",
                    Icons.manage_accounts_outlined,
                    "إدارة المستخدمين",
                  ),
                if (canReport)
                  _buildPopupItem(
                      "CreateReport", Icons.assignment_outlined, "إنشاء تبليغ"),
                if (canTicket)
                  _buildPopupItem("Submit Ticket",
                      Icons.confirmation_number_outlined, "تقديم تذكرة"),
                if (canViewSiteTickets)
                  _buildPopupItem("View Site Tickets", Icons.business,
                      "تذاكر صيانة الموقع"),
                if (canViewDeviceTickets)
                  _buildPopupItem("View Device Tickets", Icons.computer,
                      "تذاكر صيانة الأجهزة"),
                const PopupMenuDivider(),
                _buildPopupItem("About", Icons.info_outline, "حول التطبيق"),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(30),
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: "بحث...",
                    prefixIcon: Icon(
                      Icons.search,
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                    _chatPageKey.currentState?.updateSearchQuery(_searchQuery);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: colorScheme.primary,
        unselectedItemColor: isDark ? Colors.white60 : Colors.grey[600],
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.people), label: "المستخدمين"),
          BottomNavigationBarItem(icon: Icon(Icons.business), label: "المكاتب"),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline), label: "المحادثات"),
          BottomNavigationBarItem(
              icon: Icon(Icons.call_outlined), label: "المكالمات"),
        ],
      ),
    );
  }
}
