# Indicators & Work · Flutter-клиент

Полный дашборд: исходники **0.1.35**, build **37**, для Windows x64 и Android arm64. Сборка, установка на устройства и публикация — отдельные шаги. Прежний Google Play AAB build 20 предшествует этим изменениям: для первого выпуска в Play нужна свежая сборка с большим code. Первое знакомство описано в [QUICKSTART](../docs/QUICKSTART.md), эксплуатация — в [RUNBOOK](../docs/RUNBOOK.md).

Отдельная редакция **Focus & Norms 0.1.0+1** запускается через `lib/focus_main.dart`, работает с собственной локальной базой без сервера и описана в [своём README](../FOCUS-README.md).

## Запуск готовой сборки

- Windows: для полного дашборда нужна вся распакованная папка клиентского ZIP и собственный работающий сервер. Для самостоятельного таймера открой `focus_norms.exe` из ZIP Focus & Norms.
- Android: установи APK, укажи свой HTTPS-адрес в **Настройки → Сервер и разрешения** и выполни первую синхронизацию. Для адреса Tailscale нужен включённый Tailscale; обычный защищённый HTTPS-прокси использует ключ доступа в той же форме. Ключ пустым полем не стирается и действует только для сохранённого origin. Сервер без защиты не публикуй.
- Для типа времени норматива сервер нужен версии **1.27.0** для текущего набора функций. Первоначальное подключение обязательно; затем изменения и действия таймера сохраняются в SQLite при отсутствии связи.
- У каждого пробующего — собственный сервер и данные. Отдельные аккаунты на одном сервере ещё не реализованы.

## Что входит

Пять разделов: показатели, проекты, работа, письмо и данные. Таймер поддерживает Play выбранной работы, паузу, учёт, наблюдения несколькими абзацами, ежедневные нормы помидорок, недельный обзор, темы и локальные звуки. Полное описание поведения и подсчёта — в [runbook](../docs/RUNBOOK.md).

В 0.1.17 попытка начать другую работу называет текущий сеанс и предлагает открыть его. Ничего не завершается и не учитывается автоматически. На Windows при сворачивании активного таймера показывается компактное окно; Android требует отдельного разрешения для показа поверх других приложений.

В 0.1.19 Play открывает плеер и на широком экране Windows. Истёкшая помидорка предлагает «Учесть и запустить», полный дашборд возвращается в исходный размер после плеера и компактного окна. Общий дневной факт показан полосой до личного лимита, превышение — отдельной красной частью и числом. [Решение и приёмка](../docs/ADR-034-capacity-progress-and-desktop-player.md).

Локальные данные — `indicators-work.sqlite` в системном каталоге приложения; путь виден в **Данных**. Очередь, черновики и ожидающие команды сохраняются при обновлении. Перед переустановкой, очисткой данных и сменой устройства выполни синхронизацию и выгрузи локальную копию.

## Сборка из исходников

Использованный toolchain: Flutter stable 3.47.7 / Dart 3.13.5; Android SDK 36, minSdk 26, JDK 17; для Windows — Visual Studio Build Tools с Desktop development with C++.

Из каталога `native-app`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

Папка результата — `build/windows/x64/runner/Release/`. Для распространения нужна вся папка с runtime-библиотеками; одного EXE недостаточно. [Упаковка Windows](https://docs.flutter.dev/platform-integration/windows/building#building-your-own-zip-file-for-windows).

Android release использует постоянный собственный ключ подписи:

```powershell
keytool -genkeypair -keystore android/owner-release.jks -alias iw-owner -keyalg RSA -keysize 3072 -validity 10000
```

Приватный `android/key.properties` содержит `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. Альтернатива — переменная `IW_ANDROID_KEY_PROPERTIES`, указывающая на такой файл. Ключи и пароли не добавляются в Git. Для обновления установленного APK нужна прежняя подпись.

```powershell
flutter build apk --release --target-platform android-arm64
```

APK — `build/app/outputs/flutter-apk/app-release.apk`. Текущий распространяемый вариант предназначен для arm64.

Для Google Play из корня репозитория предусмотрен `Build-Android.ps1 -Format AppBundle`; результат — `build/app/outputs/bundle/release/app-release.aab` в каталоге сборки. [Порядок регистрации, подписи и выпуска](../docs/GOOGLE-PLAY.md). AAB не является устанавливаемым APK; первая публикация ещё требует настройки аккаунта и Play App Signing.

## Архитектура и проверки

- SQLite с WAL, транзакциями, UUID устройства, снимками и очередью.
- [ADR-012 · нативный клиент](../docs/ADR-012-native-client-and-daily-reminders.md).
- [ADR-019 · постоянные нормы](../docs/ADR-019-recurring-pomodoro-targets.md).
- [ADR-022 · локальное сохранение](../docs/ADR-022-local-first-timer-sync.md).
- [ADR-030 · активный таймер и VPS](../docs/ADR-030-digitalocean-and-active-focus.md).
- [Исторические заметки разработчика](DEVELOPMENT-NOTES.md), сохранённые без удаления прежних инструкций. При расхождении приоритет у текущего README и ADR.

## Сборка отдельного Focus & Norms

Те же Flutter-зависимости и платформенные инструменты. Точка входа — `lib/focus_main.dart`; база и пакет отделены от полного приложения. Из `native-app` в PowerShell:

```powershell
$env:IW_FOCUS_EDITION = '1'
flutter build windows --release --target=lib/focus_main.dart --build-name=0.1.0 --build-number=1
Remove-Item Env:\IW_FOCUS_EDITION
```

Windows-файл — `build/windows/x64/runner/Release/focus_norms.exe`; распространяется вся папка Release.

```powershell
$env:IW_FOCUS_EDITION = '1'
flutter build apk --release --target=lib/focus_main.dart --target-platform=android-arm64 --build-name=0.1.0 --build-number=1
Remove-Item Env:\IW_FOCUS_EDITION
```

APK — `build/app/outputs/flutter-apk/app-release.apk`. Android release использует тот же механизм приватного ключа, но applicationId — **uz.iw.focus_norms**. В release-манифесте этой редакции удалено разрешение INTERNET. Windows использует отдельные mutex, имя и путь данных.

Локальная редакция сохраняет снимки в SQLite сразу и не создаёт фиктивную серверную очередь. Расчёт сеанса, помидорок, норм и фоновые механизмы общие; основное приложение сохраняет прежний путь записи через серверную очередь.

После доработок:

```powershell
flutter analyze
flutter test test/focus_repository_test.dart test/focus_home_test.dart test/quick_focus_test.dart test/durable_timer_test.dart test/recurring_pomodoro_test.dart
```
