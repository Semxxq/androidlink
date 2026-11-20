# Правила работы (постоянные, не забывать)

## Экономия токенов
- В начале работы прочитай NOTES.md в корне проекта. Это память между сессиями. Остальную историю не пересказывай.
- После каждой законченной задачи обнови NOTES.md: что сделали, какие файлы менялись, какие решения приняли, что осталось. Не больше 15 строк, старое сжимай.
- Файлы читай точечно: нужную функцию или диапазон строк, а не весь файл. Файл, который уже читал и который не менялся, заново не читай.
- Не пиши длинные вступления и повторы того, что я уже сказал. Отвечай коротко, подробно только если я попрошу.
- Шумные команды (логи, длинный вывод) запускай с фильтром (grep, head, tail) или через субагента.
- Большие поиски по проекту делай субагентом и возвращай только итог.
- Перед большой правкой или удалением спроси меня. Лишних итераций не делай: сначала план в 3 строки.
- Когда задача закончена, напомни мне сделать /clear.

# Состояние проекта (androidlink)

- Flutter-приложение: связь Android <-> Mac (UDP discovery, QR-паринг, уведомления, буфер обмена, ответ на SMS).
- Цель: сейчас слишком сырое, нужно чтобы весь функционал реально работал. Конкретная задача будет дана отдельно.
- Последний коммит: 7a26585 "Fix connection + add Continuity features".
- Задача: полностью рабочий функционал + realtime-синхронизация без серверов (LAN P2P), уровень Continuity iPhone↔Mac.
- План: Ф1 ядро → Ф2 функции (SMS история/контакты, звонки answer/decline/dial, баннеры macOS, авто-буфер+картинки, файлы чанками, Mac-экраны без утечек/потери истории) → Ф3 menubar, find-phone, drag&drop.
- Ф1 сделано (не закоммичено): протокол v2 — Mac WS-сервер :41234(+5), UDP-маяк `ANDROIDLINK2|macId|port` :41235; QR `androidlink://pair?h&p&k&i&m&n`; hello plaintext → всё AES-256-GCM (LinkCrypto.kt ↔ link_crypto.dart), session id `s` в конверте.
- Android: связь в нативном `LinkService.kt` (foreground connectedDevice, OkHttp, автореконнект+маяк+NetworkCallback, очередь 300, батарея). SMS/звонки/уведомления — manifest-ресиверы → LinkService.post. Flutter ↔ через `com.androidlink/methods` + EventChannel `com.androidlink/link`. SMS reply чинён (+sms_status ack).
- Mac: `bridge_service.dart` — _MacHost (pairing.json в AppSupport, мульти-девайс, PeerInfo), _PhoneLink (Android-прокси).
- Платформы перегенерены Flutter 3.50.1 (gradle .kts, macos проект, target 12.0). CI: analyze+test+apk+macos на любой push.
- Ветка phase1-core-link влита в main (PR #1). Репо ПУБЛИЧНОЕ, релиз v1.0.0 (APK + AndroidLink-mac.zip, не нотаризован). Локально всё есть: Flutter 3.50.1, Android SDK переустановлен 2026-11-21 (/opt/homebrew/share/android-commandlinetools: platforms;android-37.0, build-tools 37.0.0; sdkmanager требует export JAVA_HOME=$(/usr/libexec/java_home), Temurin 17). CLion удалён, Xcode, CocoaPods. APK и macOS .app собираются локально.
- Пины: equatable ^2.0.7 (macos_ui 2.2.2), window_manager ^0.5.1 (0.7 ломает Linux-тесты), Podfile target 12.0.
- Дизайн (выбор юзера): Mac — нативный macOS (как Messages: сайдбар с телефоном+батареей, системные шрифты, светлая/тёмная авто, menubar). Android — Material You (dynamic color, M3).
- Ф2 сделано (коммит 5413467): Android — PhoneData.kt (sms/calls/contacts sync, SmsObserver по content://sms), PhoneControl.kt (answer/decline/dial, ring), FileTransfer.kt (чанки 192К, окно 24, ack/8), ShareActivity (share + буфер), ClipTileService, ответ на уведомления через RemoteInput. Mac — lib/mac/: store.dart (MacStore, history.json), notifier.dart (баннеры с действиями), tray.dart + AppDelegate.swift (menubar), ui/*. Android UI — lib/android/ (M3, seed из system_accent1_500).
- Решения: dynamic_color убран (несовместим с material_ui), window_manager убран (окно через macos_window_utils + Swift), desugaring вкл. для flutter_local_notifications.
- Подпись: android/app/release.jks + android/key.properties (в .gitignore, НЕ терять — иначе обновления только с удалением). Телефон Samsung: мешает «Автоблокировщик» (блокирует и установку, и adb).
- 2026-11-20: СВЯЗЬ РАБОТАЕТ на Samsung SM-S947B (коммит c106217). Причины были: Dart отвечал permessage-deflate с client_max_window_bits → OkHttp рвал (compressionOff); маяк через VPN-маршрут (сокет на каждый LAN IP); macOS «Локальная сеть» (ad-hoc подпись сбрасывала → macos/install_local.sh с постоянной подписью). Лог Mac: ~/Library/Containers/com.androidlink.app/Data/Library/Application Support/com.androidlink.app/diag.log.
- Синк: 1437 SMS, 510 контактов. Звонки=0 чинено в 6b5e24d (CallLog отвергал LIMIT в sortOrder), ждёт проверки на телефоне.
- Юзер подтвердил: всё работает. Был обрыв 1002 в 16:09 (причина не выяснена, логирование ошибок добавлено, Mac не переустановлен).
- Ф3 картинки в буфере (91c8b92): Mac — Swift методы clipCount/clipImage/setClipImage в канале androidlink/tray, store поллит changeCount; тип `clip_image` {image: base64 JPEG ≤8МБ}. Android — ClipProvider (content://com.androidlink.clip), приём в LinkService, отправка через плитку ClipPushActivity. Ждёт теста.
- Mac UI: «?» вместо иконок = не было cupertino_icons в pubspec (добавлен). Menubar — карточка PhoneCardView в AppDelegate.swift (батарея, SMS/уведомл./пропущ. за 24ч), данные из tray.dart. SwiftUI в NSMenu не работал → карточка на чистом AppKit (PhoneCardView.apply).
- MMS/группы: Android Mms.kt (content://mms, превью JPEG ≤640px base64, sender, names; observer content://mms-sms/), MMS идут в sms_batch (до 300). Mac: threadKey() — группа = "g:"+отсорт. номера, address "a,b,c"; ответ в группу = SMS каждому по отдельности (не групповой MMS). Ждёт теста.
- Файлы Mac: open/reveal через NSWorkspace (канал tray: openFile/reveal; Process open в sandbox не работает), история передач в AppSupport/transfers.json (200).
- Найти телефон: PhoneControl.ring — перебор URI мелодий, вибрация, уведомление-будильник (Нашёл → MainActivity стопит); Mac кнопка = стоп при повторе.
- Mac сайдбар: const _DeviceHeader/_SidebarActions не перерисовывались → свой ListenableBuilder.
- Осталось: Ф3: картинки в буфере, MMS/группы. Скриншоты недоступны (нет Screen Recording у терминала).
- Обрыв 1002 повторяется ~раз в сессию, реконнект за 3с — некритично; причину смотреть по логу Android (adb заблокирован).
