import 'package:flutter/material.dart';
import '../../../models/system_model.dart';

/// Original transparent PNG marks, kept separate from system/platform artwork.
const manufacturerLogos = <String, String>{
  'Nintendo': 'publisher_nintendo', 'Sony': 'publisher_sony',
  'Sega': 'publisher_sega', 'Atari': 'publisher_atari',
  'Microsoft': 'publisher_microsoft', 'NEC': 'publisher_nec',
  'SNK': 'publisher_snk', 'Bandai': 'publisher_bandai_tall',
  'Coleco': 'publisher_coleco', 'Mattel': 'publisher_mattel_electronics',
  'Amstrad': 'publisher_amstrad', 'Fairchild': 'publisher_fairchild',
  'Magnavox': 'publisher_magnavox', 'Commodore': 'publisher_commodore',
  'Sinclair': 'publisher_sinclair', 'Sharp': 'publisher_sharp',
  'Fujitsu': 'publisher_fujitsu', 'Philips': 'publisher_philips',
  '3DO Company': '3do', 'Apple': 'publisher_apple_alt',
  'Nokia': 'publisher_nokia', 'Emerson': 'publisher_emerson',
  // These groups use the source's actual platform/category marks, not invented
  // corporate logos; their accessible labels retain the registry manufacturer.
  'GCE': 'vectrex', 'Tangerine': 'oric', 'Various': 'arcade',
  'Nesbox': 'tic-80', 'Lexaloffle': 'pico-8',
};

List<SystemModel> systemsForManufacturer(
        List<SystemModel> systems, String? brand) =>
    brand == null
        ? List.of(systems)
        : systems.where((s) => s.manufacturer == brand).toList();

class ManufacturerFilter extends StatelessWidget {
  final List<SystemModel> systems;
  final String? selected;
  final ValueChanged<String?> onSelected;
  const ManufacturerFilter(
      {super.key,
      required this.systems,
      required this.selected,
      required this.onSelected});

  Widget _button(String? brand) {
    final active = selected == brand;
    return Semantics(
      label: brand ?? 'All manufacturers',
      selected: active,
      button: true,
      child: Tooltip(
        message: brand ?? 'All manufacturers',
        child: TextButton(
          key: ValueKey('brand-${brand ?? 'All'}'),
          onPressed: () => onSelected(brand),
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16)),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            backgroundColor: WidgetStatePropertyAll(
                active ? const Color(0xFFB71C1C) : Colors.black54),
            side: WidgetStateProperty.resolveWith((states) => BorderSide(
                width: states.contains(WidgetState.focused) ? 2 : 1,
                color: states.contains(WidgetState.focused)
                    ? Colors.white
                    : active
                        ? Colors.redAccent
                        : Colors.white24)),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
          ),
          child: brand == null
              ? const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.apps, size: 20),
                  SizedBox(width: 6),
                  Text('All')
                ])
              : Image.asset(
                  'assets/brand_logos/${manufacturerLogos[brand]}.png',
                  width: 98,
                  height: 30,
                  fit: BoxFit.contain,
                  color: Colors.white,
                  semanticLabel: brand),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brands = systems.map((s) => s.manufacturer).toSet().toList()..sort();
    return SizedBox(
      key: const ValueKey('manufacturer-filter'),
      height: 56,
      child: FocusTraversalGroup(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            _button(null),
            const SizedBox(width: 8),
            Expanded(
                child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: brands.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) => _button(brands[index]),
            )),
          ]),
        ),
      ),
    );
  }
}
