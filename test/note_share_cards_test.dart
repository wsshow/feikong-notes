import 'dart:io';

import 'package:fknotes/l10n/generated/app_localizations.dart';
import 'package:fknotes/models/note.dart';
import 'package:fknotes/models/note_document.dart';
import 'package:fknotes/models/note_semantic_projection.dart';
import 'package:fknotes/models/note_share.dart';
import 'package:fknotes/services/file_storage_service.dart';
import 'package:fknotes/services/note_share_layout_engine.dart';
import 'package:fknotes/theme/app_theme.dart';
import 'package:fknotes/widgets/note_share_page_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final _date = DateTime(2026, 11, 5, 15);

void main() {
  late Directory storage;
  setUpAll(() async {
    await initializeDateFormatting('zh');
    storage = await Directory.systemTemp.createTemp('fknotes-share-cards-');
    await FileStorageService.instance.init(baseDir: storage.path);
    await File(
      'assets/brand/fknotes_mark.png',
    ).copy(FileStorageService.instance.absolutePath('notes/images/sample.png'));
  });
  tearDownAll(() => storage.delete(recursive: true));

  test(
    'file reference snapshots survive sharing without becoming paragraphs',
    () {
      final references = _references(3);
      final note = Note.newDraft().copyWith(
        title: '',
        document: NoteDocument.fromDelta(
          Delta()
            ..insert(NoteEmbed.fileReferences(references).toDeltaData())
            ..insert('\n'),
        ),
      );
      final semantic = NoteSemanticProjection.fromNote(note);
      expect(
        semantic.blocks.single.fileReferences.map((e) => e.toJson()),
        references.map((e) => e.toJson()),
      );
      expect(
        semantic.blocks.single.plainText,
        references.map((e) => e.name).join('、'),
      );
      expect(semantic.speechText(), isEmpty);
      expect(semantic.assistantSource(), contains(references.first.name));

      final draft = NoteShareDraft.fromNote(note);
      expect(draft.hasContent, isTrue);
      expect(draft.blocks.single.type, NoteShareBlockType.fileReferences);
      expect(
        draft.blocks.single.fileReferences.map((e) => e.toJson()),
        references.map((e) => e.toJson()),
      );
      expect(draft.blocks.single.text, isEmpty);
      expect(draft.attachments, isEmpty);
      final hidden = _layout(
        draft,
        const NoteShareOptions(includeAttachments: false),
      );
      expect(hidden.pages.single.blocks, isEmpty);
    },
  );

  test(
    'file lists paginate between files without losing or duplicating names',
    () {
      final references = _references(28, longNames: true);
      final draft = _draft([
        NoteShareBlock(type: NoteShareBlockType.paragraph, text: '资料清单'),
        NoteShareBlock(
          type: NoteShareBlockType.fileReferences,
          fileReferences: references,
        ),
      ]);
      for (final template in NoteShareTemplateId.values) {
        for (final density in NoteShareDensity.values) {
          final options = NoteShareOptions(
            template: template,
            density: density,
          );
          final layout = _layout(draft, options);
          final cards = layout.pages
              .expand((page) => page.blocks)
              .where(
                (item) => item.block.type == NoteShareBlockType.fileReferences,
              )
              .toList();
          expect(layout.pages.length, greaterThan(1));
          expect(cards.expand((item) => item.block.fileReferences), references);
          expect(cards.first.showMarker, isTrue);
          expect(cards.skip(1).every((item) => !item.showMarker), isTrue);
        }
      }
    },
  );

  testWidgets(
    'file lists fit every template and density on all of their pages',
    (tester) async {
      _setView(tester, const Size(500, 1000));
      final draft = _draft([
        NoteShareBlock(
          type: NoteShareBlockType.fileReferences,
          fileReferences: _references(6, longNames: true),
        ),
      ]);
      for (final template in NoteShareTemplateId.values) {
        for (final density in NoteShareDensity.values) {
          final options = NoteShareOptions(
            template: template,
            density: density,
          );
          final layout = _layout(draft, options);
          for (var page = 0; page < layout.pages.length; page++) {
            await _pumpCanvas(tester, draft, options, layout, page: page);
            _expectBodyFits(tester, '${template.name}/${density.name}/$page');
            if (page > 0) expect(find.text('文件引用（续）'), findsOneWidget);
          }
        }
      }
    },
  );

  testWidgets(
    'mixed cards stay static and measured in every long-image template',
    (tester) async {
      _setView(tester, const Size(500, 2400));
      final draft = _mixedDraft();
      for (final template in NoteShareTemplateId.values) {
        for (final density in NoteShareDensity.values) {
          final options = NoteShareOptions(
            template: template,
            density: density,
            canvas: const NoteShareCanvasSpec(
              preset: NoteShareCanvasPreset.long,
            ),
          );
          final layout = _layout(draft, options);
          await _pumpCanvas(tester, draft, options, layout);
          _expectBodyFits(tester, '${template.name}/${density.name}');
          expect(find.text('音频 · 01:32 · 2.0 MB'), findsOneWidget);
          expect(find.text('视频 · 02:05 · 8.0 MB'), findsOneWidget);
          expect(find.text('PDF · 32.0 KB'), findsOneWidget);
          expect(find.text('XML · 8.4 KB'), findsOneWidget);
          final title = tester.widget<Text>(
            find.text('项目资料_${'详细说明' * 12}.pdf'),
          );
          expect(title.maxLines, isNull);
          expect(find.byType(IconButton), findsNothing);
          expect(find.byType(InkWell), findsNothing);
          expect(find.byType(Table), findsOneWidget);
        }
      }
    },
  );

  testWidgets('missing images have a named localized placeholder', (
    tester,
  ) async {
    _setView(tester, const Size(500, 1000));
    final draft = _draft([
      NoteShareBlock(
        type: NoteShareBlockType.attachment,
        asset: _asset(NoteAssetKind.image, 'missing.png'),
      ),
    ]);
    const options = NoteShareOptions();
    final layout = _layout(draft, options);
    await _pumpCanvas(
      tester,
      draft,
      options,
      layout,
      locale: const Locale('en'),
    );
    expect(find.text('Image unavailable'), findsOneWidget);
    expect(find.text('missing.png'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final template in [
    NoteShareTemplateId.letter,
    NoteShareTemplateId.night,
  ]) {
    testWidgets(
      'mixed share cards ${template.name} fit with the production font',
      (tester) async {
        _setView(tester, const Size(430, 1700));
        final font = await rootBundle.load(
          'assets/fonts/source_han_serif/SourceHanSerifCN-VF.otf',
        );
        for (final family in ['Ahem', 'Roboto', 'Source Han Serif CN']) {
          await (FontLoader(family)..addFont(Future.value(font))).load();
        }
        final draft = _mixedDraft();
        final options = NoteShareOptions(
          template: template,
          canvas: const NoteShareCanvasSpec(preset: NoteShareCanvasPreset.long),
        );
        final layout = _layout(draft, options);
        await _pumpCanvas(tester, draft, options, layout);
        _expectBodyFits(tester, template.name);
      },
    );
  }
}

List<NoteFileReference> _references(int count, {bool longNames = false}) => [
  for (var index = 0; index < count; index++)
    NoteFileReference(
      fileId:
          '00000000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}',
      name: index == 0
          ? 'fkradar-window.xml'
          : longNames
          ? '资料_${index}_${'完整说明' * 10}.pdf'
          : 'Screenshot_20261027-103258_$index.png',
      size: index == 0 ? 8601 : 683622,
    ),
];

NoteAsset _asset(
  NoteAssetKind kind,
  String name, {
  String? title,
  int? durationMs,
}) => NoteAsset(
  id: NoteAttachmentId.generate(),
  kind: kind,
  storageKey:
      '${switch (kind) {
        NoteAssetKind.image => 'notes/images',
        NoteAssetKind.audio => 'notes/audio',
        NoteAssetKind.video => 'notes/video',
        NoteAssetKind.file => 'notes/files',
      }}/$name',
  originalName: name,
  displayName: title,
  byteLength: switch (kind) {
    NoteAssetKind.audio => 2 * 1024 * 1024,
    NoteAssetKind.video => 8 * 1024 * 1024,
    _ => 32 * 1024,
  },
  mimeType: 'application/octet-stream',
  durationMs: durationMs,
  createdAt: _date,
  updatedAt: _date,
);

NoteShareDraft _mixedDraft() => _draft([
  NoteShareBlock(type: NoteShareBlockType.paragraph, text: '把记录和资料，一起好好留下。'),
  NoteShareBlock(
    type: NoteShareBlockType.fileReferences,
    fileReferences: _references(3),
  ),
  NoteShareBlock(
    type: NoteShareBlockType.attachment,
    asset: _asset(
      NoteAssetKind.audio,
      'discussion.m4a',
      title: '产品讨论 · 下一步计划',
      durationMs: 92000,
    ),
  ),
  NoteShareBlock(
    type: NoteShareBlockType.attachment,
    asset: _asset(
      NoteAssetKind.video,
      'visit.mp4',
      title: '现场记录',
      durationMs: 125000,
    ),
  ),
  NoteShareBlock(
    type: NoteShareBlockType.attachment,
    asset: _asset(
      NoteAssetKind.file,
      'plan.pdf',
      title: '项目资料_${'详细说明' * 12}.pdf',
    ),
  ),
  NoteShareBlock(
    type: NoteShareBlockType.attachment,
    asset: _asset(NoteAssetKind.image, 'sample.png'),
  ),
  NoteShareBlock(
    type: NoteShareBlockType.table,
    table: NoteTable(
      rows: const [
        ['项目', '状态', '负责人'],
        ['分享排版', '已检查', '设计'],
        ['资料卡片', '已整理', '产品'],
      ],
    ),
  ),
  NoteShareBlock(type: NoteShareBlockType.quote, text: '清楚的内容，比多余的装饰更重要。'),
  NoteShareBlock(type: NoteShareBlockType.code, text: 'notes.keepTogether();'),
  NoteShareBlock(type: NoteShareBlockType.divider),
  NoteShareBlock(
    type: NoteShareBlockType.paragraph,
    text: '阅读更多',
    styles: const [
      NoteShareTextRange(0, 4, NoteShareTextStyle(link: 'https://example.com')),
    ],
  ),
]);

NoteShareDraft _draft(List<NoteShareBlock> blocks) => NoteShareDraft(
  title: '记录与手边资料',
  blocks: blocks,
  tags: const ['分享'],
  createdAt: _date,
  updatedAt: _date,
);

NoteShareLayoutResult _layout(NoteShareDraft draft, NoteShareOptions options) =>
    const NoteShareLayoutEngine().paginate(
      draft: draft,
      options: options,
      textDirection: TextDirection.ltr,
      untitledTitle: '一则笔记',
    );

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpCanvas(
  WidgetTester tester,
  NoteShareDraft draft,
  NoteShareOptions options,
  NoteShareLayoutResult layout, {
  int page = 0,
  Locale locale = const Locale('zh'),
}) async {
  if (find.byType(MaterialApp).evaluate().isEmpty) {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  }
  // Resolve real file IO before a widget starts the same image stream in the
  // test clock; awaiting that pending stream from runAsync can otherwise stall.
  await tester.runAsync(() async {
    for (final asset in draft.attachments.where(
      (e) => e.kind == NoteAssetKind.image,
    )) {
      final file = File(
        FileStorageService.instance.absolutePath(asset.storageKey),
      );
      if (await file.exists()) {
        await precacheImage(
          FileImage(file),
          tester.element(find.byType(MaterialApp)),
          onError: (_, _) {},
        );
      }
    }
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(AppThemeStyle.editorialJournal, Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: const ValueKey('share-cards-capture'),
            child: NoteSharePageCanvas(
              draft: draft,
              options: options,
              layout: layout,
              pageIndex: page,
              untitledTitle: '一则笔记',
              sourceLabel: '来自「非空笔记」',
              locale: locale,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pumpAndSettle();
}

void _expectBodyFits(WidgetTester tester, String reason) {
  expect(tester.takeException(), isNull, reason: reason);
  final viewport = tester.getRect(
    find.byKey(const ValueKey('note-share-body-viewport')),
  );
  final body = tester.getRect(
    find.byKey(const ValueKey('note-share-body-content')),
  );
  expect(body.bottom, lessThanOrEqualTo(viewport.bottom + .01), reason: reason);
}
