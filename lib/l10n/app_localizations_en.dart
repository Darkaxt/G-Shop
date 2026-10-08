// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get metadata_credentials => 'Credentials';

  @override
  String get metadata_scraping => 'Scraping';

  @override
  String get metadata_latestGame => 'Latest processed game';

  @override
  String get metadata_unverifiedCandidate => 'Unverified candidate';

  @override
  String get metadata_dailyQuota => 'Daily API quota';

  @override
  String get metadata_requestsRemaining => 'Remaining attempts';

  @override
  String get metadata_requestsUsed => 'Reported attempts used';

  @override
  String get metadata_failedRequestsRemaining =>
      'Failed-request attempts remaining';

  @override
  String get metadata_quotaObserved => 'Last provider report';

  @override
  String get metadata_localBudget => 'Locally reserved remaining budget';

  @override
  String get metadata_quotaUnknown => 'Unknown';

  @override
  String get metadata_esDe => 'ES-DE metadata publication';

  @override
  String get metadata_esDeReviewArtwork => 'Review and reuse existing artwork';

  @override
  String get metadata_esDeReviewArtworkHelp =>
      'Confirm this cover or screenshot belongs to this exact console and edition, including its region/revision/patch. Only its explicitly mapped ES-DE path is accepted. Existing artwork remains launcher-owned; old metadata is not imported as fresh evidence.';

  @override
  String get metadata_esDeHelp =>
      'Map this edition to the configured ROM destination, then select its ES-DE system gamelist folder. Updates are queued by normal refreshes. Close ES-DE and keep it closed during publication. Missing ROMs are not created or made launchable.';

  @override
  String get metadata_esDeMap => 'Map this edition to ES-DE';

  @override
  String get metadata_esDeRomRoot =>
      'Select the ES-DE ROM folder for this console';

  @override
  String get metadata_esDeMediaRoot =>
      'Select the ES-DE media folder for this console (not covers/screenshots)';

  @override
  String get metadata_esDeGamelist =>
      'Select the ES-DE gamelist folder for this console';

  @override
  String get metadata_esDeClosed =>
      'ES-DE is closed and will remain closed during publication';

  @override
  String get metadata_esDePublish => 'Publish pending metadata';

  @override
  String get metadata_esDePublished => 'Pending metadata published';

  @override
  String get metadata_esDeConflict =>
      'Publication paused: review changed paths, identities or manual fields. Pending updates and existing launcher data are preserved.';

  @override
  String get metadata_esDeNoMapping =>
      'Open a freshly matched edition\'s metadata settings to map it. Shared metadata storage is required.';

  @override
  String get metadata_sharedStorage => 'Persistent shared metadata';

  @override
  String get metadata_sharedUnavailable =>
      'Shared metadata storage is unavailable or could not be read. Reconnect storage and choose the same folder again. Cached facts remain usable; refresh and publication require restored access.';

  @override
  String get metadata_sharedStorageHelp =>
      'Choose a shared folder for scraped facts and artwork. Existing cache is copied, not deleted. This data survives uninstall; reconnect your source and reselect the folder to recover matching records. Credentials and installations are not backed up. ES-DE publication is configured separately.';

  @override
  String get metadata_privateStorage =>
      'Not selected — current cache is app-private';

  @override
  String get metadata_chooseSharedStorage => 'Choose / reconnect shared folder';

  @override
  String get metadata_artwork => 'Artwork';

  @override
  String get metadata_rediscover => 'Find another match';

  @override
  String get metadata_rediscoverHelp =>
      'Search for this exact game again without reusing its saved match. Existing facts stay cached until you select and verify a replacement. No ROM is downloaded.';

  @override
  String get metadata_reviewChanged =>
      'This file or identity changed. These saved candidates cannot be accepted; re-scrape the current edition.';

  @override
  String get metadata_openReview => 'Review cached matches';

  @override
  String get metadata_reviewTitle => 'Review cached matches';

  @override
  String get metadata_reviewInfo =>
      'Candidates are identity hints, not verified scores. Select the correct game/project and classify this edition explicitly. Tags may overlap; an official release cannot also be a modification. Confirming saves the correction and rechecks only this game. No ROM is downloaded.';

  @override
  String get metadata_chooseCandidate => 'Choose game / project identity';

  @override
  String get metadata_candidateEvidence => 'Candidate evidence';

  @override
  String get metadata_reviewAccept => 'Save match and recheck';

  @override
  String get metadata_reviewEmpty =>
      'No cached review outcomes on this page. Unmatched or pending games are not automatically rated.';

  @override
  String get metadata_noCandidates =>
      'No candidate was returned. Re-scrape after correcting the title/platform or checking provider access; no match will be guessed.';

  @override
  String get metadata_reviewReload => 'Reload cached reviews';

  @override
  String get metadata_reviewNext => 'Next page';

  @override
  String get metadata_reviewPrevious => 'Previous page';

  @override
  String get metadata_reviewSaved =>
      'Selection saved. Check the refreshed job\'s coverage: a saved match alone is not a verified rating.';

  @override
  String get metadata_reviewError =>
      'Review or recheck could not finish. The identity/candidate may have changed, or provider access may be unavailable. Reload cached reviews or resume the saved job; existing ROM actions remain available.';

  @override
  String get metadata_setupTitle => 'Game metadata';

  @override
  String get metadata_setupSubtitle =>
      'Provider access, fresh scraping and saved progress';

  @override
  String get metadata_provider => 'Metadata provider';

  @override
  String get metadata_accessInfo =>
      'ScreenScraper uses a standard account plus separate application access. IGDB uses a private application pair. Credentials are saved securely on this device, not in exported configuration. Saving is not proof of provider access; refresh checks access. No ROM files are downloaded.';

  @override
  String get metadata_saved => 'Saved on this device';

  @override
  String get metadata_notConfigured => 'Not configured';

  @override
  String get metadata_applicationAccess => 'Private application access';

  @override
  String get metadata_softwareName => 'Software name';

  @override
  String get metadata_clientId => 'Client ID';

  @override
  String get metadata_clientSecret => 'Client secret';

  @override
  String get metadata_fullScope => 'Entire collection';

  @override
  String get metadata_systemScope => 'Console';

  @override
  String get metadata_gameScope => 'Selected game';

  @override
  String get metadata_refresh => 'Fresh re-scrape';

  @override
  String get metadata_pause => 'Pause';

  @override
  String get metadata_resume => 'Resume saved job';

  @override
  String get metadata_savedJobs => 'Saved jobs';

  @override
  String get metadata_savedJobsHelp =>
      'Select existing progress. Resume uses this saved job, not the console chosen for a fresh re-scrape. Selection makes no provider requests.';

  @override
  String get metadata_noSavedJobs => 'No saved jobs on this page.';

  @override
  String get metadata_olderJobs => 'Older jobs';

  @override
  String get metadata_newestJobs => 'Newest jobs';

  @override
  String metadata_savedJobLabel(int id, String state, int requested) {
    return 'Job $id · $state · $requested lookups';
  }

  @override
  String get metadata_retryOutcomes => 'Retry failed / unmatched';

  @override
  String get metadata_jobQueued => 'Queued';

  @override
  String get metadata_jobRunning => 'Running';

  @override
  String get metadata_jobCompleted => 'Traversal completed';

  @override
  String get metadata_requested => 'Requested lookups';

  @override
  String get metadata_matched => 'Matched';

  @override
  String get metadata_review => 'Needs review';

  @override
  String get metadata_ambiguous => 'Ambiguous';

  @override
  String get metadata_unmatched => 'Unmatched';

  @override
  String get metadata_failed => 'Failed / unsupported';

  @override
  String get metadata_rated => 'Rated';

  @override
  String get metadata_pending => 'Pending';

  @override
  String get metadata_completeNote =>
      'Completed traversal does not mean every game has metadata or a reliable rating.';

  @override
  String get metadata_controlsError =>
      'Metadata operation failed. Saved progress and ROM actions remain available. Check access or resume the saved job.';

  @override
  String get metadata_configureAccess =>
      'Open this provider\'s Credentials to configure account/application access, then resume the saved job. A standard ScreenScraper account does not need to become a developer account.';

  @override
  String get metadata_quotaWait =>
      'Provider quota or cadence applies. Resume when access permits; completed items are retained.';

  @override
  String get metadata_offlineWait =>
      'Provider unavailable. Check connectivity and resume the saved job.';

  @override
  String get metadata_invalidInput =>
      'Complete all required fields. Leave application fields blank to keep existing access.';

  @override
  String get metadata_forget => 'Forget this provider\'s credentials';

  @override
  String get metadata_cacheLoading => 'Loading cached metadata…';

  @override
  String get metadata_cacheError =>
      'Cached metadata is unavailable. ROM actions remain available.';

  @override
  String get metadata_fieldSources => 'Field sources';

  @override
  String get metadata_description => 'Description';

  @override
  String get metadata_developer => 'Developer';

  @override
  String get metadata_publisher => 'Publisher';

  @override
  String get metadata_releaseDate => 'Release date';

  @override
  String get metadata_empty =>
      'No verified metadata is cached for this edition.';

  @override
  String get filter_oneLimit => 'One limit across the selected consoles';

  @override
  String get filter_scope => 'Console scope';

  @override
  String get filter_allScope => 'All consoles · one collection-wide limit';

  @override
  String get filter_noMatches => 'No games match these filters';

  @override
  String get filter_discoveryTitle => 'Best rated in my collection';

  @override
  String get filter_ratingOrder => 'Rating order';

  @override
  String get filter_anyTags => 'Match any tag';

  @override
  String get filter_allTags => 'Match all tags';

  @override
  String get filter_contentTags => 'Content tags';

  @override
  String get filter_genres => 'Genres';

  @override
  String get filter_allGames => 'All games';

  @override
  String get filter_provisional => 'Provisional';

  @override
  String filter_coverage(int ranked, int total, int matches) {
    return '$ranked/$total ranked · $matches matching games';
  }

  @override
  String get filter_basis =>
      'Ranking basis: IGDB community average (20+ ratings; assessed systems only)';

  @override
  String get filter_querying => 'Updating cached filters…';

  @override
  String filter_topLimit(int limit) {
    return 'Best $limit';
  }

  @override
  String get filter_official => 'Official releases';

  @override
  String get filter_unknown => 'Unknown classification';

  @override
  String get filter_homebrew => 'Homebrew';

  @override
  String get filter_demo => 'Demo';

  @override
  String get metadata_staleScore => 'Stale score';

  @override
  String get metadata_originalGame => 'Original game';

  @override
  String get metadata_projectScore => 'Project score';

  @override
  String get metadata_advisoryScore => 'Advisory';

  @override
  String get metadata_gameScore => 'Game score';

  @override
  String get metadata_unknownCount => 'Unknown';

  @override
  String get metadata_ratingOverlays => 'Cover ratings';

  @override
  String get metadata_ratingOverlaysSubtitle =>
      'Show cached, source-labelled ratings on game covers';

  @override
  String metadata_scoreDetails(String source, String score, String raw,
      String minimum, String maximum, String count, String date) {
    return '$source: $score/100. Original scale: $raw ($minimum–$maximum). $count ratings. Retrieved $date.';
  }

  @override
  String get appTitle => 'R-Shop';

  @override
  String get settings_language => 'Language';

  @override
  String get settings_languageSystem => 'System default';

  @override
  String get common_back => 'Back';

  @override
  String get common_close => 'Close';

  @override
  String get common_cancel => 'Cancel';

  @override
  String get common_cancelUpper => 'CANCEL';

  @override
  String get common_select => 'Select';

  @override
  String get common_search => 'Search';

  @override
  String get common_searchEllipsis => 'Search...';

  @override
  String get common_menu => 'Menu';

  @override
  String get common_navigate => 'Navigate';

  @override
  String get common_toggle => 'Toggle';

  @override
  String get common_clear => 'Clear';

  @override
  String get common_done => 'Done';

  @override
  String get common_save => 'Save';

  @override
  String get common_connect => 'Connect';

  @override
  String get common_retry => 'Retry';

  @override
  String get common_remove => 'Remove';

  @override
  String get common_favorite => 'Favorite';

  @override
  String get common_unfavorite => 'Unfavorite';

  @override
  String get common_downloads => 'Downloads';

  @override
  String get common_installed => 'INSTALLED';

  @override
  String get common_move => 'Move';

  @override
  String get common_drop => 'Drop';

  @override
  String get common_grab => 'Grab';

  @override
  String get confirm_deleteTitle => 'Delete ROM?';

  @override
  String confirm_deleteMessage(String gameTitle) {
    return 'Do you really want to delete this version of $gameTitle?';
  }

  @override
  String get confirm_exitTitle => 'Exit App?';

  @override
  String get confirm_exitMessage => 'Do you really want to exit Retro eShop?';

  @override
  String get confirm_resetTitle => 'Reset App?';

  @override
  String get confirm_resetMessage =>
      'This will return to the onboarding screen.';

  @override
  String get confirm_deleteButton => 'DELETE';

  @override
  String get confirm_exitButton => 'EXIT';

  @override
  String get confirm_resetButton => 'RESET';

  @override
  String get confirm_gamepadHint => '← → Select   A Confirm   B Cancel';

  @override
  String get exit_title => 'EXIT APPLICATION';

  @override
  String get exit_message => 'Are you sure you want to quit?';

  @override
  String get exit_confirmButton => 'EXIT';

  @override
  String get exit_cancelButton => 'STAY';

  @override
  String get downloads_title => 'Downloads';

  @override
  String downloads_activeCount(int count) {
    return '$count active';
  }

  @override
  String get downloads_noDownloads => 'No downloads';

  @override
  String get downloads_sectionDownloading => 'Downloading';

  @override
  String get downloads_sectionQueued => 'Queued';

  @override
  String get downloads_sectionPaused => 'Paused';

  @override
  String get downloads_sectionComplete => 'Complete';

  @override
  String get downloads_actionCancel => 'Cancel';

  @override
  String get downloads_actionPause => 'Pause';

  @override
  String get downloads_actionResume => 'Resume';

  @override
  String get downloads_moveEarlier => 'Move up';

  @override
  String get downloads_moveLater => 'Move down';

  @override
  String get downloads_actionRetry => 'Retry';

  @override
  String get downloads_actionRemove => 'Remove';

  @override
  String get downloads_actionClear => 'Clear';

  @override
  String get downloads_clearDone => 'Clear Done';

  @override
  String get downloadStatus_downloading => 'Downloading...';

  @override
  String get downloadStatus_extracting => 'Extracting...';

  @override
  String get downloadStatus_installing => 'Installing...';

  @override
  String get downloadStatus_waiting => 'Waiting...';

  @override
  String get downloadStatus_complete => 'Complete';

  @override
  String get downloadStatus_cancelled => 'Cancelled';

  @override
  String get downloadStatus_failed => 'Failed';

  @override
  String get downloadStatus_paused => 'Paused';

  @override
  String get downloadStatus_awaitingAuthorization => 'Reconnect in Sources';

  @override
  String get downloadStatus_verifying => 'Verifying...';

  @override
  String get downloadStatus_publishing => 'Finishing installation...';

  @override
  String storage_free(String size) {
    return '$size free';
  }

  @override
  String storage_veryLow(String freeSpace) {
    return 'Very low storage: $freeSpace';
  }

  @override
  String storage_gettingLow(String freeSpace) {
    return 'Storage getting low: $freeSpace';
  }

  @override
  String sync_progress(int completed, int total) {
    return 'Syncing $completed/$total';
  }

  @override
  String sync_singleSystemFailed(String system) {
    return '$system sync failed';
  }

  @override
  String sync_multipleSystemsFailed(int count) {
    return '$count systems failed to sync';
  }

  @override
  String sync_raProgress(int completed, int total) {
    return 'Achievements $completed/$total';
  }

  @override
  String get sync_raFailed => 'RA sync failed';

  @override
  String get toast_addedToQueue => 'Added to queue';

  @override
  String get toast_configRecovered => 'Config recovered from backup';

  @override
  String gameCard_variantCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count variants',
      one: '1 variant',
    );
    return '$_temp0';
  }

  @override
  String get gameDetail_achievements => 'Achievements';

  @override
  String get gameDetail_mastered => 'MASTERED';

  @override
  String get gameDetail_noAchievementsFound => 'No achievements found';

  @override
  String get gameDetail_retroachievements => 'RETROACHIEVEMENTS';

  @override
  String get gameDetail_romVerified => 'ROM Verified';

  @override
  String get gameDetail_incompatibleRom => 'Incompatible ROM';

  @override
  String get gameDetail_gameHasAchievements => 'Game Has Achievements';

  @override
  String get gameDetail_viewAchievements => 'View Achievements';

  @override
  String get gameDetail_versions => 'VERSIONS';

  @override
  String get gameDetail_download => 'DOWNLOAD';

  @override
  String get gameDetail_adding => 'ADDING...';

  @override
  String get gameDetail_queued => 'QUEUED';

  @override
  String get gameDetail_extracting => 'EXTRACTING...';

  @override
  String get gameDetail_delete => 'DELETE';

  @override
  String get gameDetail_manageFiles => 'MANAGE FILES';

  @override
  String get gameDetail_unavailable => 'UNAVAILABLE';

  @override
  String get gameDetail_installedLabel => 'Installed';

  @override
  String get gameDetail_notFound => 'Not found';

  @override
  String get gameDetail_details => 'Details';

  @override
  String get gameDetail_screenshots => 'Screenshots';

  @override
  String get gameDetail_otherVersions => 'Other Versions';

  @override
  String get gameDetail_readMore => 'Read more...';

  @override
  String get gameDetail_showLess => 'Show less';

  @override
  String get gameDetail_standard => 'Standard';

  @override
  String get gameDetail_franchise => 'Franchise';

  @override
  String get gameDetail_gameModes => 'Game Modes';

  @override
  String get gameDetail_perspective => 'Perspective';

  @override
  String get gameDetail_ageRating => 'Age Rating';

  @override
  String get gameDetail_themes => 'Themes';

  @override
  String get gameDetail_fileTags => 'FILE TAGS';

  @override
  String get gameDetail_tagVersion => 'Version';

  @override
  String get gameDetail_tagBuild => 'Build';

  @override
  String get gameDetail_tagDisc => 'Disc';

  @override
  String get gameDetail_tagQuality => 'Quality';

  @override
  String get gameDetail_tagInfo => 'Info';

  @override
  String get gameDetail_tagTechnical => 'Technical';

  @override
  String get gameDetail_gameInfo => 'Game Info';

  @override
  String get gameDetail_showTitle => 'Show Title';

  @override
  String get gameDetail_showFilename => 'Show Filename';

  @override
  String gameDetail_fromProvider(String provider) {
    return 'from $provider';
  }

  @override
  String get gameDetail_addToShelf => 'Add to Shelf';

  @override
  String get gameDetail_removeFromShelf => 'Remove from Shelf';

  @override
  String get gameDetail_removeFromShelfTitle => 'REMOVE FROM SHELF';

  @override
  String get gameDetail_gameNotInstalled => 'Game is not installed';

  @override
  String get gameDetail_couldNotShare => 'Could not share game file';

  @override
  String get gameDetail_pressAPickVersion => 'Press A to pick a version';

  @override
  String get gameDetail_pressAManage => 'Press A to manage';

  @override
  String get gameDetail_pressADownload => 'Press A to download';

  @override
  String gameDetail_errorPrefix(String error) {
    return 'Error: $error';
  }

  @override
  String get settings_title => 'SETTINGS';

  @override
  String get settings_tabGeneral => 'General';

  @override
  String get settings_tabAudio => 'Audio';

  @override
  String get settings_tabAdvanced => 'Advanced';

  @override
  String get settings_tabAbout => 'About';

  @override
  String get settings_previousTab => 'Previous Tab';

  @override
  String get settings_nextTab => 'Next Tab';

  @override
  String get settings_resetApp => 'Reset App';

  @override
  String get settings_resetDialogTitle => 'RESET APPLICATION';

  @override
  String get settings_resetDialogMessage =>
      'This will delete all settings and restart the setup.';

  @override
  String get settings_resetDialogConfirm => 'RESET';

  @override
  String get settings_resetDialogCancel => 'CANCEL';

  @override
  String get settings_sectionLibrary => 'Library';

  @override
  String get settings_sectionDisplay => 'Display';

  @override
  String get settings_mySources => 'My Sources';

  @override
  String get settings_mySourcesSubtitle =>
      'Add or manage RomM, SMB, FTP servers';

  @override
  String get settings_consoleSettings => 'Console Settings';

  @override
  String get settings_consoleSettingsSubtitle =>
      'Folder paths, extraction, per-system options';

  @override
  String get settings_retroAchievements => 'RetroAchievements';

  @override
  String get settings_retroAchievementsSubtitle =>
      'Achievement tracking and ROM verification';

  @override
  String get settings_homeLayout => 'Home Layout';

  @override
  String get settings_homeLayoutGrid => 'Grid View';

  @override
  String get settings_homeLayoutCarousel => 'Horizontal Carousel';

  @override
  String get settings_hideEmptyConsoles => 'Hide Empty Consoles';

  @override
  String get settings_hideEmptyConsolesSubtitle =>
      'Only show systems that have games';

  @override
  String get settings_controllerButtons => 'Controller Buttons';

  @override
  String get settings_controllerNintendo => 'Nintendo (default)';

  @override
  String get settings_controllerXbox => 'XBOX';

  @override
  String get settings_controllerPs => 'PS';

  @override
  String get settings_controllerNin => 'NIN';

  @override
  String get settings_sectionFeedback => 'Feedback';

  @override
  String get settings_vibration => 'Vibration';

  @override
  String get settings_vibrationSubtitle => 'Vibrate on button presses';

  @override
  String get settings_soundEffects => 'Sound Effects';

  @override
  String get settings_soundEffectsSubtitle => 'Play sounds for menu actions';

  @override
  String get settings_sectionVolume => 'Volume';

  @override
  String get settings_music => 'Music';

  @override
  String get settings_musicSubtitle => 'Ambient background music';

  @override
  String get settings_effects => 'Effects';

  @override
  String get settings_effectsSubtitle => 'Interface sound effects';

  @override
  String get settings_sectionDownloads => 'Downloads';

  @override
  String get settings_simultaneousDownloads => 'Simultaneous Downloads';

  @override
  String get settings_simultaneousDownloadsSubtitle =>
      'How many files download at once';

  @override
  String get settings_downloadAllCovers => 'DOWNLOAD ALL COVERS';

  @override
  String get settings_downloadingCovers => 'DOWNLOADING COVERS...';

  @override
  String get settings_sectionSync => 'Sync';

  @override
  String get settings_syncTimeout => 'Sync Timeout';

  @override
  String get settings_syncTimeoutSubtitle => 'How long to wait for each server';

  @override
  String get settings_autoSyncInterval => 'Auto-Sync Interval';

  @override
  String get settings_autoSyncIntervalSubtitle =>
      'Minimum time between automatic syncs';

  @override
  String get settings_sectionDebug => 'Debug';

  @override
  String get settings_allowInsecure => 'Allow Insecure Connections';

  @override
  String get settings_allowInsecureSubtitle =>
      'Enable HTTP for servers without HTTPS';

  @override
  String get settings_exportErrorLog => 'Export Error Log';

  @override
  String get settings_exportErrorLogSubtitle =>
      'Share crash log for troubleshooting';

  @override
  String get settings_sectionInfo => 'Info';

  @override
  String get settings_sectionLinks => 'Links';

  @override
  String get settings_github => 'GitHub';

  @override
  String get settings_githubSubtitle => 'View source code on GitHub';

  @override
  String get settings_issues => 'Issues';

  @override
  String get settings_issuesSubtitle => 'Report bugs or request features';

  @override
  String get settings_tagline => 'INTENSIV, AGGRESSIV, MUTIG';

  @override
  String get settings_deviceMemoryLow => 'LOW';

  @override
  String get settings_deviceMemoryStandard => 'STANDARD';

  @override
  String get settings_deviceMemoryHigh => 'HIGH';

  @override
  String get settings_fetchingCovers => 'Fetching covers...';

  @override
  String settings_coversResult(int ok, int failed) {
    return 'Covers: $ok ok, $failed failed';
  }

  @override
  String settings_coversLoaded(int count) {
    return '$count covers loaded!';
  }

  @override
  String get settings_noErrorLog => 'No error log available';

  @override
  String get settings_configImported => 'Config imported!';

  @override
  String get settings_controllerXboxFull => 'Xbox (A/B & X/Y swapped)';

  @override
  String get settings_controllerPlaystationFull => 'PlayStation (✕ ○ □ △)';

  @override
  String get settings_allCoversCached => 'All covers cached';

  @override
  String get settings_downloadCoverArt => 'Download cover art for all games';

  @override
  String settings_coverCacheInfo(String size, int count) {
    return '$size ($count cached)';
  }

  @override
  String settings_coversRemaining(int count, String size) {
    return '$count remaining (~$size MB)';
  }

  @override
  String settings_coversProgress(int completed, int total) {
    return '$completed / $total games';
  }

  @override
  String get configMode_title => 'CONSOLE SETTINGS';

  @override
  String get configMode_globalTitle => 'GLOBAL SETTINGS';

  @override
  String get configMode_noFolderSet => 'No folder set';

  @override
  String get configMode_notConfigured => 'Not configured';

  @override
  String get configMode_export => 'Export';

  @override
  String get configMode_import => 'Import';

  @override
  String get systemDetail_sectionStorage => 'Storage';

  @override
  String get systemDetail_selectRomFolder => 'Select ROM folder';

  @override
  String get systemDetail_tapToChangeFolder => 'Tap to change folder';

  @override
  String get systemDetail_sectionBehavior => 'Behavior';

  @override
  String get systemDetail_autoExtractZips => 'Auto-Extract ZIPs';

  @override
  String get systemDetail_autoExtractEnabled =>
      'Zipped ROMs are extracted after download';

  @override
  String get systemDetail_autoExtractDisabled =>
      'ROMs stay zipped after download';

  @override
  String get systemDetail_autoSyncOnLaunch => 'Auto-Sync on Launch';

  @override
  String get systemDetail_autoSyncEnabled =>
      'Syncs automatically (respects cooldown)';

  @override
  String get systemDetail_autoSyncDisabled =>
      'Only syncs manually via Start menu';

  @override
  String get systemDetail_sectionSources => 'Sources';

  @override
  String get sources_title => 'SOURCES';

  @override
  String get sources_refreshCatalogue => 'Refresh catalogue';

  @override
  String get sources_configureDrive => 'Connect / configure';

  @override
  String get sources_disconnectDrive =>
      'Disconnect Google Drive (all Drive sources)';

  @override
  String get sources_revokeDrive =>
      'Revoke Google Drive access (all Drive sources)';

  @override
  String get sources_sourceTypeDriveHint =>
      'Private read-only folder via native Google authorization';

  @override
  String get sources_sourceTypeSmbHint => 'Windows / NAS network share';

  @override
  String get sources_sourceTypeFtpHint => 'FTP/FTPS server';

  @override
  String get sources_noSourcesConfigured => 'No sources configured';

  @override
  String get sources_noSourcesYet => 'No sources yet';

  @override
  String get sources_noSourcesDescription =>
      'Pair a RomM server to start downloading games. ';

  @override
  String get sources_addSource => 'Add source';

  @override
  String get sources_whereDoGamesComeFrom => 'Where do your games come from?';

  @override
  String get sources_sourceTypeRomm => 'RomM Server';

  @override
  String get sources_sourceTypeRommHint => 'Pair via QR or 8-digit code';

  @override
  String get sources_sourceTypeRommLegacy => 'RomM Login (older servers)';

  @override
  String get sources_sourceTypeSmb => 'SMB Share';

  @override
  String get sources_sourceTypeFtp => 'FTP Server';

  @override
  String get sources_sourceTypeWeb => 'Web Mirror';

  @override
  String get sources_sourceTypeWebHint => 'HTTPS directory listing';

  @override
  String get sources_expired => 'EXPIRED';

  @override
  String get sources_borrowed => 'BORROWED';

  @override
  String get sources_off => 'OFF';

  @override
  String get sources_noPlatforms => 'No platforms';

  @override
  String get sources_rePair => 'Re-pair';

  @override
  String get sources_editMappings => 'Edit mappings';

  @override
  String get sources_disable => 'Disable';

  @override
  String get sources_enable => 'Enable';

  @override
  String get manualSource_defaultNameSmb => 'My NAS';

  @override
  String get manualSource_defaultNameFtp => 'My FTP';

  @override
  String get manualSource_defaultNameWeb => 'Web Mirror';

  @override
  String get manualSource_defaultNameOther => 'Source';

  @override
  String get manualSource_name => 'Name';

  @override
  String get manualSource_url => 'URL';

  @override
  String get manualSource_urlHint => 'https://example.com/roms';

  @override
  String get manualSource_host => 'Host';

  @override
  String get manualSource_hostHint => 'nas.local or 192.168.1.10';

  @override
  String get manualSource_port => 'Port';

  @override
  String get manualSource_share => 'Share';

  @override
  String get manualSource_shareHint => 'roms';

  @override
  String get manualSource_usernameOptional => 'Username (optional)';

  @override
  String get manualSource_usernameHint => 'leave blank for guest';

  @override
  String get manualSource_passwordOptional => 'Password (optional)';

  @override
  String get manualSource_nameRequired => 'Name is required';

  @override
  String get manualSource_urlRequired => 'URL is required';

  @override
  String get manualSource_hostRequired => 'Host is required';

  @override
  String get manualSource_shareRequired => 'Share is required';

  @override
  String get manualSource_saveSource => 'Save source';

  @override
  String get manualSource_smb => 'SMB';

  @override
  String get manualSource_ftp => 'FTP';

  @override
  String get manualSource_web => 'Web';

  @override
  String get manualSource_searchingNetwork => 'Searching network…';

  @override
  String get manualSource_foundOnNetwork => 'Found on your network';

  @override
  String get sourceMappings_title => 'System mappings';

  @override
  String get sourceMappings_instruction =>
      'Enter the remote folder for each system you want this source to serve. Leave empty to skip.';

  @override
  String get sourceMappings_save => 'Save mappings';

  @override
  String get library_title => 'LIBRARY';

  @override
  String get library_tabAll => 'All';

  @override
  String get library_tabInstalled => 'Installed';

  @override
  String get library_tabFavorites => 'Favorites';

  @override
  String get library_sortSystem => 'Sort by System';

  @override
  String get library_sortManual => 'Sort Manual';

  @override
  String get library_sortAZ => 'Sort A-Z';

  @override
  String get library_sortIndicatorAZ => 'A-Z';

  @override
  String get library_sortIndicatorBySystem => 'BY SYSTEM';

  @override
  String get library_sortIndicatorManual => 'MANUAL';

  @override
  String get library_searchHint => 'Search library...';

  @override
  String get library_zoomIn => 'Zoom In';

  @override
  String get library_zoomOut => 'Zoom Out';

  @override
  String get library_newShelf => 'New Shelf';

  @override
  String get library_editShelf => 'Edit Shelf';

  @override
  String get library_addToShelf => 'Add to Shelf';

  @override
  String get library_removeFromShelf => 'Remove from Shelf';

  @override
  String get library_reorderGames => 'Reorder Games';

  @override
  String library_noResults(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get library_tryShorterSearch => 'Try a shorter search term';

  @override
  String get library_noInstalledGames => 'No installed games';

  @override
  String get library_downloadGamesToSee => 'Download games to see them here';

  @override
  String get library_noFavoritesYet => 'No favorites yet';

  @override
  String get library_pressFavoriteHint =>
      'Press SELECT on a game to favorite it';

  @override
  String get library_noGamesInShelf => 'No games in this shelf';

  @override
  String get library_addGamesViaEditor => 'Add games via the shelf editor';

  @override
  String get library_noGamesInLibrary => 'No games in library';

  @override
  String get library_gamesAfterSync => 'Games will appear after sync completes';

  @override
  String get shelfEdit_title => 'EDIT SHELF';

  @override
  String get shelfEdit_titleNew => 'NEW SHELF';

  @override
  String get shelfEdit_nameSection => 'NAME';

  @override
  String get shelfEdit_shelfName => 'Shelf Name';

  @override
  String get shelfEdit_filterText => 'Filter Text';

  @override
  String get shelfEdit_tapToSet => 'Tap to set...';

  @override
  String get shelfEdit_filterRules => 'FILTER RULES';

  @override
  String get shelfEdit_resetManualOrder => 'Reset Manual Order';

  @override
  String get shelfEdit_saveButton => 'SAVE';

  @override
  String get shelfEdit_deleteShelf => 'DELETE SHELF';

  @override
  String get shelfEdit_anyText => 'Any text';

  @override
  String get shelfEdit_allSystems => 'All systems';

  @override
  String get shelfPicker_title => 'ADD TO SHELF';

  @override
  String get systemSelector_title => 'SELECT SYSTEMS';

  @override
  String get textInput_hint => 'Enter text...';

  @override
  String get textInput_ok => 'OK';

  @override
  String get gameListOverlay_hiddenGames => 'HIDDEN GAMES';

  @override
  String get gameListOverlay_addedGames => 'ADDED GAMES';

  @override
  String get gameListOverlay_restore => 'Restore';

  @override
  String get gameListOverlay_noGames => 'No games';

  @override
  String get gameListOverlay_clearAll => 'Clear All';

  @override
  String get home_allGames => 'ALL GAMES';

  @override
  String get home_library => 'Library';

  @override
  String get home_noConsoles => 'No consoles configured';

  @override
  String get home_pressStartForMenu => 'Press Start for Menu';

  @override
  String get home_settings => 'Settings';

  @override
  String home_syncSystem(String system) {
    return 'Sync $system';
  }

  @override
  String get home_syncAll => 'Sync All';

  @override
  String get home_lastSyncNever => 'Never synced';

  @override
  String get home_lastSyncJustNow => 'Synced just now';

  @override
  String home_lastSyncMinutes(int minutes) {
    return 'Synced ${minutes}min ago';
  }

  @override
  String home_lastSyncHours(int hours) {
    return 'Synced ${hours}h ago';
  }

  @override
  String home_lastSyncDays(int days) {
    return 'Synced ${days}d ago';
  }

  @override
  String get common_exit => 'Exit';

  @override
  String gameList_gamesCount(int count) {
    return '$count Games';
  }

  @override
  String get gameList_offline => 'Offline';

  @override
  String get gameList_zoomIn => 'Zoom In';

  @override
  String get gameList_zoomOut => 'Zoom Out';

  @override
  String get gameList_filterActive => 'Filter (active)';

  @override
  String get gameList_filter => 'Filter';

  @override
  String gameList_noGamesMatchSearch(String query) {
    return 'No games match \'$query\'';
  }

  @override
  String get gameList_tryShorterSearch => 'Try a shorter search term';

  @override
  String get gameList_noGamesMatchFilters => 'No games match current filters';

  @override
  String get gameList_changeFilters => 'Change or reset filters in the menu';

  @override
  String gameList_noRomsFound(String folder) {
    return 'No ROMs found in $folder';
  }

  @override
  String get gameList_addRomFiles => 'Add ROM files to this folder and refresh';

  @override
  String get gameList_couldNotLoadGames => 'Could not load games';

  @override
  String get gameList_checkConnection => 'Check your connection and try again';

  @override
  String get gameList_errorLoadingGames => 'Error loading games';

  @override
  String get gameList_gamesAppearShortly => 'Games will appear shortly';

  @override
  String get gameList_syncingLibrary => 'Syncing library…';

  @override
  String get gameList_localFilesOnly =>
      'Local files only · Add a provider to download more';

  @override
  String get gameList_pressMenuHint => 'Press  +  for menu';

  @override
  String filter_activeCount(int count) {
    return '$count active';
  }

  @override
  String get shelfEdit_addFilter => '+ ADD FILTER';

  @override
  String shelfEdit_hiddenGamesCount(int count) {
    return 'Hidden Games ($count)';
  }

  @override
  String shelfEdit_addedGamesCount(int count) {
    return 'Added Games ($count)';
  }

  @override
  String get shelfEdit_textHint => '← Text  Sys →';

  @override
  String gameListOverlay_gameCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count games',
      one: '1 game',
    );
    return '$_temp0';
  }

  @override
  String gameListOverlay_actionHint(String action) {
    return 'A: $action';
  }

  @override
  String systemSelector_selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get filter_favoritesOnly => 'Favorites Only';

  @override
  String get filter_installedOnly => 'Installed Only';

  @override
  String get filter_regions => 'REGIONS';

  @override
  String get filter_languages => 'LANGUAGES';

  @override
  String get filter_title => 'FILTER';

  @override
  String get onboarding_welcomeTitle => 'Welcome to R-Shop';

  @override
  String get onboarding_welcomeSubtitle => 'Where do your games come from?';

  @override
  String get onboarding_pairQrTitle => 'Pair RomM via QR';

  @override
  String get onboarding_pairQrSubtitle => 'Scan a code from your RomM server';

  @override
  String get onboarding_legacyLoginTitle => 'RomM login (older servers)';

  @override
  String get onboarding_legacyLoginSubtitle =>
      'Username + password for RomM < 4.8';

  @override
  String get onboarding_addServerTitle => 'Add my own server';

  @override
  String get onboarding_addServerSubtitle =>
      'SMB, FTP or Web mirror — map systems manually';

  @override
  String get onboarding_localOnlyTitle => 'Local games only';

  @override
  String get onboarding_localOnlySubtitle => 'ROMs already on this device';

  @override
  String get onboarding_working => 'Working…';

  @override
  String get onboarding_scanningFolders => 'Scanning local ROM folders…';

  @override
  String get onboarding_discoveringPlatforms => 'Discovering platforms…';

  @override
  String get onboarding_savingSource => 'Saving source…';

  @override
  String get onboarding_allSet => 'You\'re all set';

  @override
  String get onboarding_noSystems =>
      'No systems configured yet — you can add sources later from Settings.';

  @override
  String onboarding_systemsReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count systems ready to browse',
      one: '1 system ready to browse',
    );
    return '$_temp0';
  }

  @override
  String get onboarding_jumpIn => 'Jump in';

  @override
  String get onboarding_jumpInSubtitle =>
      'Open the home screen and start syncing';

  @override
  String get onboarding_retroachievements => 'RetroAchievements';

  @override
  String get onboarding_retroachievementsSubtitle =>
      'Track your retro gaming achievements';

  @override
  String get onboarding_exportConfig => 'Export config';

  @override
  String get onboarding_exportConfigSubtitle =>
      'Re-use this setup on another device';

  @override
  String get onboarding_importConfig => 'Import config';

  @override
  String get onboarding_configImported => 'Config imported!';

  @override
  String onboarding_exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String onboarding_invalidConfig(String error) {
    return 'Invalid config: $error';
  }

  @override
  String onboarding_failedToSave(String error) {
    return 'Failed to save: $error';
  }

  @override
  String get onboarding_selectFolderPrompt =>
      'Pick the folder where ROMs should be saved';

  @override
  String get onboarding_serverType => 'Server type';

  @override
  String get onboarding_hangOn => 'Hang on, testing the connection...';

  @override
  String get onboarding_foundConsole =>
      'I found this console on your RomM server! Confirm or pick a different one.';

  @override
  String get onboarding_pickPlatform =>
      'Pick the matching platform from your RomM server.';

  @override
  String get onboarding_couldNotReach =>
      'Couldn\'t reach your RomM server. Check the URL and try again.';

  @override
  String get onboarding_connectionGood =>
      'Connection looks good! You\'re all set to save this source.';

  @override
  String get onboarding_couldNotConnect =>
      'Hmm, couldn\'t connect. Double-check the address and credentials.';

  @override
  String get onboarding_whatKindOfSource =>
      'What kind of source is this? Pick the connection type.';

  @override
  String get onboarding_lookingGood =>
      'Looking good! Add more sources or press Done when you\'re ready.';

  @override
  String get onboarding_localCollection =>
      'This is a local collection. Add a source to download more, or just hit Done!';

  @override
  String get onboarding_addMoreSources =>
      'Now add at least one source so I know where to find the ROMs.';

  @override
  String get onboarding_letsSetUp =>
      'Let\'s set up your consoles! Select any system to get started.';

  @override
  String get onboarding_romFolder => 'ROM FOLDER';

  @override
  String get onboarding_options => 'OPTIONS';

  @override
  String get onboarding_autoExtractZips => 'Auto-extract zipped ROMs';

  @override
  String get onboarding_autoSyncLabel => 'Auto-sync on app launch';

  @override
  String get onboarding_autoSyncEnabled =>
      'Syncs automatically (respects cooldown)';

  @override
  String get onboarding_autoSyncDisabled =>
      'Only syncs manually via Start menu';

  @override
  String get onboarding_selectFolder => 'Select folder...';

  @override
  String get providerForm_addSource => 'Add Source';

  @override
  String get providerForm_editSource => 'Edit Source';

  @override
  String get providerForm_url => 'URL';

  @override
  String get providerForm_urlPlaceholder => 'https://...';

  @override
  String get providerForm_path => 'Path';

  @override
  String get providerForm_pathPlaceholder => '/roms/nes/ (optional)';

  @override
  String get providerForm_username => 'Username';

  @override
  String get providerForm_usernameOptional => '(optional)';

  @override
  String get providerForm_password => 'Password';

  @override
  String get providerForm_host => 'Host';

  @override
  String get providerForm_hostPlaceholder => '192.168.1.100';

  @override
  String get providerForm_port => 'Port';

  @override
  String get providerForm_share => 'Share';

  @override
  String get providerForm_sharePlaceholder => 'roms';

  @override
  String get providerForm_domain => 'Domain';

  @override
  String get providerForm_domainOptional => '(optional)';

  @override
  String get providerForm_rommUrl => 'URL';

  @override
  String get providerForm_rommUrlPlaceholder => 'https://romm.example.com';

  @override
  String get providerForm_apiKey => 'API Key';

  @override
  String get providerForm_apiKeyOptional => '(optional)';

  @override
  String get providerForm_httpBlocked =>
      'HTTP to non-local servers is blocked. Use HTTPS, or enable after setup in Settings.';

  @override
  String get providerForm_httpWarning =>
      'Credentials will be sent unencrypted over HTTP';

  @override
  String get providerForm_testingConnection => 'Testing connection...';

  @override
  String get providerForm_connectionSuccessful => 'Connection successful!';

  @override
  String get providerForm_fetchingPlatforms => 'Fetching platforms...';

  @override
  String get providerForm_noPlatformsFound =>
      'No platforms found on this RomM server.';

  @override
  String get providerForm_platform => 'PLATFORM';

  @override
  String get providerForm_pickPlatform => 'Pick a platform...';

  @override
  String get providerForm_testAndSave => 'Test & Save';

  @override
  String get providerForm_connectionFailed => 'Connection failed';

  @override
  String get providerForm_hostMissing => 'Host';

  @override
  String get providerForm_portMissing => 'Port';

  @override
  String get providerForm_pathMissing => 'Path';

  @override
  String get providerForm_shareMissing => 'Share';

  @override
  String get providerForm_urlMissing => 'URL';

  @override
  String get rommLogin_title => 'Log in to RomM';

  @override
  String get rommLogin_name => 'Name';

  @override
  String get rommLogin_nameDefault => 'My RomM';

  @override
  String get rommLogin_serverUrl => 'Server URL';

  @override
  String get rommLogin_username => 'Username';

  @override
  String get rommLogin_usernameHint => 'admin';

  @override
  String get rommLogin_password => 'Password';

  @override
  String get rommLogin_passwordHint => '••••••••';

  @override
  String get rommLogin_nameRequired => 'Name is required';

  @override
  String get rommLogin_serverUrlRequired => 'Server URL is required';

  @override
  String get rommLogin_credentialsRequired => 'Username or password required';

  @override
  String get ra_title => 'RetroAchievements';

  @override
  String get ra_subtitle => 'Track your retro gaming achievements. ';

  @override
  String get ra_usernameLabel => 'Username';

  @override
  String get ra_usernameHint => 'your RA username';

  @override
  String get ra_apiKeyLabel => 'API Key';

  @override
  String get ra_apiKeyHint => 'paste from retroachievements.org';

  @override
  String get ra_usernameRequired => 'Username is required';

  @override
  String get ra_apiKeyRequired => 'API Key is required';

  @override
  String get ra_connectionFailed => 'Connection failed';

  @override
  String get ra_disconnect => 'Disconnect';

  @override
  String get ra_syncNow => 'Sync achievements now';

  @override
  String get ra_skipForNow => 'Skip for now';

  @override
  String get pairing_scanQrTitle => 'Scan QR code';

  @override
  String get pairing_scanQrHint => 'Hold the QR code inside the frame';

  @override
  String get pairing_enterManually => 'Enter code manually';

  @override
  String get pairing_invalidQr => 'QR code is not a valid RomM pairing link';

  @override
  String get pairing_manualTitle => 'Manual pairing';

  @override
  String get pairing_manualInstructions =>
      'Generate the code in your RomM web UI under ';

  @override
  String get pairing_serverUrl => 'Server URL';

  @override
  String get pairing_pairingCode => 'Pairing code';

  @override
  String get pairing_pairingCodeHint => 'ABCD-1234';

  @override
  String get pairing_probingServer => 'Probing server…';

  @override
  String get pairing_serverNotReachable =>
      'Server not reachable or not a RomM instance';

  @override
  String get pairing_serverUrlRequired => 'Server URL and code are required';

  @override
  String get pairing_successTitle => 'Pairing successful';

  @override
  String get pairing_server => 'Server';

  @override
  String get pairing_token => 'Token';

  @override
  String get pairing_userId => 'User ID';

  @override
  String get pairing_expiry => 'Expiry';

  @override
  String get pairing_neverExpires => 'Never expires';

  @override
  String get pairing_alreadyExpired => 'Already expired';

  @override
  String get pairing_permissions => 'PERMISSIONS';

  @override
  String get pairing_addServer => 'Add server';

  @override
  String get gameCard_cloudAvailable => 'Available to download';

  @override
  String get library_dashboard => 'Dashboard';

  @override
  String get library_catalogueEntries => 'Catalogue entries';

  @override
  String get library_sourceStorage => 'Known source size';

  @override
  String get library_managedStorage => 'Managed local files';

  @override
  String get library_sizeUnknown => 'Unknown';

  @override
  String library_unknownSizes(int count) {
    return '$count source sizes unknown';
  }

  @override
  String get library_dashboardNote =>
      'Cached catalogue entries, not unique games. Source sizes are not SD usage; managed local bytes exclude unmanaged files, saves and BIOS.';

  @override
  String get service_notificationTitle => 'R-Shop';

  @override
  String get service_channelName => 'Downloads';

  @override
  String get service_channelDescription =>
      'Shows progress while downloading games';

  @override
  String get service_downloadComplete => 'Downloads complete';

  @override
  String service_downloading(String details) {
    return 'Downloading: $details';
  }

  @override
  String service_activeCount(int count) {
    return '$count active';
  }

  @override
  String service_queuedCount(int count) {
    return '$count queued';
  }
}
