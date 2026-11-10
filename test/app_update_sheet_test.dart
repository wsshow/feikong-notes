import 'dart:async';
import 'dart:io';

import 'package:fknotes/app.dart';
import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/services/app_update_service.dart';
import 'package:fknotes/widgets/app_update_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'update sheet fills the bottom safe area and keeps header and footer fixed',
    (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 2400);
      addTearDown(tester.view.reset);

      final artifact = AppUpdateArtifact(
        id: 'android-arm64-v8a',
        abi: 'arm64-v8a',
        url: Uri.https('example.com', '/fknotes.apk'),
        size: 12 * 1024 * 1024,
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      final manifest = AppUpdateManifest(
        version: '2.0.0',
        versionCode: 200,
        releaseDate: DateTime(2026, 8, 25),
        mandatory: false,
        changelog: Uri.https('example.com', '/changelog.md'),
        artifacts: {'android-arm64-v8a': artifact},
      );
      final notes = List.generate(
        36,
        (index) => '- 更新项目 ${index + 1}：优化手机端记录体验。',
      ).join('\n');

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: AppColors.ink),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    useSafeArea: true,
                    isScrollControlled: true,
                    isDismissible: false,
                    enableDrag: false,
                    backgroundColor: Colors.transparent,
                    builder: (_) => AppUpdateSheet(
                      manifest: manifest,
                      artifact: artifact,
                      releaseNotes: Future.value(notes),
                    ),
                  ),
                  child: const Text('显示更新'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('显示更新'));
      await tester.pumpAndSettle();

      final sheet = find.byKey(const Key('app-update-sheet'));
      final header = find.byKey(const Key('app-update-header'));
      final notesScroll = find.byKey(
        const Key('app-update-release-notes-scroll'),
      );
      final footerDivider = find.byKey(const Key('app-update-footer-divider'));
      final footer = find.byKey(const Key('app-update-footer'));

      expect(sheet, findsOneWidget);
      expect(notesScroll, findsOneWidget);
      expect(footerDivider, findsOneWidget);
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('v2.0.0'), findsOneWidget);
      expect(find.text('2026年8月25日'), findsOneWidget);
      expect(find.text('12.0 MB'), findsOneWidget);
      expect(find.text('arm64-v8a'), findsNothing);
      expect(find.text('稍后提醒'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
      expect(tester.getSize(footerDivider).height, 1);

      for (final bottomInset in [0.0, 24.0, 48.0]) {
        final padding = FakeViewPadding(bottom: bottomInset * 3);
        tester.view.viewPadding = padding;
        tester.view.padding = padding;
        await tester.pumpAndSettle();

        expect(tester.getBottomRight(sheet).dy, closeTo(800, .1));
        expect(
          tester.getBottomRight(footer).dy,
          closeTo(800 - bottomInset, .1),
        );

        final headerTop = tester.getTopLeft(header).dy;
        final footerTop = tester.getTopLeft(footer).dy;
        await tester.drag(notesScroll, const Offset(0, -420));
        await tester.pumpAndSettle();

        expect(tester.getTopLeft(header).dy, closeTo(headerTop, .1));
        expect(tester.getTopLeft(footer).dy, closeTo(footerTop, .1));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('download and verification share one stable progress footer', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.viewPadding = const FakeViewPadding(bottom: 72);
    tester.view.padding = const FakeViewPadding(bottom: 72);
    addTearDown(tester.view.reset);

    final artifact = AppUpdateArtifact(
      id: 'android-arm64-v8a',
      abi: 'arm64-v8a',
      url: Uri.https('example.com', '/fknotes.apk'),
      size: 12 * 1024 * 1024,
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    final manifest = AppUpdateManifest(
      version: '2.0.0',
      versionCode: 200,
      releaseDate: DateTime(2026, 8, 25),
      mandatory: false,
      changelog: Uri.https('example.com', '/changelog.md'),
      artifacts: {'android-arm64-v8a': artifact},
    );
    final service = _ProgressUpdateClient(artifact.size ~/ 4);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildAppTheme(AppThemeStyle.paper, Brightness.light),
        home: Scaffold(
          body: AppUpdateSheet(
            manifest: manifest,
            artifact: artifact,
            releaseNotes: Future.value('本次更新优化了记录体验。'),
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final footer = find.byKey(const Key('app-update-footer'));
    final notes = find.byKey(const Key('app-update-release-notes-scroll'));
    final footerRect = tester.getRect(footer);
    final notesRect = tester.getRect(notes);

    await tester.tap(find.text('立即更新'));
    await tester.pump();

    final progress = find.byKey(const Key('app-update-download-progress'));
    final indicator = tester.widget<LinearProgressIndicator>(progress);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.descendant(of: footer, matching: progress), findsOneWidget);
    expect(indicator.value, closeTo(.25, .001));
    expect(tester.getSemantics(progress).value, '25');
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('3.0 MB / 12.0 MB'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getRect(footer), footerRect);
    expect(tester.getRect(notes), notesRect);

    final label = tester.getTopLeft(find.text('正在下载更新'));
    final percent = tester.getTopLeft(find.text('25%'));
    expect(label.dy, closeTo(percent.dy, .1));
    expect(label.dx, lessThan(percent.dx));
    expect(tester.getTopLeft(progress).dy, greaterThan(label.dy));

    service.finishDownload();
    await tester.pump();
    expect(find.text('正在校验安装包'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(progress).value, isNull);
    expect(find.text('25%'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.getRect(footer), footerRect);
    expect(tester.getRect(notes), notesRect);

    service.finishVerification();
    await tester.pumpAndSettle();
    expect(find.text('更新安装包已校验，可以安装了。'), findsOneWidget);
    await tester.tap(find.text('立即安装'));
    await tester.pumpAndSettle();
    expect(find.text('需要安装权限'), findsOneWidget);
    expect(find.text('前往授权'), findsOneWidget);
    expect(find.text('稍后提醒'), findsOneWidget);
    expect(progress, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the installer stays in the progress area', (
    tester,
  ) async {
    final service = _ProgressUpdateClient(3 * 1024 * 1024, allowInstall: true);
    await _pumpUpdateSheet(tester, service);
    final footer = find.byKey(const Key('app-update-footer'));
    final initialFooter = tester.getRect(footer);

    await tester.tap(find.text('立即更新'));
    await tester.pump();
    service.finishDownload();
    service.finishVerification();
    await tester.pumpAndSettle();
    await tester.tap(find.text('立即安装'));
    await tester.pump();

    expect(find.text('正在打开系统安装器'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('app-update-download-progress')),
          )
          .value,
      isNull,
    );
    expect(tester.getRect(footer), initialFooter);

    service.finishInstall();
    await tester.pumpAndSettle();
    expect(find.text('更新安装包已校验，可以安装了。'), findsOneWidget);
    expect(find.text('立即安装'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final mandatory in [false, true]) {
    testWidgets('verification failure restores actions: mandatory=$mandatory', (
      tester,
    ) async {
      final service = _ProgressUpdateClient(3 * 1024 * 1024);
      await _pumpUpdateSheet(tester, service, mandatory: mandatory);
      await tester.tap(find.text('立即更新'));
      await tester.pump();
      service.finishDownload();
      await tester.pump();
      service.failVerification();
      await tester.pumpAndSettle();

      expect(find.text('更新没有完成'), findsOneWidget);
      expect(find.text('安装包校验失败，文件可能不完整，已停止安装。'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('稍后提醒'), mandatory ? findsNothing : findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('progress and actions remain accessible with 160% English text', (
    tester,
  ) async {
    final service = _ProgressUpdateClient(3 * 1024 * 1024);
    await _pumpUpdateSheet(
      tester,
      service,
      locale: const Locale('en'),
      width: 320,
      textScale: 1.6,
      brightness: Brightness.dark,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Update now'));
    await tester.pump();
    expect(find.text('Downloading update'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(tester.takeException(), isNull);

    service.finishDownload();
    await tester.pump();
    expect(find.text('Verifying update package'), findsOneWidget);
    expect(tester.takeException(), isNull);

    service.finishVerification();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Install now'));
    await tester.tap(find.text('Install now'));
    await tester.pumpAndSettle();
    expect(find.text('Open settings'), findsOneWidget);
    await tester.ensureVisible(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(service.settingsOpened, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUpdateSheet(
  WidgetTester tester,
  AppUpdateClient service, {
  Locale locale = const Locale('zh'),
  double width = 360,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  bool mandatory = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  tester.view.padding = const FakeViewPadding(bottom: 24);
  addTearDown(tester.view.reset);
  final artifact = AppUpdateArtifact(
    id: 'android-arm64-v8a',
    abi: 'arm64-v8a',
    url: Uri.https('example.com', '/fknotes.apk'),
    size: 12 * 1024 * 1024,
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildAppTheme(AppThemeStyle.paper, brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: AppUpdateSheet(
            manifest: AppUpdateManifest(
              version: '2.0.0',
              versionCode: 200,
              releaseDate: DateTime(2026, 8, 25),
              mandatory: mandatory,
              changelog: Uri.https('example.com', '/changelog.md'),
              artifacts: {'android-arm64-v8a': artifact},
            ),
            artifact: artifact,
            releaseNotes: Future.value('本次更新优化了记录体验。'),
            service: service,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _ProgressUpdateClient implements AppUpdateClient {
  final int downloadedBytes;
  final bool allowInstall;
  final Completer<File> _download = Completer<File>();
  final Completer<void> _verification = Completer<void>();
  final Completer<void> _installation = Completer<void>();
  int settingsOpened = 0;

  _ProgressUpdateClient(this.downloadedBytes, {this.allowInstall = false});

  void finishDownload() => _download.complete(File('/tmp/fknotes-update.apk'));

  void finishVerification() => _verification.complete();

  void failVerification() => _verification.completeError(
    const AppUpdateException('UPDATE_CHECKSUM_MISMATCH'),
  );

  void finishInstall() => _installation.complete();

  @override
  Future<bool> canInstallUpdates() async => allowInstall;

  @override
  Future<void> clearPendingUpdate() async {}

  @override
  Future<File> download(
    AppUpdateManifest manifest, {
    required AppUpdateArtifact artifact,
    required AppUpdateDownloadProgress onProgress,
    bool restart = false,
    bool requestNotifications = true,
  }) {
    onProgress(downloadedBytes, artifact.size);
    return _download.future;
  }

  @override
  Future<void> install(
    AppUpdateManifest manifest,
    AppUpdateArtifact artifact,
    File file,
  ) => _installation.future;

  @override
  Future<void> openInstallPermissionSettings() async {
    settingsOpened++;
  }

  @override
  Future<void> snooze(int versionCode) async {}

  @override
  Future<void> verify(
    AppUpdateManifest manifest,
    AppUpdateArtifact artifact,
    File file,
  ) => _verification.future;
}
