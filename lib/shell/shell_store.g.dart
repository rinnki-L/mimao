// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shell_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$ShellStore on _ShellStore, Store {
  Computed<bool>? _$onEntryPageComputed;

  @override
  bool get onEntryPage => (_$onEntryPageComputed ??= Computed<bool>(
    () => super.onEntryPage,
    name: '_ShellStore.onEntryPage',
  )).value;

  late final _$activeModuleAtom = Atom(
    name: '_ShellStore.activeModule',
    context: context,
  );

  @override
  MediaType? get activeModule {
    _$activeModuleAtom.reportRead();
    return super.activeModule;
  }

  @override
  set activeModule(MediaType? value) {
    _$activeModuleAtom.reportWrite(value, super.activeModule, () {
      super.activeModule = value;
    });
  }

  late final _$showLibraryAtom = Atom(
    name: '_ShellStore.showLibrary',
    context: context,
  );

  @override
  bool get showLibrary {
    _$showLibraryAtom.reportRead();
    return super.showLibrary;
  }

  @override
  set showLibrary(bool value) {
    _$showLibraryAtom.reportWrite(value, super.showLibrary, () {
      super.showLibrary = value;
    });
  }

  late final _$settingsOpenAtom = Atom(
    name: '_ShellStore.settingsOpen',
    context: context,
  );

  @override
  bool get settingsOpen {
    _$settingsOpenAtom.reportRead();
    return super.settingsOpen;
  }

  @override
  set settingsOpen(bool value) {
    _$settingsOpenAtom.reportWrite(value, super.settingsOpen, () {
      super.settingsOpen = value;
    });
  }

  late final _$themeSeedAtom = Atom(
    name: '_ShellStore.themeSeed',
    context: context,
  );

  @override
  String get themeSeed {
    _$themeSeedAtom.reportRead();
    return super.themeSeed;
  }

  @override
  set themeSeed(String value) {
    _$themeSeedAtom.reportWrite(value, super.themeSeed, () {
      super.themeSeed = value;
    });
  }

  late final _$themeModeAtom = Atom(
    name: '_ShellStore.themeMode',
    context: context,
  );

  @override
  ThemeMode get themeMode {
    _$themeModeAtom.reportRead();
    return super.themeMode;
  }

  @override
  set themeMode(ThemeMode value) {
    _$themeModeAtom.reportWrite(value, super.themeMode, () {
      super.themeMode = value;
    });
  }

  late final _$systemAccentEpochAtom = Atom(
    name: '_ShellStore.systemAccentEpoch',
    context: context,
  );

  @override
  int get systemAccentEpoch {
    _$systemAccentEpochAtom.reportRead();
    return super.systemAccentEpoch;
  }

  @override
  set systemAccentEpoch(int value) {
    _$systemAccentEpochAtom.reportWrite(value, super.systemAccentEpoch, () {
      super.systemAccentEpoch = value;
    });
  }

  late final _$_ShellStoreActionController = ActionController(
    name: '_ShellStore',
    context: context,
  );

  @override
  void openModule(MediaType type) {
    final _$actionInfo = _$_ShellStoreActionController.startAction(
      name: '_ShellStore.openModule',
    );
    try {
      return super.openModule(type);
    } finally {
      _$_ShellStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void openLibrary() {
    final _$actionInfo = _$_ShellStoreActionController.startAction(
      name: '_ShellStore.openLibrary',
    );
    try {
      return super.openLibrary();
    } finally {
      _$_ShellStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void goHome() {
    final _$actionInfo = _$_ShellStoreActionController.startAction(
      name: '_ShellStore.goHome',
    );
    try {
      return super.goHome();
    } finally {
      _$_ShellStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void openSettings() {
    final _$actionInfo = _$_ShellStoreActionController.startAction(
      name: '_ShellStore.openSettings',
    );
    try {
      return super.openSettings();
    } finally {
      _$_ShellStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void closeSettings() {
    final _$actionInfo = _$_ShellStoreActionController.startAction(
      name: '_ShellStore.closeSettings',
    );
    try {
      return super.closeSettings();
    } finally {
      _$_ShellStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setThemeSeed(String seed) {
    final _$actionInfo = _$_ShellStoreActionController.startAction(
      name: '_ShellStore.setThemeSeed',
    );
    try {
      return super.setThemeSeed(seed);
    } finally {
      _$_ShellStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setThemeMode(ThemeMode mode) {
    final _$actionInfo = _$_ShellStoreActionController.startAction(
      name: '_ShellStore.setThemeMode',
    );
    try {
      return super.setThemeMode(mode);
    } finally {
      _$_ShellStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void bumpSystemAccent() {
    final _$actionInfo = _$_ShellStoreActionController.startAction(
      name: '_ShellStore.bumpSystemAccent',
    );
    try {
      return super.bumpSystemAccent();
    } finally {
      _$_ShellStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
activeModule: ${activeModule},
showLibrary: ${showLibrary},
settingsOpen: ${settingsOpen},
themeSeed: ${themeSeed},
themeMode: ${themeMode},
systemAccentEpoch: ${systemAccentEpoch},
onEntryPage: ${onEntryPage}
    ''';
  }
}
