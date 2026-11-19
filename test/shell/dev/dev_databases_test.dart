import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/shell/dev/dev_databases.dart';

void main() {
  test('注册/覆盖/注销/列名', () async {
    final db = AppDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    expect(devDatabaseNames(), isNot(contains('__test_db__')));

    devRegisterDatabase('__test_db__', db);
    expect(devDatabases['__test_db__'], same(db));
    expect(devDatabaseNames(), contains('__test_db__'));

    // 同名覆盖：后注册者胜。
    final other = AppDb.forTesting(NativeDatabase.memory());
    addTearDown(other.close);
    devRegisterDatabase('__test_db__', other);
    expect(devDatabases['__test_db__'], same(other));

    devUnregisterDatabase('__test_db__');
    expect(devDatabases.containsKey('__test_db__'), isFalse);
  });

  test('devDatabaseNames 字典序', () {
    devRegisterDatabase('b', AppDb.forTesting(NativeDatabase.memory()));
    devRegisterDatabase('a', AppDb.forTesting(NativeDatabase.memory()));
    addTearDown(() {
      devUnregisterDatabase('a');
      devUnregisterDatabase('b');
    });

    final names = devDatabaseNames().where((n) => n == 'a' || n == 'b');
    expect(names.toList(), ['a', 'b']);
  });
}
