import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:g_shop/services/network_discovery_service.dart';

void main() {
  group('DiscoveredHost', () {
    test('equality is based on address+port+kind, not name', () {
      const a = DiscoveredHost(
        name: 'NAS',
        address: '192.168.1.10',
        port: 445,
        kind: DiscoveredKind.smb,
      );
      const b = DiscoveredHost(
        name: 'truenas',
        address: '192.168.1.10',
        port: 445,
        kind: DiscoveredKind.smb,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different ports are not equal', () {
      const a = DiscoveredHost(
        name: 'x',
        address: '10.0.0.1',
        port: 445,
        kind: DiscoveredKind.smb,
      );
      const b = DiscoveredHost(
        name: 'x',
        address: '10.0.0.1',
        port: 139,
        kind: DiscoveredKind.smb,
      );
      expect(a, isNot(equals(b)));
    });

    test('different kinds are not equal', () {
      const a = DiscoveredHost(
        name: 'x',
        address: '10.0.0.1',
        port: 80,
        kind: DiscoveredKind.http,
      );
      const b = DiscoveredHost(
        name: 'x',
        address: '10.0.0.1',
        port: 80,
        kind: DiscoveredKind.romm,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('NetworkDiscoveryService', () {
    test('unsupported multicast is nonfatal and stops its client', () async {
      final client = _UnsupportedMulticastClient();
      final results =
          await NetworkDiscoveryService(client: client).discover().toList();
      expect(results, isEmpty);
      expect(client.stopped, isTrue);
    });

    test('completes without crashing on a network without mDNS responders',
        () async {
      // This opens real LAN sockets; run explicitly with --tags live.
      final service = NetworkDiscoveryService();
      final results = await service
          .discover(timeout: const Duration(milliseconds: 500))
          .toList();
      expect(results, isA<List<DiscoveredHost>>());
    }, tags: ['live']);
  });
}

class _UnsupportedMulticastClient extends MDnsClient {
  bool stopped = false;

  @override
  Future<void> start(
      {InternetAddress? listenAddress,
      InternetAddress? mDnsAddress,
      int mDnsPort = 5353,
      NetworkInterfacesFactory? interfacesFactory,
      Function? onError}) async {
    throw const OSError('Unsupported multicast socket option', 10042);
  }

  @override
  void stop() {
    stopped = true;
  }
}
