// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'music_library_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$MusicLibraryStore on _MusicLibraryStore, Store {
  Computed<Set<String>>? _$collectedIdsComputed;

  @override
  Set<String> get collectedIds =>
      (_$collectedIdsComputed ??= Computed<Set<String>>(
        () => super.collectedIds,
        name: '_MusicLibraryStore.collectedIds',
      )).value;
  Computed<bool>? _$isEmptyComputed;

  @override
  bool get isEmpty => (_$isEmptyComputed ??= Computed<bool>(
    () => super.isEmpty,
    name: '_MusicLibraryStore.isEmpty',
  )).value;

  late final _$collectedAtom = Atom(
    name: '_MusicLibraryStore.collected',
    context: context,
  );

  @override
  ObservableList<MusicCollectItem> get collected {
    _$collectedAtom.reportRead();
    return super.collected;
  }

  @override
  set collected(ObservableList<MusicCollectItem> value) {
    _$collectedAtom.reportWrite(value, super.collected, () {
      super.collected = value;
    });
  }

  late final _$historyAtom = Atom(
    name: '_MusicLibraryStore.history',
    context: context,
  );

  @override
  ObservableList<MusicHistoryItem> get history {
    _$historyAtom.reportRead();
    return super.history;
  }

  @override
  set history(ObservableList<MusicHistoryItem> value) {
    _$historyAtom.reportWrite(value, super.history, () {
      super.history = value;
    });
  }

  late final _$isLoadingAtom = Atom(
    name: '_MusicLibraryStore.isLoading',
    context: context,
  );

  @override
  bool get isLoading {
    _$isLoadingAtom.reportRead();
    return super.isLoading;
  }

  @override
  set isLoading(bool value) {
    _$isLoadingAtom.reportWrite(value, super.isLoading, () {
      super.isLoading = value;
    });
  }

  late final _$errorAtom = Atom(
    name: '_MusicLibraryStore.error',
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

  late final _$libraryTabAtom = Atom(
    name: '_MusicLibraryStore.libraryTab',
    context: context,
  );

  @override
  int get libraryTab {
    _$libraryTabAtom.reportRead();
    return super.libraryTab;
  }

  @override
  set libraryTab(int value) {
    _$libraryTabAtom.reportWrite(value, super.libraryTab, () {
      super.libraryTab = value;
    });
  }

  late final _$refreshAsyncAction = AsyncAction(
    '_MusicLibraryStore.refresh',
    context: context,
  );

  @override
  Future<void> refresh() {
    return _$refreshAsyncAction.run(() => super.refresh());
  }

  late final _$_MusicLibraryStoreActionController = ActionController(
    name: '_MusicLibraryStore',
    context: context,
  );

  @override
  void selectTab(int index) {
    final _$actionInfo = _$_MusicLibraryStoreActionController.startAction(
      name: '_MusicLibraryStore.selectTab',
    );
    try {
      return super.selectTab(index);
    } finally {
      _$_MusicLibraryStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
collected: ${collected},
history: ${history},
isLoading: ${isLoading},
error: ${error},
libraryTab: ${libraryTab},
collectedIds: ${collectedIds},
isEmpty: ${isEmpty}
    ''';
  }
}
