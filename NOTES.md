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
- Ветка `phase1-core-link` запушена. Локально всё есть: Flutter 3.50.1, Android SDK (/opt/homebrew/share/android-commandlinetools, compileSdk 37), Xcode, CocoaPods. APK и macOS .app собираются локально.
- Пины: equatable ^2.0.7 (macos_ui 2.2.2), window_manager ^0.5.1 (0.7 ломает Linux-тесты), Podfile target 12.0.
- Дизайн (выбор юзера): Mac — нативный macOS (как Messages: сайдбар с телефоном+батареей, системные шрифты, светлая/тёмная авто, menubar). Android — Material You (dynamic color, M3).
- Mac-приложение установлено в /Applications/AndroidLink.app. Телефон по adb не подключён.
- Осталось: зелёный CI → тест на телефоне → Ф2 (+редизайн).
