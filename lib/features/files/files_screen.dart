import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';

import '../bridge/services/bridge_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';

class _FileItem {
  const _FileItem({required this.name, required this.size, required this.path});
  final String name, path;
  final int    size;
}

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final List<_FileItem> _received = [];
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    BridgeService.instance.messages.listen((msg) async {
      if (msg.type != AL.typeFile) return;
      final name = msg.payload['name'] as String? ?? 'file';
      final data = msg.payload['data'] as String? ?? '';
      if (data.isEmpty) return;
      final dir  = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$name';
      final bytes = base64Decode(data);
      await File(path).writeAsBytes(bytes);
      setState(() => _received.insert(0, _FileItem(
        name: name, size: bytes.length, path: path,
      )));
    });
  }

  Future<void> _sendFile() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty || files.single.path == null) return;
    final file  = files.single;
    setState(() => _sending = true);
    final bytes = await File(file.path!).readAsBytes();
    BridgeService.instance.sendRaw({
      'name': file.name,
      'size': bytes.length,
      'data': base64Encode(bytes),
    }, AL.typeFile);
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Файлы', style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              )),
              const Spacer(),
              _ActionBtn(
                label:   'Отправить на Android',
                loading: _sending,
                onTap:   _sendFile,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Передача файлов через WiFi',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          if (_received.isEmpty)
            Expanded(child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: const [
                Icon(CupertinoIcons.tray_arrow_down, size: 48, color: AppTheme.textTertiary),
                SizedBox(height: 12),
                Text('Файлы с Android появятся здесь',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ]),
            ))
          else
            Expanded(
              child: ListView.builder(
                itemCount: _received.length,
                itemBuilder: (_, i) {
                  final f = _received[i];
                  return Container(
                    margin:  const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(CupertinoIcons.doc, size: 28, color: AppTheme.accent),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name, style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13,
                            color: AppTheme.textPrimary,
                          )),
                          Text('${(f.size / 1024).toStringAsFixed(1)} KB',
                              style: const TextStyle(
                                fontSize: 11, color: AppTheme.textSecondary)),
                        ],
                      )),
                    ]),
                  ).animate().fadeIn(delay: Duration(milliseconds: i * 30));
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.label, required this.loading, required this.onTap});
  final String label;
  final bool   loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color:        AppTheme.accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border:       Border.all(color: AppTheme.accent.withOpacity(0.3)),
        ),
        child: Row(children: [
          if (loading)
            const SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
          else
            const Icon(CupertinoIcons.arrow_up_doc, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppTheme.accent, fontSize: 13)),
        ]),
      ),
    );
  }
}
