import 'stat_tile.dart';

/// Back-compat wrapper — prefer [StatTile] for new code.
@Deprecated('Use StatTile instead')
class StatBox extends StatTile {
  const StatBox({
    super.key,
    required super.label,
    required super.value,
  });
}
