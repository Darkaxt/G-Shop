import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:g_shop/models/rom_cache_policy.dart';
import 'package:g_shop/services/rom_cache_store.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late RomCacheStore store;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await RomCacheSchema.install(db);
    store = RomCacheStore(Future.value(db));
  });
  tearDown(() => db.close());
  test(
      'late concurrent clock samples do not move the monotonic anchor backwards',
      () async {
    expect(
        await store.observeClock(
            {'wallMillis': 1000000, 'elapsedMillis': 1000, 'bootCount': 1}),
        isTrue);
    expect(
        await store.observeClock(
            {'wallMillis': 1002000, 'elapsedMillis': 3000, 'bootCount': 1}),
        isTrue);
    expect(
        await store.observeClock(
            {'wallMillis': 1001000, 'elapsedMillis': 2000, 'bootCount': 1}),
        isTrue);
    expect((await db.query('rom_cache_clock')).single['elapsed_ms'], 3000);
    expect(
        await store.observeClock(
            {'wallMillis': 1001500, 'elapsedMillis': 4000, 'bootCount': 1}),
        isFalse);
  });
  test('clock anomalies persist a pause until explicit clock acknowledgement',
      () async {
    const initial = {
      'wallMillis': 1000000,
      'elapsedMillis': 1000,
      'bootCount': 1
    };
    expect(await store.observeClock(initial), isTrue);
    expect(
        await store.observeClock(
            {'wallMillis': 2000000, 'elapsedMillis': 2000, 'bootCount': 1}),
        isFalse);
    expect(
        await store.observeClock(
            {'wallMillis': 2001000, 'elapsedMillis': 3000, 'bootCount': 1}),
        isFalse);
    expect(
        await store.observeClock(
            {'wallMillis': 2001000, 'elapsedMillis': 3000, 'bootCount': 1},
            acknowledge: true),
        isTrue);
    expect(
        await store.observeClock(
            {'wallMillis': 2000000, 'elapsedMillis': 4000, 'bootCount': 1}),
        isFalse);
  });
  test(
      'upgrade starts disabled, retains unknown histories and preserves saved configuration',
      () async {
    expect((await store.policy()).enabled, isFalse);
    expect(await store.usage('old'), isNull);
    final configured =
        RomCachePolicy(enabled: true, defaults: RomCacheLimits(maxGames: 2));
    await store.savePolicy(configured);
    await RomCacheSchema.install(db);
    expect((await RomCacheStore(Future.value(db)).policy()).toJson(),
        configured.toJson());
  });
  test(
      'verified installation and successful handoff keep distinct durable time facts',
      () async {
    final installed = DateTime.utc(2026, 10, 13);
    final played = installed.add(const Duration(hours: 2));
    await RomCacheSchema.recordInstalled(db, 'one', installed);
    await store.recordSuccessfulUse('one', played);
    final row = (await store.usage('one'))!;
    expect(row.installedAt, installed);
    expect(row.lastUsedAt, played);
    await store.recordSuccessfulUse('one', installed);
    expect((await store.usage('one'))!.lastUsedAt, played);
    await store.recordSuccessfulUse('legacy', played);
    expect((await store.usage('legacy'))!.installedAt, isNull);
    expect((await store.usage('legacy'))!.lastUsedAt, played);
  });
  test('pins belong to stable collection identity, not a download attempt',
      () async {
    await store.setPinned('game:gba:one', true);
    expect(await store.isPinned('game:gba:one'), isTrue);
    expect(await store.isPinned('game:gba:other'), isFalse);
    expect(
        await RomCacheStore(Future.value(db)).isPinned('game:gba:one'), isTrue);
    await store.setPinned('game:gba:one', false);
    expect(await store.isPinned('game:gba:one'), isFalse);
  });
}
