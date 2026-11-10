import 'package:uuid/uuid.dart';

import 'note.dart';

enum NoteConstellationGroupKind { cluster, nebula, galaxy }

final class NoteConstellationPosition {
  NoteConstellationPosition({
    required this.noteId,
    required this.x,
    required this.y,
    required DateTime updatedAt,
  }) : updatedAt = updatedAt.toUtc() {
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('Constellation coordinates must be finite');
    }
  }

  final NoteId noteId;
  final double x;
  final double y;
  final DateTime updatedAt;

  NoteConstellationPosition copyWith({
    double? x,
    double? y,
    DateTime? updatedAt,
  }) => NoteConstellationPosition(
    noteId: noteId,
    x: x ?? this.x,
    y: y ?? this.y,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteConstellationPosition &&
          other.noteId == noteId &&
          other.x == x &&
          other.y == y &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(noteId, x, y, updatedAt);
}

final class NoteConstellationOverviewPosition {
  NoteConstellationOverviewPosition({
    required String groupKey,
    required this.noteId,
    required this.x,
    required this.y,
    required DateTime updatedAt,
  }) : groupKey = groupKey.trim(),
       updatedAt = updatedAt.toUtc() {
    if (this.groupKey.isEmpty) throw ArgumentError.value(groupKey, 'groupKey');
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('Constellation coordinates must be finite');
    }
  }

  final String groupKey;
  final NoteId noteId;
  final double x;
  final double y;
  final DateTime updatedAt;
}

final class NoteConstellationOverviewRegionPosition {
  NoteConstellationOverviewRegionPosition({
    required String groupKey,
    required this.x,
    required this.y,
    required DateTime updatedAt,
  }) : groupKey = groupKey.trim(),
       updatedAt = updatedAt.toUtc() {
    if (this.groupKey.isEmpty) throw ArgumentError.value(groupKey, 'groupKey');
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('Constellation coordinates must be finite');
    }
  }

  final String groupKey;
  final double x;
  final double y;
  final DateTime updatedAt;
}

final class NoteConstellationGroup {
  NoteConstellationGroup({
    required this.id,
    required String name,
    required this.kind,
    required this.colorIndex,
    required Iterable<NoteId> noteIds,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : name = name.trim(),
       noteIds = Set.unmodifiable(noteIds),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (this.name.isEmpty) throw ArgumentError.value(name, 'name');
    if (colorIndex < 0 || colorIndex >= paletteLength) {
      throw ArgumentError.value(colorIndex, 'colorIndex');
    }
  }

  factory NoteConstellationGroup.create({
    required String name,
    required NoteConstellationGroupKind kind,
    required int colorIndex,
    required Iterable<NoteId> noteIds,
    DateTime? now,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    return NoteConstellationGroup(
      id: const Uuid().v4(),
      name: name,
      kind: kind,
      colorIndex: colorIndex,
      noteIds: noteIds,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static const paletteLength = 5;

  final String id;
  final String name;
  final NoteConstellationGroupKind kind;
  final int colorIndex;
  final Set<NoteId> noteIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoteConstellationGroup copyWith({
    String? name,
    NoteConstellationGroupKind? kind,
    int? colorIndex,
    Iterable<NoteId>? noteIds,
    DateTime? updatedAt,
  }) => NoteConstellationGroup(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    colorIndex: colorIndex ?? this.colorIndex,
    noteIds: noteIds ?? this.noteIds,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteConstellationGroup &&
          other.id == id &&
          other.name == name &&
          other.kind == kind &&
          other.colorIndex == colorIndex &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          _setsEqual(other.noteIds, noteIds);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    colorIndex,
    Object.hashAllUnordered(noteIds),
    createdAt,
    updatedAt,
  );
}

final class NoteConstellationSnapshot {
  NoteConstellationSnapshot({
    required Map<NoteId, NoteConstellationPosition> positions,
    required Iterable<NoteConstellationGroup> groups,
    Map<String, Map<NoteId, NoteConstellationOverviewPosition>>
        overviewPositions =
        const {},
    Map<String, NoteConstellationOverviewRegionPosition>
        overviewRegionPositions =
        const {},
  }) : positions = Map.unmodifiable(positions),
       groups = List.unmodifiable(groups),
       overviewPositions = Map.unmodifiable({
         for (final entry in overviewPositions.entries)
           entry.key:
               Map<NoteId, NoteConstellationOverviewPosition>.unmodifiable(
                 entry.value,
               ),
       }),
       overviewRegionPositions = Map.unmodifiable(overviewRegionPositions);

  const NoteConstellationSnapshot.empty()
    : positions = const {},
      groups = const [],
      overviewPositions = const {},
      overviewRegionPositions = const {};

  final Map<NoteId, NoteConstellationPosition> positions;
  final List<NoteConstellationGroup> groups;
  final Map<String, Map<NoteId, NoteConstellationOverviewPosition>>
  overviewPositions;
  final Map<String, NoteConstellationOverviewRegionPosition>
  overviewRegionPositions;
}

bool _setsEqual<T>(Set<T> first, Set<T> second) =>
    first.length == second.length && first.containsAll(second);
