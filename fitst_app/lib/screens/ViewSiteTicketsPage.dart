import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ViewSiteTicketsPage extends StatefulWidget {
  final String baseUrl;
  final String currentUserId;

  const ViewSiteTicketsPage({
    Key? key,
    required this.baseUrl,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<ViewSiteTicketsPage> createState() => _ViewSiteTicketsPageState();
}

class _ViewSiteTicketsPageState extends State<ViewSiteTicketsPage> {
  List<dynamic> _tickets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchTickets();
  }

  Future<void> _fetchTickets() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        "${widget.baseUrl}/api/tickets/list?type=site&userId=${widget.currentUserId}",
      );
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tickets = data['tickets'] ?? [];
        setState(() {
          _tickets = tickets;
          _loading = false;
        });
      } else {
        setState(() {
          _error = "فشل تحميل البيانات: ${response.statusCode}";
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = "خطأ في الاتصال: $e";
        _loading = false;
      });
    }
  }

  String _getFieldValue(
    Map<String, dynamic> ticket,
    List<String> possibleKeys,
  ) {
    for (var key in possibleKeys) {
      if (ticket.containsKey(key) && ticket[key] != null) {
        return ticket[key].toString();
      }
    }
    return '';
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return "غير محدد";
    try {
      String datePart = dateString;
      if (dateString.contains('T')) datePart = dateString.split('T')[0];
      List<String> parts = datePart.split('-');
      if (parts.length == 3) return "${parts[2]}/${parts[1]}/${parts[0]}";
      return datePart;
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _deleteTicket(String ticketId, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("تأكيد الحذف"),
        content: const Text("هل أنت متأكد من حذف هذه التذكرة؟"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("إلغاء"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("حذف", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final uri = Uri.parse("${widget.baseUrl}/api/tickets/delete/$ticketId");
      final response = await http.delete(uri);
      if (response.statusCode == 200) {
        setState(() => _tickets.removeAt(index));
        _showSnackBar("تم حذف التذكرة بنجاح", isError: false);
      } else {
        _showSnackBar("فشل الحذف: ${response.statusCode}");
      }
    } catch (e) {
      _showSnackBar("خطأ: $e");
    }
  }

  Future<pw.Font?> _loadArabicFont() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      return pw.Font.ttf(fontData);
    } catch (e) {
      return null;
    }
  }

  Future<void> _openFileUrl(String filePath) async {
    final url = widget.baseUrl + filePath;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnackBar("لا يمكن فتح الملف");
    }
  }

  // ==================== طباعة تذكرة واحدة فقط ====================
  Future<void> _printSingleTicket(Map<String, dynamic> ticket) async {
    final pdf = pw.Document();
    final font = await _loadArabicFont();
    final now = DateTime.now();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'طلب صيانة الموقع',
                        style: pw.TextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          font: font,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'نظام إدارة الصيانة والتقارير الفنية',
                        style: pw.TextStyle(
                          fontSize: 10,
                          font: font,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 12,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue50,
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(6),
                      ),
                      border: pw.Border.all(color: PdfColors.blue200, width: 1),
                    ),
                    child: pw.Text(
                      'ID: ${ticket['id'].toString().substring(0, 8).toUpperCase()}',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Divider(thickness: 1.5, color: PdfColors.blue900),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'تاريخ إصدار التقرير: ${now.year}/${now.month}/${now.day}',
                    style: pw.TextStyle(
                      fontSize: 9,
                      font: font,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    'حالة التذكرة: معالجة فنية',
                    style: pw.TextStyle(
                      fontSize: 9,
                      font: font,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 25),

              // محتوى التذكرة (عمودين)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // العمود الأيمن
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildHeaderSection(font, 'البيانات الأساسية'),
                        pw.SizedBox(height: 10),
                        _buildProfessionalRow(
                          'التاريخ',
                          _formatDate(ticket['date'] ?? ticket['created_at']),
                          font,
                        ),
                        _buildProfessionalRow(
                          'المحافظة',
                          _getFieldValue(ticket, [
                            'governorate',
                            'gov',
                            'province',
                          ]),
                          font,
                        ),
                        _buildProfessionalRow(
                          'موقع العمل',
                          _getFieldValue(ticket, [
                            'workLocation',
                            'work_location',
                            'location',
                          ]),
                          font,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 25),
                  // العمود الأيسر
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _buildHeaderSection(font, 'تفاصيل الحالة'),
                        pw.SizedBox(height: 10),
                        _buildProfessionalRow(
                          'نوع العطل',
                          _getFieldValue(ticket, [
                            'siteIssue',
                            'site_issue',
                            'issue_type',
                            'problem_type',
                          ]),
                          font,
                        ),
                        _buildProfessionalRow(
                          'الوصف الفني',
                          _getFieldValue(ticket, [
                            'problemDescription',
                            'problem_description',
                            'description',
                            'problem_details',
                          ]),
                          font,
                        ),
                        if (ticket['attachments'] != null &&
                            (ticket['attachments'] as List).isNotEmpty)
                          _buildProfessionalRow(
                            'المرفقات',
                            '${(ticket['attachments'] as List).length} ملفات مرفقة',
                            font,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.Spacer(),

              // Footer
              pw.Column(
                children: [
                  pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.Text(
                      'تعتبر هذه الوثيقة مستنداً داخلياً لأغراض الصيانة والمتابعة الفنية فقط.',
                      style: pw.TextStyle(
                        fontSize: 8,
                        font: font,
                        color: PdfColors.grey500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'ticket_${ticket['id']}.pdf',
    );
  }

  pw.Widget _buildHeaderSection(pw.Font? font, String title) {
    return pw.Row(
      children: [
        pw.Container(width: 4, height: 14, color: PdfColors.blue900),
        pw.SizedBox(width: 6),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            font: font,
            color: PdfColors.blue900,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildProfessionalRow(String label, String value, pw.Font? font) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$label:',
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
              font: font,
              color: PdfColors.blueGrey800,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 10.5,
                font: font,
                color: PdfColors.grey900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  void _showOptionsDialog(Map<String, dynamic> ticket, int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("خيارات التذكرة", textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text("حذف التذكرة"),
              onTap: () {
                Navigator.pop(ctx);
                _deleteTicket(ticket['id'].toString(), index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.blue),
              title: const Text("طباعة PDF"),
              onTap: () {
                Navigator.pop(ctx);
                _printSingleTicket(ticket);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("إغلاق"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("تذاكر صيانة الموقع"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchTickets,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!, style: TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchTickets,
                    child: const Text("إعادة المحاولة"),
                  ),
                ],
              ),
            )
          : _tickets.isEmpty
          ? const Center(child: Text("لا توجد تذاكر صيانة موقع"))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _tickets.length,
              itemBuilder: (context, index) {
                final ticket = _tickets[index] as Map<String, dynamic>;
                final date = _formatDate(
                  ticket['date'] ?? ticket['created_at'],
                );
                final governorate = _getFieldValue(ticket, [
                  'governorate',
                  'gov',
                  'province',
                ]);
                final workLocation = _getFieldValue(ticket, [
                  'workLocation',
                  'work_location',
                  'location',
                ]);
                final siteIssue = _getFieldValue(ticket, [
                  'siteIssue',
                  'site_issue',
                  'issue_type',
                  'problem_type',
                ]);
                final description = _getFieldValue(ticket, [
                  'problemDescription',
                  'problem_description',
                  'description',
                  'problem_details',
                ]);
                final attachments =
                    ticket['attachments'] ?? ticket['files'] ?? [];
                final isAttachments =
                    attachments is List && attachments.isNotEmpty;

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: InkWell(
                    onLongPress: () => _showOptionsDialog(ticket, index),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                date,
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (governorate.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    governorate,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (workLocation.isNotEmpty)
                            Text(
                              "موقع العمل: $workLocation",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          if (siteIssue.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text("نوع العطل: $siteIssue"),
                            ),
                          if (description.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                "الوصف: $description",
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          if (isAttachments)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  const Icon(Icons.attach_file, size: 16),
                                  ...(attachments as List).map((filePath) {
                                    String fileName = filePath
                                        .toString()
                                        .split('/')
                                        .last;
                                    return InkWell(
                                      onTap: () =>
                                          _openFileUrl(filePath.toString()),
                                      child: Chip(
                                        label: Text(fileName),
                                        avatar: const Icon(
                                          Icons.file_present,
                                          size: 16,
                                        ),
                                        backgroundColor: colorScheme.primary
                                            .withOpacity(0.1),
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
