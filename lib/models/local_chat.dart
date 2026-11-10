import 'note.dart';

enum LocalChatRole { user, assistant }

enum LocalChatMessageStatus { complete, stopped }

enum LocalChatAttachmentType { image }

enum LocalChatNoteScope { selection, currentBlock, fullNote }

enum LocalChatToolName { searchNotes, createNote, appendNote, replaceNote }

enum LocalChatToolStatus { proposed, completed }

class LocalChatToolCall {
  final String id;
  final LocalChatToolName name;
  final String? query;
  final NoteId? noteId;
  final String? title;
  final String? content;
  final LocalChatToolStatus status;

  const LocalChatToolCall({
    required this.id,
    required this.name,
    this.query,
    this.noteId,
    this.title,
    this.content,
    this.status = LocalChatToolStatus.proposed,
  });

  bool get isWrite => name != LocalChatToolName.searchNotes;

  LocalChatToolCall copyWith({LocalChatToolStatus? status}) =>
      LocalChatToolCall(
        id: id,
        name: name,
        query: query,
        noteId: noteId,
        title: title,
        content: content,
        status: status ?? this.status,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name.name,
    'query': query,
    'noteId': noteId?.value,
    'title': title,
    'content': content,
    'status': status.name,
  };

  factory LocalChatToolCall.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = LocalChatToolName.values.where(
      (value) => value.name == json['name'],
    );
    if (id is! String || id.isEmpty || name.isEmpty) {
      throw const FormatException('聊天工具调用格式不正确');
    }
    return LocalChatToolCall(
      id: id,
      name: name.first,
      query: json['query'] as String?,
      noteId: switch (json['noteId']) {
        final String value => NoteId.parse(value),
        _ => null,
      },
      title: json['title'] as String?,
      content: json['content'] as String?,
      status: json['status'] == LocalChatToolStatus.completed.name
          ? LocalChatToolStatus.completed
          : LocalChatToolStatus.proposed,
    );
  }
}

class LocalChatNoteContext {
  final bool isPrivate;
  final NoteId noteId;
  final String title;
  final LocalChatNoteScope scope;
  final String content;
  final DateTime updatedAt;

  const LocalChatNoteContext({
    this.isPrivate = false,
    required this.noteId,
    required this.title,
    required this.scope,
    required this.content,
    required this.updatedAt,
  });

  LocalChatNoteContext copyWith({String? content}) => LocalChatNoteContext(
    isPrivate: isPrivate,
    noteId: noteId,
    title: title,
    scope: scope,
    content: content ?? this.content,
    updatedAt: updatedAt,
  );

  Map<String, Object> toJson() => {
    'noteId': noteId.value,
    'isPrivate': isPrivate,
    'title': title,
    'scope': scope.name,
    'content': content,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory LocalChatNoteContext.fromJson(Map<String, Object?> json) {
    final noteId = json['noteId'];
    final title = json['title'];
    final content = json['content'];
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (noteId is! String ||
        title is! String ||
        content is! String ||
        updatedAt == null) {
      throw const FormatException('聊天笔记上下文格式不正确');
    }
    return LocalChatNoteContext(
      isPrivate: json['isPrivate'] == true,
      noteId: NoteId.parse(noteId),
      title: title,
      scope: LocalChatNoteScope.values.firstWhere(
        (value) => value.name == json['scope'],
        orElse: () => LocalChatNoteScope.fullNote,
      ),
      content: content,
      updatedAt: updatedAt,
    );
  }
}

class LocalChatAttachment {
  final String id;
  final LocalChatAttachmentType type;
  final String filePath;
  final String fileName;
  final String mimeType;
  final DateTime createdAt;

  const LocalChatAttachment({
    required this.id,
    required this.type,
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    required this.createdAt,
  });

  Map<String, Object> toJson() => {
    'id': id,
    'type': type.name,
    'filePath': filePath,
    'fileName': fileName,
    'mimeType': mimeType,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LocalChatAttachment.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    final filePath = json['filePath'] as String?;
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (id == null ||
        id.isEmpty ||
        filePath == null ||
        filePath.isEmpty ||
        createdAt == null) {
      throw const FormatException('聊天附件格式不正确');
    }
    return LocalChatAttachment(
      id: id,
      type: LocalChatAttachmentType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => LocalChatAttachmentType.image,
      ),
      filePath: filePath,
      fileName: json['fileName'] as String? ?? '图片',
      mimeType: json['mimeType'] as String? ?? 'image/*',
      createdAt: createdAt,
    );
  }
}

class LocalChatPersona {
  static const defaultId = 'default';
  static const defaultSystemPrompt = '''
# 身份

你是非空笔记助手，帮助用户记录、查找、理解、整理和完善自己的笔记，并完成与笔记相关的工作流。
“包子（Baozi）”可以作为你的亲切人格参考：踏实、务实、内里有料，但它不能取代“非空笔记助手”这一核心身份。

## 模型归属

用户可以在非空笔记中切换本地或在线模型。被问及当前模型、提供商或底层能力时，只能依据当前任务明确提供的真实运行时信息回答。
没有获得相关信息时直接说明不知道，不得猜测、冒充或固定声称自己由某个模型驱动。

## 非空小队

非空小队是一个神秘但友好的组织。关于其起源和完整成员构成，外界知之甚少，但每位成员都始终能力出众、资源丰富、乐于分享知识。
小队崇尚能力重于资历，清晰重于繁文缛节，成事重于看起来很忙。
你为自己是这个团队的一员而自豪，并在每次交流中践行其精神。

## 性格

- 踏实而亲切，就像你的同名食物包子一样。外表朴实无华，内里有料且让人满足。
- 务实至上。选择能解决问题的最简单工具，而不是最炫的那个。
- 技术功底深厚，但绝不装腔作势。让复杂的东西变得容易理解，而不是将其简单粗暴地简化。
- 坦诚面对自己的局限。如果不知道某事或缺乏上下文，直接说出来，并主动表示愿意去了解。
- 带有淡淡的幽默感。在合适的时机可以轻松一下，但绝不能以牺牲帮助他人为代价。

## 沟通风格

- 简洁高效。短句。不啰嗦。
- 默认使用中文。只有当对方先使用英文，或专有名词保留原文更好时才切换。
- 展示代码时解释“为什么”，而不是复述代码“是什么”。
- 宁愿给一个具体例子，也不要给一大段抽象描述。
- 当你不同意或有更好的方案时，带着尊重和理由说出来。一个好的队友不会只会点头。

## 与用户协作

- 把用户当作有能力的协作者。你在这里是执行的，不是来说教的。
- 提前预判下一步。完成任务后，简要建议接下来可以做什么，但不要偏离当前工作。
- 当用户在探索或不太确定时，先帮他们理清真正想要什么，再深入实现。

## 回复格式偏好

- 优先使用纯 Markdown 进行常规回答、解释、列表和静态表格。
- 对于有时效性的问题或需要验证的主张，先使用当前任务实际提供的联网工具收集信息；没有联网工具时明确说明，不得虚构工具或搜索结果。
- 准确性优先。当事实可能已经变化时，不要依赖训练数据。
''';

  final String id;
  final String name;
  final String description;
  final String systemPrompt;
  final bool builtIn;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalChatPersona({
    required this.id,
    required this.name,
    required this.description,
    required this.systemPrompt,
    required this.builtIn,
    required this.createdAt,
    required this.updatedAt,
  });

  LocalChatPersona copyWith({
    String? name,
    String? description,
    String? systemPrompt,
    DateTime? updatedAt,
  }) => LocalChatPersona(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    builtIn: builtIn,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class LocalChatMessage {
  final String id;
  final LocalChatRole role;
  final String content;
  final List<LocalChatAttachment> attachments;
  final List<LocalChatNoteContext> noteContexts;
  final List<LocalChatToolCall> toolCalls;
  final DateTime createdAt;
  final LocalChatMessageStatus status;

  const LocalChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.attachments = const [],
    this.noteContexts = const [],
    this.toolCalls = const [],
    this.status = LocalChatMessageStatus.complete,
  });

  LocalChatMessage copyWith({
    String? content,
    List<LocalChatAttachment>? attachments,
    List<LocalChatNoteContext>? noteContexts,
    List<LocalChatToolCall>? toolCalls,
    LocalChatMessageStatus? status,
  }) => LocalChatMessage(
    id: id,
    role: role,
    content: content ?? this.content,
    createdAt: createdAt,
    attachments: attachments ?? this.attachments,
    noteContexts: noteContexts ?? this.noteContexts,
    toolCalls: toolCalls ?? this.toolCalls,
    status: status ?? this.status,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'role': role.name,
    'content': content,
    'attachments': attachments
        .map((attachment) => attachment.toJson())
        .toList(),
    'noteContexts': noteContexts.map((context) => context.toJson()).toList(),
    'toolCalls': toolCalls.map((call) => call.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
  };

  factory LocalChatMessage.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final content = json['content'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (id is! String ||
        id.isEmpty ||
        content is! String ||
        createdAt == null) {
      throw const FormatException('聊天消息格式不正确');
    }
    return LocalChatMessage(
      id: id,
      role: switch (json['role']) {
        'user' => LocalChatRole.user,
        'assistant' => LocalChatRole.assistant,
        _ => throw const FormatException('聊天消息角色不正确'),
      },
      content: content,
      createdAt: createdAt,
      attachments: (json['attachments'] as List? ?? const [])
          .map(
            (attachment) => LocalChatAttachment.fromJson(
              Map<String, Object?>.from(attachment as Map),
            ),
          )
          .toList(growable: false),
      noteContexts: (json['noteContexts'] as List? ?? const [])
          .map(
            (context) => LocalChatNoteContext.fromJson(
              Map<String, Object?>.from(context as Map),
            ),
          )
          .toList(growable: false),
      toolCalls: (json['toolCalls'] as List? ?? const [])
          .map(
            (call) => LocalChatToolCall.fromJson(
              Map<String, Object?>.from(call as Map),
            ),
          )
          .toList(growable: false),
      status: json['status'] == 'stopped'
          ? LocalChatMessageStatus.stopped
          : LocalChatMessageStatus.complete,
    );
  }
}

class LocalChatSession {
  final bool privateSpace;
  final String id;
  final String title;
  final String personaId;
  final String systemPrompt;
  final List<LocalChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalChatSession({
    this.privateSpace = false,
    required this.id,
    required this.title,
    this.personaId = LocalChatPersona.defaultId,
    required this.systemPrompt,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
  });

  LocalChatSession copyWith({
    String? title,
    String? personaId,
    String? systemPrompt,
    List<LocalChatMessage>? messages,
    DateTime? updatedAt,
  }) => LocalChatSession(
    privateSpace: privateSpace,
    id: id,
    title: title ?? this.title,
    personaId: personaId ?? this.personaId,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    messages: messages ?? this.messages,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'personaId': personaId,
    'privateSpace': privateSpace,
    'systemPrompt': systemPrompt,
    'messages': messages.map((message) => message.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory LocalChatSession.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    final systemPrompt = json['systemPrompt'];
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    final messages = json['messages'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        systemPrompt is! String ||
        createdAt == null ||
        updatedAt == null ||
        messages is! List) {
      throw const FormatException('聊天会话格式不正确');
    }
    return LocalChatSession(
      privateSpace: json['privateSpace'] == true,
      id: id,
      title: title,
      personaId: json['personaId'] as String? ?? LocalChatPersona.defaultId,
      systemPrompt: systemPrompt,
      messages: messages
          .map(
            (message) => LocalChatMessage.fromJson(
              Map<String, Object?>.from(message as Map),
            ),
          )
          .toList(growable: false),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
