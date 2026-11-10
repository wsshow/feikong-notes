import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_llm/local_llm_output_filter.dart';
import 'package:fknotes/services/note_assistant_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'online editor context follows its model budget without an offline privacy claim',
    () {
      final content = '正文' * 4000;
      final request = NoteAssistantPromptBuilder.build(
        action: NoteAssistantAction.custom('整理'),
        title: '在线上下文',
        content: content,
        onDevice: false,
        maxSourceCharacters: 10000,
      );
      expect(request.messages.first.content, isNot(contains('所有内容只在设备上处理')));
      expect(request.messages.last.content, contains(content));
    },
  );
  test('summary prompt preserves title and note content', () {
    final request = NoteAssistantPromptBuilder.build(
      action: const NoteAssistantAction.preset(NoteAssistantTask.summarize),
      title: '周会',
      content: '下周发布 1.0 版本。',
    );

    expect(request.messages.first.role, LocalLlmRole.system);
    expect(request.messages.last.content, contains('标题：周会'));
    expect(request.messages.last.content, contains('下周发布 1.0 版本。'));
    expect(request.options.maxNewTokens, 512);
  });

  test('todo prompt requires parseable unchecked todo lines', () {
    final request = NoteAssistantPromptBuilder.build(
      action: const NoteAssistantAction.preset(NoteAssistantTask.extractTodos),
      title: '',
      content: '明天提交报告',
    );

    expect(request.messages.last.content, contains('每行使用“☐ ”开头'));
  });

  test('prompt describes the selected editor scope precisely', () {
    final request = NoteAssistantPromptBuilder.build(
      action: const NoteAssistantAction.preset(NoteAssistantTask.polish),
      title: '上下文标题',
      content: '只处理这一小段',
      scope: NoteAssistantScope.selection,
    );

    expect(request.messages.last.content, contains('润色选中的文字'));
    expect(request.messages.last.content, contains('只处理这一小段'));
  });

  test('long notes keep both ends within the mobile context budget', () {
    final content = '开' * 4000 + '中' * 4000 + '尾' * 4000;
    final request = NoteAssistantPromptBuilder.build(
      action: const NoteAssistantAction.preset(NoteAssistantTask.polish),
      title: '',
      content: content,
    );
    final prompt = request.messages.last.content;

    expect(prompt, contains('中间内容因移动端上下文限制已省略'));
    expect(prompt, contains('开' * 100));
    expect(prompt, contains('尾' * 100));
    expect(request.options.maxNewTokens, 768);
  });

  test('custom instructions are preserved and work without note content', () {
    final request = NoteAssistantPromptBuilder.build(
      action: NoteAssistantAction.custom('写一份周末露营清单，用 Markdown 表格组织'),
      title: '',
      content: '',
    );

    expect(request.messages.last.content, contains('写一份周末露营清单'));
    expect(request.messages.last.content, contains('当前笔记为空'));
    expect(request.options.maxNewTokens, 768);
  });

  test('inline insertion returns only new text and includes caret context', () {
    final request = NoteAssistantPromptBuilder.build(
      action: NoteAssistantAction.custom('接着写下去'),
      title: '随笔',
      content: '前文内容',
      outputMode: NoteAssistantOutputMode.insertAtCursor,
      cursorContext: '正在写的这一段',
    );

    expect(request.messages.first.content, contains('直接写入当前编辑器'));
    expect(request.messages.first.content, contains('只输出可直接使用的正文'));
    expect(request.messages.last.content, contains('只输出需要在光标处新增的内容'));
    expect(request.messages.last.content, contains('正在写的这一段'));
  });

  test('inline replacement requests a complete revised target', () {
    final request = NoteAssistantPromptBuilder.build(
      action: NoteAssistantAction.custom('改写得更简洁'),
      title: '草稿',
      content: '需要修改的原文',
      scope: NoteAssistantScope.currentBlock,
      outputMode: NoteAssistantOutputMode.replaceTarget,
    );

    expect(request.messages.last.content, contains('修改后的完整内容'));
    expect(request.messages.last.content, contains('需要修改的原文'));
  });

  test('metadata updates use a strict local editor contract', () {
    final request = NoteAssistantPromptBuilder.build(
      action: NoteAssistantAction.custom('根据正文生成标题和标签'),
      title: '旧标题',
      tags: const ['旧标签'],
      content: '春天的露珠落在檐角。',
      outputMode: NoteAssistantOutputMode.updateMetadata,
    );

    expect(request.messages.first.content, contains('只输出一个合法 JSON 对象'));
    expect(request.messages.first.content, isNot(contains('只输出可直接使用的正文')));
    expect(request.messages.last.content, contains('标题与标签'));
    expect(request.messages.last.content, contains('标签：旧标签'));
    expect(request.messages.last.content, contains('"title"'));
  });

  test('metadata parser accepts fenced JSON and normalizes tags', () {
    final update = NoteAssistantMetadataUpdate.tryParse('''
```json
{"title":" 春日檐角 ","tags":["#春天","露珠","春天",""]}
```
''');

    expect(update?.title, '春日檐角');
    expect(update?.tags, ['春天', '露珠']);
    expect(NoteAssistantMetadataUpdate.tryParse('标题：无效'), isNull);
  });

  test('English locale produces an English on-device prompt', () {
    final request = NoteAssistantPromptBuilder.build(
      action: const NoteAssistantAction.preset(NoteAssistantTask.summarize),
      title: 'Release plan',
      content: 'Ship version 2.0 next week.',
      languageCode: 'en',
    );

    expect(
      request.messages.first.content,
      contains('on-device editing assistant'),
    );
    expect(request.messages.last.content, contains('Title: Release plan'));
    expect(request.messages.last.content, contains('Summarize this note'));
    expect(request.messages.last.content, isNot(contains('请用简洁的中文')));
  });

  test('reasoning blocks never reach assistant output', () {
    expect(
      LocalLlmOutputFilter.visibleText(
        '<think>private reasoning</think>\n用户可见内容',
      ),
      '用户可见内容',
    );
    expect(LocalLlmOutputFilter.visibleText('开头\n<think>尚未结束'), '开头\n');
    expect(
      LocalLlmOutputFilter.visibleText('回答一<think>内部</think>回答二'),
      '回答一回答二',
    );
  });
}
