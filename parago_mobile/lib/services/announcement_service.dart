import '../core/network/api_client.dart';
import '../core/exceptions/api_exception.dart';
import '../models/operations/announcement.dart';

abstract interface class AnnouncementRepository {
  Future<List<AnnouncementModel>> getActive({bool useCache = true});

  Future<void> dismiss(String id, {required int revision});
}

class AnnouncementService implements AnnouncementRepository {
  AnnouncementService(this._client);

  final ApiClient _client;

  @override
  Future<List<AnnouncementModel>> getActive({bool useCache = true}) async {
    final data = await _client.getList(
      path: '/announcements/active',
      useCache: useCache,
    );
    return data
        .whereType<Map>()
        .map((item) => AnnouncementModel.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList(growable: false);
  }

  @override
  Future<void> dismiss(String id, {required int revision}) async {
    await _client.request(
      method: 'POST',
      path: '/announcements/$id/dismiss',
      body: {'revision': revision},
      useCache: false,
    );
  }
}

enum AnnouncementDismissStatus {
  dismissed,
  staleRevision,
  failed,
}

class AnnouncementDismissResult {
  const AnnouncementDismissResult._(this.status, [this.error]);

  const AnnouncementDismissResult.dismissed()
      : this._(AnnouncementDismissStatus.dismissed);

  const AnnouncementDismissResult.staleRevision()
      : this._(AnnouncementDismissStatus.staleRevision);

  const AnnouncementDismissResult.failed(Object error)
      : this._(AnnouncementDismissStatus.failed, error);

  final AnnouncementDismissStatus status;
  final Object? error;
}

class AnnouncementFeedController {
  AnnouncementFeedController(this._repository);

  final AnnouncementRepository _repository;
  List<AnnouncementModel> _items = const [];
  Future<List<AnnouncementModel>>? _activeRefresh;
  bool _refreshQueued = false;
  bool _queuedUseCache = true;
  bool _hasSuccessfulSnapshot = false;
  bool _disposed = false;
  int _generation = 0;

  List<AnnouncementModel> get items => List.unmodifiable(_items);
  bool get hasSuccessfulSnapshot => _hasSuccessfulSnapshot;

  Future<List<AnnouncementModel>> refresh({bool useCache = false}) {
    if (_disposed) return Future.value(items);
    if (_refreshQueued) {
      _queuedUseCache = _queuedUseCache && useCache;
    } else {
      _refreshQueued = true;
      _queuedUseCache = useCache;
    }

    final active = _activeRefresh;
    if (active != null) return active;

    final operation = _drainRefreshQueue();
    _activeRefresh = operation;
    operation.whenComplete(() {
      if (identical(_activeRefresh, operation)) {
        _activeRefresh = null;
      }
    });
    return operation;
  }

  Future<List<AnnouncementModel>> _drainRefreshQueue() async {
    while (_refreshQueued && !_disposed) {
      final useCache = _queuedUseCache;
      _refreshQueued = false;
      _queuedUseCache = true;
      final generation = ++_generation;
      try {
        final loaded = await _repository.getActive(useCache: useCache);
        if (!_disposed && generation == _generation) {
          _items = _sortNewestFirst(loaded);
          _hasSuccessfulSnapshot = true;
        }
      } catch (_) {
        if (!_hasSuccessfulSnapshot && generation == _generation) {
          _items = const [];
        }
      }
    }
    return items;
  }

  Future<AnnouncementDismissResult> dismiss(
    AnnouncementModel announcement,
  ) async {
    final index = _items.indexWhere(
      (item) =>
          item.id == announcement.id && item.revision == announcement.revision,
    );
    if (index < 0) {
      return const AnnouncementDismissResult.dismissed();
    }

    _generation++;
    final next = List<AnnouncementModel>.from(_items)..removeAt(index);
    _items = List.unmodifiable(next);

    try {
      await _repository.dismiss(
        announcement.id,
        revision: announcement.revision,
      );
      return const AnnouncementDismissResult.dismissed();
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        await refresh(useCache: false);
        return const AnnouncementDismissResult.staleRevision();
      }
      _restoreIfCurrent(index, announcement);
      return AnnouncementDismissResult.failed(error);
    } catch (error) {
      _restoreIfCurrent(index, announcement);
      return AnnouncementDismissResult.failed(error);
    }
  }

  void _restoreIfCurrent(int index, AnnouncementModel removed) {
    final current = _items.where((item) => item.id == removed.id);
    if (current.any((item) => item.revision >= removed.revision)) return;
    final restored = List<AnnouncementModel>.from(_items);
    restored.insert(index.clamp(0, restored.length), removed);
    _items = List.unmodifiable(restored);
  }

  List<AnnouncementModel> _sortNewestFirst(
    List<AnnouncementModel> announcements,
  ) {
    final sorted = List<AnnouncementModel>.from(announcements);
    sorted.sort((left, right) {
      final leftDate = left.publishedAt ?? left.startsAt;
      final rightDate = right.publishedAt ?? right.startsAt;
      return rightDate.compareTo(leftDate);
    });
    return List.unmodifiable(sorted);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _refreshQueued = false;
  }
}
