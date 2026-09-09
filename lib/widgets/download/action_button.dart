import 'package:flutter/material.dart';
import '../../core/responsive/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/config/provider_config.dart';
import '../../models/download_item.dart';

/// Action button (cancel / retry / dismiss)
class DownloadActionButton extends StatelessWidget {
  final DownloadItem item;
  final bool isHighlighted;
  final VoidCallback onTap;

  const DownloadActionButton({
    super.key,
    required this.item,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final (color, icon, label) = _getConfig(L.of(context));
    final buttonSize = rs.isSmall ? 34.0 : 40.0;

    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isHighlighted
                  ? color.withValues(alpha: 0.25)
                  : color.withValues(alpha: 0.1),
              border: Border.all(
                color: isHighlighted
                    ? color.withValues(alpha: 0.6)
                    : color.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              icon,
              color: isHighlighted ? color : color.withValues(alpha: 0.6),
              size: rs.isSmall ? 16 : 20,
            ),
          ),
        ),
      ),
    );
  }

  (Color, IconData, String) _getConfig(L l) {
    if (item.isComplete) {
      return (Colors.green, Icons.check_rounded, l.downloads_actionClear);
    } else if (item.isCancelled) {
      return (Colors.grey, Icons.close_rounded, l.downloads_actionClear);
    } else if (item.canResume) {
      return (Colors.amber, Icons.play_arrow_rounded, l.downloads_actionResume);
    } else if (item.isFailed) {
      return (Colors.red, Icons.refresh_rounded, l.downloads_actionRetry);
    } else if (item.isActive) {
      if (item.game.remoteArtifact != null ||
          item.game.providerConfig?.type == ProviderType.drive) {
        return (Colors.amber, Icons.pause_rounded, l.downloads_actionPause);
      }
      return (
        Colors.red.shade300,
        Icons.stop_rounded,
        l.downloads_actionCancel
      );
    } else {
      return (Colors.white38, Icons.close_rounded, l.downloads_actionRemove);
    }
  }
}
