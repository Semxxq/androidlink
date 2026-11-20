import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../features/bridge/services/file_transfer.dart';
import '../store.dart';
import 'common.dart';

class ClipboardPage extends StatelessWidget {
  const ClipboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = MacStore.instance;
    return MacosScaffold(
      toolBar: ToolBar(
        title: const Text('Буфер обмена'),
        actions: [
          ToolBarIconButton(
            label: 'Отправить на телефон',
            icon: const MacosIcon(CupertinoIcons.arrow_up_doc),
            showLabel: true,
            onPressed: () => s.pushClipboard(),
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (context, sc) => ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              final p = Pal.of(context);
              return ListView(
                controller: sc,
                padding: const EdgeInsets.all(20),
                children: [
                  Section(
                    footer: 'Скопированное на Mac сразу появляется в буфере телефона. С телефона — кнопка «Буфер → Mac» '
                        'в шторке, плитка быстрых настроек или «Поделиться → Отправить на Mac» (Android не даёт '
                        'приложениям читать буфер в фоне).',
                    children: [
                      Row2(
                        title: 'Общий буфер обмена',
                        subtitle: 'Автоматически отправлять скопированное на телефон',
                        trailing: MacosSwitch(value: s.autoClipboard, onChanged: s.setAutoClipboard),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (s.clipboard.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Text('История пуста', textAlign: TextAlign.center, style: txt(context, color: p.secondary)),
                    )
                  else
                    Section(
                      title: 'История',
                      children: [
                        for (final c in s.clipboard)
                          HoverTile(
                            radius: 0,
                            onTap: () => s.copyEntry(c),
                            child: Row2(
                              leading: c.image != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.memory(c.image!, width: 48, height: 48, fit: BoxFit.cover, gaplessPlayback: true),
                                    )
                                  : MacosIcon(
                                c.fromPhone ? CupertinoIcons.device_phone_portrait : CupertinoIcons.desktopcomputer,
                                size: 16,
                                color: p.secondary,
                              ),
                              title: c.text.length > 300 ? '${c.text.substring(0, 300)}…' : c.text,
                              subtitle: '${c.fromPhone ? 'С телефона' : 'С Mac'} · ${shortTime(c.time)}',
                              trailing: MacosTooltip(
                                message: 'Скопировать',
                                child: MacosIcon(CupertinoIcons.doc_on_doc, size: 15, color: p.secondary),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class FilesPage extends StatefulWidget {
  const FilesPage({super.key});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  bool _dragging = false;

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles();
    final paths = files.map((f) => f.path).whereType<String>().map(File.new).toList();
    await MacStore.instance.sendFiles(paths);
  }

  @override
  Widget build(BuildContext context) {
    final s = MacStore.instance;
    final hub = FileTransferHub.instance;
    return MacosScaffold(
      toolBar: ToolBar(
        title: const Text('Файлы'),
        actions: [
          ToolBarIconButton(
            label: 'Очистить',
            icon: const MacosIcon(CupertinoIcons.trash),
            showLabel: false,
            tooltipMessage: 'Убрать завершённые',
            onPressed: hub.clearFinished,
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (context, sc) {
            final p = Pal.of(context);
            return ListenableBuilder(
              listenable: s,
              builder: (context, _) => DropTarget(
                enable: s.connected,
                onDragEntered: (_) => setState(() => _dragging = true),
                onDragExited: (_) => setState(() => _dragging = false),
                onDragDone: (d) {
                  setState(() => _dragging = false);
                  s.sendFiles(d.files.map((x) => File(x.path)).toList());
                },
                child: ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 170,
                    decoration: BoxDecoration(
                      color: _dragging ? Pal.blue.withValues(alpha: 0.12) : p.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _dragging ? Pal.blue : p.separator, width: _dragging ? 2 : 1),
                    ),
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        MacosIcon(CupertinoIcons.arrow_down_doc, size: 38, color: _dragging ? Pal.blue : p.tertiary),
                        const SizedBox(height: 10),
                        Text(
                          s.connected ? 'Перетащи файлы сюда, чтобы отправить на ${s.device!.name}' : 'Телефон не подключён',
                          style: txt(context, w: FontWeight.w500),
                        ),
                        const SizedBox(height: 10),
                        PushButton(
                          controlSize: ControlSize.regular,
                          secondary: true,
                          onPressed: s.connected ? _pick : null,
                          child: const Text('Выбрать файлы…'),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Файлы с телефона («Поделиться → Отправить на Mac») сохраняются в «Загрузки». '
                    'На телефоне файлы с Mac лежат в Download/AndroidLink.',
                    style: txt(context, size: 11, color: p.secondary),
                  ),
                  const SizedBox(height: 20),
                  StreamBuilder<List<Transfer>>(
                    stream: hub.transfers,
                    initialData: hub.current,
                    builder: (context, snap) {
                      final list = snap.data ?? const [];
                      if (list.isEmpty) return const SizedBox.shrink();
                      return Section(title: 'Передачи', children: [for (final t in list) _TransferRow(t: t)]);
                    },
                  ),
                ]),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({required this.t});
  final Transfer t;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final status = t.failed
        ? 'Ошибка'
        : t.finished
            ? (t.incoming ? 'Получено · ${bytes(t.size > 0 ? t.size : t.done)}' : 'Отправлено · ${bytes(t.size)}')
            : '${bytes(t.done)} из ${bytes(t.size)}';
    final canOpen = t.finished && t.path != null;
    final ext = t.name.split('.').last.toLowerCase();
    final isImage = const {'jpg', 'jpeg', 'png', 'gif', 'heic', 'webp', 'bmp'}.contains(ext);
    final s = MacStore.instance;
    Widget leading = MacosIcon(t.incoming ? CupertinoIcons.arrow_down_circle : CupertinoIcons.arrow_up_circle,
        size: 22, color: t.failed ? Pal.red : (t.finished ? Pal.green : Pal.blue));
    if (canOpen && isImage && File(t.path!).existsSync()) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.file(File(t.path!), width: 36, height: 36, fit: BoxFit.cover, cacheWidth: 96),
      );
    } else if (canOpen) {
      leading = MacosIcon(_iconFor(ext), size: 24, color: Pal.blue);
    }
    return HoverTile(
      radius: 0,
      onTap: canOpen ? () => s.openFile(t.path!) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(children: [
          SizedBox(width: 36, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: txt(context, w: FontWeight.w500)),
              const SizedBox(height: 4),
              if (!t.finished && !t.failed) ProgressBar(value: t.progress * 100),
              if (!t.finished && !t.failed) const SizedBox(height: 4),
              Text('$status · ${shortTime(t.started)}', style: txt(context, size: 11, color: t.failed ? Pal.red : p.secondary)),
            ]),
          ),
          const SizedBox(width: 8),
          if (canOpen) ...[
            PushButton(
              controlSize: ControlSize.small,
              onPressed: () => s.openFile(t.path!),
              child: const Text('Открыть'),
            ),
            const SizedBox(width: 6),
            MacosTooltip(
              message: 'Показать в Finder',
              child: MacosIconButton(
                icon: MacosIcon(CupertinoIcons.folder, size: 16, color: p.secondary),
                onPressed: () => s.revealInFinder(t.path!),
              ),
            ),
          ] else if (!t.finished && !t.failed)
            MacosIconButton(
              icon: MacosIcon(CupertinoIcons.xmark_circle_fill, size: 16, color: p.secondary),
              onPressed: () => FileTransferHub.instance.cancel(t.fid),
            ),
        ]),
      ),
    );
  }
}

IconData _iconFor(String ext) => switch (ext) {
      'pdf' || 'doc' || 'docx' || 'txt' || 'rtf' || 'pages' => CupertinoIcons.doc_text_fill,
      'mp4' || 'mov' || 'mkv' || 'avi' || 'webm' => CupertinoIcons.film_fill,
      'mp3' || 'm4a' || 'wav' || 'ogg' || 'flac' || 'opus' => CupertinoIcons.music_note_2,
      'zip' || 'rar' || '7z' || 'tar' || 'gz' => CupertinoIcons.archivebox_fill,
      'apk' => CupertinoIcons.device_phone_portrait,
      _ => CupertinoIcons.doc_fill,
    };
