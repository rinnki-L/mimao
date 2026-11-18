// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'music_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$MusicStore on _MusicStore, Store {
  late final _$resultsAtom = Atom(
    name: '_MusicStore.results',
    context: context,
  );

  @override
  ObservableList<MusicSong> get results {
    _$resultsAtom.reportRead();
    return super.results;
  }

  @override
  set results(ObservableList<MusicSong> value) {
    _$resultsAtom.reportWrite(value, super.results, () {
      super.results = value;
    });
  }

  late final _$lastKeywordAtom = Atom(
    name: '_MusicStore.lastKeyword',
    context: context,
  );

  @override
  String get lastKeyword {
    _$lastKeywordAtom.reportRead();
    return super.lastKeyword;
  }

  @override
  set lastKeyword(String value) {
    _$lastKeywordAtom.reportWrite(value, super.lastKeyword, () {
      super.lastKeyword = value;
    });
  }

  late final _$isLoadingAtom = Atom(
    name: '_MusicStore.isLoading',
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

  late final _$errorAtom = Atom(name: '_MusicStore.error', context: context);

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

  late final _$searchedAtom = Atom(
    name: '_MusicStore.searched',
    context: context,
  );

  @override
  bool get searched {
    _$searchedAtom.reportRead();
    return super.searched;
  }

  @override
  set searched(bool value) {
    _$searchedAtom.reportWrite(value, super.searched, () {
      super.searched = value;
    });
  }

  late final _$searchAsyncAction = AsyncAction(
    '_MusicStore.search',
    context: context,
  );

  @override
  Future<void> search(String keyword) {
    return _$searchAsyncAction.run(() => super.search(keyword));
  }

  late final _$_MusicStoreActionController = ActionController(
    name: '_MusicStore',
    context: context,
  );

  @override
  void clearError() {
    final _$actionInfo = _$_MusicStoreActionController.startAction(
      name: '_MusicStore.clearError',
    );
    try {
      return super.clearError();
    } finally {
      _$_MusicStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
results: ${results},
lastKeyword: ${lastKeyword},
isLoading: ${isLoading},
error: ${error},
searched: ${searched}
    ''';
  }
}
