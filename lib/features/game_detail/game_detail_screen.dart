import 'dart:ui' as ui;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../settings/metadata_settings_screen.dart';
import '../settings/save_backup_settings_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/input/input.dart';
import '../../l10n/app_localizations.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../models/download_item.dart';
import '../../models/game_item.dart';
import '../../models/console_model.dart';
import '../../models/nes_launch_scene.dart';
import '../../models/scene_launch_presentation.dart';
import '../../models/socket_media_model.dart';
import '../preview/nes_launch_preview.dart';
import '../preview/scene_idle_hints.dart';
import '../preview/dual_screen_preview_host.dart' show previewRouteObserver;
import 'widgets/game_scene_information.dart';
import '../../models/config/provider_config.dart';
import '../../models/game_metadata_info.dart';
import '../../models/system_model.dart';
import '../../models/retroarch_battery_route.dart';
import '../../models/ra_models.dart';
import '../../providers/app_providers.dart';
import '../../providers/download_providers.dart';
import '../../providers/ra_providers.dart';
import '../../providers/rom_status_providers.dart';
import '../../providers/game_providers.dart';
import '../../providers/metadata_cloud_providers.dart';
import '../../providers/preview_providers.dart';
import '../../providers/shelf_providers.dart';
import '../../services/download_queue_manager.dart';
import '../../services/input_debouncer.dart';
import '../../services/library_store.dart';
import '../../providers/library_providers.dart';
import '../../services/metadata/metadata_artwork_cache.dart';
import '../../services/metadata/preview_video_cache.dart';
import '../../services/owned_emulator_launcher.dart';
import '../../utils/game_metadata.dart';
import '../../utils/rom_share_helper.dart';
import '../../utils/image_helper.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/console_notification.dart';
import '../../widgets/console_hud.dart';
import '../../widgets/download_overlay.dart';
import '../../widgets/quick_menu.dart';
import '../../widgets/physical_media_view.dart';
import '../library/widgets/shelf_picker_dialog.dart';
import 'achievements_screen.dart';
import 'game_detail_controller.dart';
import 'open_managed_game.dart';
import 'patch_launch_selection.dart';
import 'game_detail_state.dart';
import 'widgets/cover_section.dart';
import 'widgets/ra_info_section.dart';
import 'widgets/action_buttons_row.dart';
import 'widgets/badges_row.dart';
import 'widgets/details_section.dart';
import 'widgets/download_action_button.dart';
import 'widgets/file_details_row.dart';
import 'widgets/game_detail_overlay.dart';
import 'widgets/other_versions_section.dart';
import 'widgets/screenshot_fullscreen.dart';
import 'widgets/screenshots_carousel.dart';
import 'widgets/section_header.dart';
import 'widgets/summary_section.dart';
import 'widgets/variant_picker_overlay.dart';
import 'widgets/drive_recovery_review_dialog.dart';
import 'widgets/companion_picker_dialog.dart';

class GameDetailScreen extends ConsumerStatefulWidget {
  final GameItem game;
  final List<GameItem> variants;
  final SystemModel system;
  final String targetFolder;
  final bool isLocalOnly;
  final bool autoExtract;

  const GameDetailScreen({
    super.key,
    required this.game,
    required this.variants,
    required this.system,
    required this.targetFolder,
    this.isLocalOnly = false,
    this.autoExtract = false,
  });

  @override
  ConsumerState<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends ConsumerState<GameDetailScreen>
    with ConsoleScreenMixin, WidgetsBindingObserver, RouteAware {
  double get _galleryVolume {
    final audio = ref.watch(soundSettingsProvider);
    return audio.enabled && ref.watch(previewSettingsProvider).sound
        ? audio.bgmVolume.clamp(0.0, 1.0)
        : 0.0;
  }

  GameDetailController? _controller;
  late InputDebouncer _debouncer;
  final _emulatorLauncher = OwnedEmulatorLauncher();
  final _physicalMediaKey = GlobalKey<PhysicalMediaViewState>();
  final _coverSectionKey = GlobalKey<CoverSectionState>();
  bool _openingOwnedRom = false;
  bool _sceneInformation = false;
  final _sceneLaunch = SceneLaunchPresentation();
  NesLaunchScene? _nesLaunchScene;
  SocketMediaPose? _nesInitialPose;
  Widget? _nesLaunchLabel;
  Object? _nesLaunchLabelIdentity;
  PhysicalMediaViewState? _launchHeldMedia;
  String? _sceneSelection;
  ModalRoute<void>? _sceneRoute;
  bool get _sceneView =>
      ref.read(mediaPresentationProvider).enabled && widget.system.id == 'nes';

  void _sceneChanged() {
    debugPrint('GShopSceneLaunch ${jsonEncode({
          'token': _sceneLaunch.token,
          'phase': _sceneLaunch.phase.name,
          'console': _sceneLaunch.consoleId,
          'view': 'ordinary',
          'skip': _sceneLaunch.skipRequested,
          'visualAvailable': _sceneLaunch.visualAvailable,
        })}');
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_sceneRoute != route) {
      previewRouteObserver.unsubscribe(this);
      _sceneRoute = route;
      if (route != null) previewRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() => _sceneLaunch.cancel();

  void _clearSceneLaunch() {
    if (_launchHeldMedia?.mounted == true)
      _launchHeldMedia!.releaseLaunchHold();
    _launchHeldMedia = null;
    _nesLaunchScene = null;
    _nesInitialPose = null;
    _nesLaunchLabel = null;
    _nesLaunchLabelIdentity = null;
  }

  @override
  void toggleQuickMenu() {
    if (_sceneLaunch.phase == SceneLaunchPhase.committing) return;
    _sceneLaunch.cancel();
    super.toggleQuickMenu();
  }

  ProviderSubscription? _romChangeSubscription;

  // Section scroll keys for auto-scroll on D-pad navigation
  final Map<DetailSection, GlobalKey> _sectionKeys = {};

  @override
  String get routeId => 'game_detail_${widget.game.filename}';

  bool _dialogOrNoOverlay(dynamic _) {
    final priority = ref.read(overlayPriorityProvider);
    if (priority == OverlayPriority.none) return true;
    final state = _controller?.state;
    return state?.isDialogOpen == true || state?.showVariantPicker == true;
  }

  @override
  Map<Type, Action<Intent>> get screenActions => {
        BackIntent: CallbackAction<BackIntent>(
          onInvoke: (_) {
            _handleBack();
            return null;
          },
        ),
        ConfirmIntent: OverlayGuardedAction<ConfirmIntent>(
          ref,
          onInvoke: (_) {
            _handleConfirm();
            return null;
          },
          isEnabledOverride: _dialogOrNoOverlay,
        ),
        NavigateIntent: OverlayGuardedAction<NavigateIntent>(
          ref,
          onInvoke: (intent) {
            _handleNavigate(intent.direction);
            return null;
          },
          isEnabledOverride: _dialogOrNoOverlay,
        ),
        FavoriteIntent: OverlayGuardedAction<FavoriteIntent>(
          ref,
          onInvoke: (_) {
            _handleFavorite();
            return null;
          },
        ),
        ToggleOverlayIntent:
            ToggleOverlayAction(ref, onToggle: toggleQuickMenu),
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sceneLaunch.addListener(_sceneChanged);
    _debouncer = ref.read(inputDebouncerProvider);
    final queueManager = ref.read(downloadQueueManagerProvider);
    _initController(queueManager);
  }

  void _initController(DownloadQueueManager queueManager) {
    final storage = ref.read(storageServiceProvider);
    _controller = GameDetailController(
      game: widget.game,
      variants: widget.variants,
      system: widget.system,
      targetFolder: widget.targetFolder,
      isLocalOnly: widget.isLocalOnly,
      autoExtract: widget.autoExtract,
      showFullFilename: storage.getShowFullFilename(),
      queueManager: queueManager,
      onAddedToQueue: _fireAddToQueueAnimation,
    );
    _controller!.onOpenLocal = _openOwnedRom;
    _controller!.addListener(_onControllerChanged);

    _romChangeSubscription =
        ref.listenManual(romChangeSignalProvider, (prev, next) {
      if (!mounted) return;
      if (prev != null && prev != next) {
        _controller?.checkInstallationStatus();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestScreenFocus();
    });
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final identity = _controller?.selectedVariant.selectionKey;
    if (_sceneSelection != identity) {
      _sceneLaunch.cancel();
      _clearSceneLaunch();
      _sceneInformation = false;
      _sceneSelection = identity;
    }

    setState(() {});

    final error = _controller?.state.error;
    if (error != null) {
      showErrorNotification(context, ref,
          message: L.of(context).gameDetail_errorPrefix(error));
    }
  }

  @override
  void dispose() {
    previewRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _clearSceneLaunch();
    _sceneLaunch.removeListener(_sceneChanged);
    _sceneLaunch.dispose();
    _romChangeSubscription?.close();
    _debouncer.stopHold();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  GlobalKey _keyForSection(DetailSection section) {
    return _sectionKeys.putIfAbsent(section, () => GlobalKey());
  }

  void _scrollToFocusedSection({bool scrollingUp = false}) {
    final controller = _controller;
    if (controller == null) return;
    final section = controller.focusedSection;
    final key = _sectionKeys[section];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    // Use alignment to position the section with breathing room above the HUD.
    // 0.0 = top of viewport, 1.0 = bottom. 0.7 keeps it comfortably visible.
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: scrollingUp ? 0.2 : 0.7,
    );
  }

  // ---------------------------------------------------------------------------
  // Input handling
  // ---------------------------------------------------------------------------

  void _handleBack() {
    if (_sceneLaunch.cancel()) return;
    if (_sceneLaunch.phase == SceneLaunchPhase.committing) return;
    if (_sceneInformation) {
      setState(() => _sceneInformation = false);
      return;
    }
    if (_sceneView &&
        _physicalMediaKey.currentState?.closeInspection() == true) {
      return;
    }
    final controller = _controller;
    if (controller == null) return;

    ref.read(feedbackServiceProvider).cancel();

    if (controller.state.isOverlayOpen) {
      controller.closeOverlay();
      return;
    }

    Navigator.pop(context);
  }

  void _handleConfirm() {
    final controller = _controller;
    if (controller == null) return;

    // Variant picker handles its own A-button input
    if (controller.state.showVariantPicker) return;

    if (controller.state.isDialogOpen) {
      final selection = controller.state.dialogSelection;
      if (selection == 0) {
        ref.read(feedbackServiceProvider).warning();
      } else {
        ref.read(feedbackServiceProvider).cancel();
      }
      _executeDialogAction(controller).then((_) {
        if (mounted) requestScreenFocus();
      });
      return;
    }

    if (_sceneView) {
      if (_sceneLaunch.canInterrupt) {
        _sceneLaunch.confirm();
      } else if (controller.canOpenSelected) {
        unawaited(_openOwnedRom());
      } else {
        controller.performAction();
      }
      return;
    }

    if (controller.state.showGameInfo) {
      return;
    }

    // Context-sensitive A-button per focused section
    ref.read(feedbackServiceProvider).confirm();
    final section = controller.focusedSection;
    switch (section) {
      case DetailSection.summary:
        controller.toggleSummaryExpanded();
      case DetailSection.screenshots:
        controller.openScreenshotViewer();
      case DetailSection.otherVersions:
        // Only select if index points to a real variant (not an unmatched sibling)
        final idx = controller.state.siblingIndex;
        if (idx < controller.variants.length) {
          controller.selectVariant(idx);
        }
      case DetailSection.primaryAction:
        controller.performAction();
      case DetailSection.actions:
        _handleActionButtonConfirm(controller);
      case DetailSection.achievements:
        _tryNavigateToAchievements();
      case DetailSection.title:
      case DetailSection.badges:
      case DetailSection.fileDetails:
      case DetailSection.details:
        break; // Non-actionable sections
    }
  }

  void _handleNavigate(GridDirection direction) {
    final controller = _controller;
    if (controller == null) return;

    if (controller.state.isDialogOpen) {
      if (direction == GridDirection.left) {
        ref.read(feedbackServiceProvider).tick();
        controller.selectDialogOption(1);
      } else if (direction == GridDirection.right) {
        ref.read(feedbackServiceProvider).tick();
        controller.selectDialogOption(0);
      }
      return;
    }

    final rs = context.rs;
    final isLandscape = !rs.isPortrait;

    // Up/down within left column (primaryAction ↔ actions)
    if (isLandscape &&
        (direction == GridDirection.up || direction == GridDirection.down) &&
        controller.navigateLeftColumn(direction)) {
      ref.read(feedbackServiceProvider).tick();
      return;
    }

    // Up/down: navigate between sections (skips left-column in landscape)
    if (direction == GridDirection.up) {
      ref.read(feedbackServiceProvider).tick();
      controller.focusPreviousSection();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToFocusedSection(scrollingUp: true);
      });
      return;
    }
    if (direction == GridDirection.down) {
      ref.read(feedbackServiceProvider).tick();
      controller.focusNextSection();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToFocusedSection();
      });
      return;
    }

    // Left/right: navigate within horizontal sections first
    if (controller.navigateInSection(direction)) {
      ref.read(feedbackServiceProvider).tick();
      return;
    }

    // Cross-column navigation (landscape only): LEFT → left column, RIGHT → back
    if (isLandscape && controller.navigateCrossColumn(direction)) {
      ref.read(feedbackServiceProvider).tick();
    }
  }

  /// Dispatches A-button press per focused icon button index.
  /// 0 = favorite, 1 = share, 2 = collection
  void _handleActionButtonConfirm(GameDetailController controller) {
    switch (controller.state.actionButtonIndex) {
      case 0:
        _handleFavorite();
      case 1:
        _handleShare();
      case 2:
        _handleCollection(controller);
    }
  }

  Future<void> _handleShare() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.state.isOverlayOpen || controller.state.isSharing) return;

    if (!controller.canShareSelected) {
      showConsoleNotification(context,
          message: L.of(context).gameDetail_gameNotInstalled);
      ref.read(feedbackServiceProvider).cancel();
      return;
    }

    ref.read(feedbackServiceProvider).tick();
    controller.setSharing(true);

    try {
      final files = await RomShareHelper.prepareShareFiles(
        game: controller.selectedVariant,
        system: widget.system,
        targetFolder: widget.targetFolder,
      );

      if (!mounted) return;

      await Share.shareXFiles(
        files,
        subject: controller.cleanTitle,
      );
    } catch (e) {
      debugPrint('Share failed: $e');
      if (mounted) {
        showConsoleNotification(context,
            message: L.of(context).gameDetail_couldNotShare);
      }
    } finally {
      controller.setSharing(false);
      // Re-enter immersive mode after the share sheet closes
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _handleCollection(GameDetailController controller) {
    final variant = controller.selectedVariant;
    final allShelves = ref.read(customShelvesProvider);
    if (allShelves.isEmpty) return;
    final addable = allShelves
        .where((s) => !s.containsGame(
            variant.selectionKey, variant.displayName, widget.system.id))
        .toList();
    if (addable.isNotEmpty) {
      // Show shelves where the game can still be added
      showShelfPickerDialog(
        context: context,
        ref: ref,
        shelves: addable,
        onSelect: (shelfId) {
          ref
              .read(customShelvesProvider.notifier)
              .addGameToShelf(shelfId, variant.selectionKey);
        },
      );
    } else {
      // Game is in all shelves — offer removal
      final containingShelves = allShelves
          .where((s) => s.containsGame(
              variant.selectionKey, variant.displayName, widget.system.id))
          .toList();
      showShelfPickerDialog(
        context: context,
        ref: ref,
        shelves: containingShelves,
        title: L.of(context).gameDetail_removeFromShelfTitle,
        onSelect: (shelfId) {
          final shelf = containingShelves.firstWhere((s) => s.id == shelfId);
          final matchesFilter = shelf.filterRules.any(
            (r) => r.matches(variant.displayName, widget.system.id),
          );
          if (matchesFilter) {
            ref
                .read(customShelvesProvider.notifier)
                .excludeGameFromShelf(shelfId, variant.selectionKey);
          } else {
            ref
                .read(customShelvesProvider.notifier)
                .removeGameFromShelf(shelfId, variant.selectionKey);
          }
        },
      );
    }
  }

  void _handleFilenameToggle() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.state.isOverlayOpen) return;

    ref.read(feedbackServiceProvider).tick();
    controller.toggleFullFilename();
    ref.read(storageServiceProvider).setShowFullFilename(
          controller.state.showFullFilename,
        );
  }

  void _handleFavorite() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.state.isOverlayOpen) return;

    ref.read(feedbackServiceProvider).tick();
    ref
        .read(favoriteGamesProvider.notifier)
        .toggleFavorite(controller.selectedVariant.selectionKey);
  }

  void _tryNavigateToAchievements() {
    final raMatches =
        ref.read(raMatchesForSystemProvider(widget.system.id)).value ?? {};
    final raMatch = raMatches[_controller?.selectedVariant.raMatchKey];
    if (raMatch != null && raMatch.raGameId != null) {
      _navigateToAchievements(raMatch);
    }
  }

  void _navigateToAchievements(RaMatchResult match) {
    if (match.raGameId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AchievementsScreen(
          raGameId: match.raGameId!,
          raTitle: match.raTitle,
          imageIcon: match.imageIcon,
          accentColor: widget.system.accentColor,
        ),
      ),
    );
  }

  void _fireAddToQueueAnimation() {
    final controller = _controller;
    if (controller == null) return;
    ref.read(addToQueueEventProvider.notifier).state = AddToQueueEvent(
      gameTitle: controller.cleanTitle,
      accentColor: widget.system.accentColor,
      timestamp: DateTime.now(),
    );
  }

  void _downloadFromSource(AlternativeSource source) {
    final controller = _controller;
    if (controller == null) return;

    final variant = controller.selectedVariant;
    final modifiedGame = variant.copyWith(
      url: source.url,
      providerConfig: source.providerConfig,
    );

    final queueManager = ref.read(downloadQueueManagerProvider);
    final sizeBefore = queueManager.state.queue.length;
    queueManager.addToQueue(modifiedGame, widget.system, widget.targetFolder,
        autoExtract: widget.autoExtract);
    if (queueManager.state.queue.length > sizeBefore) {
      _fireAddToQueueAnimation();
    }
  }

  Future<void> _openOwnedRom({bool withoutCompanion = false}) async {
    if (_openingOwnedRom) {
      if (_sceneView) {
        _sceneLaunch.confirm();
      } else {
        _physicalMediaKey.currentState?.skipInsertion();
      }
      return;
    }
    final game = _controller?.selectedVariant;
    if (game == null) return;
    _openingOwnedRom = true;
    int? token;
    if (_sceneInformation) setState(() => _sceneInformation = false);
    var handedOff = false;
    try {
      final chosen = await choosePatchLaunch(
          ref, context, game, widget.system, widget.targetFolder);
      if (!mounted ||
          _controller?.selectedVariant.selectionKey != game.selectionKey) {
        throw PlatformException(code: 'cancelled');
      }
      token = _sceneView && widget.system.id == 'nes'
          ? _sceneLaunch.begin(
              identity: chosen.game.selectionKey, consoleId: null)
          : null;
      if (token != null) await _prepareNesLaunch(token);
      if (!mounted) return;
      await openManagedGame(ref, context, _emulatorLauncher, chosen.game,
          widget.system, chosen.target, withoutCompanion: withoutCompanion,
          beforeHandoff: () async {
        if (!mounted ||
            !isCurrentScreen ||
            _controller?.selectedVariant.selectionKey != game.selectionKey) {
          throw PlatformException(code: 'cancelled');
        }
        if (token != null) {
          if (!await _sceneLaunch.commitWhenPresented(token)) {
            throw PlatformException(code: 'cancelled');
          }
          return;
        }
        final media = _physicalMediaKey.currentState;
        if (media != null && !await media.playInsertion()) {
          throw PlatformException(code: 'cancelled');
        }
      });
      handedOff = true;
      if (token != null) _sceneLaunch.handedOff(token);
    } catch (error) {
      if (token != null) _sceneLaunch.failed(token);
      if (!mounted) return;
      final code =
          error is PlatformException ? error.code : 'installation_unavailable';
      final message = switch (code) {
        'cancelled' => 'Opening cancelled.',
        'save_conflict' ||
        'conflict_changed' =>
          'Choose which save to use in Save backups before opening this game.',
        'watch_unavailable' =>
          'Save monitoring could not start. Check the mapped folder in Save backups.',
        'stop_ppsspp_required' ||
        'stop_melon_required' ||
        'close_content_required' =>
          'Close the emulator safely, then finish the save restore in Save backups.',
        'source_changed' =>
          'The saved game mapping changed. Review it in Save backups.',
        'pending_restore' =>
          'Finish the pending save restore in Save backups before opening this game.',
        'save_restore_pending' =>
          'Finish the pending save restore in Save backups before opening this game.',
        'companion_missing' =>
          'Companion app is missing. Change it or open without companion.',
        'companion_unlaunchable' =>
          'Companion app cannot be launched. Change it or open without companion.',
        'companion_display_unavailable' =>
          'Two unambiguous displays are unavailable. Open without companion.',
        'companion_display_denied' ||
        'companion_launch_denied' =>
          'Android rejected companion display placement. Open without companion.',
        'emulator_launch_denied_after_companion' =>
          'Companion was opened, but Android rejected the emulator launch.',
        _ => 'Could not open verified ROM: $code',
      };
      if (code != 'cancelled' || !_sceneView) {
        showConsoleNotification(context, message: message);
      }
    } finally {
      _openingOwnedRom = false;
      if (_sceneLaunch.canInterrupt) _sceneLaunch.cancel();
      if (!handedOff) {
        _clearSceneLaunch();
        if (mounted) setState(() {});
      }
      // Android accepts startActivity before the emulator covers our surface.
      // Hold the inserted pose through that handoff; reset on actual return.
      if (!handedOff) _physicalMediaKey.currentState?.resetInsertion();
    }
  }

  Future<void> _prepareNesLaunch(int token) async {
    bool current() =>
        mounted &&
        isCurrentScreen &&
        _sceneLaunch.token == token &&
        _sceneLaunch.canInterrupt;
    try {
      final cover = _coverSectionKey.currentState;
      if (cover == null) {
        _sceneLaunch.unavailable(token);
        return;
      }
      if (!await cover.physicalMediaResolved || !current()) {
        throw PlatformException(code: 'cancelled');
      }
      final media = _physicalMediaKey.currentState;
      if (media?.widget.nesScene == null) {
        _sceneLaunch.unavailable(token);
        return;
      }
      final frame = await media!.renderReady;
      if (!current()) throw PlatformException(code: 'cancelled');
      if (frame['error'] != null || frame['frameRendered'] != true) {
        _sceneLaunch.unavailable(token);
        return;
      }
      final target =
          await NesLaunchScene.chooseConsole(media.widget.nesScene!.style);
      final display = await ConsoleModel.findNesLaunchDisplay();
      if (!current()) throw PlatformException(code: 'cancelled');
      if (target == null || display == null) {
        _sceneLaunch.unavailable(token);
        return;
      }
      _sceneLaunch.selectConsole(token, 'nes-${target.launchTarget}');
      if (!mounted || !media.mounted)
        throw PlatformException(code: 'cancelled');
      media.holdForLaunch();
      _launchHeldMedia = media;
      final box = media.context.findRenderObject() as RenderBox;
      setState(() {
        _nesInitialPose = media.pose;
        _nesLaunchLabel = media.widget.label;
        _nesLaunchLabelIdentity = media.widget.labelIdentity;
        _nesLaunchScene = NesLaunchScene(
            media.widget.nesScene!, target, display,
            initialViewport: box.localToGlobal(Offset.zero) & box.size);
      });
    } on FormatException {
      _sceneLaunch.unavailable(token);
    } on FileSystemException {
      _sceneLaunch.unavailable(token);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _sceneLaunch.cancel();
    } else if (_sceneLaunch.phase == SceneLaunchPhase.handedOff) {
      _clearSceneLaunch();
      _sceneLaunch.reset();
    }
  }

  Future<void> _chooseCompanion(String editionId) async {
    closeQuickMenu();
    const channel = MethodChannel('com.darkaxt.gshop/companions');
    final apps = channel.invokeListMethod<dynamic>('applications').then(
        (items) => (items ?? const [])
            .map((item) => Map<String, String>.from(item as Map))
            .toList());
    await showDialog<void>(
        context: context,
        builder: (_) => CompanionPickerDialog(
            storage: ref.read(storageServiceProvider),
            editionId: editionId,
            applications: apps));
    if (mounted) setState(() {});
  }

  Future<Map<String, List<String>>> _galleryResources(
      GameMetadataInfo? info) async {
    final edition = info?.editionId;
    if (edition == null) return {};
    final resources = await (await ref.read(cachedMetadataArtworkProvider))
        .galleryForEdition(edition, hydrate: true);
    final record = await LibraryStore(ref.read(libraryDbProvider).database)
        .metadata(edition, 'screenscraper');
    if (record != null) {
      for (final media
          in MetadataArtworkCache.displayMedia(record, includeVideo: true)
              .where((m) => {'video', 'video-normalized'}.contains(m.type))) {
        await ref.read(metadataCloudProvider.notifier).ready;
        final store = await ref.read(sharedMetadataStoreProvider);
        final path =
            store == null ? null : await PreviewVideoCache(store).find(media);
        if (path != null) resources[media.type] = [Uri.file(path).toString()];
      }
    }
    return resources;
  }

  List<QuickMenuItem?> _buildQuickMenuItems() {
    final controller = _controller;
    if (controller == null) return [];
    final variant = controller.selectedVariant;
    final metadata = GameMetadata.parse(variant.filename);
    final isFavorite =
        ref.read(favoriteGamesProvider).contains(variant.selectionKey);
    final hasDownloads = ref.read(hasQueueItemsProvider);
    final hasAlternatives = variant.alternativeSources.isNotEmpty;
    final richMetadata = ref
        .read(gameMetadataProvider(
          (filename: variant.selectionKey, systemSlug: widget.system.id),
        ))
        .valueOrNull;
    final hasDetails = richMetadata?.hasContent ?? false;
    final editionId = richMetadata?.editionId;
    final companion = editionId == null
        ? null
        : ref.read(storageServiceProvider).getCompanion(editionId);
    final raMatches =
        ref.read(raMatchesForSystemProvider(widget.system.id)).value ?? {};
    final raMatch = raMatches[variant.raMatchKey];
    return [
      QuickMenuItem(label: 'Display', icon: Icons.album_outlined, children: [
        QuickMenuItem(
            label: 'Resources',
            icon: Icons.view_in_ar,
            onSelect: () => _coverSectionKey.currentState?.openGallery()),
        QuickMenuItem(
            label: _coverSectionKey.currentState?.physical == true
                ? 'Cover view'
                : 'Media preview',
            icon: Icons.photo_outlined,
            onSelect: () => _coverSectionKey.currentState?.toggleView()),
        if (_coverSectionKey.currentState?.physical == true)
          QuickMenuItem(
              label: 'Reduced motion',
              icon: Icons.motion_photos_off_outlined,
              onSelect: () => _coverSectionKey.currentState?.toggleMotion()),
      ]),
      if (editionId != null &&
          (RetroArchBatteryRoute.forPlatform(widget.system.id) != null ||
              const {'psp', 'nds', 'psx'}.contains(widget.system.id)) &&
          variant.remoteArtifact != null)
        QuickMenuItem(
            label: L.of(context).saveBackup_title,
            icon: Icons.backup_outlined,
            onSelect: () {
              closeQuickMenu();
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => SaveBackupSettingsScreen(
                          editionId: editionId,
                          game: variant,
                          system: widget.system,
                          targetFolder: widget.targetFolder,
                          gameTitle: variant.displayName)));
            }),
      if (!variant.isFolder &&
          variant.remoteArtifact != null &&
          variant.providerConfig?.type == ProviderType.drive)
        QuickMenuItem(
            label: 'Compare with Google Drive',
            icon: Icons.fact_check_outlined,
            onSelect: () async {
              closeQuickMenu();
              await showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => DriveRecoveryReviewDialog(
                      platformId: widget.system.id,
                      config: variant.providerConfig!,
                      artifact: variant.remoteArtifact!,
                      supportedExtensions: widget.system.romExtensions
                          .where((extension) =>
                              !(widget.system.multiFileExtensions ?? const [])
                                  .contains(extension))
                          .toSet(),
                      destinationRoot: widget.targetFolder));
              if (mounted) await controller.checkInstallationStatus();
            }),
      if (controller.state.isVariantInstalled &&
          OwnedEmulatorLauncher.supports(variant, widget.system))
        QuickMenuItem(
            label:
                'Open in ${OwnedEmulatorLauncher.emulatorName(widget.system.id)}',
            icon: Icons.play_arrow_rounded,
            onSelect: _openOwnedRom),
      if (controller.state.isVariantInstalled &&
          companion != null &&
          OwnedEmulatorLauncher.supports(variant, widget.system))
        QuickMenuItem(
            label: 'Open without companion',
            icon: Icons.play_arrow_outlined,
            onSelect: () => _openOwnedRom(withoutCompanion: true)),
      if (editionId != null &&
          OwnedEmulatorLauncher.supports(variant, widget.system))
        QuickMenuItem(
            label: companion == null
                ? 'Set companion app'
                : 'Change / clear companion',
            icon: Icons.splitscreen_outlined,
            onSelect: () => _chooseCompanion(editionId)),
      if (controller.state.isVariantInstalled && controller.canRemoveSelected)
        QuickMenuItem(
            label: L.of(context).gameDetail_delete,
            icon: Icons.delete_outline_rounded,
            onSelect: () async {
              closeQuickMenu();
              await controller.showDeleteDialog();
            }),
      QuickMenuItem(
        label: isFavorite
            ? L.of(context).common_unfavorite
            : L.of(context).common_favorite,
        icon:
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        shortcutHint: '−',
        onSelect: _handleFavorite,
        highlight: isFavorite,
      ),
      if (metadata.allTags.isNotEmpty || hasDetails)
        QuickMenuItem(
          label: L.of(context).gameDetail_gameInfo,
          icon: Icons.info_outline_rounded,
          onSelect: () {
            if (_sceneView) {
              setState(() => _sceneInformation = true);
            } else {
              controller.openGameInfo();
            }
          },
        ),
      if (richMetadata?.cacheRowId != null)
        QuickMenuItem(
            label: L.of(context).metadata_setupTitle,
            icon: Icons.auto_stories_outlined,
            onSelect: () {
              closeQuickMenu();
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => MetadataSettingsScreen(
                          systemSlug: widget.system.id,
                          cacheRowId: richMetadata!.cacheRowId,
                          editionId: richMetadata.editionId,
                          gameTitle: variant.displayName)));
            }),
      if (raMatch != null && raMatch.hasMatch && raMatch.raGameId != null)
        QuickMenuItem(
          label: L.of(context).gameDetail_achievements,
          icon: Icons.emoji_events_rounded,
          onSelect: () => _navigateToAchievements(raMatch),
        ),
      QuickMenuItem(
        label: controller.state.showFullFilename
            ? L.of(context).gameDetail_showTitle
            : L.of(context).gameDetail_showFilename,
        icon: Icons.text_fields_rounded,
        onSelect: _handleFilenameToggle,
      ),
      if (hasAlternatives && !controller.state.isVariantInstalled) ...[
        null,
        QuickMenuItem(
          label: L.of(context).gameDetail_fromProvider(
              variant.providerConfig?.detailLabel ?? 'Primary'),
          icon: Icons.cloud_download_outlined,
          onSelect: () => controller.performAction(),
        ),
        for (final alt in variant.alternativeSources)
          QuickMenuItem(
            label: L
                .of(context)
                .gameDetail_fromProvider(alt.providerConfig.detailLabel),
            icon: Icons.cloud_download_outlined,
            onSelect: () => _downloadFromSource(alt),
          ),
      ],
      if (ref.read(customShelvesProvider).isNotEmpty) ...[
        null,
        () {
          final allShelves = ref.read(customShelvesProvider);
          final addable = allShelves
              .where((s) => !s.containsGame(
                  variant.selectionKey, variant.displayName, widget.system.id))
              .toList();
          if (addable.isNotEmpty) {
            return QuickMenuItem(
              label: L.of(context).gameDetail_addToShelf,
              icon: Icons.shelves,
              onSelect: () {
                showShelfPickerDialog(
                  context: context,
                  ref: ref,
                  shelves: addable,
                  onSelect: (shelfId) {
                    ref
                        .read(customShelvesProvider.notifier)
                        .addGameToShelf(shelfId, variant.selectionKey);
                  },
                );
              },
            );
          } else {
            final containing = allShelves
                .where((s) => s.containsGame(variant.selectionKey,
                    variant.displayName, widget.system.id))
                .toList();
            return QuickMenuItem(
              label: L.of(context).gameDetail_removeFromShelf,
              icon: Icons.shelves,
              onSelect: () {
                showShelfPickerDialog(
                  context: context,
                  ref: ref,
                  shelves: containing,
                  title: L.of(context).gameDetail_removeFromShelfTitle,
                  onSelect: (shelfId) {
                    final shelf = containing.firstWhere((s) => s.id == shelfId);
                    final matchesFilter = shelf.filterRules.any(
                      (r) => r.matches(variant.displayName, widget.system.id),
                    );
                    if (matchesFilter) {
                      ref
                          .read(customShelvesProvider.notifier)
                          .excludeGameFromShelf(shelfId, variant.selectionKey);
                    } else {
                      ref
                          .read(customShelvesProvider.notifier)
                          .removeGameFromShelf(shelfId, variant.selectionKey);
                    }
                  },
                );
              },
            );
          }
        }(),
      ],
      if (hasDownloads) ...[
        null,
        QuickMenuItem(
          label: L.of(context).common_downloads,
          icon: Icons.download_rounded,
          onSelect: () => toggleDownloadOverlay(ref),
          highlight: true,
        ),
      ],
    ];
  }

  Future<void> _executeDialogAction(GameDetailController controller) async {
    final selection = controller.state.dialogSelection;

    if (selection == 0) {
      await controller.deleteRom();
      ref.read(romChangeSignalProvider.notifier).state++;
      ref.invalidate(visibleSystemsProvider);
      controller.cancelDialog();
    } else {
      controller.cancelDialog();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      _debouncer.stopHold();
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: DecoratedBox(
          decoration:
              const BoxDecoration(gradient: AppTheme.backgroundGradient),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: widget.system.accentColor),
                const SizedBox(height: 16),
                Text(
                  widget.game.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.system.name,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final rs = context.rs;
    final state = controller.state;
    final selectedVariant = controller.selectedVariant;
    final coverUrls = ImageHelper.getCoverUrlsForSingle(
        widget.system, selectedVariant.filename);
    final GameMetadataFull fileMetadata =
        GameMetadata.parse(selectedVariant.filename);
    final isMultiRom = widget.variants.length > 1;
    final isFavorite = ref
        .watch(favoriteGamesProvider)
        .contains(controller.selectedVariant.selectionKey);
    final raMatches =
        ref.watch(raMatchesForSystemProvider(widget.system.id)).value ?? {};
    final raMatch = raMatches[selectedVariant.raMatchKey];

    // Fetch rich metadata
    ref.watch(cloudSelectionMediaProvider((
      platform: widget.system.id,
      selection: selectedVariant.selectionKey,
      details: true
    )));
    final gameMetadata = ref.watch(gameMetadataProvider(
      (filename: selectedVariant.selectionKey, systemSlug: widget.system.id),
    ));
    final richMetadata =
        gameMetadata.isLoading ? null : gameMetadata.valueOrNull;

    // Update available sections based on current data
    controller.updateAvailableSections(
      metadata: richMetadata,
      fileMetadata: fileMetadata,
      raMatch: raMatch,
    );

    // In landscape, actions are in a separate left column — skip in up/down nav
    controller.skipActionsInVerticalNav = !rs.isPortrait;

    // Clamp horizontal indices
    final hasShelves = ref.watch(customShelvesProvider).isNotEmpty;
    final isShareable = controller.canShareSelected;
    final disabledButtons = <int>{
      if (!isShareable) 1, // Share button index
      if (!hasShelves) 2, // Collection button index
    };

    controller.clampHorizontalIndices(
      screenshotCount: richMetadata?.screenshotUrlList.length ?? 0,
      siblingCount: _getSiblingOrVariantCount(richMetadata, isMultiRom),
      actionButtonCount: ActionButtonsRow.itemCount,
      disabledActionButtons: disabledButtons,
    );

    return buildWithActions(
      PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _handleBack();
          }
        },
        child: Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          body: Stack(
            children: [
              Positioned.fill(
                child: _CoverBackground(
                  coverUrl: richMetadata?.cachedCover ??
                      selectedVariant.cachedCoverUrl ??
                      coverUrls.firstOrNull,
                ),
              ),
              SafeArea(
                bottom: false,
                child: Padding(
                  // Reserve space at the bottom so content never sits behind the HUD
                  padding: const EdgeInsets.only(bottom: 56),
                  child: Column(children: [
                    if (gameMetadata.isLoading)
                      Semantics(
                          label: L.of(context).metadata_cacheLoading,
                          child: const LinearProgressIndicator())
                    else if (gameMetadata.hasError)
                      Row(children: [
                        Expanded(
                            child: Text(L.of(context).metadata_cacheError,
                                style: const TextStyle(color: Colors.white70))),
                        TextButton(
                            onPressed: () => ref.invalidate(
                                    gameMetadataProvider((
                                  filename: selectedVariant.selectionKey,
                                  systemSlug: widget.system.id
                                ))),
                            child: Text(L.of(context).common_retry)),
                      ]),
                    Expanded(
                        child: _sceneView
                            ? _buildSceneLayout(
                                controller,
                                state,
                                selectedVariant,
                                fileMetadata,
                                richMetadata,
                                coverUrls,
                                isFavorite,
                                !gameMetadata.isLoading)
                            : rs.isPortrait
                                ? _buildPortraitLayout(
                                    rs,
                                    state,
                                    controller,
                                    fileMetadata,
                                    richMetadata,
                                    isMultiRom,
                                    coverUrls,
                                    selectedVariant,
                                    isFavorite,
                                    raMatch)
                                : _buildLandscapeLayout(
                                    rs,
                                    state,
                                    controller,
                                    fileMetadata,
                                    richMetadata,
                                    isMultiRom,
                                    coverUrls,
                                    selectedVariant,
                                    isFavorite,
                                    raMatch)),
                  ]),
                ),
              ),
              if (_nesLaunchScene != null && _sceneLaunch.pending)
                Positioned.fill(
                    child: NesLaunchPreview(
                        key: ValueKey('detail-launch:${_sceneLaunch.token}'),
                        token: _sceneLaunch.token!,
                        scene: _nesLaunchScene!,
                        initialPose: _nesInitialPose!,
                        label: _nesLaunchLabel!,
                        labelIdentity: _nesLaunchLabelIdentity,
                        title: selectedVariant.displayName,
                        phase: _sceneLaunch.phase,
                        skip: _sceneLaunch.skipRequested,
                        reducedMotion:
                            ref.watch(mediaPresentationProvider).reducedMotion,
                        onPrepared: (ready) => ready
                            ? _sceneLaunch.ready(_sceneLaunch.token!)
                            : _sceneLaunch.unavailable(_sceneLaunch.token!),
                        onFinished: () =>
                            _sceneLaunch.rendered(_sceneLaunch.token!),
                        onCancel: _sceneLaunch.cancel,
                        onSkip: _sceneLaunch.skip)),
              _buildControls(state, controller),
              if (showQuickMenu)
                QuickMenuOverlay(
                  items: _buildQuickMenuItems(),
                  onClose: closeQuickMenu,
                ),
              DialogFocusScope(
                isVisible: state.isDialogOpen,
                onClose: controller.cancelDialog,
                child: ConfirmDialog(
                  type: ConfirmDialogType.delete,
                  selection: state.dialogSelection,
                  gameTitle: controller.cleanTitle,
                  details: controller.removalPreview,
                  onPrimary: () async {
                    await controller.deleteRom();
                    ref.read(romChangeSignalProvider.notifier).state++;
                    ref.invalidate(visibleSystemsProvider);
                    controller.cancelDialog();
                    requestScreenFocus();
                  },
                  onSecondary: controller.cancelDialog,
                ),
              ),
              if (state.showGameInfo)
                OverlayFocusScope(
                  priority: OverlayPriority.dialog,
                  isVisible: state.showGameInfo,
                  onClose: controller.closeGameInfo,
                  child: Builder(
                    builder: (context) {
                      return GameDetailOverlay(
                        richMetadata: richMetadata,
                        fileMetadata: fileMetadata,
                        gameTitle: controller.cleanTitle,
                        accentColor: widget.system.accentColor,
                        onClose: controller.closeGameInfo,
                      );
                    },
                  ),
                ),
              if (state.showVariantPicker && isMultiRom)
                VariantPickerOverlay(
                  variants: widget.variants,
                  system: widget.system,
                  installedStatus: state.installedStatus,
                  isLocalOnly: widget.isLocalOnly,
                  onDownload: (index) async {
                    final success = await controller.addVariantToQueue(index);
                    if (success) _fireAddToQueueAnimation();
                    return success;
                  },
                  onDelete: (index) {
                    controller.selectVariant(index);
                    controller.closeVariantPicker();
                    if (controller.canOpenSelected) {
                      _openOwnedRom();
                    } else if (controller.canRemoveSelected) {
                      controller.showDeleteDialog();
                    }
                  },
                  onClose: () {
                    controller.closeVariantPicker();
                    requestScreenFocus();
                  },
                ),
              if (state.showScreenshotViewer &&
                  (richMetadata?.screenshotUrlList.isNotEmpty ?? false))
                ScreenshotFullscreen(
                  screenshots: richMetadata!.screenshotUrlList,
                  initialIndex: state.screenshotIndex,
                  accentColor: widget.system.accentColor,
                  onClose: () {
                    controller.closeScreenshotViewer();
                    requestScreenFocus();
                  },
                ),
            ],
          ),
        ),
      ),
      onKeyEvent: _handleKeyEvent,
    );
  }

  int _getSiblingOrVariantCount(
      GameMetadataInfo? richMetadata, bool isMultiRom) {
    return OtherVersionsSection.entryCount(
      variants: widget.variants,
      siblings: richMetadata?.siblingList ?? const [],
    );
  }

  // ---------------------------------------------------------------------------
  // Landscape layout: Cover + actions left (~30%), sections right (~70%)
  // ---------------------------------------------------------------------------

  Widget _buildSceneLayout(
          GameDetailController controller,
          GameDetailState state,
          GameItem game,
          GameMetadataFull fileMetadata,
          GameMetadataInfo? metadata,
          List<String> coverUrls,
          bool favorite,
          bool resourcesReady) =>
      SceneIdleHints(
          identity: game.selectionKey,
          hints: SceneIdleHints.forView(widget.system.id,
              canLaunch: controller.canOpenSelected),
          enabled: resourcesReady &&
              !_sceneInformation &&
              !_sceneLaunch.pending &&
              !_openingOwnedRom &&
              !state.isOverlayOpen,
          child: Stack(fit: StackFit.expand, children: [
            Padding(
                padding: const EdgeInsets.only(top: 64),
                child: IgnorePointer(
                    ignoring: _sceneInformation || _sceneLaunch.pending,
                    child: CoverSection(
                        key: _coverSectionKey,
                        game: game,
                        system: widget.system,
                        coverUrls: coverUrls,
                        metadata: fileMetadata,
                        isFavorite: favorite,
                        isInstalled: state.isVariantInstalled,
                        hasThumbnail: game.hasThumbnail,
                        physicalMediaKey: _physicalMediaKey,
                        physicalMediaEnabled: true,
                        gameInformationVisible: _sceneInformation,
                        showGameWatchVariants: true,
                        showPresentationControls: false,
                        scenePresentation: true,
                        reducedMotion:
                            ref.watch(mediaPresentationProvider).reducedMotion,
                        resourcesReady: resourcesReady,
                        physicalLabelUrl: metadata?.cachedSupportTexture,
                        gbcDualMode: metadata?.gbcDualMode,
                        contentTags: metadata?.contentTags ?? const [],
                        cachedUrl: metadata?.cachedCover ?? game.cachedCoverUrl,
                        packagingResources: metadata?.editionId == null
                            ? const {}
                            : ref
                                    .watch(editionGalleryMediaProvider(
                                        metadata!.editionId!))
                                    .valueOrNull ??
                                const {},
                        galleryResources: () => _galleryResources(metadata),
                        galleryVolume: _galleryVolume,
                        onGalleryPlaying:
                            ref.read(audioManagerProvider).setPreviewPlaying))),
            Positioned(
                top: 16,
                left: 72,
                right: 72,
                child: Text(game.displayName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: Theme.of(context).textTheme.titleLarge)),
            Positioned(
                top: 8,
                left: 16,
                child: IconButton.filledTonal(
                    tooltip: 'Game information',
                    onPressed: () {
                      _physicalMediaKey.currentState?.inspectCartridge();
                      setState(() => _sceneInformation = true);
                    },
                    icon: const Icon(Icons.info_outline))),
            Positioned(
                top: 8,
                right: 16,
                child: IconButton.filledTonal(
                    tooltip: controller.canOpenSelected ? 'Play' : 'Download',
                    onPressed: _openingOwnedRom
                        ? null
                        : () => controller.canOpenSelected
                            ? unawaited(_openOwnedRom())
                            : controller.performAction(),
                    icon: Icon(controller.canOpenSelected
                        ? Icons.play_arrow
                        : Icons.download))),
            if (_sceneInformation)
              GameSceneInformation(
                  title: game.displayName,
                  referenceNote:
                      'Box and cartridge models are reference editions. Physical releases can differ.',
                  summary: metadata?.summary,
                  genres: metadata?.genres,
                  credits: metadata?.creditsLine,
                  score: metadata?.overallRating == null
                      ? null
                      : '${metadata!.overallRating!.rating.sourceLabel} ${metadata.overallRating!.rating.normalizedValue.toStringAsFixed(1)}/100',
                  onClose: () => setState(() => _sceneInformation = false)),
          ]));

  Widget _buildLandscapeLayout(
    Responsive rs,
    GameDetailState state,
    GameDetailController controller,
    GameMetadataFull fileMetadata,
    GameMetadataInfo? richMetadata,
    bool isMultiRom,
    List<String> coverUrls,
    GameItem selectedVariant,
    bool isFavorite,
    RaMatchResult? raMatch,
  ) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        rs.spacing.lg,
        rs.spacing.md,
        rs.spacing.lg,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column: Cover + action buttons (wider when no metadata)
          SizedBox(
            width: richMetadata?.hasContent == true
                ? (rs.screenWidth * (rs.isSmall ? 0.28 : 0.22)).clamp(150, 280)
                : (rs.screenWidth * (rs.isSmall ? 0.35 : 0.30)).clamp(180, 340),
            child: Column(
              children: [
                // Cover takes available space, buttons anchor to bottom
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 0.75,
                          child: CoverSection(
                            key: _coverSectionKey,
                            galleryVolume: _galleryVolume,
                            packagingResources: richMetadata?.editionId == null
                                ? const {}
                                : ref
                                        .watch(editionGalleryMediaProvider(
                                            richMetadata!.editionId!))
                                        .valueOrNull ??
                                    const {},
                            galleryResources: () =>
                                _galleryResources(richMetadata),
                            onGalleryPlaying: ref
                                .read(audioManagerProvider)
                                .setPreviewPlaying,
                            game: selectedVariant,
                            physicalMediaKey: _physicalMediaKey,
                            physicalMediaEnabled:
                                ref.watch(mediaPresentationProvider).enabled,
                            reducedMotion: ref
                                .watch(mediaPresentationProvider)
                                .reducedMotion,
                            system: widget.system,
                            coverUrls: coverUrls,
                            physicalLabelUrl:
                                richMetadata?.cachedSupportTexture,
                            gbcDualMode: richMetadata?.gbcDualMode,
                            contentTags: richMetadata?.contentTags ?? const [],
                            cachedUrl: richMetadata?.cachedCover ??
                                selectedVariant.cachedCoverUrl,
                            metadata: fileMetadata,
                            isFavorite: isFavorite,
                            isInstalled: state.isVariantInstalled,
                            hasThumbnail: selectedVariant.hasThumbnail,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: rs.spacing.sm),
                // Action buttons always anchored at bottom of left column
                _buildSection(
                  rs,
                  state,
                  controller,
                  DetailSection.primaryAction,
                  fileMetadata: fileMetadata,
                  richMetadata: richMetadata,
                  isMultiRom: isMultiRom,
                  raMatch: raMatch,
                  isFocused:
                      controller.focusedSection == DetailSection.primaryAction,
                ),
                _buildSection(
                  rs,
                  state,
                  controller,
                  DetailSection.actions,
                  fileMetadata: fileMetadata,
                  richMetadata: richMetadata,
                  isMultiRom: isMultiRom,
                  raMatch: raMatch,
                  isFocused: controller.focusedSection == DetailSection.actions,
                ),
              ],
            ),
          ),
          SizedBox(width: rs.spacing.lg),
          // Right column: all other sections (scrollable)
          Expanded(
            child: SingleChildScrollView(
              child: _buildSections(rs, state, controller, fileMetadata,
                  richMetadata, isMultiRom, raMatch,
                  excludeActions: true),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Portrait layout: Cover header + scrollable sections
  // ---------------------------------------------------------------------------

  Widget _buildPortraitLayout(
    Responsive rs,
    GameDetailState state,
    GameDetailController controller,
    GameMetadataFull fileMetadata,
    GameMetadataInfo? richMetadata,
    bool isMultiRom,
    List<String> coverUrls,
    GameItem selectedVariant,
    bool isFavorite,
    RaMatchResult? raMatch,
  ) {
    final hasCardContent = richMetadata?.hasCardContent ?? false;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: rs.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: rs.spacing.md),
          AspectRatio(
            aspectRatio: hasCardContent ? 0.85 : 0.75,
            child: CoverSection(
              packagingResources: richMetadata?.editionId == null
                  ? const {}
                  : ref
                          .watch(editionGalleryMediaProvider(
                              richMetadata!.editionId!))
                          .valueOrNull ??
                      const {},
              key: _coverSectionKey,
              galleryVolume: _galleryVolume,
              galleryResources: () => _galleryResources(richMetadata),
              onGalleryPlaying:
                  ref.read(audioManagerProvider).setPreviewPlaying,
              game: selectedVariant,
              physicalMediaKey: _physicalMediaKey,
              physicalMediaEnabled:
                  ref.watch(mediaPresentationProvider).enabled,
              reducedMotion: ref.watch(mediaPresentationProvider).reducedMotion,
              system: widget.system,
              coverUrls: coverUrls,
              physicalLabelUrl: richMetadata?.cachedSupportTexture,
              gbcDualMode: richMetadata?.gbcDualMode,
              contentTags: richMetadata?.contentTags ?? const [],
              cachedUrl:
                  richMetadata?.cachedCover ?? selectedVariant.cachedCoverUrl,
              metadata: fileMetadata,
              isFavorite: isFavorite,
              isInstalled: state.isVariantInstalled,
              hasThumbnail: selectedVariant.hasThumbnail,
            ),
          ),
          SizedBox(height: rs.spacing.md),
          _buildSections(rs, state, controller, fileMetadata, richMetadata,
              isMultiRom, raMatch),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared section builder — renders all visible sections in order
  // ---------------------------------------------------------------------------

  Widget _buildSections(
    Responsive rs,
    GameDetailState state,
    GameDetailController controller,
    GameMetadataFull fileMetadata,
    GameMetadataInfo? richMetadata,
    bool isMultiRom,
    RaMatchResult? raMatch, {
    bool excludeActions = false,
  }) {
    const leftColumnSections = {
      DetailSection.primaryAction,
      DetailSection.actions,
    };
    final sections = controller.availableSections;
    final focused = controller.focusedSection;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final section in sections)
          if (!(excludeActions && leftColumnSections.contains(section)))
            _buildSection(
              rs,
              state,
              controller,
              section,
              fileMetadata: fileMetadata,
              richMetadata: richMetadata,
              isMultiRom: isMultiRom,
              raMatch: raMatch,
              isFocused: section == focused,
            ),
      ],
    );
  }

  Widget _buildSection(
    Responsive rs,
    GameDetailState state,
    GameDetailController controller,
    DetailSection section, {
    required GameMetadataFull fileMetadata,
    GameMetadataInfo? richMetadata,
    required bool isMultiRom,
    RaMatchResult? raMatch,
    required bool isFocused,
  }) {
    final Widget content;

    switch (section) {
      case DetailSection.title:
        content = _buildTitleSection(rs, controller);

      case DetailSection.badges:
        content = BadgesRow(
          metadata: richMetadata!,
          accentColor: widget.system.textAccentColor,
        );

      case DetailSection.fileDetails:
        content = FileDetailsRow(
          fileMetadata: fileMetadata,
          richMetadata: richMetadata,
        );

      case DetailSection.summary:
        content = SummarySection(
          metadata: richMetadata!,
          accentColor: widget.system.textAccentColor,
          isExpanded: state.summaryExpanded,
          onToggle: controller.toggleSummaryExpanded,
        );

      case DetailSection.primaryAction:
        content = _buildPrimaryActionSection(state, controller, isMultiRom,
            isFocused: isFocused);

      case DetailSection.actions:
        content =
            _buildIconButtonsSection(state, controller, isFocused: isFocused);

      case DetailSection.screenshots:
        content = ScreenshotsCarousel(
          screenshots: richMetadata!.screenshotUrlList,
          focusedIndex: state.screenshotIndex,
          isSectionFocused: isFocused,
          accentColor: widget.system.textAccentColor,
          onOpenViewer: controller.openScreenshotViewer,
        );

      case DetailSection.otherVersions:
        content = OtherVersionsSection(
          siblings: richMetadata?.siblingList ?? const [],
          variants: widget.variants,
          isMultiRom: isMultiRom,
          focusedIndex: state.siblingIndex,
          isSectionFocused: isFocused,
          installedStatus: state.installedStatus,
          accentColor: widget.system.textAccentColor,
        );

      case DetailSection.details:
        content = DetailsSection(
          fileMetadata: fileMetadata,
        );

      case DetailSection.achievements:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(label: L.of(context).gameDetail_achievements),
            RaInfoSection(
              match: raMatch!,
              filename: controller.selectedVariant.raMatchKey,
              systemSlug: widget.system.id,
              onViewAchievements: () => _navigateToAchievements(raMatch),
            ),
          ],
        );
    }

    return Container(
      key: _keyForSection(section),
      margin: EdgeInsets.only(bottom: rs.spacing.sm),
      decoration: isFocused
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(rs.radius.md),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.system.accentColor.withValues(alpha: 0.15),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            )
          : null,
      padding: EdgeInsets.all(rs.spacing.xs),
      child: content,
    );
  }

  // ---------------------------------------------------------------------------
  // HUD controls
  // ---------------------------------------------------------------------------

  Widget _buildControls(
      GameDetailState state, GameDetailController controller) {
    if (showQuickMenu) return const SizedBox.shrink();
    if (_sceneLaunch.pending) return const SizedBox.shrink();
    if (_sceneView) {
      return ConsoleHud(
          b: HudAction(L.of(context).common_back, onTap: _handleBack),
          a: HudAction(controller.canOpenSelected ? 'Play' : 'Download',
              onTap: _handleConfirm),
          select:
              HudAction(L.of(context).common_favorite, onTap: _handleFavorite),
          start: HudAction(L.of(context).common_menu, onTap: toggleQuickMenu));
    }

    final l = L.of(context);

    // Context-sensitive A-button hint per focused section
    String aHint;
    final section = controller.focusedSection;
    switch (section) {
      case DetailSection.summary:
        aHint = state.summaryExpanded ? 'Collapse' : 'Read More';
      case DetailSection.screenshots:
        aHint = 'View';
      case DetailSection.otherVersions:
        aHint = 'View';
      case DetailSection.primaryAction:
        aHint = l.common_select;
      case DetailSection.actions:
        // Show hint based on focused icon button
        switch (state.actionButtonIndex) {
          case 0:
            aHint = l.common_favorite;
          case 1:
            aHint = 'Share';
          case 2:
            aHint = l.gameDetail_addToShelf;
          default:
            aHint = l.common_select;
        }
      case DetailSection.achievements:
        aHint = 'View';
      case DetailSection.title:
      case DetailSection.badges:
      case DetailSection.fileDetails:
      case DetailSection.details:
        aHint = '';
    }

    // Show D-pad hint for horizontal sections
    final bool hasHorizontalNav = section == DetailSection.screenshots ||
        section == DetailSection.otherVersions ||
        section == DetailSection.actions;

    return ConsoleHud(
      b: HudAction(l.common_back, onTap: () => Navigator.pop(context)),
      a: aHint.isNotEmpty ? HudAction(aHint, onTap: _handleConfirm) : null,
      dpad: hasHorizontalNav ? (label: '', action: l.common_navigate) : null,
      select: HudAction(l.common_favorite, onTap: _handleFavorite),
      start: HudAction(l.common_menu, onTap: toggleQuickMenu),
    );
  }

  // ---------------------------------------------------------------------------
  // Section widgets
  // ---------------------------------------------------------------------------

  Widget _buildTitleSection(Responsive rs, GameDetailController controller) {
    final titleFontSize = rs.isSmall ? 20.0 : (rs.isMedium ? 24.0 : 28.0);
    final badgeFontSize = rs.isSmall ? 10.0 : 12.0;
    final manufacturerFontSize = rs.isSmall ? 8.0 : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          controller.displayTitle,
          style: TextStyle(
            color: controller.state.showFullFilename
                ? Colors.white.withValues(alpha: 0.85)
                : Colors.white,
            fontSize: controller.state.showFullFilename
                ? titleFontSize * 0.8
                : titleFontSize,
            fontWeight: FontWeight.bold,
            fontFamily: controller.state.showFullFilename ? 'monospace' : null,
            height: 1.1,
            shadows: const [
              Shadow(
                color: Colors.black54,
                blurRadius: 8,
              ),
            ],
          ),
          maxLines: controller.state.showFullFilename ? 3 : 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: rs.spacing.sm),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: rs.spacing.sm,
            vertical: rs.spacing.xs,
          ),
          decoration: BoxDecoration(
            color: widget.system.accentColor.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(rs.radius.sm),
            border: Border.all(
              color: widget.system.accentColor.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.system.name,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w600,
                    fontSize: badgeFontSize,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                margin: EdgeInsets.only(left: rs.spacing.sm),
                padding: EdgeInsets.symmetric(
                  horizontal: rs.spacing.xs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  widget.system.manufacturer,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: manufacturerFontSize,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryActionSection(
    GameDetailState state,
    GameDetailController controller,
    bool isMultiRom, {
    required bool isFocused,
  }) {
    final baseState = _getDownloadButtonState(state, isMultiRom);
    var buttonState = baseState;
    var progress = 0.0;

    // Check if any variant is actively downloading/queued.
    // For single-ROM: check the selected variant.
    // For multi-ROM: check all variants, pick the most "active" one.
    if (baseState == DownloadButtonState.download ||
        baseState == DownloadButtonState.open ||
        baseState == DownloadButtonState.delete) {
      final variantsToCheck =
          isMultiRom ? widget.variants : [controller.selectedVariant];

      for (final variant in variantsToCheck) {
        final gameId = DownloadQueueManager.idFor(variant, widget.system);
        final dlStatus = ref.watch(
          downloadStatusForGameProvider((gameId: gameId)),
        );
        if (dlStatus == null) continue;
        switch (dlStatus.status) {
          case DownloadStatus.downloading:
            buttonState = DownloadButtonState.downloading;
            progress = dlStatus.progress;
          case DownloadStatus.extracting:
          case DownloadStatus.moving:
          case DownloadStatus.verifying:
          case DownloadStatus.publishing:
            if (buttonState != DownloadButtonState.downloading) {
              buttonState = DownloadButtonState.extracting;
            }
          case DownloadStatus.queued:
          case DownloadStatus.paused:
          case DownloadStatus.awaitingAuthorization:
            if (buttonState != DownloadButtonState.downloading &&
                buttonState != DownloadButtonState.extracting) {
              buttonState = DownloadButtonState.queued;
            }
          case DownloadStatus.completed:
          case DownloadStatus.cancelled:
          case DownloadStatus.error:
            break;
        }
      }
    }

    return ActionButtonsRow.primaryOnly(
      accentColor: widget.system.textAccentColor,
      downloadButtonState: buttonState,
      downloadProgress: progress,
      variantCount: isMultiRom ? widget.variants.length : null,
      onPrimaryAction: controller.performAction,
      hintText: _getButtonHintText(state, isMultiRom),
      isSectionFocused: isFocused,
    );
  }

  Widget _buildIconButtonsSection(
    GameDetailState state,
    GameDetailController controller, {
    required bool isFocused,
  }) {
    final isFavorite = ref
        .watch(favoriteGamesProvider)
        .contains(controller.selectedVariant.selectionKey);

    final hasShelves = ref.watch(customShelvesProvider).isNotEmpty;
    final shareEnabled = controller.canShareSelected;

    return ActionButtonsRow.iconsOnly(
      accentColor: widget.system.textAccentColor,
      isFavorite: isFavorite,
      isShareEnabled: shareEnabled,
      isCollectionEnabled: hasShelves,
      focusedButtonIndex: state.actionButtonIndex,
      isSectionFocused: isFocused,
      onFavorite: _handleFavorite,
      onShare: _handleShare,
      onCollection: () => _handleCollection(controller),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  DownloadButtonState _getDownloadButtonState(
    GameDetailState state,
    bool isMultiRom,
  ) {
    if (state.isAddingToQueue) return DownloadButtonState.adding;
    if (isMultiRom) {
      final allInstalled =
          state.installedStatus.length == widget.variants.length &&
              state.installedStatus.values.every((v) => v);
      if (allInstalled) return DownloadButtonState.installed;
      final hasActionableVariant = widget.variants.asMap().entries.any(
          (entry) =>
              state.installedStatus[entry.key] == true ||
              (!widget.isLocalOnly && entry.value.hasDownloadSource));
      return hasActionableVariant
          ? DownloadButtonState.download
          : DownloadButtonState.unavailable;
    }
    if (state.isVariantInstalled) {
      return _controller!.canOpenSelected
          ? DownloadButtonState.open
          : _controller!.canRemoveSelected
              ? DownloadButtonState.delete
              : DownloadButtonState.unavailable;
    }
    return !widget.isLocalOnly &&
            widget.variants[state.selectedIndex].hasDownloadSource
        ? DownloadButtonState.download
        : DownloadButtonState.unavailable;
  }

  String _getButtonHintText(GameDetailState state, bool isMultiRom) {
    final l = L.of(context);
    if (state.isAddingToQueue) return '';
    if (isMultiRom) return l.gameDetail_pressAPickVersion;
    if (state.isVariantInstalled) {
      return _controller!.canOpenSelected
          ? l.gameDetail_pressAOpen
          : _controller!.canRemoveSelected
              ? l.gameDetail_pressAManage
              : '';
    }
    if (widget.isLocalOnly ||
        !widget.variants[state.selectedIndex].hasDownloadSource) {
      return '';
    }
    return l.gameDetail_pressADownload;
  }
}

/// Artwork remains subordinate to G-Shop's red/dark background identity.
class _CoverBackground extends StatelessWidget {
  final String? coverUrl;

  const _CoverBackground({
    required this.coverUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: AppTheme.backgroundGradient),
        ),
        if (coverUrl != null)
          Opacity(
            opacity: 0.12,
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Image(
                  image: ImageHelper.imageProvider(coverUrl!),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, __, ___) => const SizedBox.expand(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
