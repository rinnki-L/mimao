// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$MusicPlayerStore on _MusicPlayerStore, Store {
  Computed<MusicSong?>? _$currentSongComputed;

  @override
  MusicSong? get currentSong => (_$currentSongComputed ??= Computed<MusicSong?>(
    () => super.currentSong,
    name: '_MusicPlayerStore.currentSong',
  )).value;

  late final _$queueAtom = Atom(
    name: '_MusicPlayerStore.queue',
    context: context,
  );

  @override
  ObservableList<MusicSong> get queue {
    _$queueAtom.reportRead();
    return super.queue;
  }

  @override
  set queue(ObservableList<MusicSong> value) {
    _$queueAtom.reportWrite(value, super.queue, () {
      super.queue = value;
    });
  }

  late final _$indexAtom = Atom(
    name: '_MusicPlayerStore.index',
    context: context,
  );

  @override
  int get index {
    _$indexAtom.reportRead();
    return super.index;
  }

  @override
  set index(int value) {
    _$indexAtom.reportWrite(value, super.index, () {
      super.index = value;
    });
  }

  late final _$snapshotAtom = Atom(
    name: '_MusicPlayerStore.snapshot',
    context: context,
  );

  @override
  MusicPlaybackSnapshot get snapshot {
    _$snapshotAtom.reportRead();
    return super.snapshot;
  }

  @override
  set snapshot(MusicPlaybackSnapshot value) {
    _$snapshotAtom.reportWrite(value, super.snapshot, () {
      super.snapshot = value;
    });
  }

  late final _$isResolvingAtom = Atom(
    name: '_MusicPlayerStore.isResolving',
    context: context,
  );

  @override
  bool get isResolving {
    _$isResolvingAtom.reportRead();
    return super.isResolving;
  }

  @override
  set isResolving(bool value) {
    _$isResolvingAtom.reportWrite(value, super.isResolving, () {
      super.isResolving = value;
    });
  }

  late final _$playModeAtom = Atom(
    name: '_MusicPlayerStore.playMode',
    context: context,
  );

  @override
  PlayMode get playMode {
    _$playModeAtom.reportRead();
    return super.playMode;
  }

  @override
  set playMode(PlayMode value) {
    _$playModeAtom.reportWrite(value, super.playMode, () {
      super.playMode = value;
    });
  }

  late final _$errorAtom = Atom(
    name: '_MusicPlayerStore.error',
    context: context,
  );

  @override
  String? get error {
    _$errorAtom.reportRead();
    return super.error;
  }

  @override
  set error(String? value) {
    _$errorAtom.reportWrite(value, super.error, () {
      super.error = value;
    });
  }

  late final _$volumeAtom = Atom(
    name: '_MusicPlayerStore.volume',
    context: context,
  );

  @override
  double get volume {
    _$volumeAtom.reportRead();
    return super.volume;
  }

  @override
  set volume(double value) {
    _$volumeAtom.reportWrite(value, super.volume, () {
      super.volume = value;
    });
  }

  late final _$mutedAtom = Atom(
    name: '_MusicPlayerStore.muted',
    context: context,
  );

  @override
  bool get muted {
    _$mutedAtom.reportRead();
    return super.muted;
  }

  @override
  set muted(bool value) {
    _$mutedAtom.reportWrite(value, super.muted, () {
      super.muted = value;
    });
  }

  late final _$playAtAsyncAction = AsyncAction(
    '_MusicPlayerStore.playAt',
    context: context,
  );

  @override
  Future<void> playAt(int target) {
    return _$playAtAsyncAction.run(() => super.playAt(target));
  }

  late final _$playListAsyncAction = AsyncAction(
    '_MusicPlayerStore.playList',
    context: context,
  );

  @override
  Future<void> playList(
    List<MusicSong> songs, {
    int startIndex = 0,
    Duration startAt = Duration.zero,
  }) {
    return _$playListAsyncAction.run(
      () => super.playList(songs, startIndex: startIndex, startAt: startAt),
    );
  }

  late final _$nextAsyncAction = AsyncAction(
    '_MusicPlayerStore.next',
    context: context,
  );

  @override
  Future<void> next() {
    return _$nextAsyncAction.run(() => super.next());
  }

  late final _$previousAsyncAction = AsyncAction(
    '_MusicPlayerStore.previous',
    context: context,
  );

  @override
  Future<void> previous() {
    return _$previousAsyncAction.run(() => super.previous());
  }

  late final _$toggleAsyncAction = AsyncAction(
    '_MusicPlayerStore.toggle',
    context: context,
  );

  @override
  Future<void> toggle() {
    return _$toggleAsyncAction.run(() => super.toggle());
  }

  late final _$seekToAsyncAction = AsyncAction(
    '_MusicPlayerStore.seekTo',
    context: context,
  );

  @override
  Future<void> seekTo(Duration position) {
    return _$seekToAsyncAction.run(() => super.seekTo(position));
  }

  late final _$setVolumeAsyncAction = AsyncAction(
    '_MusicPlayerStore.setVolume',
    context: context,
  );

  @override
  Future<void> setVolume(double value) {
    return _$setVolumeAsyncAction.run(() => super.setVolume(value));
  }

  late final _$retryAsyncAction = AsyncAction(
    '_MusicPlayerStore.retry',
    context: context,
  );

  @override
  Future<void> retry() {
    return _$retryAsyncAction.run(() => super.retry());
  }

  late final _$_MusicPlayerStoreActionController = ActionController(
    name: '_MusicPlayerStore',
    context: context,
  );

  @override
  Future<void> playSong(MusicSong song, {Duration startAt = Duration.zero}) {
    final _$actionInfo = _$_MusicPlayerStoreActionController.startAction(
      name: '_MusicPlayerStore.playSong',
    );
    try {
      return super.playSong(song, startAt: startAt);
    } finally {
      _$_MusicPlayerStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setPlayMode(PlayMode mode) {
    final _$actionInfo = _$_MusicPlayerStoreActionController.startAction(
      name: '_MusicPlayerStore.setPlayMode',
    );
    try {
      return super.setPlayMode(mode);
    } finally {
      _$_MusicPlayerStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void dispose() {
    final _$actionInfo = _$_MusicPlayerStoreActionController.startAction(
      name: '_MusicPlayerStore.dispose',
    );
    try {
      return super.dispose();
    } finally {
      _$_MusicPlayerStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
queue: ${queue},
index: ${index},
snapshot: ${snapshot},
isResolving: ${isResolving},
playMode: ${playMode},
error: ${error},
volume: ${volume},
muted: ${muted},
currentSong: ${currentSong}
    ''';
  }
}
