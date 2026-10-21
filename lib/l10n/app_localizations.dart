import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('ja'),
    Locale('pt')
  ];

  /// No description provided for @saveBackup_title.
  ///
  /// In en, this message translates to:
  /// **'Save backups'**
  String get saveBackup_title;

  /// No description provided for @saveBackup_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Back up emulator saves, not ROMs'**
  String get saveBackup_subtitle;

  /// No description provided for @saveBackup_help.
  ///
  /// In en, this message translates to:
  /// **'Keep save backups in a separate private area of Google Drive. G-Shop can change only backups it creates, not your cloud ROMs. Choose the saves to back up before anything is uploaded.'**
  String get saveBackup_help;

  /// No description provided for @saveBackup_authorize.
  ///
  /// In en, this message translates to:
  /// **'Set up Drive backups'**
  String get saveBackup_authorize;

  /// No description provided for @saveBackup_ready.
  ///
  /// In en, this message translates to:
  /// **'Drive backups are ready to set up for your games'**
  String get saveBackup_ready;

  /// No description provided for @saveBackup_notMapped.
  ///
  /// In en, this message translates to:
  /// **'No saves selected yet. Choose a game\'s save in Back up save to start backing it up.'**
  String get saveBackup_notMapped;

  /// No description provided for @saveBackup_verify.
  ///
  /// In en, this message translates to:
  /// **'Check Drive backup access'**
  String get saveBackup_verify;

  /// No description provided for @saveBackup_problem.
  ///
  /// In en, this message translates to:
  /// **'Setup needs attention: {code}'**
  String saveBackup_problem(String code);

  /// No description provided for @saveBackup_noDrive.
  ///
  /// In en, this message translates to:
  /// **'Add a Google Drive source first to select its connected account.'**
  String get saveBackup_noDrive;

  /// No description provided for @saveBackup_preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing private backup area…'**
  String get saveBackup_preparing;

  /// No description provided for @metadata_credentials.
  ///
  /// In en, this message translates to:
  /// **'Account & API keys'**
  String get metadata_credentials;

  /// No description provided for @metadata_scraping.
  ///
  /// In en, this message translates to:
  /// **'Get game information'**
  String get metadata_scraping;

  /// No description provided for @metadata_latestGame.
  ///
  /// In en, this message translates to:
  /// **'Latest processed game'**
  String get metadata_latestGame;

  /// No description provided for @metadata_unverifiedCandidate.
  ///
  /// In en, this message translates to:
  /// **'Possible match · needs confirmation'**
  String get metadata_unverifiedCandidate;

  /// No description provided for @metadata_dailyQuota.
  ///
  /// In en, this message translates to:
  /// **'Daily lookup allowance'**
  String get metadata_dailyQuota;

  /// No description provided for @metadata_requestsRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining attempts'**
  String get metadata_requestsRemaining;

  /// No description provided for @metadata_requestsUsed.
  ///
  /// In en, this message translates to:
  /// **'Reported attempts used'**
  String get metadata_requestsUsed;

  /// No description provided for @metadata_failedRequestsRemaining.
  ///
  /// In en, this message translates to:
  /// **'Failed-request attempts remaining'**
  String get metadata_failedRequestsRemaining;

  /// No description provided for @metadata_quotaObserved.
  ///
  /// In en, this message translates to:
  /// **'Last provider report'**
  String get metadata_quotaObserved;

  /// No description provided for @metadata_localBudget.
  ///
  /// In en, this message translates to:
  /// **'Lookups available after queued requests'**
  String get metadata_localBudget;

  /// No description provided for @metadata_quotaUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get metadata_quotaUnknown;

  /// No description provided for @metadata_esDe.
  ///
  /// In en, this message translates to:
  /// **'Share game information with ES-DE'**
  String get metadata_esDe;

  /// No description provided for @metadata_esDeReviewArtwork.
  ///
  /// In en, this message translates to:
  /// **'Review and reuse existing artwork'**
  String get metadata_esDeReviewArtwork;

  /// No description provided for @metadata_esDeReviewArtworkHelp.
  ///
  /// In en, this message translates to:
  /// **'Confirm this cover or screenshot belongs to this exact console and edition, including its region/revision/patch. Only its explicitly mapped ES-DE path is accepted. Existing artwork remains launcher-owned; old metadata is not imported as fresh evidence.'**
  String get metadata_esDeReviewArtworkHelp;

  /// No description provided for @metadata_esDeHelp.
  ///
  /// In en, this message translates to:
  /// **'Link this game to its ROM folder, then choose this console\'s ES-DE gamelist folder. New game information is queued when you refresh. Close ES-DE and keep it closed while updates are saved. Games that are not downloaded will not become playable in ES-DE.'**
  String get metadata_esDeHelp;

  /// No description provided for @metadata_esDeMap.
  ///
  /// In en, this message translates to:
  /// **'Map this edition to ES-DE'**
  String get metadata_esDeMap;

  /// No description provided for @metadata_esDeRomRoot.
  ///
  /// In en, this message translates to:
  /// **'Select the ES-DE ROM folder for this console'**
  String get metadata_esDeRomRoot;

  /// No description provided for @metadata_esDeMediaRoot.
  ///
  /// In en, this message translates to:
  /// **'Select the ES-DE media folder for this console (not covers/screenshots)'**
  String get metadata_esDeMediaRoot;

  /// No description provided for @metadata_esDeGamelist.
  ///
  /// In en, this message translates to:
  /// **'Select the ES-DE gamelist folder for this console'**
  String get metadata_esDeGamelist;

  /// No description provided for @metadata_esDeClosed.
  ///
  /// In en, this message translates to:
  /// **'ES-DE is closed and will remain closed during publication'**
  String get metadata_esDeClosed;

  /// No description provided for @metadata_esDePublish.
  ///
  /// In en, this message translates to:
  /// **'Save updates to ES-DE'**
  String get metadata_esDePublish;

  /// No description provided for @metadata_esDePublished.
  ///
  /// In en, this message translates to:
  /// **'Updates saved to ES-DE'**
  String get metadata_esDePublished;

  /// No description provided for @metadata_esDeConflict.
  ///
  /// In en, this message translates to:
  /// **'Updates paused because game files or ES-DE information changed. Review the linked folders and any manual edits. Pending updates and existing ES-DE data are kept.'**
  String get metadata_esDeConflict;

  /// No description provided for @metadata_esDeNoMapping.
  ///
  /// In en, this message translates to:
  /// **'Open a freshly matched edition\'s metadata settings to map it. Shared metadata storage is required.'**
  String get metadata_esDeNoMapping;

  /// No description provided for @metadata_sharedStorage.
  ///
  /// In en, this message translates to:
  /// **'Shared game-information folder'**
  String get metadata_sharedStorage;

  /// No description provided for @metadata_sharedUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Your shared game-information folder could not be opened. Reconnect the storage and choose the same folder again. Saved information is still usable; updates and ES-DE sharing need folder access.'**
  String get metadata_sharedUnavailable;

  /// No description provided for @metadata_sharedStorageHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose a folder to keep game information and artwork outside G-Shop. Existing information is copied, not deleted. It survives uninstall: reconnect your source and choose this folder again to recover it. Account details and downloaded-game records are not backed up here. Set up ES-DE sharing separately.'**
  String get metadata_sharedStorageHelp;

  /// No description provided for @metadata_privateStorage.
  ///
  /// In en, this message translates to:
  /// **'No folder selected — saved inside G-Shop only'**
  String get metadata_privateStorage;

  /// No description provided for @metadata_chooseSharedStorage.
  ///
  /// In en, this message translates to:
  /// **'Choose / reconnect shared folder'**
  String get metadata_chooseSharedStorage;

  /// No description provided for @metadata_artwork.
  ///
  /// In en, this message translates to:
  /// **'Artwork'**
  String get metadata_artwork;

  /// No description provided for @metadata_rediscover.
  ///
  /// In en, this message translates to:
  /// **'Find another match'**
  String get metadata_rediscover;

  /// No description provided for @metadata_rediscoverHelp.
  ///
  /// In en, this message translates to:
  /// **'Search for this exact game again without reusing its saved match. Existing facts stay cached until you select and verify a replacement. No ROM is downloaded.'**
  String get metadata_rediscoverHelp;

  /// No description provided for @metadata_reviewChanged.
  ///
  /// In en, this message translates to:
  /// **'This game file changed. Search again before choosing a match.'**
  String get metadata_reviewChanged;

  /// No description provided for @metadata_openReview.
  ///
  /// In en, this message translates to:
  /// **'Review possible matches'**
  String get metadata_openReview;

  /// No description provided for @metadata_reviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review possible matches'**
  String get metadata_reviewTitle;

  /// No description provided for @metadata_reviewInfo.
  ///
  /// In en, this message translates to:
  /// **'Choose the correct game or fan project and its tags. A possible match is not yet a confirmed rating. Tags can be combined, but Official release cannot be combined with modification tags. Saving checks this game again without downloading its ROM.'**
  String get metadata_reviewInfo;

  /// No description provided for @metadata_chooseCandidate.
  ///
  /// In en, this message translates to:
  /// **'Choose the matching game or fan project'**
  String get metadata_chooseCandidate;

  /// No description provided for @metadata_candidateEvidence.
  ///
  /// In en, this message translates to:
  /// **'Why this match was suggested'**
  String get metadata_candidateEvidence;

  /// No description provided for @metadata_reviewAccept.
  ///
  /// In en, this message translates to:
  /// **'Save match and recheck'**
  String get metadata_reviewAccept;

  /// No description provided for @metadata_reviewEmpty.
  ///
  /// In en, this message translates to:
  /// **'No possible matches to review on this page. Games without a confirmed match do not receive a guessed rating.'**
  String get metadata_reviewEmpty;

  /// No description provided for @metadata_noCandidates.
  ///
  /// In en, this message translates to:
  /// **'No matching game was found. Check its title and console, or the service connection, then search again.'**
  String get metadata_noCandidates;

  /// No description provided for @metadata_reviewReload.
  ///
  /// In en, this message translates to:
  /// **'Reload possible matches'**
  String get metadata_reviewReload;

  /// No description provided for @metadata_reviewNext.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get metadata_reviewNext;

  /// No description provided for @metadata_reviewPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get metadata_reviewPrevious;

  /// No description provided for @metadata_reviewSaved.
  ///
  /// In en, this message translates to:
  /// **'Your choice was saved. G-Shop will check the match before using its rating.'**
  String get metadata_reviewSaved;

  /// No description provided for @metadata_reviewError.
  ///
  /// In en, this message translates to:
  /// **'The match could not be checked. The game may have changed or the service may be unavailable. Reload possible matches or resume the search. You can still play and download games.'**
  String get metadata_reviewError;

  /// No description provided for @metadata_setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Game metadata'**
  String get metadata_setupTitle;

  /// No description provided for @metadata_setupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts, game information and saved progress'**
  String get metadata_setupSubtitle;

  /// No description provided for @metadata_provider.
  ///
  /// In en, this message translates to:
  /// **'Metadata provider'**
  String get metadata_provider;

  /// No description provided for @metadata_accessInfo.
  ///
  /// In en, this message translates to:
  /// **'ScreenScraper needs your account and app access details. IGDB needs a client ID and secret. These are saved securely on this device and excluded from exported settings. Start a lookup to check the connection. No ROMs are downloaded.'**
  String get metadata_accessInfo;

  /// No description provided for @metadata_saved.
  ///
  /// In en, this message translates to:
  /// **'Saved on this device'**
  String get metadata_saved;

  /// No description provided for @metadata_notConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get metadata_notConfigured;

  /// No description provided for @metadata_applicationAccess.
  ///
  /// In en, this message translates to:
  /// **'Private application access'**
  String get metadata_applicationAccess;

  /// No description provided for @metadata_softwareName.
  ///
  /// In en, this message translates to:
  /// **'Software name'**
  String get metadata_softwareName;

  /// No description provided for @metadata_clientId.
  ///
  /// In en, this message translates to:
  /// **'Client ID'**
  String get metadata_clientId;

  /// No description provided for @metadata_clientSecret.
  ///
  /// In en, this message translates to:
  /// **'Client secret'**
  String get metadata_clientSecret;

  /// No description provided for @metadata_fullScope.
  ///
  /// In en, this message translates to:
  /// **'Entire collection'**
  String get metadata_fullScope;

  /// No description provided for @metadata_systemScope.
  ///
  /// In en, this message translates to:
  /// **'Console'**
  String get metadata_systemScope;

  /// No description provided for @metadata_gameScope.
  ///
  /// In en, this message translates to:
  /// **'Selected game'**
  String get metadata_gameScope;

  /// No description provided for @metadata_refresh.
  ///
  /// In en, this message translates to:
  /// **'Get fresh game information'**
  String get metadata_refresh;

  /// No description provided for @metadata_pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get metadata_pause;

  /// No description provided for @metadata_resume.
  ///
  /// In en, this message translates to:
  /// **'Resume saved job'**
  String get metadata_resume;

  /// No description provided for @metadata_savedJobs.
  ///
  /// In en, this message translates to:
  /// **'Saved jobs'**
  String get metadata_savedJobs;

  /// No description provided for @metadata_savedJobsHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose an earlier search to continue where it stopped. Resume uses that search\'s games, not the console selected above. Choosing a saved search does not use any lookups.'**
  String get metadata_savedJobsHelp;

  /// No description provided for @metadata_noSavedJobs.
  ///
  /// In en, this message translates to:
  /// **'No saved jobs on this page.'**
  String get metadata_noSavedJobs;

  /// No description provided for @metadata_olderJobs.
  ///
  /// In en, this message translates to:
  /// **'Older jobs'**
  String get metadata_olderJobs;

  /// No description provided for @metadata_newestJobs.
  ///
  /// In en, this message translates to:
  /// **'Newest jobs'**
  String get metadata_newestJobs;

  /// No description provided for @metadata_savedJobLabel.
  ///
  /// In en, this message translates to:
  /// **'Job {id} · {state} · {requested} lookups'**
  String metadata_savedJobLabel(int id, String state, int requested);

  /// No description provided for @metadata_retryOutcomes.
  ///
  /// In en, this message translates to:
  /// **'Retry failed / unmatched'**
  String get metadata_retryOutcomes;

  /// No description provided for @metadata_jobQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get metadata_jobQueued;

  /// No description provided for @metadata_jobRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get metadata_jobRunning;

  /// No description provided for @metadata_jobCompleted.
  ///
  /// In en, this message translates to:
  /// **'Search finished'**
  String get metadata_jobCompleted;

  /// No description provided for @metadata_requested.
  ///
  /// In en, this message translates to:
  /// **'Lookups made'**
  String get metadata_requested;

  /// No description provided for @metadata_matched.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get metadata_matched;

  /// No description provided for @metadata_review.
  ///
  /// In en, this message translates to:
  /// **'Needs review'**
  String get metadata_review;

  /// No description provided for @metadata_ambiguous.
  ///
  /// In en, this message translates to:
  /// **'More than one possible match'**
  String get metadata_ambiguous;

  /// No description provided for @metadata_unmatched.
  ///
  /// In en, this message translates to:
  /// **'No match found'**
  String get metadata_unmatched;

  /// No description provided for @metadata_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed / unsupported'**
  String get metadata_failed;

  /// No description provided for @metadata_rated.
  ///
  /// In en, this message translates to:
  /// **'Rated'**
  String get metadata_rated;

  /// No description provided for @metadata_pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get metadata_pending;

  /// No description provided for @metadata_completeNote.
  ///
  /// In en, this message translates to:
  /// **'A finished search does not mean every game has information or a reliable rating.'**
  String get metadata_completeNote;

  /// No description provided for @metadata_controlsError.
  ///
  /// In en, this message translates to:
  /// **'Metadata operation failed. Saved progress and ROM actions remain available. Check access or resume the saved job.'**
  String get metadata_controlsError;

  /// No description provided for @metadata_configureAccess.
  ///
  /// In en, this message translates to:
  /// **'Open Account & API keys for this service, check the details, then resume your saved search. Your ScreenScraper user account can remain a standard account.'**
  String get metadata_configureAccess;

  /// No description provided for @metadata_quotaWait.
  ///
  /// In en, this message translates to:
  /// **'The service has limited lookups for now. Resume when access is available again. Completed results are saved.'**
  String get metadata_quotaWait;

  /// No description provided for @metadata_offlineWait.
  ///
  /// In en, this message translates to:
  /// **'Provider unavailable. Check connectivity and resume the saved job.'**
  String get metadata_offlineWait;

  /// No description provided for @metadata_invalidInput.
  ///
  /// In en, this message translates to:
  /// **'Complete all required fields. Leave application fields blank to keep existing access.'**
  String get metadata_invalidInput;

  /// No description provided for @metadata_forget.
  ///
  /// In en, this message translates to:
  /// **'Forget this provider\'s credentials'**
  String get metadata_forget;

  /// No description provided for @metadata_cacheLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading cached metadata…'**
  String get metadata_cacheLoading;

  /// No description provided for @metadata_cacheError.
  ///
  /// In en, this message translates to:
  /// **'Cached metadata is unavailable. ROM actions remain available.'**
  String get metadata_cacheError;

  /// No description provided for @metadata_fieldSources.
  ///
  /// In en, this message translates to:
  /// **'Field sources'**
  String get metadata_fieldSources;

  /// No description provided for @metadata_description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get metadata_description;

  /// No description provided for @metadata_developer.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get metadata_developer;

  /// No description provided for @metadata_publisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get metadata_publisher;

  /// No description provided for @metadata_releaseDate.
  ///
  /// In en, this message translates to:
  /// **'Release date'**
  String get metadata_releaseDate;

  /// No description provided for @metadata_empty.
  ///
  /// In en, this message translates to:
  /// **'No verified metadata is cached for this edition.'**
  String get metadata_empty;

  /// No description provided for @filter_oneLimit.
  ///
  /// In en, this message translates to:
  /// **'One limit across the selected consoles'**
  String get filter_oneLimit;

  /// No description provided for @filter_scope.
  ///
  /// In en, this message translates to:
  /// **'Console scope'**
  String get filter_scope;

  /// No description provided for @filter_allScope.
  ///
  /// In en, this message translates to:
  /// **'All consoles · one collection-wide limit'**
  String get filter_allScope;

  /// No description provided for @filter_noMatches.
  ///
  /// In en, this message translates to:
  /// **'No games match these filters'**
  String get filter_noMatches;

  /// No description provided for @filter_discoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Best rated in my collection'**
  String get filter_discoveryTitle;

  /// No description provided for @filter_ratingOrder.
  ///
  /// In en, this message translates to:
  /// **'Rating order'**
  String get filter_ratingOrder;

  /// No description provided for @filter_anyTags.
  ///
  /// In en, this message translates to:
  /// **'Match any tag'**
  String get filter_anyTags;

  /// No description provided for @filter_allTags.
  ///
  /// In en, this message translates to:
  /// **'Match all tags'**
  String get filter_allTags;

  /// No description provided for @filter_contentTags.
  ///
  /// In en, this message translates to:
  /// **'Content tags'**
  String get filter_contentTags;

  /// No description provided for @filter_genres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get filter_genres;

  /// No description provided for @filter_allGames.
  ///
  /// In en, this message translates to:
  /// **'All games'**
  String get filter_allGames;

  /// No description provided for @filter_provisional.
  ///
  /// In en, this message translates to:
  /// **'Ratings incomplete'**
  String get filter_provisional;

  /// No description provided for @filter_coverage.
  ///
  /// In en, this message translates to:
  /// **'{ranked}/{total} ranked · {matches} matching games'**
  String filter_coverage(int ranked, int total, int matches);

  /// No description provided for @filter_basis.
  ///
  /// In en, this message translates to:
  /// **'Ranking basis: IGDB community average (20+ ratings; assessed systems only)'**
  String get filter_basis;

  /// No description provided for @filter_querying.
  ///
  /// In en, this message translates to:
  /// **'Updating cached filters…'**
  String get filter_querying;

  /// No description provided for @filter_topLimit.
  ///
  /// In en, this message translates to:
  /// **'Best {limit}'**
  String filter_topLimit(int limit);

  /// No description provided for @filter_official.
  ///
  /// In en, this message translates to:
  /// **'Official releases'**
  String get filter_official;

  /// No description provided for @filter_unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown classification'**
  String get filter_unknown;

  /// No description provided for @filter_homebrew.
  ///
  /// In en, this message translates to:
  /// **'Homebrew'**
  String get filter_homebrew;

  /// No description provided for @filter_demo.
  ///
  /// In en, this message translates to:
  /// **'Demo'**
  String get filter_demo;

  /// No description provided for @metadata_staleScore.
  ///
  /// In en, this message translates to:
  /// **'Needs a fresh rating'**
  String get metadata_staleScore;

  /// No description provided for @metadata_originalGame.
  ///
  /// In en, this message translates to:
  /// **'Original game'**
  String get metadata_originalGame;

  /// No description provided for @metadata_projectScore.
  ///
  /// In en, this message translates to:
  /// **'Project score'**
  String get metadata_projectScore;

  /// No description provided for @metadata_advisoryScore.
  ///
  /// In en, this message translates to:
  /// **'Not used for Top lists'**
  String get metadata_advisoryScore;

  /// No description provided for @metadata_gameScore.
  ///
  /// In en, this message translates to:
  /// **'Game score'**
  String get metadata_gameScore;

  /// No description provided for @metadata_unknownCount.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get metadata_unknownCount;

  /// No description provided for @metadata_ratingOverlays.
  ///
  /// In en, this message translates to:
  /// **'Cover ratings'**
  String get metadata_ratingOverlays;

  /// No description provided for @metadata_ratingOverlaysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show cached, source-labelled ratings on game covers'**
  String get metadata_ratingOverlaysSubtitle;

  /// No description provided for @metadata_scoreDetails.
  ///
  /// In en, this message translates to:
  /// **'{source}: {score}/100. Original scale: {raw} ({minimum}–{maximum}). {count} ratings. Retrieved {date}.'**
  String metadata_scoreDetails(String source, String score, String raw,
      String minimum, String maximum, String count, String date);

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'G-Shop'**
  String get appTitle;

  /// No description provided for @settings_language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settings_language;

  /// No description provided for @settings_languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settings_languageSystem;

  /// No description provided for @common_back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get common_back;

  /// No description provided for @common_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get common_close;

  /// No description provided for @common_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get common_cancel;

  /// No description provided for @common_cancelUpper.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get common_cancelUpper;

  /// No description provided for @common_select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get common_select;

  /// No description provided for @common_search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get common_search;

  /// No description provided for @common_searchEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get common_searchEllipsis;

  /// No description provided for @common_menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get common_menu;

  /// No description provided for @common_navigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get common_navigate;

  /// No description provided for @common_toggle.
  ///
  /// In en, this message translates to:
  /// **'Toggle'**
  String get common_toggle;

  /// No description provided for @common_clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get common_clear;

  /// No description provided for @common_done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get common_done;

  /// No description provided for @common_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get common_save;

  /// No description provided for @common_connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get common_connect;

  /// No description provided for @common_retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get common_retry;

  /// No description provided for @common_remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get common_remove;

  /// No description provided for @common_favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get common_favorite;

  /// No description provided for @common_unfavorite.
  ///
  /// In en, this message translates to:
  /// **'Unfavorite'**
  String get common_unfavorite;

  /// No description provided for @common_downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get common_downloads;

  /// No description provided for @common_installed.
  ///
  /// In en, this message translates to:
  /// **'INSTALLED'**
  String get common_installed;

  /// No description provided for @common_move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get common_move;

  /// No description provided for @common_drop.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get common_drop;

  /// No description provided for @common_grab.
  ///
  /// In en, this message translates to:
  /// **'Grab'**
  String get common_grab;

  /// No description provided for @confirm_deleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete ROM?'**
  String get confirm_deleteTitle;

  /// No description provided for @confirm_deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Do you really want to delete this version of {gameTitle}?'**
  String confirm_deleteMessage(String gameTitle);

  /// No description provided for @confirm_exitTitle.
  ///
  /// In en, this message translates to:
  /// **'Exit App?'**
  String get confirm_exitTitle;

  /// No description provided for @confirm_exitMessage.
  ///
  /// In en, this message translates to:
  /// **'Do you really want to exit Retro eShop?'**
  String get confirm_exitMessage;

  /// No description provided for @confirm_resetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset App?'**
  String get confirm_resetTitle;

  /// No description provided for @confirm_resetMessage.
  ///
  /// In en, this message translates to:
  /// **'This will return to the onboarding screen.'**
  String get confirm_resetMessage;

  /// No description provided for @confirm_deleteButton.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get confirm_deleteButton;

  /// No description provided for @confirm_exitButton.
  ///
  /// In en, this message translates to:
  /// **'EXIT'**
  String get confirm_exitButton;

  /// No description provided for @confirm_resetButton.
  ///
  /// In en, this message translates to:
  /// **'RESET'**
  String get confirm_resetButton;

  /// No description provided for @confirm_gamepadHint.
  ///
  /// In en, this message translates to:
  /// **'← → Select   A Confirm   B Cancel'**
  String get confirm_gamepadHint;

  /// No description provided for @exit_title.
  ///
  /// In en, this message translates to:
  /// **'EXIT APPLICATION'**
  String get exit_title;

  /// No description provided for @exit_message.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to quit?'**
  String get exit_message;

  /// No description provided for @exit_confirmButton.
  ///
  /// In en, this message translates to:
  /// **'EXIT'**
  String get exit_confirmButton;

  /// No description provided for @exit_cancelButton.
  ///
  /// In en, this message translates to:
  /// **'STAY'**
  String get exit_cancelButton;

  /// No description provided for @downloads_title.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads_title;

  /// No description provided for @downloads_activeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String downloads_activeCount(int count);

  /// No description provided for @downloads_noDownloads.
  ///
  /// In en, this message translates to:
  /// **'No downloads'**
  String get downloads_noDownloads;

  /// No description provided for @downloads_sectionDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get downloads_sectionDownloading;

  /// No description provided for @downloads_sectionQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get downloads_sectionQueued;

  /// No description provided for @downloads_sectionPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get downloads_sectionPaused;

  /// No description provided for @downloads_sectionComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get downloads_sectionComplete;

  /// No description provided for @downloads_actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get downloads_actionCancel;

  /// No description provided for @downloads_actionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get downloads_actionPause;

  /// No description provided for @downloads_actionResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get downloads_actionResume;

  /// No description provided for @downloads_moveEarlier.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get downloads_moveEarlier;

  /// No description provided for @downloads_moveLater.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get downloads_moveLater;

  /// No description provided for @downloads_actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get downloads_actionRetry;

  /// No description provided for @downloads_actionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get downloads_actionRemove;

  /// No description provided for @downloads_actionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get downloads_actionClear;

  /// No description provided for @downloads_clearDone.
  ///
  /// In en, this message translates to:
  /// **'Clear Done'**
  String get downloads_clearDone;

  /// No description provided for @downloadStatus_downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get downloadStatus_downloading;

  /// No description provided for @downloadStatus_extracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting...'**
  String get downloadStatus_extracting;

  /// No description provided for @downloadStatus_installing.
  ///
  /// In en, this message translates to:
  /// **'Installing...'**
  String get downloadStatus_installing;

  /// No description provided for @downloadStatus_waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting...'**
  String get downloadStatus_waiting;

  /// No description provided for @downloadStatus_complete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get downloadStatus_complete;

  /// No description provided for @downloadStatus_cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get downloadStatus_cancelled;

  /// No description provided for @downloadStatus_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get downloadStatus_failed;

  /// No description provided for @downloadStatus_paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get downloadStatus_paused;

  /// No description provided for @downloadStatus_awaitingAuthorization.
  ///
  /// In en, this message translates to:
  /// **'Reconnect in Sources'**
  String get downloadStatus_awaitingAuthorization;

  /// No description provided for @downloadStatus_verifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying...'**
  String get downloadStatus_verifying;

  /// No description provided for @downloadStatus_publishing.
  ///
  /// In en, this message translates to:
  /// **'Finishing installation...'**
  String get downloadStatus_publishing;

  /// No description provided for @storage_free.
  ///
  /// In en, this message translates to:
  /// **'{size} free'**
  String storage_free(String size);

  /// No description provided for @storage_veryLow.
  ///
  /// In en, this message translates to:
  /// **'Very low storage: {freeSpace}'**
  String storage_veryLow(String freeSpace);

  /// No description provided for @storage_gettingLow.
  ///
  /// In en, this message translates to:
  /// **'Storage getting low: {freeSpace}'**
  String storage_gettingLow(String freeSpace);

  /// No description provided for @sync_progress.
  ///
  /// In en, this message translates to:
  /// **'Syncing {completed}/{total}'**
  String sync_progress(int completed, int total);

  /// No description provided for @sync_singleSystemFailed.
  ///
  /// In en, this message translates to:
  /// **'{system} sync failed'**
  String sync_singleSystemFailed(String system);

  /// No description provided for @sync_multipleSystemsFailed.
  ///
  /// In en, this message translates to:
  /// **'{count} systems failed to sync'**
  String sync_multipleSystemsFailed(int count);

  /// No description provided for @sync_raProgress.
  ///
  /// In en, this message translates to:
  /// **'Achievements {completed}/{total}'**
  String sync_raProgress(int completed, int total);

  /// No description provided for @sync_raFailed.
  ///
  /// In en, this message translates to:
  /// **'RA sync failed'**
  String get sync_raFailed;

  /// No description provided for @toast_addedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get toast_addedToQueue;

  /// No description provided for @toast_configRecovered.
  ///
  /// In en, this message translates to:
  /// **'Config recovered from backup'**
  String get toast_configRecovered;

  /// No description provided for @gameCard_variantCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 variant} other{{count} variants}}'**
  String gameCard_variantCount(int count);

  /// No description provided for @gameDetail_achievements.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get gameDetail_achievements;

  /// No description provided for @gameDetail_mastered.
  ///
  /// In en, this message translates to:
  /// **'MASTERED'**
  String get gameDetail_mastered;

  /// No description provided for @gameDetail_noAchievementsFound.
  ///
  /// In en, this message translates to:
  /// **'No achievements found'**
  String get gameDetail_noAchievementsFound;

  /// No description provided for @gameDetail_retroachievements.
  ///
  /// In en, this message translates to:
  /// **'RETROACHIEVEMENTS'**
  String get gameDetail_retroachievements;

  /// No description provided for @gameDetail_romVerified.
  ///
  /// In en, this message translates to:
  /// **'ROM Verified'**
  String get gameDetail_romVerified;

  /// No description provided for @gameDetail_incompatibleRom.
  ///
  /// In en, this message translates to:
  /// **'Incompatible ROM'**
  String get gameDetail_incompatibleRom;

  /// No description provided for @gameDetail_gameHasAchievements.
  ///
  /// In en, this message translates to:
  /// **'Game Has Achievements'**
  String get gameDetail_gameHasAchievements;

  /// No description provided for @gameDetail_viewAchievements.
  ///
  /// In en, this message translates to:
  /// **'View Achievements'**
  String get gameDetail_viewAchievements;

  /// No description provided for @gameDetail_versions.
  ///
  /// In en, this message translates to:
  /// **'VERSIONS'**
  String get gameDetail_versions;

  /// No description provided for @gameDetail_download.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOAD'**
  String get gameDetail_download;

  /// No description provided for @gameDetail_open.
  ///
  /// In en, this message translates to:
  /// **'OPEN'**
  String get gameDetail_open;

  /// No description provided for @gameDetail_pressAOpen.
  ///
  /// In en, this message translates to:
  /// **'Press A to open'**
  String get gameDetail_pressAOpen;

  /// No description provided for @gameDetail_adding.
  ///
  /// In en, this message translates to:
  /// **'ADDING...'**
  String get gameDetail_adding;

  /// No description provided for @gameDetail_queued.
  ///
  /// In en, this message translates to:
  /// **'QUEUED'**
  String get gameDetail_queued;

  /// No description provided for @gameDetail_extracting.
  ///
  /// In en, this message translates to:
  /// **'EXTRACTING...'**
  String get gameDetail_extracting;

  /// No description provided for @gameDetail_delete.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get gameDetail_delete;

  /// No description provided for @gameDetail_manageFiles.
  ///
  /// In en, this message translates to:
  /// **'MANAGE FILES'**
  String get gameDetail_manageFiles;

  /// No description provided for @gameDetail_unavailable.
  ///
  /// In en, this message translates to:
  /// **'UNAVAILABLE'**
  String get gameDetail_unavailable;

  /// No description provided for @gameDetail_installedLabel.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get gameDetail_installedLabel;

  /// No description provided for @gameDetail_notFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get gameDetail_notFound;

  /// No description provided for @gameDetail_details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get gameDetail_details;

  /// No description provided for @gameDetail_screenshots.
  ///
  /// In en, this message translates to:
  /// **'Screenshots'**
  String get gameDetail_screenshots;

  /// No description provided for @gameDetail_otherVersions.
  ///
  /// In en, this message translates to:
  /// **'Other Versions'**
  String get gameDetail_otherVersions;

  /// No description provided for @gameDetail_readMore.
  ///
  /// In en, this message translates to:
  /// **'Read more...'**
  String get gameDetail_readMore;

  /// No description provided for @gameDetail_showLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get gameDetail_showLess;

  /// No description provided for @gameDetail_standard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get gameDetail_standard;

  /// No description provided for @gameDetail_franchise.
  ///
  /// In en, this message translates to:
  /// **'Franchise'**
  String get gameDetail_franchise;

  /// No description provided for @gameDetail_gameModes.
  ///
  /// In en, this message translates to:
  /// **'Game Modes'**
  String get gameDetail_gameModes;

  /// No description provided for @gameDetail_perspective.
  ///
  /// In en, this message translates to:
  /// **'Perspective'**
  String get gameDetail_perspective;

  /// No description provided for @gameDetail_ageRating.
  ///
  /// In en, this message translates to:
  /// **'Age Rating'**
  String get gameDetail_ageRating;

  /// No description provided for @gameDetail_themes.
  ///
  /// In en, this message translates to:
  /// **'Themes'**
  String get gameDetail_themes;

  /// No description provided for @gameDetail_fileTags.
  ///
  /// In en, this message translates to:
  /// **'FILE TAGS'**
  String get gameDetail_fileTags;

  /// No description provided for @gameDetail_tagVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get gameDetail_tagVersion;

  /// No description provided for @gameDetail_tagBuild.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get gameDetail_tagBuild;

  /// No description provided for @gameDetail_tagDisc.
  ///
  /// In en, this message translates to:
  /// **'Disc'**
  String get gameDetail_tagDisc;

  /// No description provided for @gameDetail_tagQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get gameDetail_tagQuality;

  /// No description provided for @gameDetail_tagInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get gameDetail_tagInfo;

  /// No description provided for @gameDetail_tagTechnical.
  ///
  /// In en, this message translates to:
  /// **'Technical'**
  String get gameDetail_tagTechnical;

  /// No description provided for @gameDetail_gameInfo.
  ///
  /// In en, this message translates to:
  /// **'Game Info'**
  String get gameDetail_gameInfo;

  /// No description provided for @gameDetail_showTitle.
  ///
  /// In en, this message translates to:
  /// **'Show Title'**
  String get gameDetail_showTitle;

  /// No description provided for @gameDetail_showFilename.
  ///
  /// In en, this message translates to:
  /// **'Show Filename'**
  String get gameDetail_showFilename;

  /// No description provided for @gameDetail_fromProvider.
  ///
  /// In en, this message translates to:
  /// **'from {provider}'**
  String gameDetail_fromProvider(String provider);

  /// No description provided for @gameDetail_addToShelf.
  ///
  /// In en, this message translates to:
  /// **'Add to Shelf'**
  String get gameDetail_addToShelf;

  /// No description provided for @gameDetail_removeFromShelf.
  ///
  /// In en, this message translates to:
  /// **'Remove from Shelf'**
  String get gameDetail_removeFromShelf;

  /// No description provided for @gameDetail_removeFromShelfTitle.
  ///
  /// In en, this message translates to:
  /// **'REMOVE FROM SHELF'**
  String get gameDetail_removeFromShelfTitle;

  /// No description provided for @gameDetail_gameNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Game is not installed'**
  String get gameDetail_gameNotInstalled;

  /// No description provided for @gameDetail_couldNotShare.
  ///
  /// In en, this message translates to:
  /// **'Could not share game file'**
  String get gameDetail_couldNotShare;

  /// No description provided for @gameDetail_pressAPickVersion.
  ///
  /// In en, this message translates to:
  /// **'Press A to pick a version'**
  String get gameDetail_pressAPickVersion;

  /// No description provided for @gameDetail_pressAManage.
  ///
  /// In en, this message translates to:
  /// **'Press A to manage'**
  String get gameDetail_pressAManage;

  /// No description provided for @gameDetail_pressADownload.
  ///
  /// In en, this message translates to:
  /// **'Press A to download'**
  String get gameDetail_pressADownload;

  /// No description provided for @gameDetail_errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String gameDetail_errorPrefix(String error);

  /// No description provided for @settings_title.
  ///
  /// In en, this message translates to:
  /// **'SETTINGS'**
  String get settings_title;

  /// No description provided for @settings_tabGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settings_tabGeneral;

  /// No description provided for @settings_tabAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get settings_tabAudio;

  /// No description provided for @settings_tabAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settings_tabAdvanced;

  /// No description provided for @settings_tabAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settings_tabAbout;

  /// No description provided for @settings_previousTab.
  ///
  /// In en, this message translates to:
  /// **'Previous Tab'**
  String get settings_previousTab;

  /// No description provided for @settings_nextTab.
  ///
  /// In en, this message translates to:
  /// **'Next Tab'**
  String get settings_nextTab;

  /// No description provided for @settings_resetApp.
  ///
  /// In en, this message translates to:
  /// **'Reset App'**
  String get settings_resetApp;

  /// No description provided for @settings_resetDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'RESET APPLICATION'**
  String get settings_resetDialogTitle;

  /// No description provided for @settings_resetDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'This will delete all settings and restart the setup.'**
  String get settings_resetDialogMessage;

  /// No description provided for @settings_resetDialogConfirm.
  ///
  /// In en, this message translates to:
  /// **'RESET'**
  String get settings_resetDialogConfirm;

  /// No description provided for @settings_resetDialogCancel.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get settings_resetDialogCancel;

  /// No description provided for @settings_sectionLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get settings_sectionLibrary;

  /// No description provided for @settings_sectionDisplay.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get settings_sectionDisplay;

  /// No description provided for @settings_mySources.
  ///
  /// In en, this message translates to:
  /// **'My Sources'**
  String get settings_mySources;

  /// No description provided for @settings_mySourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage your Google Drive collection'**
  String get settings_mySourcesSubtitle;

  /// No description provided for @settings_consoleSettings.
  ///
  /// In en, this message translates to:
  /// **'Console Settings'**
  String get settings_consoleSettings;

  /// No description provided for @settings_consoleSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Folder paths, extraction, per-system options'**
  String get settings_consoleSettingsSubtitle;

  /// No description provided for @settings_retroAchievements.
  ///
  /// In en, this message translates to:
  /// **'RetroAchievements'**
  String get settings_retroAchievements;

  /// No description provided for @settings_retroAchievementsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Achievement tracking and ROM verification'**
  String get settings_retroAchievementsSubtitle;

  /// No description provided for @settings_homeLayout.
  ///
  /// In en, this message translates to:
  /// **'Home Layout'**
  String get settings_homeLayout;

  /// No description provided for @settings_homeLayoutGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid View'**
  String get settings_homeLayoutGrid;

  /// No description provided for @settings_homeLayoutCarousel.
  ///
  /// In en, this message translates to:
  /// **'Horizontal Carousel'**
  String get settings_homeLayoutCarousel;

  /// No description provided for @settings_hideEmptyConsoles.
  ///
  /// In en, this message translates to:
  /// **'Hide Empty Consoles'**
  String get settings_hideEmptyConsoles;

  /// No description provided for @settings_hideEmptyConsolesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only show systems that have games'**
  String get settings_hideEmptyConsolesSubtitle;

  /// No description provided for @settings_controllerButtons.
  ///
  /// In en, this message translates to:
  /// **'Controller Buttons'**
  String get settings_controllerButtons;

  /// No description provided for @settings_controllerNintendo.
  ///
  /// In en, this message translates to:
  /// **'Nintendo (default)'**
  String get settings_controllerNintendo;

  /// No description provided for @settings_controllerXbox.
  ///
  /// In en, this message translates to:
  /// **'XBOX'**
  String get settings_controllerXbox;

  /// No description provided for @settings_controllerPs.
  ///
  /// In en, this message translates to:
  /// **'PS'**
  String get settings_controllerPs;

  /// No description provided for @settings_controllerNin.
  ///
  /// In en, this message translates to:
  /// **'NIN'**
  String get settings_controllerNin;

  /// No description provided for @settings_sectionFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get settings_sectionFeedback;

  /// No description provided for @settings_vibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get settings_vibration;

  /// No description provided for @settings_vibrationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vibrate on button presses'**
  String get settings_vibrationSubtitle;

  /// No description provided for @settings_soundEffects.
  ///
  /// In en, this message translates to:
  /// **'Sound Effects'**
  String get settings_soundEffects;

  /// No description provided for @settings_soundEffectsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play sounds for menu actions'**
  String get settings_soundEffectsSubtitle;

  /// No description provided for @settings_sectionVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get settings_sectionVolume;

  /// No description provided for @settings_music.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get settings_music;

  /// No description provided for @settings_musicSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ambient background music'**
  String get settings_musicSubtitle;

  /// No description provided for @settings_effects.
  ///
  /// In en, this message translates to:
  /// **'Effects'**
  String get settings_effects;

  /// No description provided for @settings_effectsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Interface sound effects'**
  String get settings_effectsSubtitle;

  /// No description provided for @settings_sectionDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get settings_sectionDownloads;

  /// No description provided for @settings_simultaneousDownloads.
  ///
  /// In en, this message translates to:
  /// **'Simultaneous Downloads'**
  String get settings_simultaneousDownloads;

  /// No description provided for @settings_simultaneousDownloadsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How many files download at once'**
  String get settings_simultaneousDownloadsSubtitle;

  /// No description provided for @settings_downloadAllCovers.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOAD ALL COVERS'**
  String get settings_downloadAllCovers;

  /// No description provided for @settings_downloadingCovers.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOADING COVERS...'**
  String get settings_downloadingCovers;

  /// No description provided for @settings_sectionSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get settings_sectionSync;

  /// No description provided for @settings_syncTimeout.
  ///
  /// In en, this message translates to:
  /// **'Sync Timeout'**
  String get settings_syncTimeout;

  /// No description provided for @settings_syncTimeoutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How long to wait for each server'**
  String get settings_syncTimeoutSubtitle;

  /// No description provided for @settings_autoSyncInterval.
  ///
  /// In en, this message translates to:
  /// **'Auto-Sync Interval'**
  String get settings_autoSyncInterval;

  /// No description provided for @settings_autoSyncIntervalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Minimum time between automatic syncs'**
  String get settings_autoSyncIntervalSubtitle;

  /// No description provided for @settings_sectionDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get settings_sectionDebug;

  /// No description provided for @settings_allowInsecure.
  ///
  /// In en, this message translates to:
  /// **'Allow Insecure Connections'**
  String get settings_allowInsecure;

  /// No description provided for @settings_allowInsecureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable HTTP for servers without HTTPS'**
  String get settings_allowInsecureSubtitle;

  /// No description provided for @settings_exportErrorLog.
  ///
  /// In en, this message translates to:
  /// **'Export Error Log'**
  String get settings_exportErrorLog;

  /// No description provided for @settings_exportErrorLogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share crash log for troubleshooting'**
  String get settings_exportErrorLogSubtitle;

  /// No description provided for @settings_sectionInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get settings_sectionInfo;

  /// No description provided for @settings_sectionLinks.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get settings_sectionLinks;

  /// No description provided for @settings_github.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get settings_github;

  /// No description provided for @settings_githubSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View source code on GitHub'**
  String get settings_githubSubtitle;

  /// No description provided for @settings_issues.
  ///
  /// In en, this message translates to:
  /// **'Issues'**
  String get settings_issues;

  /// No description provided for @settings_issuesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Report bugs or request features'**
  String get settings_issuesSubtitle;

  /// No description provided for @settings_tagline.
  ///
  /// In en, this message translates to:
  /// **'INTENSIV, AGGRESSIV, MUTIG'**
  String get settings_tagline;

  /// No description provided for @settings_deviceMemoryLow.
  ///
  /// In en, this message translates to:
  /// **'LOW'**
  String get settings_deviceMemoryLow;

  /// No description provided for @settings_deviceMemoryStandard.
  ///
  /// In en, this message translates to:
  /// **'STANDARD'**
  String get settings_deviceMemoryStandard;

  /// No description provided for @settings_deviceMemoryHigh.
  ///
  /// In en, this message translates to:
  /// **'HIGH'**
  String get settings_deviceMemoryHigh;

  /// No description provided for @settings_fetchingCovers.
  ///
  /// In en, this message translates to:
  /// **'Fetching covers...'**
  String get settings_fetchingCovers;

  /// No description provided for @settings_coversResult.
  ///
  /// In en, this message translates to:
  /// **'Covers: {ok} ok, {failed} failed'**
  String settings_coversResult(int ok, int failed);

  /// No description provided for @settings_coversLoaded.
  ///
  /// In en, this message translates to:
  /// **'{count} covers loaded!'**
  String settings_coversLoaded(int count);

  /// No description provided for @settings_noErrorLog.
  ///
  /// In en, this message translates to:
  /// **'No error log available'**
  String get settings_noErrorLog;

  /// No description provided for @settings_configImported.
  ///
  /// In en, this message translates to:
  /// **'Config imported!'**
  String get settings_configImported;

  /// No description provided for @settings_controllerXboxFull.
  ///
  /// In en, this message translates to:
  /// **'Xbox (A/B & X/Y swapped)'**
  String get settings_controllerXboxFull;

  /// No description provided for @settings_controllerPlaystationFull.
  ///
  /// In en, this message translates to:
  /// **'PlayStation (✕ ○ □ △)'**
  String get settings_controllerPlaystationFull;

  /// No description provided for @settings_allCoversCached.
  ///
  /// In en, this message translates to:
  /// **'All covers cached'**
  String get settings_allCoversCached;

  /// No description provided for @settings_downloadCoverArt.
  ///
  /// In en, this message translates to:
  /// **'Download cover art for all games'**
  String get settings_downloadCoverArt;

  /// No description provided for @settings_coverCacheInfo.
  ///
  /// In en, this message translates to:
  /// **'{size} ({count} cached)'**
  String settings_coverCacheInfo(String size, int count);

  /// No description provided for @settings_coversRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} remaining (~{size} MB)'**
  String settings_coversRemaining(int count, String size);

  /// No description provided for @settings_coversProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed} / {total} games'**
  String settings_coversProgress(int completed, int total);

  /// No description provided for @configMode_title.
  ///
  /// In en, this message translates to:
  /// **'CONSOLE SETTINGS'**
  String get configMode_title;

  /// No description provided for @configMode_globalTitle.
  ///
  /// In en, this message translates to:
  /// **'GLOBAL SETTINGS'**
  String get configMode_globalTitle;

  /// No description provided for @configMode_noFolderSet.
  ///
  /// In en, this message translates to:
  /// **'No folder set'**
  String get configMode_noFolderSet;

  /// No description provided for @configMode_notConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get configMode_notConfigured;

  /// No description provided for @configMode_export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get configMode_export;

  /// No description provided for @configMode_import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get configMode_import;

  /// No description provided for @systemDetail_sectionStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get systemDetail_sectionStorage;

  /// No description provided for @systemDetail_selectRomFolder.
  ///
  /// In en, this message translates to:
  /// **'Select ROM folder'**
  String get systemDetail_selectRomFolder;

  /// No description provided for @systemDetail_tapToChangeFolder.
  ///
  /// In en, this message translates to:
  /// **'Tap to change folder'**
  String get systemDetail_tapToChangeFolder;

  /// No description provided for @systemDetail_sectionBehavior.
  ///
  /// In en, this message translates to:
  /// **'Behavior'**
  String get systemDetail_sectionBehavior;

  /// No description provided for @systemDetail_autoExtractZips.
  ///
  /// In en, this message translates to:
  /// **'Auto-Extract ZIPs'**
  String get systemDetail_autoExtractZips;

  /// No description provided for @systemDetail_autoExtractEnabled.
  ///
  /// In en, this message translates to:
  /// **'Zipped ROMs are extracted after download'**
  String get systemDetail_autoExtractEnabled;

  /// No description provided for @systemDetail_autoExtractDisabled.
  ///
  /// In en, this message translates to:
  /// **'ROMs stay zipped after download'**
  String get systemDetail_autoExtractDisabled;

  /// No description provided for @systemDetail_autoSyncOnLaunch.
  ///
  /// In en, this message translates to:
  /// **'Auto-Sync on Launch'**
  String get systemDetail_autoSyncOnLaunch;

  /// No description provided for @systemDetail_autoSyncEnabled.
  ///
  /// In en, this message translates to:
  /// **'Syncs automatically (respects cooldown)'**
  String get systemDetail_autoSyncEnabled;

  /// No description provided for @systemDetail_autoSyncDisabled.
  ///
  /// In en, this message translates to:
  /// **'Only syncs manually via Start menu'**
  String get systemDetail_autoSyncDisabled;

  /// No description provided for @systemDetail_sectionSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get systemDetail_sectionSources;

  /// No description provided for @sources_title.
  ///
  /// In en, this message translates to:
  /// **'SOURCES'**
  String get sources_title;

  /// No description provided for @sources_refreshCatalogue.
  ///
  /// In en, this message translates to:
  /// **'Refresh catalogue'**
  String get sources_refreshCatalogue;

  /// No description provided for @sources_configureDrive.
  ///
  /// In en, this message translates to:
  /// **'Connect / configure'**
  String get sources_configureDrive;

  /// No description provided for @sources_disconnectDrive.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Google Drive (all Drive sources)'**
  String get sources_disconnectDrive;

  /// No description provided for @sources_revokeDrive.
  ///
  /// In en, this message translates to:
  /// **'Revoke Google Drive access (all Drive sources)'**
  String get sources_revokeDrive;

  /// No description provided for @sources_noSourcesConfigured.
  ///
  /// In en, this message translates to:
  /// **'No sources configured'**
  String get sources_noSourcesConfigured;

  /// No description provided for @sources_noSourcesYet.
  ///
  /// In en, this message translates to:
  /// **'No sources yet'**
  String get sources_noSourcesYet;

  /// No description provided for @sources_addSource.
  ///
  /// In en, this message translates to:
  /// **'Add source'**
  String get sources_addSource;

  /// No description provided for @sources_whereDoGamesComeFrom.
  ///
  /// In en, this message translates to:
  /// **'Where do your games come from?'**
  String get sources_whereDoGamesComeFrom;

  /// No description provided for @sources_expired.
  ///
  /// In en, this message translates to:
  /// **'EXPIRED'**
  String get sources_expired;

  /// No description provided for @sources_borrowed.
  ///
  /// In en, this message translates to:
  /// **'BORROWED'**
  String get sources_borrowed;

  /// No description provided for @sources_off.
  ///
  /// In en, this message translates to:
  /// **'OFF'**
  String get sources_off;

  /// No description provided for @sources_noPlatforms.
  ///
  /// In en, this message translates to:
  /// **'No platforms'**
  String get sources_noPlatforms;

  /// No description provided for @sources_rePair.
  ///
  /// In en, this message translates to:
  /// **'Re-pair'**
  String get sources_rePair;

  /// No description provided for @sources_editMappings.
  ///
  /// In en, this message translates to:
  /// **'Edit mappings'**
  String get sources_editMappings;

  /// No description provided for @sources_disable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get sources_disable;

  /// No description provided for @sources_enable.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get sources_enable;

  /// No description provided for @sourceMappings_title.
  ///
  /// In en, this message translates to:
  /// **'System mappings'**
  String get sourceMappings_title;

  /// No description provided for @sourceMappings_instruction.
  ///
  /// In en, this message translates to:
  /// **'Enter the remote folder for each system you want this source to serve. Leave empty to skip.'**
  String get sourceMappings_instruction;

  /// No description provided for @sourceMappings_save.
  ///
  /// In en, this message translates to:
  /// **'Save mappings'**
  String get sourceMappings_save;

  /// No description provided for @library_title.
  ///
  /// In en, this message translates to:
  /// **'LIBRARY'**
  String get library_title;

  /// No description provided for @library_tabAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get library_tabAll;

  /// No description provided for @library_tabInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get library_tabInstalled;

  /// No description provided for @library_tabFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get library_tabFavorites;

  /// No description provided for @library_sortSystem.
  ///
  /// In en, this message translates to:
  /// **'Sort by System'**
  String get library_sortSystem;

  /// No description provided for @library_sortManual.
  ///
  /// In en, this message translates to:
  /// **'Sort Manual'**
  String get library_sortManual;

  /// No description provided for @library_sortAZ.
  ///
  /// In en, this message translates to:
  /// **'Sort A-Z'**
  String get library_sortAZ;

  /// No description provided for @library_sortIndicatorAZ.
  ///
  /// In en, this message translates to:
  /// **'A-Z'**
  String get library_sortIndicatorAZ;

  /// No description provided for @library_sortIndicatorBySystem.
  ///
  /// In en, this message translates to:
  /// **'BY SYSTEM'**
  String get library_sortIndicatorBySystem;

  /// No description provided for @library_sortIndicatorManual.
  ///
  /// In en, this message translates to:
  /// **'MANUAL'**
  String get library_sortIndicatorManual;

  /// No description provided for @library_searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search library...'**
  String get library_searchHint;

  /// No description provided for @library_zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom In'**
  String get library_zoomIn;

  /// No description provided for @library_zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom Out'**
  String get library_zoomOut;

  /// No description provided for @library_newShelf.
  ///
  /// In en, this message translates to:
  /// **'New Shelf'**
  String get library_newShelf;

  /// No description provided for @library_editShelf.
  ///
  /// In en, this message translates to:
  /// **'Edit Shelf'**
  String get library_editShelf;

  /// No description provided for @library_addToShelf.
  ///
  /// In en, this message translates to:
  /// **'Add to Shelf'**
  String get library_addToShelf;

  /// No description provided for @library_removeFromShelf.
  ///
  /// In en, this message translates to:
  /// **'Remove from Shelf'**
  String get library_removeFromShelf;

  /// No description provided for @library_reorderGames.
  ///
  /// In en, this message translates to:
  /// **'Reorder Games'**
  String get library_reorderGames;

  /// No description provided for @library_noResults.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String library_noResults(String query);

  /// No description provided for @library_tryShorterSearch.
  ///
  /// In en, this message translates to:
  /// **'Try a shorter search term'**
  String get library_tryShorterSearch;

  /// No description provided for @library_noInstalledGames.
  ///
  /// In en, this message translates to:
  /// **'No installed games'**
  String get library_noInstalledGames;

  /// No description provided for @library_downloadGamesToSee.
  ///
  /// In en, this message translates to:
  /// **'Download games to see them here'**
  String get library_downloadGamesToSee;

  /// No description provided for @library_noFavoritesYet.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get library_noFavoritesYet;

  /// No description provided for @library_pressFavoriteHint.
  ///
  /// In en, this message translates to:
  /// **'Press SELECT on a game to favorite it'**
  String get library_pressFavoriteHint;

  /// No description provided for @library_noGamesInShelf.
  ///
  /// In en, this message translates to:
  /// **'No games in this shelf'**
  String get library_noGamesInShelf;

  /// No description provided for @library_addGamesViaEditor.
  ///
  /// In en, this message translates to:
  /// **'Add games via the shelf editor'**
  String get library_addGamesViaEditor;

  /// No description provided for @library_noGamesInLibrary.
  ///
  /// In en, this message translates to:
  /// **'No games in library'**
  String get library_noGamesInLibrary;

  /// No description provided for @library_gamesAfterSync.
  ///
  /// In en, this message translates to:
  /// **'Games will appear after sync completes'**
  String get library_gamesAfterSync;

  /// No description provided for @shelfEdit_title.
  ///
  /// In en, this message translates to:
  /// **'EDIT SHELF'**
  String get shelfEdit_title;

  /// No description provided for @shelfEdit_titleNew.
  ///
  /// In en, this message translates to:
  /// **'NEW SHELF'**
  String get shelfEdit_titleNew;

  /// No description provided for @shelfEdit_nameSection.
  ///
  /// In en, this message translates to:
  /// **'NAME'**
  String get shelfEdit_nameSection;

  /// No description provided for @shelfEdit_shelfName.
  ///
  /// In en, this message translates to:
  /// **'Shelf Name'**
  String get shelfEdit_shelfName;

  /// No description provided for @shelfEdit_filterText.
  ///
  /// In en, this message translates to:
  /// **'Filter Text'**
  String get shelfEdit_filterText;

  /// No description provided for @shelfEdit_tapToSet.
  ///
  /// In en, this message translates to:
  /// **'Tap to set...'**
  String get shelfEdit_tapToSet;

  /// No description provided for @shelfEdit_filterRules.
  ///
  /// In en, this message translates to:
  /// **'FILTER RULES'**
  String get shelfEdit_filterRules;

  /// No description provided for @shelfEdit_resetManualOrder.
  ///
  /// In en, this message translates to:
  /// **'Reset Manual Order'**
  String get shelfEdit_resetManualOrder;

  /// No description provided for @shelfEdit_saveButton.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get shelfEdit_saveButton;

  /// No description provided for @shelfEdit_deleteShelf.
  ///
  /// In en, this message translates to:
  /// **'DELETE SHELF'**
  String get shelfEdit_deleteShelf;

  /// No description provided for @shelfEdit_anyText.
  ///
  /// In en, this message translates to:
  /// **'Any text'**
  String get shelfEdit_anyText;

  /// No description provided for @shelfEdit_allSystems.
  ///
  /// In en, this message translates to:
  /// **'All systems'**
  String get shelfEdit_allSystems;

  /// No description provided for @shelfPicker_title.
  ///
  /// In en, this message translates to:
  /// **'ADD TO SHELF'**
  String get shelfPicker_title;

  /// No description provided for @systemSelector_title.
  ///
  /// In en, this message translates to:
  /// **'SELECT SYSTEMS'**
  String get systemSelector_title;

  /// No description provided for @textInput_hint.
  ///
  /// In en, this message translates to:
  /// **'Enter text...'**
  String get textInput_hint;

  /// No description provided for @textInput_ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get textInput_ok;

  /// No description provided for @gameListOverlay_hiddenGames.
  ///
  /// In en, this message translates to:
  /// **'HIDDEN GAMES'**
  String get gameListOverlay_hiddenGames;

  /// No description provided for @gameListOverlay_addedGames.
  ///
  /// In en, this message translates to:
  /// **'ADDED GAMES'**
  String get gameListOverlay_addedGames;

  /// No description provided for @gameListOverlay_restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get gameListOverlay_restore;

  /// No description provided for @gameListOverlay_noGames.
  ///
  /// In en, this message translates to:
  /// **'No games'**
  String get gameListOverlay_noGames;

  /// No description provided for @gameListOverlay_clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get gameListOverlay_clearAll;

  /// No description provided for @home_allGames.
  ///
  /// In en, this message translates to:
  /// **'ALL GAMES'**
  String get home_allGames;

  /// No description provided for @home_library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get home_library;

  /// No description provided for @home_noConsoles.
  ///
  /// In en, this message translates to:
  /// **'No consoles configured'**
  String get home_noConsoles;

  /// No description provided for @home_pressStartForMenu.
  ///
  /// In en, this message translates to:
  /// **'Press Start for Menu'**
  String get home_pressStartForMenu;

  /// No description provided for @home_settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get home_settings;

  /// No description provided for @home_syncSystem.
  ///
  /// In en, this message translates to:
  /// **'Sync {system}'**
  String home_syncSystem(String system);

  /// No description provided for @home_syncAll.
  ///
  /// In en, this message translates to:
  /// **'Sync All'**
  String get home_syncAll;

  /// No description provided for @home_lastSyncNever.
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get home_lastSyncNever;

  /// No description provided for @home_lastSyncJustNow.
  ///
  /// In en, this message translates to:
  /// **'Synced just now'**
  String get home_lastSyncJustNow;

  /// No description provided for @home_lastSyncMinutes.
  ///
  /// In en, this message translates to:
  /// **'Synced {minutes}min ago'**
  String home_lastSyncMinutes(int minutes);

  /// No description provided for @home_lastSyncHours.
  ///
  /// In en, this message translates to:
  /// **'Synced {hours}h ago'**
  String home_lastSyncHours(int hours);

  /// No description provided for @home_lastSyncDays.
  ///
  /// In en, this message translates to:
  /// **'Synced {days}d ago'**
  String home_lastSyncDays(int days);

  /// No description provided for @common_exit.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get common_exit;

  /// No description provided for @gameList_gamesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Games'**
  String gameList_gamesCount(int count);

  /// No description provided for @gameList_offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get gameList_offline;

  /// No description provided for @gameList_zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom In'**
  String get gameList_zoomIn;

  /// No description provided for @gameList_zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom Out'**
  String get gameList_zoomOut;

  /// No description provided for @gameList_filterActive.
  ///
  /// In en, this message translates to:
  /// **'Filter (active)'**
  String get gameList_filterActive;

  /// No description provided for @gameList_filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get gameList_filter;

  /// No description provided for @gameList_noGamesMatchSearch.
  ///
  /// In en, this message translates to:
  /// **'No games match \'{query}\''**
  String gameList_noGamesMatchSearch(String query);

  /// No description provided for @gameList_tryShorterSearch.
  ///
  /// In en, this message translates to:
  /// **'Try a shorter search term'**
  String get gameList_tryShorterSearch;

  /// No description provided for @gameList_noGamesMatchFilters.
  ///
  /// In en, this message translates to:
  /// **'No games match current filters'**
  String get gameList_noGamesMatchFilters;

  /// No description provided for @gameList_changeFilters.
  ///
  /// In en, this message translates to:
  /// **'Change or reset filters in the menu'**
  String get gameList_changeFilters;

  /// No description provided for @gameList_noRomsFound.
  ///
  /// In en, this message translates to:
  /// **'No ROMs found in {folder}'**
  String gameList_noRomsFound(String folder);

  /// No description provided for @gameList_addRomFiles.
  ///
  /// In en, this message translates to:
  /// **'Add ROM files to this folder and refresh'**
  String get gameList_addRomFiles;

  /// No description provided for @gameList_couldNotLoadGames.
  ///
  /// In en, this message translates to:
  /// **'Could not load games'**
  String get gameList_couldNotLoadGames;

  /// No description provided for @gameList_checkConnection.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again'**
  String get gameList_checkConnection;

  /// No description provided for @gameList_errorLoadingGames.
  ///
  /// In en, this message translates to:
  /// **'Error loading games'**
  String get gameList_errorLoadingGames;

  /// No description provided for @gameList_gamesAppearShortly.
  ///
  /// In en, this message translates to:
  /// **'Games will appear shortly'**
  String get gameList_gamesAppearShortly;

  /// No description provided for @gameList_syncingLibrary.
  ///
  /// In en, this message translates to:
  /// **'Syncing library…'**
  String get gameList_syncingLibrary;

  /// No description provided for @gameList_localFilesOnly.
  ///
  /// In en, this message translates to:
  /// **'Local files only · Add a provider to download more'**
  String get gameList_localFilesOnly;

  /// No description provided for @gameList_pressMenuHint.
  ///
  /// In en, this message translates to:
  /// **'Press  +  for menu'**
  String get gameList_pressMenuHint;

  /// No description provided for @filter_activeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String filter_activeCount(int count);

  /// No description provided for @shelfEdit_addFilter.
  ///
  /// In en, this message translates to:
  /// **'+ ADD FILTER'**
  String get shelfEdit_addFilter;

  /// No description provided for @shelfEdit_hiddenGamesCount.
  ///
  /// In en, this message translates to:
  /// **'Hidden Games ({count})'**
  String shelfEdit_hiddenGamesCount(int count);

  /// No description provided for @shelfEdit_addedGamesCount.
  ///
  /// In en, this message translates to:
  /// **'Added Games ({count})'**
  String shelfEdit_addedGamesCount(int count);

  /// No description provided for @shelfEdit_textHint.
  ///
  /// In en, this message translates to:
  /// **'← Text  Sys →'**
  String get shelfEdit_textHint;

  /// No description provided for @gameListOverlay_gameCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 game} other{{count} games}}'**
  String gameListOverlay_gameCount(int count);

  /// No description provided for @gameListOverlay_actionHint.
  ///
  /// In en, this message translates to:
  /// **'A: {action}'**
  String gameListOverlay_actionHint(String action);

  /// No description provided for @systemSelector_selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String systemSelector_selectedCount(int count);

  /// No description provided for @filter_favoritesOnly.
  ///
  /// In en, this message translates to:
  /// **'Favorites Only'**
  String get filter_favoritesOnly;

  /// No description provided for @filter_installedOnly.
  ///
  /// In en, this message translates to:
  /// **'Installed Only'**
  String get filter_installedOnly;

  /// No description provided for @filter_regions.
  ///
  /// In en, this message translates to:
  /// **'REGIONS'**
  String get filter_regions;

  /// No description provided for @filter_languages.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGES'**
  String get filter_languages;

  /// No description provided for @filter_title.
  ///
  /// In en, this message translates to:
  /// **'FILTER'**
  String get filter_title;

  /// No description provided for @onboarding_welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to G-Shop'**
  String get onboarding_welcomeTitle;

  /// No description provided for @onboarding_welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Where do your games come from?'**
  String get onboarding_welcomeSubtitle;

  /// No description provided for @onboarding_addServerTitle.
  ///
  /// In en, this message translates to:
  /// **'Add my own server'**
  String get onboarding_addServerTitle;

  /// No description provided for @onboarding_localOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'ROMs already on this device'**
  String get onboarding_localOnlySubtitle;

  /// No description provided for @onboarding_working.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get onboarding_working;

  /// No description provided for @onboarding_scanningFolders.
  ///
  /// In en, this message translates to:
  /// **'Scanning local ROM folders…'**
  String get onboarding_scanningFolders;

  /// No description provided for @onboarding_discoveringPlatforms.
  ///
  /// In en, this message translates to:
  /// **'Discovering platforms…'**
  String get onboarding_discoveringPlatforms;

  /// No description provided for @onboarding_savingSource.
  ///
  /// In en, this message translates to:
  /// **'Saving source…'**
  String get onboarding_savingSource;

  /// No description provided for @onboarding_allSet.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set'**
  String get onboarding_allSet;

  /// No description provided for @onboarding_noSystems.
  ///
  /// In en, this message translates to:
  /// **'No systems configured yet — you can add sources later from Settings.'**
  String get onboarding_noSystems;

  /// No description provided for @onboarding_systemsReady.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 system ready to browse} other{{count} systems ready to browse}}'**
  String onboarding_systemsReady(int count);

  /// No description provided for @onboarding_jumpIn.
  ///
  /// In en, this message translates to:
  /// **'Jump in'**
  String get onboarding_jumpIn;

  /// No description provided for @onboarding_jumpInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open the home screen and start syncing'**
  String get onboarding_jumpInSubtitle;

  /// No description provided for @onboarding_retroachievements.
  ///
  /// In en, this message translates to:
  /// **'RetroAchievements'**
  String get onboarding_retroachievements;

  /// No description provided for @onboarding_retroachievementsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track your retro gaming achievements'**
  String get onboarding_retroachievementsSubtitle;

  /// No description provided for @onboarding_exportConfig.
  ///
  /// In en, this message translates to:
  /// **'Export config'**
  String get onboarding_exportConfig;

  /// No description provided for @onboarding_exportConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Re-use this setup on another device'**
  String get onboarding_exportConfigSubtitle;

  /// No description provided for @onboarding_importConfig.
  ///
  /// In en, this message translates to:
  /// **'Import config'**
  String get onboarding_importConfig;

  /// No description provided for @onboarding_configImported.
  ///
  /// In en, this message translates to:
  /// **'Config imported!'**
  String get onboarding_configImported;

  /// No description provided for @onboarding_exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String onboarding_exportFailed(String error);

  /// No description provided for @onboarding_invalidConfig.
  ///
  /// In en, this message translates to:
  /// **'Invalid config: {error}'**
  String onboarding_invalidConfig(String error);

  /// No description provided for @onboarding_failedToSave.
  ///
  /// In en, this message translates to:
  /// **'Failed to save: {error}'**
  String onboarding_failedToSave(String error);

  /// No description provided for @onboarding_selectFolderPrompt.
  ///
  /// In en, this message translates to:
  /// **'Pick the folder where ROMs should be saved'**
  String get onboarding_selectFolderPrompt;

  /// No description provided for @onboarding_serverType.
  ///
  /// In en, this message translates to:
  /// **'Server type'**
  String get onboarding_serverType;

  /// No description provided for @onboarding_hangOn.
  ///
  /// In en, this message translates to:
  /// **'Hang on, testing the connection...'**
  String get onboarding_hangOn;

  /// No description provided for @onboarding_connectionGood.
  ///
  /// In en, this message translates to:
  /// **'Connection looks good! You\'re all set to save this source.'**
  String get onboarding_connectionGood;

  /// No description provided for @onboarding_couldNotConnect.
  ///
  /// In en, this message translates to:
  /// **'Hmm, couldn\'t connect. Double-check the address and credentials.'**
  String get onboarding_couldNotConnect;

  /// No description provided for @onboarding_whatKindOfSource.
  ///
  /// In en, this message translates to:
  /// **'What kind of source is this? Pick the connection type.'**
  String get onboarding_whatKindOfSource;

  /// No description provided for @onboarding_lookingGood.
  ///
  /// In en, this message translates to:
  /// **'Looking good! Add more sources or press Done when you\'re ready.'**
  String get onboarding_lookingGood;

  /// No description provided for @onboarding_localCollection.
  ///
  /// In en, this message translates to:
  /// **'This is a local collection. Add a source to download more, or just hit Done!'**
  String get onboarding_localCollection;

  /// No description provided for @onboarding_addMoreSources.
  ///
  /// In en, this message translates to:
  /// **'Now add at least one source so I know where to find the ROMs.'**
  String get onboarding_addMoreSources;

  /// No description provided for @onboarding_letsSetUp.
  ///
  /// In en, this message translates to:
  /// **'Let\'s set up your consoles! Select any system to get started.'**
  String get onboarding_letsSetUp;

  /// No description provided for @onboarding_romFolder.
  ///
  /// In en, this message translates to:
  /// **'ROM FOLDER'**
  String get onboarding_romFolder;

  /// No description provided for @onboarding_options.
  ///
  /// In en, this message translates to:
  /// **'OPTIONS'**
  String get onboarding_options;

  /// No description provided for @onboarding_autoExtractZips.
  ///
  /// In en, this message translates to:
  /// **'Auto-extract zipped ROMs'**
  String get onboarding_autoExtractZips;

  /// No description provided for @onboarding_autoSyncLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-sync on app launch'**
  String get onboarding_autoSyncLabel;

  /// No description provided for @onboarding_autoSyncEnabled.
  ///
  /// In en, this message translates to:
  /// **'Syncs automatically (respects cooldown)'**
  String get onboarding_autoSyncEnabled;

  /// No description provided for @onboarding_autoSyncDisabled.
  ///
  /// In en, this message translates to:
  /// **'Only syncs manually via Start menu'**
  String get onboarding_autoSyncDisabled;

  /// No description provided for @onboarding_selectFolder.
  ///
  /// In en, this message translates to:
  /// **'Select folder...'**
  String get onboarding_selectFolder;

  /// No description provided for @providerForm_username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get providerForm_username;

  /// No description provided for @providerForm_password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get providerForm_password;

  /// No description provided for @providerForm_testingConnection.
  ///
  /// In en, this message translates to:
  /// **'Testing connection...'**
  String get providerForm_testingConnection;

  /// No description provided for @ra_title.
  ///
  /// In en, this message translates to:
  /// **'RetroAchievements'**
  String get ra_title;

  /// No description provided for @ra_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Track your retro gaming achievements. '**
  String get ra_subtitle;

  /// No description provided for @ra_usernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get ra_usernameLabel;

  /// No description provided for @ra_usernameHint.
  ///
  /// In en, this message translates to:
  /// **'your RA username'**
  String get ra_usernameHint;

  /// No description provided for @ra_apiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get ra_apiKeyLabel;

  /// No description provided for @ra_apiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'paste from retroachievements.org'**
  String get ra_apiKeyHint;

  /// No description provided for @ra_usernameRequired.
  ///
  /// In en, this message translates to:
  /// **'Username is required'**
  String get ra_usernameRequired;

  /// No description provided for @ra_apiKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'API Key is required'**
  String get ra_apiKeyRequired;

  /// No description provided for @ra_connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get ra_connectionFailed;

  /// No description provided for @ra_disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get ra_disconnect;

  /// No description provided for @ra_syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync achievements now'**
  String get ra_syncNow;

  /// No description provided for @ra_skipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get ra_skipForNow;

  /// No description provided for @gameCard_cloudAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available to download'**
  String get gameCard_cloudAvailable;

  /// No description provided for @library_dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get library_dashboard;

  /// No description provided for @library_catalogueEntries.
  ///
  /// In en, this message translates to:
  /// **'Catalogue entries'**
  String get library_catalogueEntries;

  /// No description provided for @library_sourceStorage.
  ///
  /// In en, this message translates to:
  /// **'Known source size'**
  String get library_sourceStorage;

  /// No description provided for @library_managedStorage.
  ///
  /// In en, this message translates to:
  /// **'Managed local files'**
  String get library_managedStorage;

  /// No description provided for @library_sizeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get library_sizeUnknown;

  /// No description provided for @library_unknownSizes.
  ///
  /// In en, this message translates to:
  /// **'{count} source sizes unknown'**
  String library_unknownSizes(int count);

  /// No description provided for @library_dashboardNote.
  ///
  /// In en, this message translates to:
  /// **'Cached catalogue entries, not unique games. Source sizes are not SD usage; managed local bytes exclude unmanaged files, saves and BIOS.'**
  String get library_dashboardNote;

  /// No description provided for @service_notificationTitle.
  ///
  /// In en, this message translates to:
  /// **'G-Shop'**
  String get service_notificationTitle;

  /// No description provided for @service_channelName.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get service_channelName;

  /// No description provided for @service_channelDescription.
  ///
  /// In en, this message translates to:
  /// **'Shows progress while downloading games'**
  String get service_channelDescription;

  /// No description provided for @service_downloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Downloads complete'**
  String get service_downloadComplete;

  /// No description provided for @service_downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading: {details}'**
  String service_downloading(String details);

  /// No description provided for @service_activeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String service_activeCount(int count);

  /// No description provided for @service_queuedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} queued'**
  String service_queuedCount(int count);
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'de',
        'en',
        'es',
        'fr',
        'ja',
        'pt'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return LDe();
    case 'en':
      return LEn();
    case 'es':
      return LEs();
    case 'fr':
      return LFr();
    case 'ja':
      return LJa();
    case 'pt':
      return LPt();
  }

  throw FlutterError(
      'L.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
