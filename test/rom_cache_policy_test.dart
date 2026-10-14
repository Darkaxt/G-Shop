import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/rom_cache_policy.dart';

void main() {
  final now = DateTime.utc(2026, 10, 14);
  RomCacheEntry entry(String id, String console,
          {int bytes = 10,
          int age = 4,
          bool pinned = false,
          bool sample = false,
          bool busy = false,
          bool known = true,
          int? usedAge}) =>
      RomCacheEntry(
          id: id,
          platform: console,
          bytes: bytes,
          installedAt: known ? now.subtract(Duration(days: age)) : null,
          lastUsedAt:
              usedAge == null ? null : now.subtract(Duration(days: usedAge)),
          pinned: pinned,
          offlineSample: sample,
          block: busy ? 'in_use' : null);

  test(
      'expiry and capacity rotate whole games while pins and sample stay protected',
      () {
    final policy = RomCachePolicy(
        enabled: true,
        defaults: RomCacheLimits(
            keepFor: const Duration(days: 3), maxGames: 2, maxBytes: 25));
    final result = policy.plan([
      entry('sample', 'gba', bytes: 1000, sample: true),
      entry('pin', 'psp', bytes: 1000, pinned: true),
      entry('old', 'gba'),
      entry('new', 'gba', age: 1),
      entry('newer', 'psp', age: 0),
    ], now: now);
    expect(result.victims.map((v) => v.entry.id), ['old']);
    expect(result.victims.single.reasons, contains('expired'));
    expect(result.protectedBytes, 2000);
    expect(result.eligibleGames, 3);
    expect(result.remainingGames, 2);
  });

  test(
      'Never disables age only; capacity respects unified or per-console pools',
      () {
    final policy =
        RomCachePolicy(enabled: true, defaults: RomCacheLimits(maxGames: 1));
    final entries = [entry('a', 'gba'), entry('b', 'psp')];
    expect(
        policy.plan(entries, now: now).victims.map((v) => v.entry.id), ['a']);
    expect(
        policy
            .copyWith(scope: RomCacheScope.perConsole)
            .plan(entries, now: now)
            .victims,
        isEmpty);
    expect(policy.copyWith(enabled: false).plan(entries, now: now).victims,
        isEmpty);
  });

  test('LRU uses successful handoff, FIFO uses install and ties use identity',
      () {
    final entries = [
      entry('b', 'gba', age: 8, usedAge: 0),
      entry('a', 'gba', age: 2),
      entry('c', 'gba', age: 2)
    ];
    final policy =
        RomCachePolicy(enabled: true, defaults: RomCacheLimits(maxGames: 1));
    expect(policy.plan(entries, now: now).victims.map((v) => v.entry.id),
        ['a', 'c']);
    expect(
        policy
            .copyWith(order: RomCacheOrder.fifo)
            .plan(entries, now: now)
            .victims
            .map((v) => v.entry.id),
        ['b', 'a']);
  });

  test(
      'unknown usage, active work, and a backwards or untrusted clock preserve files',
      () {
    final policy = RomCachePolicy(
        enabled: true,
        defaults:
            RomCacheLimits(keepFor: const Duration(days: 1), maxGames: 0));
    final result = policy.plan([
      entry('unknown', 'gba', known: false),
      entry('active', 'gba', busy: true),
      entry('future', 'gba', age: -1)
    ], now: now);
    expect(result.victims, isEmpty);
    expect(result.blocked.map((e) => e.reason).toSet(),
        {'unknown_usage', 'in_use', 'clock_changed'});
    expect(result.unmetPools, contains('unified'));
    expect(
        policy
            .plan([entry('old', 'gba')], now: now, clockTrusted: false).victims,
        isEmpty);
  });

  test('exact expiry boundary and byte budget operate independently', () {
    final policy = RomCachePolicy(
        enabled: true,
        defaults:
            RomCacheLimits(keepFor: const Duration(days: 4), maxBytes: 15));
    final entries = [entry('a', 'gba'), entry('b', 'gba', age: 1)];
    expect(policy.plan(entries, now: now).victims.single.reasons,
        contains('expired'));
    expect(
        policy
            .plan(entries, now: now.subtract(const Duration(milliseconds: 1)))
            .victims
            .single
            .reasons,
        ['byte_limit']);
  });

  test(
      'console field overrides inherit, retain inactive modes and round-trip without secrets',
      () {
    final policy = RomCachePolicy.decode({
      'schema': 1,
      'enabled': true,
      'scope': 'perConsole',
      'order': 'lru',
      'defaults': {
        'keepMilliseconds': 2592000000,
        'maxGames': 10,
        'maxBytes': 1000
      },
      'consoles': {
        'psp': {'keepMilliseconds': null, 'maxGames': 2}
      },
    });
    expect(policy.limitsFor('psp').keepFor, isNull);
    expect(policy.limitsFor('psp').maxGames, 2);
    expect(policy.limitsFor('psp').maxBytes, 1000);
    expect(policy.limitsFor('gba').maxGames, 10);
    final unified = policy.copyWith(scope: RomCacheScope.unified);
    expect(unified.limitsFor('psp').maxGames, 10);
    expect(
        RomCachePolicy.decode(unified.toJson())
            .copyWith(scope: RomCacheScope.perConsole)
            .limitsFor('psp')
            .maxGames,
        2);
    expect(() => RomCachePolicy.decode({...policy.toJson(), 'token': 'secret'}),
        throwsFormatException);
    expect(() => RomCacheLimits(maxGames: -1), throwsArgumentError);
  });
}
