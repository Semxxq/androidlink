import 'package:flutter/cupertino.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../features/bridge/services/bridge_service.dart';
import '../store.dart';
import 'common.dart';

/// Pairing QR + paired phones + settings.
class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key, this.onboarding = false});
  final bool onboarding;

  @override
  Widget build(BuildContext context) {
    final s = MacStore.instance;
    final b = BridgeService.instance;
    return MacosScaffold(
      toolBar: ToolBar(title: Text(onboarding ? 'Добро пожаловать' : 'Устройства')),
      children: [
        ContentArea(
          builder: (context, sc) => ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              final p = Pal.of(context);
              final paired = b.pairedDevices;
              return ListView(controller: sc, padding: const EdgeInsets.all(24), children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (onboarding) ...[
                        const SizedBox(height: 8),
                        Text('Твой Android — на твоём Mac',
                            textAlign: TextAlign.center, style: txt(context, size: 24, w: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(
                          'SMS, звонки, уведомления, общий буфер обмена и файлы. Напрямую по Wi-Fi, '
                          'без серверов и облака, с шифрованием.',
                          textAlign: TextAlign.center,
                          style: txt(context, color: p.secondary),
                        ),
                        const SizedBox(height: 24),
                      ],
                      _PairCard(),
                      const SizedBox(height: 24),
                      if (paired.isNotEmpty)
                        Section(
                          title: 'Подключённые телефоны',
                          children: [
                            for (final d in paired) _DeviceRow(paired: d),
                          ],
                        ),
                      if (!onboarding) ...[
                        const SizedBox(height: 24),
                        Section(title: 'Настройки', children: [
                          Row2(
                            title: 'Уведомления macOS',
                            subtitle: 'Баннеры для SMS, звонков и уведомлений телефона',
                            trailing: MacosSwitch(value: s.banners, onChanged: s.setBanners),
                          ),
                          Row2(
                            title: 'Общий буфер обмена',
                            subtitle: 'Скопированное на Mac — сразу на телефоне',
                            trailing: MacosSwitch(value: s.autoClipboard, onChanged: s.setAutoClipboard),
                          ),
                          Row2(
                            title: 'Синхронизировать заново',
                            subtitle: 'Перезагрузить SMS, звонки и контакты с телефона',
                            trailing: PushButton(
                              controlSize: ControlSize.regular,
                              secondary: true,
                              onPressed: s.connected ? s.resync : null,
                              child: const Text('Обновить'),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        Text(
                          'Адреса Mac: ${b.localIp ?? '—'} · Работает в строке меню, даже когда окно закрыто.',
                          style: txt(context, size: 11, color: p.secondary),
                        ),
                      ],
                    ]),
                  ),
                ),
              ]);
            },
          ),
        ),
      ],
    );
  }
}

class _PairCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.separator),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        StreamBuilder<String?>(
          stream: BridgeService.instance.qrStream,
          initialData: BridgeService.instance.qrData,
          builder: (context, snap) {
            final qr = snap.data;
            return Container(
              width: 196,
              height: 196,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(12)),
              child: qr == null
                  ? Center(
                      child: Text('Нет сети.\nПодключи Mac к Wi-Fi',
                          textAlign: TextAlign.center, style: txt(context, color: const Color(0xFF666666))),
                    )
                  : QrImageView(data: qr, version: QrVersions.auto, backgroundColor: const Color(0xFFFFFFFF)),
            );
          },
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Подключить телефон', style: txt(context, size: 16, w: FontWeight.w600)),
            const SizedBox(height: 10),
            for (final (i, step) in const [
              'Установи AndroidLink на Android',
              'Открой и нажми «Подключить Mac»',
              'Наведи камеру на этот QR-код',
            ].indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Pal.blue, shape: BoxShape.circle),
                    child: Text('${i + 1}',
                        style: txt(context, size: 11, w: FontWeight.w700, color: const Color(0xFFFFFFFF))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(step, style: txt(context))),
                ]),
              ),
            const SizedBox(height: 4),
            Text('Телефон и Mac должны быть в одной сети. QR одноразовый — для каждого телефона новый.',
                style: txt(context, size: 11, color: p.secondary)),
          ]),
        ),
      ]),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.paired});
  final PeerInfo paired;

  @override
  Widget build(BuildContext context) {
    final s = MacStore.instance;
    final p = Pal.of(context);
    final live = s.devices.where((d) => d.id == paired.id).firstOrNull;
    final selected = s.device?.id == paired.id;
    final sub = live == null
        ? 'Не в сети'
        : [
            'Подключён',
            if (live.battery >= 0) 'батарея ${live.battery}%${live.charging ? ' (заряжается)' : ''}',
            if (live.android != null) 'Android ${live.android}',
          ].join(' · ');
    return Row2(
      leading: MacosIcon(CupertinoIcons.device_phone_portrait, size: 22, color: live != null ? Pal.green : p.tertiary),
      title: live?.name ?? paired.name,
      subtitle: sub,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (live != null && s.devices.length > 1 && !selected)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PushButton(
              controlSize: ControlSize.small,
              secondary: true,
              onPressed: () => s.selectDevice(paired.id),
              child: const Text('Сделать основным'),
            ),
          ),
        PushButton(
          controlSize: ControlSize.small,
          secondary: true,
          onPressed: () => showMacosAlertDialog(
            context: context,
            builder: (c) => MacosAlertDialog(
              appIcon: const MacosIcon(CupertinoIcons.device_phone_portrait, size: 48),
              title: Text('Забыть «${paired.name}»?'),
              message: const Text('Телефон отключится. Чтобы подключить снова, придётся отсканировать новый QR-код.'),
              primaryButton: PushButton(
                controlSize: ControlSize.large,
                color: Pal.red,
                onPressed: () {
                  Navigator.of(c).pop();
                  s.forgetDevice(paired.id);
                },
                child: const Text('Забыть'),
              ),
              secondaryButton: PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('Отмена'),
              ),
            ),
          ),
          child: const Text('Забыть'),
        ),
      ]),
    );
  }
}
