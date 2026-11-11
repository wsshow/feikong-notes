import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @themeSettings.
  ///
  /// In zh, this message translates to:
  /// **'主题'**
  String get themeSettings;

  /// No description provided for @themeDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择喜欢的色彩与明暗外观。只改变视觉样式，保留原有布局与笔记内容。'**
  String get themeDescription;

  /// No description provided for @themePaper.
  ///
  /// In zh, this message translates to:
  /// **'素笺留白'**
  String get themePaper;

  /// No description provided for @themePaperDescription.
  ///
  /// In zh, this message translates to:
  /// **'素净纸面与石墨笔触，把纷扰安放在恰好的留白里。'**
  String get themePaperDescription;

  /// No description provided for @themeStarlight.
  ///
  /// In zh, this message translates to:
  /// **'星河入梦'**
  String get themeStarlight;

  /// No description provided for @themeStarlightDescription.
  ///
  /// In zh, this message translates to:
  /// **'薰衣草色铺开夜幕，靛蓝与微光收拢散落的思绪。'**
  String get themeStarlightDescription;

  /// No description provided for @themeSunnyGrowth.
  ///
  /// In zh, this message translates to:
  /// **'云间拾光'**
  String get themeSunnyGrowth;

  /// No description provided for @themeSunnyGrowthDescription.
  ///
  /// In zh, this message translates to:
  /// **'晴空、软云与明亮蓝意，让每一笔灵感都带着清晨的光。'**
  String get themeSunnyGrowthDescription;

  /// No description provided for @themeSunnyGrowthLightOnly.
  ///
  /// In zh, this message translates to:
  /// **'云间拾光住在晴朗的浅色时光里，目前仅提供浅色外观。切换回其他主题时，会恢复你之前的明暗偏好。'**
  String get themeSunnyGrowthLightOnly;

  /// No description provided for @themeEditorialJournal.
  ///
  /// In zh, this message translates to:
  /// **'纸短情长'**
  String get themeEditorialJournal;

  /// No description provided for @themeEditorialJournalDescription.
  ///
  /// In zh, this message translates to:
  /// **'暖象牙纸托住珊瑚与钴蓝，写下纸短情长的每一页。'**
  String get themeEditorialJournalDescription;

  /// No description provided for @themeEditorialJournalLightOnly.
  ///
  /// In zh, this message translates to:
  /// **'纸短情长以暖纸与日光为底，目前仅提供浅色外观。切换回其他主题时，会恢复你之前的明暗偏好。'**
  String get themeEditorialJournalLightOnly;

  /// No description provided for @editorialGreetingMorning.
  ///
  /// In zh, this message translates to:
  /// **'早上好，'**
  String get editorialGreetingMorning;

  /// No description provided for @editorialGreetingAfternoon.
  ///
  /// In zh, this message translates to:
  /// **'下午好，'**
  String get editorialGreetingAfternoon;

  /// No description provided for @editorialGreetingEvening.
  ///
  /// In zh, this message translates to:
  /// **'晚上好，'**
  String get editorialGreetingEvening;

  /// No description provided for @editorialGreetingQuestion.
  ///
  /// In zh, this message translates to:
  /// **'今天想记点什么？'**
  String get editorialGreetingQuestion;

  /// No description provided for @editorialSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索笔记、标签或灵感'**
  String get editorialSearchHint;

  /// No description provided for @editorialInspiration.
  ///
  /// In zh, this message translates to:
  /// **'今日灵感'**
  String get editorialInspiration;

  /// No description provided for @editorialInspirationQuote.
  ///
  /// In zh, this message translates to:
  /// **'把一闪而过的念头，留在这里。'**
  String get editorialInspirationQuote;

  /// No description provided for @editorialStartWriting.
  ///
  /// In zh, this message translates to:
  /// **'开始写作'**
  String get editorialStartWriting;

  /// No description provided for @editorialViewAll.
  ///
  /// In zh, this message translates to:
  /// **'查看全部'**
  String get editorialViewAll;

  /// No description provided for @themeBrightness.
  ///
  /// In zh, this message translates to:
  /// **'明暗外观'**
  String get themeBrightness;

  /// No description provided for @themeModeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeModeSystem;

  /// No description provided for @themeModeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeModeDark;

  /// No description provided for @themeSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'主题设置未保存，已恢复之前的外观，请重试。'**
  String get themeSaveFailed;

  /// No description provided for @iosAppDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记'**
  String get iosAppDisplayName;

  /// No description provided for @iosCameraPurpose.
  ///
  /// In zh, this message translates to:
  /// **'用于拍摄并添加笔记图片、视频及水印照片。'**
  String get iosCameraPurpose;

  /// No description provided for @iosMicrophonePurpose.
  ///
  /// In zh, this message translates to:
  /// **'用于录制语音笔记和实时听写。'**
  String get iosMicrophonePurpose;

  /// No description provided for @iosPhotoLibraryPurpose.
  ///
  /// In zh, this message translates to:
  /// **'用于选择要添加到笔记或识别文字的图片与视频。'**
  String get iosPhotoLibraryPurpose;

  /// No description provided for @iosFaceIdPurpose.
  ///
  /// In zh, this message translates to:
  /// **'用于通过系统 Face ID 解锁应用和隐私笔记空间。'**
  String get iosFaceIdPurpose;

  /// No description provided for @iosLocationPurpose.
  ///
  /// In zh, this message translates to:
  /// **'用于为水印照片添加地点；系统地理编码服务可能接收位置以查询地名。'**
  String get iosLocationPurpose;

  /// No description provided for @iosLocalNetworkPurpose.
  ///
  /// In zh, this message translates to:
  /// **'用于连接你配置的局域网同步服务器或在线模型服务。'**
  String get iosLocalNetworkPurpose;

  /// No description provided for @iosReminderPermissionHint.
  ///
  /// In zh, this message translates to:
  /// **'首次设置需允许通知。专注模式与系统通知设置可能影响提醒；最多同时安排 64 个待提醒。'**
  String get iosReminderPermissionHint;

  /// No description provided for @iosReminderTitle.
  ///
  /// In zh, this message translates to:
  /// **'笔记提醒'**
  String get iosReminderTitle;

  /// No description provided for @iosReminderBody.
  ///
  /// In zh, this message translates to:
  /// **'你有一条笔记待查看。打开非空笔记查看。'**
  String get iosReminderBody;

  /// No description provided for @iosSharePlaceholder.
  ///
  /// In zh, this message translates to:
  /// **'添加说明（可选）'**
  String get iosSharePlaceholder;

  /// No description provided for @iosShareSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存到待导入'**
  String get iosShareSaved;

  /// No description provided for @iosShareOpenApp.
  ///
  /// In zh, this message translates to:
  /// **'请打开非空笔记，解锁后确认保存为新笔记。'**
  String get iosShareOpenApp;

  /// No description provided for @iosShareFailedTitle.
  ///
  /// In zh, this message translates to:
  /// **'分享未完成'**
  String get iosShareFailedTitle;

  /// No description provided for @incomingShareTitle.
  ///
  /// In zh, this message translates to:
  /// **'保存分享内容'**
  String get incomingShareTitle;

  /// No description provided for @incomingShareQueueFull.
  ///
  /// In zh, this message translates to:
  /// **'请先处理之前分享的内容，再回到原应用重新分享。'**
  String get incomingShareQueueFull;

  /// No description provided for @incomingShareDescription.
  ///
  /// In zh, this message translates to:
  /// **'保存到普通笔记，随后可以继续编辑。不会修改当前笔记。'**
  String get incomingShareDescription;

  /// No description provided for @incomingShareSave.
  ///
  /// In zh, this message translates to:
  /// **'保存为新笔记'**
  String get incomingShareSave;

  /// No description provided for @incomingShareReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法读取分享内容，请回到原应用重新分享，并确认已授权访问附件。'**
  String get incomingShareReadFailed;

  /// No description provided for @incomingShareSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存未完成，请检查剩余存储空间后重试。分享内容仍保留在本机。'**
  String get incomingShareSaveFailed;

  /// No description provided for @incomingShareLimit.
  ///
  /// In zh, this message translates to:
  /// **'每次最多分享 20 个文件，单个文件不超过 100 MB，总大小不超过 200 MB，文字不超过 10 万字。'**
  String get incomingShareLimit;

  /// No description provided for @incomingShareOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开附件，请确认本机已安装支持该文件的应用。'**
  String get incomingShareOpenFailed;

  /// No description provided for @setNoteReminder.
  ///
  /// In zh, this message translates to:
  /// **'设置提醒'**
  String get setNoteReminder;

  /// No description provided for @editNoteReminder.
  ///
  /// In zh, this message translates to:
  /// **'修改提醒'**
  String get editNoteReminder;

  /// No description provided for @removeNoteReminder.
  ///
  /// In zh, this message translates to:
  /// **'取消提醒'**
  String get removeNoteReminder;

  /// No description provided for @reminderDateTime.
  ///
  /// In zh, this message translates to:
  /// **'设置日期和时间'**
  String get reminderDateTime;

  /// No description provided for @reminderConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get reminderConfirm;

  /// No description provided for @reminderChooseFuture.
  ///
  /// In zh, this message translates to:
  /// **'请选择未来的提醒时间'**
  String get reminderChooseFuture;

  /// No description provided for @reminderSaved.
  ///
  /// In zh, this message translates to:
  /// **'提醒已设置'**
  String get reminderSaved;

  /// No description provided for @reminderRemoved.
  ///
  /// In zh, this message translates to:
  /// **'提醒已取消'**
  String get reminderRemoved;

  /// No description provided for @reminderLimitReached.
  ///
  /// In zh, this message translates to:
  /// **'待提醒数量已达上限，请先移除一个提醒后重试。'**
  String get reminderLimitReached;

  /// No description provided for @reminderScheduleFailed.
  ///
  /// In zh, this message translates to:
  /// **'未能启用系统提醒，请重新设置'**
  String get reminderScheduleFailed;

  /// No description provided for @reminderNotificationsDisabled.
  ///
  /// In zh, this message translates to:
  /// **'通知未开启，提醒未设置。请开启系统通知后重试。'**
  String get reminderNotificationsDisabled;

  /// No description provided for @reminderExactDisabled.
  ///
  /// In zh, this message translates to:
  /// **'准时提醒权限未开启，提醒未设置。请允许“闹钟和提醒”后重试。'**
  String get reminderExactDisabled;

  /// No description provided for @reminderUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'当前平台暂不支持系统提醒'**
  String get reminderUnsupported;

  /// No description provided for @reminderPermissionHint.
  ///
  /// In zh, this message translates to:
  /// **'首次设置需允许通知和“闹钟和提醒”。系统省电、勿扰或强行停止应用可能影响提醒。'**
  String get reminderPermissionHint;

  /// No description provided for @reminderPastTime.
  ///
  /// In zh, this message translates to:
  /// **'提醒时间：{time}'**
  String reminderPastTime(String time);

  /// No description provided for @reminderSoon.
  ///
  /// In zh, this message translates to:
  /// **'即将提醒'**
  String get reminderSoon;

  /// No description provided for @reminderInMinutes.
  ///
  /// In zh, this message translates to:
  /// **'{minutes}分钟后'**
  String reminderInMinutes(int minutes);

  /// No description provided for @reminderToday.
  ///
  /// In zh, this message translates to:
  /// **'今天 {time}'**
  String reminderToday(String time);

  /// No description provided for @reminderTomorrow.
  ///
  /// In zh, this message translates to:
  /// **'明天 {time}'**
  String reminderTomorrow(String time);

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记'**
  String get appTitle;

  /// No description provided for @appBrandName.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记'**
  String get appBrandName;

  /// No description provided for @appTagline.
  ///
  /// In zh, this message translates to:
  /// **'本地优先 · 私密可靠'**
  String get appTagline;

  /// No description provided for @language.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get language;

  /// No description provided for @languageDescription.
  ///
  /// In zh, this message translates to:
  /// **'界面语言，可跟随系统或单独设置'**
  String get languageDescription;

  /// No description provided for @languageSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get languageSystem;

  /// No description provided for @languageSimplifiedChinese.
  ///
  /// In zh, this message translates to:
  /// **'简体中文'**
  String get languageSimplifiedChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @chooseLanguage.
  ///
  /// In zh, this message translates to:
  /// **'选择语言'**
  String get chooseLanguage;

  /// No description provided for @languageSystemDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用设备为非空笔记选择的语言'**
  String get languageSystemDescription;

  /// No description provided for @languageSimplifiedChineseDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用简体中文界面'**
  String get languageSimplifiedChineseDescription;

  /// No description provided for @languageEnglishDescription.
  ///
  /// In zh, this message translates to:
  /// **'Use the English interface'**
  String get languageEnglishDescription;

  /// No description provided for @languageSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'语言设置保存失败'**
  String get languageSaveFailed;

  /// No description provided for @localStorageInitializationFailed.
  ///
  /// In zh, this message translates to:
  /// **'本地存储初始化失败'**
  String get localStorageInitializationFailed;

  /// No description provided for @home.
  ///
  /// In zh, this message translates to:
  /// **'主页'**
  String get home;

  /// No description provided for @library.
  ///
  /// In zh, this message translates to:
  /// **'资料库'**
  String get library;

  /// No description provided for @data.
  ///
  /// In zh, this message translates to:
  /// **'数据'**
  String get data;

  /// No description provided for @createNew.
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get createNew;

  /// No description provided for @undo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get undo;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @deletePermanently.
  ///
  /// In zh, this message translates to:
  /// **'永久删除'**
  String get deletePermanently;

  /// No description provided for @deletePermanentlyQuestion.
  ///
  /// In zh, this message translates to:
  /// **'永久删除？'**
  String get deletePermanentlyQuestion;

  /// No description provided for @deletePermanentlyDescription.
  ///
  /// In zh, this message translates to:
  /// **'笔记和关联文件将无法恢复。'**
  String get deletePermanentlyDescription;

  /// No description provided for @deleteSelectedNotesQuestion.
  ///
  /// In zh, this message translates to:
  /// **'永久删除这 {count} 篇笔记？'**
  String deleteSelectedNotesQuestion(int count);

  /// No description provided for @discardNote.
  ///
  /// In zh, this message translates to:
  /// **'放弃笔记'**
  String get discardNote;

  /// No description provided for @discardNoteQuestion.
  ///
  /// In zh, this message translates to:
  /// **'放弃这篇笔记？'**
  String get discardNoteQuestion;

  /// No description provided for @discardNoteDescription.
  ///
  /// In zh, this message translates to:
  /// **'未保存的内容和新添加的附件将被删除，且无法恢复。'**
  String get discardNoteDescription;

  /// No description provided for @noteDeleteFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法删除笔记，请稍后重试'**
  String get noteDeleteFailed;

  /// No description provided for @captureMoment.
  ///
  /// In zh, this message translates to:
  /// **'捕捉此刻'**
  String get captureMoment;

  /// No description provided for @capturePrivacyHint.
  ///
  /// In zh, this message translates to:
  /// **'离线保存，你的内容只属于你'**
  String get capturePrivacyHint;

  /// No description provided for @note.
  ///
  /// In zh, this message translates to:
  /// **'笔记'**
  String get note;

  /// No description provided for @photo.
  ///
  /// In zh, this message translates to:
  /// **'拍照'**
  String get photo;

  /// No description provided for @image.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get image;

  /// No description provided for @record.
  ///
  /// In zh, this message translates to:
  /// **'录音'**
  String get record;

  /// No description provided for @audio.
  ///
  /// In zh, this message translates to:
  /// **'音频'**
  String get audio;

  /// No description provided for @video.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get video;

  /// No description provided for @file.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get file;

  /// No description provided for @voiceNote.
  ///
  /// In zh, this message translates to:
  /// **'语音笔记'**
  String get voiceNote;

  /// No description provided for @importFailed.
  ///
  /// In zh, this message translates to:
  /// **'{type}导入失败'**
  String importFailed(String type);

  /// No description provided for @recentlyUpdated.
  ///
  /// In zh, this message translates to:
  /// **'最近更新'**
  String get recentlyUpdated;

  /// No description provided for @more.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get more;

  /// No description provided for @startWithIdea.
  ///
  /// In zh, this message translates to:
  /// **'从一个念头开始'**
  String get startWithIdea;

  /// No description provided for @createNoteEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'点击“新建”，内容会安全留在本机。'**
  String get createNoteEmptyHint;

  /// No description provided for @localAssistant.
  ///
  /// In zh, this message translates to:
  /// **'本地助手'**
  String get localAssistant;

  /// No description provided for @searchLocalKnowledge.
  ///
  /// In zh, this message translates to:
  /// **'搜索本地知识库'**
  String get searchLocalKnowledge;

  /// No description provided for @searchNotes.
  ///
  /// In zh, this message translates to:
  /// **'搜索笔记'**
  String get searchNotes;

  /// No description provided for @pullToSearch.
  ///
  /// In zh, this message translates to:
  /// **'下拉搜索'**
  String get pullToSearch;

  /// No description provided for @pullToOpenShelf.
  ///
  /// In zh, this message translates to:
  /// **'继续下拉查看所有笔记'**
  String get pullToOpenShelf;

  /// No description provided for @releaseToOpenShelf.
  ///
  /// In zh, this message translates to:
  /// **'松开进入平铺视图'**
  String get releaseToOpenShelf;

  /// No description provided for @backToCardView.
  ///
  /// In zh, this message translates to:
  /// **'返回卡片视图'**
  String get backToCardView;

  /// No description provided for @selectNotes.
  ///
  /// In zh, this message translates to:
  /// **'选择'**
  String get selectNotes;

  /// No description provided for @selectNotesTitle.
  ///
  /// In zh, this message translates to:
  /// **'选择笔记'**
  String get selectNotesTitle;

  /// No description provided for @savedOnlyOnDevice.
  ///
  /// In zh, this message translates to:
  /// **'仅保存在本机'**
  String get savedOnlyOnDevice;

  /// No description provided for @allNotes.
  ///
  /// In zh, this message translates to:
  /// **'所有笔记'**
  String get allNotes;

  /// No description provided for @noteCountShort.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条笔记'**
  String noteCountShort(int count);

  /// No description provided for @attachmentCountShort.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个附件'**
  String attachmentCountShort(int count);

  /// No description provided for @createType.
  ///
  /// In zh, this message translates to:
  /// **'新建{type}'**
  String createType(String type);

  /// No description provided for @itemCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个条目'**
  String itemCount(int count);

  /// No description provided for @search.
  ///
  /// In zh, this message translates to:
  /// **'搜索'**
  String get search;

  /// No description provided for @sort.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get sort;

  /// No description provided for @creationTime.
  ///
  /// In zh, this message translates to:
  /// **'创建时间'**
  String get creationTime;

  /// No description provided for @title.
  ///
  /// In zh, this message translates to:
  /// **'标题'**
  String get title;

  /// No description provided for @fileSize.
  ///
  /// In zh, this message translates to:
  /// **'文件大小'**
  String get fileSize;

  /// No description provided for @all.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get all;

  /// No description provided for @emptyActive.
  ///
  /// In zh, this message translates to:
  /// **'还没有笔记'**
  String get emptyActive;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clear;

  /// No description provided for @allTypes.
  ///
  /// In zh, this message translates to:
  /// **'所有类型'**
  String get allTypes;

  /// No description provided for @unavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂不可用'**
  String get unavailable;

  /// No description provided for @localData.
  ///
  /// In zh, this message translates to:
  /// **'本地数据'**
  String get localData;

  /// No description provided for @localDataSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'默认只保存在本机；是否同步完全由你决定。'**
  String get localDataSubtitle;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @settingsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'管理数据、安全、偏好与应用信息'**
  String get settingsSubtitle;

  /// No description provided for @calendar.
  ///
  /// In zh, this message translates to:
  /// **'日历'**
  String get calendar;

  /// No description provided for @calendarSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'按最后编辑日期查看笔记'**
  String get calendarSubtitle;

  /// No description provided for @calendarYear.
  ///
  /// In zh, this message translates to:
  /// **'年'**
  String get calendarYear;

  /// No description provided for @calendarMonth.
  ///
  /// In zh, this message translates to:
  /// **'月'**
  String get calendarMonth;

  /// No description provided for @calendarWeek.
  ///
  /// In zh, this message translates to:
  /// **'周'**
  String get calendarWeek;

  /// No description provided for @calendarDay.
  ///
  /// In zh, this message translates to:
  /// **'日'**
  String get calendarDay;

  /// No description provided for @calendarTodayMarker.
  ///
  /// In zh, this message translates to:
  /// **'今'**
  String get calendarTodayMarker;

  /// No description provided for @calendarShowYear.
  ///
  /// In zh, this message translates to:
  /// **'查看全年'**
  String get calendarShowYear;

  /// No description provided for @calendarChooseYear.
  ///
  /// In zh, this message translates to:
  /// **'选择年份'**
  String get calendarChooseYear;

  /// No description provided for @calendarBackHome.
  ///
  /// In zh, this message translates to:
  /// **'返回主页'**
  String get calendarBackHome;

  /// No description provided for @calendarLunarDate.
  ///
  /// In zh, this message translates to:
  /// **'农历{date}'**
  String calendarLunarDate(String date);

  /// No description provided for @calendarLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'笔记数量加载失败，请重试'**
  String get calendarLoadFailed;

  /// No description provided for @calendarNoteCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String calendarNoteCount(int count);

  /// No description provided for @calendarWeekSummary.
  ///
  /// In zh, this message translates to:
  /// **'本周 {count} 条笔记 · {days} 天有记录'**
  String calendarWeekSummary(int count, int days);

  /// No description provided for @calendarLatestFirst.
  ///
  /// In zh, this message translates to:
  /// **'按最后更新时间倒序'**
  String get calendarLatestFirst;

  /// No description provided for @calendarUpdatedAt.
  ///
  /// In zh, this message translates to:
  /// **'{time} 更新'**
  String calendarUpdatedAt(String time);

  /// No description provided for @calendarViewAllNotes.
  ///
  /// In zh, this message translates to:
  /// **'查看当天全部 {count} 条笔记'**
  String calendarViewAllNotes(int count);

  /// No description provided for @tagGroups.
  ///
  /// In zh, this message translates to:
  /// **'标签分组'**
  String get tagGroups;

  /// No description provided for @tagGroupsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'每个标签自动汇集相关笔记'**
  String get tagGroupsSubtitle;

  /// No description provided for @noNotesOnDate.
  ///
  /// In zh, this message translates to:
  /// **'这一天没有笔记'**
  String get noNotesOnDate;

  /// No description provided for @noteTimeline.
  ///
  /// In zh, this message translates to:
  /// **'笔记时间轴'**
  String get noteTimeline;

  /// No description provided for @untaggedNotes.
  ///
  /// In zh, this message translates to:
  /// **'未标签'**
  String get untaggedNotes;

  /// No description provided for @localFirst.
  ///
  /// In zh, this message translates to:
  /// **'本地优先'**
  String get localFirst;

  /// No description provided for @offlineSecure.
  ///
  /// In zh, this message translates to:
  /// **'数据在本机'**
  String get offlineSecure;

  /// No description provided for @totalItems.
  ///
  /// In zh, this message translates to:
  /// **'总条目'**
  String get totalItems;

  /// No description provided for @attachments.
  ///
  /// In zh, this message translates to:
  /// **'附件'**
  String get attachments;

  /// No description provided for @userDataUsage.
  ///
  /// In zh, this message translates to:
  /// **'资料占用'**
  String get userDataUsage;

  /// No description provided for @preferences.
  ///
  /// In zh, this message translates to:
  /// **'偏好设置'**
  String get preferences;

  /// No description provided for @unifiedStorage.
  ///
  /// In zh, this message translates to:
  /// **'统一存储'**
  String get unifiedStorage;

  /// No description provided for @cloudSync.
  ///
  /// In zh, this message translates to:
  /// **'云同步'**
  String get cloudSync;

  /// No description provided for @cloudSyncSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'手动同步用户数据，支持 S3 和 WebDAV'**
  String get cloudSyncSubtitle;

  /// No description provided for @localModels.
  ///
  /// In zh, this message translates to:
  /// **'本地模型'**
  String get localModels;

  /// No description provided for @localModelsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'查看正在使用的模型并按能力分类管理'**
  String get localModelsSubtitle;

  /// No description provided for @backupAndMigration.
  ///
  /// In zh, this message translates to:
  /// **'备份与迁移'**
  String get backupAndMigration;

  /// No description provided for @exportCompleteBackup.
  ///
  /// In zh, this message translates to:
  /// **'导出完整备份'**
  String get exportCompleteBackup;

  /// No description provided for @exportCompleteBackupSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'创建多版本备份，可分享或另存到指定位置'**
  String get exportCompleteBackupSubtitle;

  /// No description provided for @restoreFromBackup.
  ///
  /// In zh, this message translates to:
  /// **'从备份恢复'**
  String get restoreFromBackup;

  /// No description provided for @restoreFromBackupSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'从备份历史或外部文件恢复，恢复前会完整校验'**
  String get restoreFromBackupSubtitle;

  /// No description provided for @backupScopeDescription.
  ///
  /// In zh, this message translates to:
  /// **'包含结构化笔记、正文附件、普通与隐私 AI 对话及对话图片；不包含模型文件、模型或云同步密钥、缓存和应用锁。'**
  String get backupScopeDescription;

  /// No description provided for @createNewBackup.
  ///
  /// In zh, this message translates to:
  /// **'创建新备份'**
  String get createNewBackup;

  /// No description provided for @backupName.
  ///
  /// In zh, this message translates to:
  /// **'备份名称'**
  String get backupName;

  /// No description provided for @backupNameHint.
  ///
  /// In zh, this message translates to:
  /// **'可选，例如：换机前'**
  String get backupNameHint;

  /// No description provided for @backupDescription.
  ///
  /// In zh, this message translates to:
  /// **'备份说明'**
  String get backupDescription;

  /// No description provided for @backupDescriptionHint.
  ///
  /// In zh, this message translates to:
  /// **'可选，记录这个版本的重要信息'**
  String get backupDescriptionHint;

  /// No description provided for @createBackup.
  ///
  /// In zh, this message translates to:
  /// **'创建备份'**
  String get createBackup;

  /// No description provided for @creatingBackup.
  ///
  /// In zh, this message translates to:
  /// **'正在校验并创建备份…'**
  String get creatingBackup;

  /// No description provided for @backupSavedDefault.
  ///
  /// In zh, this message translates to:
  /// **'已保存到非空笔记默认备份位置'**
  String get backupSavedDefault;

  /// No description provided for @backupHistory.
  ///
  /// In zh, this message translates to:
  /// **'备份历史'**
  String get backupHistory;

  /// No description provided for @backupHistorySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'默认位置保留多个版本，可随时分享、另存或恢复'**
  String get backupHistorySubtitle;

  /// No description provided for @noBackupHistory.
  ///
  /// In zh, this message translates to:
  /// **'还没有本地备份'**
  String get noBackupHistory;

  /// No description provided for @backupStoredLocally.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记默认位置'**
  String get backupStoredLocally;

  /// No description provided for @saveBackupCopy.
  ///
  /// In zh, this message translates to:
  /// **'另存到…'**
  String get saveBackupCopy;

  /// No description provided for @backupCopySaved.
  ///
  /// In zh, this message translates to:
  /// **'备份副本已保存'**
  String get backupCopySaved;

  /// No description provided for @backupDetails.
  ///
  /// In zh, this message translates to:
  /// **'备份详情'**
  String get backupDetails;

  /// No description provided for @backupDateAndSize.
  ///
  /// In zh, this message translates to:
  /// **'{date} · {size}'**
  String backupDateAndSize(String date, String size);

  /// No description provided for @backupCreatedAt.
  ///
  /// In zh, this message translates to:
  /// **'创建时间'**
  String get backupCreatedAt;

  /// No description provided for @backupFileName.
  ///
  /// In zh, this message translates to:
  /// **'文件名'**
  String get backupFileName;

  /// No description provided for @backupFormat.
  ///
  /// In zh, this message translates to:
  /// **'格式版本'**
  String get backupFormat;

  /// No description provided for @backupVerificationCode.
  ///
  /// In zh, this message translates to:
  /// **'文件校验值（SHA-256）'**
  String get backupVerificationCode;

  /// No description provided for @backupContentFingerprint.
  ///
  /// In zh, this message translates to:
  /// **'内容指纹'**
  String get backupContentFingerprint;

  /// No description provided for @deleteBackup.
  ///
  /// In zh, this message translates to:
  /// **'删除备份'**
  String get deleteBackup;

  /// No description provided for @deleteBackupQuestion.
  ///
  /// In zh, this message translates to:
  /// **'删除这个备份？'**
  String get deleteBackupQuestion;

  /// No description provided for @deleteBackupDescription.
  ///
  /// In zh, this message translates to:
  /// **'只会删除默认位置中的这个备份版本，不影响当前笔记。'**
  String get deleteBackupDescription;

  /// No description provided for @backupDeleted.
  ///
  /// In zh, this message translates to:
  /// **'备份已删除'**
  String get backupDeleted;

  /// No description provided for @restoreWarning.
  ///
  /// In zh, this message translates to:
  /// **'恢复会替换当前的笔记、聊天与附件。建议先创建一份最新备份。'**
  String get restoreWarning;

  /// No description provided for @chooseExternalBackup.
  ///
  /// In zh, this message translates to:
  /// **'从其他位置选择备份'**
  String get chooseExternalBackup;

  /// No description provided for @restoreBackupAction.
  ///
  /// In zh, this message translates to:
  /// **'恢复此备份'**
  String get restoreBackupAction;

  /// No description provided for @restoringBackup.
  ///
  /// In zh, this message translates to:
  /// **'正在校验并恢复备份…'**
  String get restoringBackup;

  /// No description provided for @organizationAndSecurity.
  ///
  /// In zh, this message translates to:
  /// **'整理与安全'**
  String get organizationAndSecurity;

  /// No description provided for @appLock.
  ///
  /// In zh, this message translates to:
  /// **'应用锁'**
  String get appLock;

  /// No description provided for @appLockEnabledSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'已开启 · 离开应用 {timeout}锁定'**
  String appLockEnabledSubtitle(String timeout);

  /// No description provided for @appLockDisabledSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'使用系统指纹、人脸或锁屏密码'**
  String get appLockDisabledSubtitle;

  /// No description provided for @lockImmediately.
  ///
  /// In zh, this message translates to:
  /// **'立即'**
  String get lockImmediately;

  /// No description provided for @lockAfterOneMinute.
  ///
  /// In zh, this message translates to:
  /// **'1 分钟后'**
  String get lockAfterOneMinute;

  /// No description provided for @lockAfterFiveMinutes.
  ///
  /// In zh, this message translates to:
  /// **'5 分钟后'**
  String get lockAfterFiveMinutes;

  /// No description provided for @lockAfterFifteenMinutes.
  ///
  /// In zh, this message translates to:
  /// **'15 分钟后'**
  String get lockAfterFifteenMinutes;

  /// No description provided for @contentCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条内容'**
  String contentCount(int count);

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get about;

  /// No description provided for @loadingVersion.
  ///
  /// In zh, this message translates to:
  /// **'正在读取版本信息…'**
  String get loadingVersion;

  /// No description provided for @versionNumber.
  ///
  /// In zh, this message translates to:
  /// **'版本号 {version}'**
  String versionNumber(String version);

  /// No description provided for @versionNumberWithBuild.
  ///
  /// In zh, this message translates to:
  /// **'版本号 {version} ({build})'**
  String versionNumberWithBuild(String version, String build);

  /// No description provided for @buildTime.
  ///
  /// In zh, this message translates to:
  /// **'构建时间 {time}'**
  String buildTime(String time);

  /// No description provided for @buildTimeUnrecorded.
  ///
  /// In zh, this message translates to:
  /// **'构建时间 未记录'**
  String get buildTimeUnrecorded;

  /// No description provided for @footerTagline.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记 · 本地优先，同步由你掌控'**
  String get footerTagline;

  /// No description provided for @backupExported.
  ///
  /// In zh, this message translates to:
  /// **'备份已交给系统保存'**
  String get backupExported;

  /// No description provided for @exportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败：{error}'**
  String exportFailed(String error);

  /// No description provided for @restoreCompleteBackupQuestion.
  ///
  /// In zh, this message translates to:
  /// **'恢复完整备份？'**
  String get restoreCompleteBackupQuestion;

  /// No description provided for @restoreCompleteBackupDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前内容将被备份中的内容替换。建议先导出一份当前数据。'**
  String get restoreCompleteBackupDescription;

  /// No description provided for @chooseBackup.
  ///
  /// In zh, this message translates to:
  /// **'选择备份'**
  String get chooseBackup;

  /// No description provided for @backupRestored.
  ///
  /// In zh, this message translates to:
  /// **'备份已安全恢复'**
  String get backupRestored;

  /// No description provided for @restoreFailed.
  ///
  /// In zh, this message translates to:
  /// **'恢复失败：{error}'**
  String restoreFailed(String error);

  /// No description provided for @localModelsPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地模型'**
  String get localModelsPageTitle;

  /// No description provided for @modelsInUse.
  ///
  /// In zh, this message translates to:
  /// **'正在使用'**
  String get modelsInUse;

  /// No description provided for @noModelsInUse.
  ///
  /// In zh, this message translates to:
  /// **'尚未配置正在使用的本地模型'**
  String get noModelsInUse;

  /// No description provided for @modelConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'分类管理'**
  String get modelConfiguration;

  /// No description provided for @activeModelCount.
  ///
  /// In zh, this message translates to:
  /// **'正在使用 {count} 个模型'**
  String activeModelCount(int count);

  /// No description provided for @activeModelsUsage.
  ///
  /// In zh, this message translates to:
  /// **'本地模型占用 {size}'**
  String activeModelsUsage(String size);

  /// No description provided for @installedModels.
  ///
  /// In zh, this message translates to:
  /// **'已安装'**
  String get installedModels;

  /// No description provided for @availableModels.
  ///
  /// In zh, this message translates to:
  /// **'可获取'**
  String get availableModels;

  /// No description provided for @installedModelsCount.
  ///
  /// In zh, this message translates to:
  /// **'已安装 {count} 个模型'**
  String installedModelsCount(int count);

  /// No description provided for @noInstalledModelsInCategory.
  ///
  /// In zh, this message translates to:
  /// **'这一分类还没有已安装的模型'**
  String get noInstalledModelsInCategory;

  /// No description provided for @noAvailableModelsInCategory.
  ///
  /// In zh, this message translates to:
  /// **'当前没有其他可获取的模型'**
  String get noAvailableModelsInCategory;

  /// No description provided for @speechModelsDescription.
  ///
  /// In zh, this message translates to:
  /// **'分别管理实时听写、录音转写、语音处理与语音合成模型。'**
  String get speechModelsDescription;

  /// No description provided for @visionModelsDescription.
  ///
  /// In zh, this message translates to:
  /// **'管理 OCR 与专用视觉能力；聊天图片理解由支持图片的语言模型提供。'**
  String get visionModelsDescription;

  /// No description provided for @liveDictationSettingsDescription.
  ///
  /// In zh, this message translates to:
  /// **'管理当前听写模型、热词、精修和实时降噪'**
  String get liveDictationSettingsDescription;

  /// No description provided for @modelDownloadsAndStorage.
  ///
  /// In zh, this message translates to:
  /// **'下载与存储'**
  String get modelDownloadsAndStorage;

  /// No description provided for @modelDownloadsAndStorageDescription.
  ///
  /// In zh, this message translates to:
  /// **'下载源、后台任务和模型文件占用'**
  String get modelDownloadsAndStorageDescription;

  /// No description provided for @localAssistantUsage.
  ///
  /// In zh, this message translates to:
  /// **'本地助手'**
  String get localAssistantUsage;

  /// No description provided for @liveDictationUsage.
  ///
  /// In zh, this message translates to:
  /// **'实时听写'**
  String get liveDictationUsage;

  /// No description provided for @audioTranscriptionUsage.
  ///
  /// In zh, this message translates to:
  /// **'录音转写'**
  String get audioTranscriptionUsage;

  /// No description provided for @voiceActivityUsage.
  ///
  /// In zh, this message translates to:
  /// **'语音检测'**
  String get voiceActivityUsage;

  /// No description provided for @speechEnhancementUsage.
  ///
  /// In zh, this message translates to:
  /// **'实时降噪'**
  String get speechEnhancementUsage;

  /// No description provided for @textRecognitionUsage.
  ///
  /// In zh, this message translates to:
  /// **'文字识别'**
  String get textRecognitionUsage;

  /// No description provided for @modelPrivacyHint.
  ///
  /// In zh, this message translates to:
  /// **'模型只在用户下载时联网，且不会进入笔记备份；用户数据仅在手动云同步时上传。'**
  String get modelPrivacyHint;

  /// No description provided for @languageModels.
  ///
  /// In zh, this message translates to:
  /// **'语言模型'**
  String get languageModels;

  /// No description provided for @languageModelsDescription.
  ///
  /// In zh, this message translates to:
  /// **'由用户下载并选择本地助手使用的模型，默认上下文为 4096。'**
  String get languageModelsDescription;

  /// No description provided for @discoverMnnModels.
  ///
  /// In zh, this message translates to:
  /// **'发现本地模型'**
  String get discoverMnnModels;

  /// No description provided for @discoverMnnModelsDescription.
  ///
  /// In zh, this message translates to:
  /// **'浏览从 taobao-mnn 与 litert-community Collections 同步的公开模型；是否校验和添加由你决定。'**
  String get discoverMnnModelsDescription;

  /// No description provided for @browseModels.
  ///
  /// In zh, this message translates to:
  /// **'浏览模型'**
  String get browseModels;

  /// No description provided for @refreshCatalog.
  ///
  /// In zh, this message translates to:
  /// **'刷新目录'**
  String get refreshCatalog;

  /// No description provided for @syncingModelCatalog.
  ///
  /// In zh, this message translates to:
  /// **'正在同步模型目录…'**
  String get syncingModelCatalog;

  /// No description provided for @modelCatalogSyncFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法刷新模型目录：{error}'**
  String modelCatalogSyncFailed(String error);

  /// No description provided for @modelCatalogRefreshTimeout.
  ///
  /// In zh, this message translates to:
  /// **'模型目录刷新超时'**
  String get modelCatalogRefreshTimeout;

  /// No description provided for @modelCatalogRefreshTimeoutDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前网络未能及时连接模型服务。你可以重试或切换模型网络源。'**
  String get modelCatalogRefreshTimeoutDescription;

  /// No description provided for @modelCatalogOffline.
  ///
  /// In zh, this message translates to:
  /// **'无法连接模型服务'**
  String get modelCatalogOffline;

  /// No description provided for @modelCatalogOfflineDescription.
  ///
  /// In zh, this message translates to:
  /// **'请检查网络连接，或尝试切换模型网络源。'**
  String get modelCatalogOfflineDescription;

  /// No description provided for @modelCatalogServiceUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'模型服务暂时不可用'**
  String get modelCatalogServiceUnavailable;

  /// No description provided for @modelCatalogServiceUnavailableDescription.
  ///
  /// In zh, this message translates to:
  /// **'服务当前没有正常响应，请稍后重试。'**
  String get modelCatalogServiceUnavailableDescription;

  /// No description provided for @modelCatalogAuthorizationRequired.
  ///
  /// In zh, this message translates to:
  /// **'部分模型需要访问授权'**
  String get modelCatalogAuthorizationRequired;

  /// No description provided for @modelCatalogAuthorizationRequiredDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前目录包含需要在 Hugging Face 接受许可后才能访问的模型。'**
  String get modelCatalogAuthorizationRequiredDescription;

  /// No description provided for @modelCatalogInvalidResponse.
  ///
  /// In zh, this message translates to:
  /// **'模型目录暂时无法读取'**
  String get modelCatalogInvalidResponse;

  /// No description provided for @modelCatalogInvalidResponseDescription.
  ///
  /// In zh, this message translates to:
  /// **'服务返回了无法识别的数据，请稍后重试。'**
  String get modelCatalogInvalidResponseDescription;

  /// No description provided for @modelCatalogCompatibilityUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法检查模型兼容性'**
  String get modelCatalogCompatibilityUnavailable;

  /// No description provided for @modelNetworkSourceSettings.
  ///
  /// In zh, this message translates to:
  /// **'切换网络源'**
  String get modelNetworkSourceSettings;

  /// No description provided for @cachedCatalogInUse.
  ///
  /// In zh, this message translates to:
  /// **'正在显示上次成功同步的目录'**
  String get cachedCatalogInUse;

  /// No description provided for @searchMnnModels.
  ///
  /// In zh, this message translates to:
  /// **'搜索本地模型'**
  String get searchMnnModels;

  /// No description provided for @noMnnModelsFound.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的本地模型'**
  String get noMnnModelsFound;

  /// No description provided for @officialMnnCollection.
  ///
  /// In zh, this message translates to:
  /// **'taobao-mnn 官方 Collection'**
  String get officialMnnCollection;

  /// No description provided for @officialLiteRtCollection.
  ///
  /// In zh, this message translates to:
  /// **'litert-community 官方 Collection'**
  String get officialLiteRtCollection;

  /// No description provided for @downloadCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 次下载'**
  String downloadCount(int count);

  /// No description provided for @modelEngine.
  ///
  /// In zh, this message translates to:
  /// **'推理引擎'**
  String get modelEngine;

  /// No description provided for @collection.
  ///
  /// In zh, this message translates to:
  /// **'模型集合'**
  String get collection;

  /// No description provided for @downloads.
  ///
  /// In zh, this message translates to:
  /// **'下载热度'**
  String get downloads;

  /// No description provided for @modelPackageNotVerified.
  ///
  /// In zh, this message translates to:
  /// **'模型包尚未校验'**
  String get modelPackageNotVerified;

  /// No description provided for @modelPackageVerificationDescription.
  ///
  /// In zh, this message translates to:
  /// **'校验会联网读取仓库元数据、固定版本和文件清单，不会下载完整模型，也不代表当前设备一定能运行。'**
  String get modelPackageVerificationDescription;

  /// No description provided for @verifyModelPackage.
  ///
  /// In zh, this message translates to:
  /// **'校验模型包'**
  String get verifyModelPackage;

  /// No description provided for @verifyingModelPackage.
  ///
  /// In zh, this message translates to:
  /// **'正在校验模型包…'**
  String get verifyingModelPackage;

  /// No description provided for @reverifyModelPackage.
  ///
  /// In zh, this message translates to:
  /// **'重新校验模型包'**
  String get reverifyModelPackage;

  /// No description provided for @modelPackageUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'该仓库不是受支持的模型包'**
  String get modelPackageUnsupported;

  /// No description provided for @modelPackageUnsupportedDescription.
  ///
  /// In zh, this message translates to:
  /// **'仓库格式、公开访问状态或必要文件不符合当前引擎要求。'**
  String get modelPackageUnsupportedDescription;

  /// No description provided for @checkingModelCompatibility.
  ///
  /// In zh, this message translates to:
  /// **'正在检查模型兼容性…'**
  String get checkingModelCompatibility;

  /// No description provided for @modelCompatibilityPassed.
  ///
  /// In zh, this message translates to:
  /// **'MNN 文件与运行配置检查通过'**
  String get modelCompatibilityPassed;

  /// No description provided for @liteRtCompatibilityPassed.
  ///
  /// In zh, this message translates to:
  /// **'LiteRT-LM 文件、固定版本与校验值检查通过'**
  String get liteRtCompatibilityPassed;

  /// No description provided for @modelCompatibilityFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法添加该模型：{error}'**
  String modelCompatibilityFailed(String error);

  /// No description provided for @pinnedCommit.
  ///
  /// In zh, this message translates to:
  /// **'固定 commit'**
  String get pinnedCommit;

  /// No description provided for @modelFileCount.
  ///
  /// In zh, this message translates to:
  /// **'模型文件'**
  String get modelFileCount;

  /// No description provided for @modelFile.
  ///
  /// In zh, this message translates to:
  /// **'模型文件'**
  String get modelFile;

  /// No description provided for @fileCountValue.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个文件'**
  String fileCountValue(int count);

  /// No description provided for @modelCapabilities.
  ///
  /// In zh, this message translates to:
  /// **'模型能力'**
  String get modelCapabilities;

  /// No description provided for @textGenerationCapability.
  ///
  /// In zh, this message translates to:
  /// **'文本生成'**
  String get textGenerationCapability;

  /// No description provided for @imageInputCapability.
  ///
  /// In zh, this message translates to:
  /// **'图片输入'**
  String get imageInputCapability;

  /// No description provided for @audioInputCapability.
  ///
  /// In zh, this message translates to:
  /// **'音频输入'**
  String get audioInputCapability;

  /// No description provided for @reasoningCapability.
  ///
  /// In zh, this message translates to:
  /// **'思考推理'**
  String get reasoningCapability;

  /// No description provided for @toolCallingCapability.
  ///
  /// In zh, this message translates to:
  /// **'工具调用'**
  String get toolCallingCapability;

  /// No description provided for @addAndDownloadModel.
  ///
  /// In zh, this message translates to:
  /// **'添加并下载'**
  String get addAndDownloadModel;

  /// No description provided for @addToLanguageModels.
  ///
  /// In zh, this message translates to:
  /// **'添加到语言模型'**
  String get addToLanguageModels;

  /// No description provided for @modelAddedToManager.
  ///
  /// In zh, this message translates to:
  /// **'模型已添加到本地模型'**
  String get modelAddedToManager;

  /// No description provided for @recommendedModelsAlreadyListed.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记推荐模型已在上一页中显示。'**
  String get recommendedModelsAlreadyListed;

  /// No description provided for @remoteMnnModelSummary.
  ///
  /// In zh, this message translates to:
  /// **'来自 {collection} 的官方模型'**
  String remoteMnnModelSummary(String collection);

  /// No description provided for @remoteMnnModelDescription.
  ///
  /// In zh, this message translates to:
  /// **'从 taobao-mnn Collections 同步；安装前会校验仓库版本和每个模型文件。'**
  String get remoteMnnModelDescription;

  /// No description provided for @liveDictationSettings.
  ///
  /// In zh, this message translates to:
  /// **'实时听写设置'**
  String get liveDictationSettings;

  /// No description provided for @speechModels.
  ///
  /// In zh, this message translates to:
  /// **'语音模型'**
  String get speechModels;

  /// No description provided for @visionModels.
  ///
  /// In zh, this message translates to:
  /// **'视觉模型'**
  String get visionModels;

  /// No description provided for @modelDownloadSource.
  ///
  /// In zh, this message translates to:
  /// **'模型下载源'**
  String get modelDownloadSource;

  /// No description provided for @downloadSourceSecurityDescription.
  ///
  /// In zh, this message translates to:
  /// **'所有模式都会在首选节点不可用时安全回退；模型仍通过固定版本和 SHA-256 校验。'**
  String get downloadSourceSecurityDescription;

  /// No description provided for @downloadSourceSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'下载源设置保存失败'**
  String get downloadSourceSaveFailed;

  /// No description provided for @downloadSourceAutomatic.
  ///
  /// In zh, this message translates to:
  /// **'自动选择'**
  String get downloadSourceAutomatic;

  /// No description provided for @downloadSourceOfficialFirst.
  ///
  /// In zh, this message translates to:
  /// **'优先官方源'**
  String get downloadSourceOfficialFirst;

  /// No description provided for @downloadSourceMainlandFirst.
  ///
  /// In zh, this message translates to:
  /// **'优先国内镜像'**
  String get downloadSourceMainlandFirst;

  /// No description provided for @downloadSourceAutomaticDescription.
  ///
  /// In zh, this message translates to:
  /// **'结合设备区域和实际连接结果动态选择'**
  String get downloadSourceAutomaticDescription;

  /// No description provided for @downloadSourceOfficialDescription.
  ///
  /// In zh, this message translates to:
  /// **'优先 Hugging Face 或 GitHub 官方节点'**
  String get downloadSourceOfficialDescription;

  /// No description provided for @downloadSourceMainlandDescription.
  ///
  /// In zh, this message translates to:
  /// **'优先国内镜像或 ModelScope 节点'**
  String get downloadSourceMainlandDescription;

  /// No description provided for @downloadSourceEffective.
  ///
  /// In zh, this message translates to:
  /// **'自动选择 · {source}优先'**
  String downloadSourceEffective(String source);

  /// No description provided for @officialSource.
  ///
  /// In zh, this message translates to:
  /// **'官方源'**
  String get officialSource;

  /// No description provided for @mainlandMirror.
  ///
  /// In zh, this message translates to:
  /// **'国内镜像'**
  String get mainlandMirror;

  /// No description provided for @lastUsedSource.
  ///
  /// In zh, this message translates to:
  /// **'最近使用：{source}'**
  String lastUsedSource(String source);

  /// No description provided for @continueModelDownloadQuestion.
  ///
  /// In zh, this message translates to:
  /// **'继续下载模型？'**
  String get continueModelDownloadQuestion;

  /// No description provided for @downloadModelQuestion.
  ///
  /// In zh, this message translates to:
  /// **'下载模型？'**
  String get downloadModelQuestion;

  /// No description provided for @modelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'{name}\n还需下载约 {size}，建议使用 Wi-Fi。\n\n下载中可离开此页面；中断后会保留进度。'**
  String modelDownloadDescription(String name, String size);

  /// No description provided for @modelMemoryRecommendation.
  ///
  /// In zh, this message translates to:
  /// **'建议设备至少具备 {memory} 运行内存；内存不足可能加载失败或被系统终止。'**
  String modelMemoryRecommendation(String memory);

  /// No description provided for @ttsStorageRecommendation.
  ///
  /// In zh, this message translates to:
  /// **'解压安装时请预留约 600 MB 可用空间。'**
  String get ttsStorageRecommendation;

  /// No description provided for @startDownload.
  ///
  /// In zh, this message translates to:
  /// **'开始下载'**
  String get startDownload;

  /// No description provided for @removeModelQuestion.
  ///
  /// In zh, this message translates to:
  /// **'移除 {name}？'**
  String removeModelQuestion(String name);

  /// No description provided for @removeModelDescription.
  ///
  /// In zh, this message translates to:
  /// **'将释放约 {size} 空间。已经生成的笔记内容不会被删除。'**
  String removeModelDescription(String size);

  /// No description provided for @removeModel.
  ///
  /// In zh, this message translates to:
  /// **'移除模型'**
  String get removeModel;

  /// No description provided for @hotwordsSaved.
  ///
  /// In zh, this message translates to:
  /// **'已保存 {count} 个热词'**
  String hotwordsSaved(int count);

  /// No description provided for @hotwordsDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已关闭实时听写热词'**
  String get hotwordsDisabled;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'设置保存失败，请检查设备存储空间'**
  String get settingsSaveFailed;

  /// No description provided for @purpose.
  ///
  /// In zh, this message translates to:
  /// **'用途'**
  String get purpose;

  /// No description provided for @engine.
  ///
  /// In zh, this message translates to:
  /// **'引擎'**
  String get engine;

  /// No description provided for @supportedLanguages.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get supportedLanguages;

  /// No description provided for @version.
  ///
  /// In zh, this message translates to:
  /// **'版本'**
  String get version;

  /// No description provided for @recommendedMemory.
  ///
  /// In zh, this message translates to:
  /// **'建议内存'**
  String get recommendedMemory;

  /// No description provided for @memoryAndAbove.
  ///
  /// In zh, this message translates to:
  /// **'{memory} 及以上'**
  String memoryAndAbove(String memory);

  /// No description provided for @source.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get source;

  /// No description provided for @license.
  ///
  /// In zh, this message translates to:
  /// **'许可'**
  String get license;

  /// No description provided for @saveFailedStorage.
  ///
  /// In zh, this message translates to:
  /// **'保存失败，请检查设备存储空间'**
  String get saveFailedStorage;

  /// No description provided for @liveDictationHotwords.
  ///
  /// In zh, this message translates to:
  /// **'实时听写热词'**
  String get liveDictationHotwords;

  /// No description provided for @hotwordsDescription.
  ///
  /// In zh, this message translates to:
  /// **'每行输入一个人名、产品名或专业术语；留空即关闭。热词从下一次听写开始生效。'**
  String get hotwordsDescription;

  /// No description provided for @hotwordsHint.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记\nsherpa onnx\n产品名称'**
  String get hotwordsHint;

  /// No description provided for @hotwordsList.
  ///
  /// In zh, this message translates to:
  /// **'热词列表'**
  String get hotwordsList;

  /// No description provided for @boostStrength.
  ///
  /// In zh, this message translates to:
  /// **'增强强度'**
  String get boostStrength;

  /// No description provided for @hotwordsStrengthWarning.
  ///
  /// In zh, this message translates to:
  /// **'过高的强度可能把发音相近的普通词误判为热词，建议先使用 2.0。'**
  String get hotwordsStrengthWarning;

  /// No description provided for @saving.
  ///
  /// In zh, this message translates to:
  /// **'保存中…'**
  String get saving;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @finalRefinement.
  ///
  /// In zh, this message translates to:
  /// **'结束后精修'**
  String get finalRefinement;

  /// No description provided for @finalRefinementDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用 SenseVoice 二次识别，仅在质量检查通过时替换（默认关闭）'**
  String get finalRefinementDescription;

  /// No description provided for @liveNoiseSuppression.
  ///
  /// In zh, this message translates to:
  /// **'实时降噪'**
  String get liveNoiseSuppression;

  /// No description provided for @liveNoiseSuppressionDescription.
  ///
  /// In zh, this message translates to:
  /// **'先抑制环境噪声，再送入流式识别'**
  String get liveNoiseSuppressionDescription;

  /// No description provided for @installDenoiserFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先安装下方的 DPDFNet 实时降噪模型'**
  String get installDenoiserFirst;

  /// No description provided for @hotwordBoost.
  ///
  /// In zh, this message translates to:
  /// **'热词增强'**
  String get hotwordBoost;

  /// No description provided for @hotwordSummary.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个热词 · 强度 {strength}'**
  String hotwordSummary(int count, String strength);

  /// No description provided for @hotwordBoostDescription.
  ///
  /// In zh, this message translates to:
  /// **'优先识别人名、品牌与专业术语'**
  String get hotwordBoostDescription;

  /// No description provided for @installedModelCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个模型可用'**
  String installedModelCount(int count);

  /// No description provided for @optionalModelsUsage.
  ///
  /// In zh, this message translates to:
  /// **'可选模型占用 {size}'**
  String optionalModelsUsage(String size);

  /// No description provided for @recommended.
  ///
  /// In zh, this message translates to:
  /// **'推荐'**
  String get recommended;

  /// No description provided for @modelTransfers.
  ///
  /// In zh, this message translates to:
  /// **'下载与待继续'**
  String get modelTransfers;

  /// No description provided for @modelTransfersDescription.
  ///
  /// In zh, this message translates to:
  /// **'集中查看正在传输、等待处理以及保留了下载进度的模型。已完成的模型会自动离开这里。'**
  String get modelTransfersDescription;

  /// No description provided for @modelTransferSectionCount.
  ///
  /// In zh, this message translates to:
  /// **'下载与待继续（{count}）'**
  String modelTransferSectionCount(int count);

  /// No description provided for @modelTransferSummary.
  ///
  /// In zh, this message translates to:
  /// **'{active} 项进行中 · {resumable} 项待继续'**
  String modelTransferSummary(int active, int resumable);

  /// No description provided for @noModelTransfers.
  ///
  /// In zh, this message translates to:
  /// **'当前没有正在传输或等待继续的模型'**
  String get noModelTransfers;

  /// No description provided for @otherModels.
  ///
  /// In zh, this message translates to:
  /// **'其他模型'**
  String get otherModels;

  /// No description provided for @currentDictation.
  ///
  /// In zh, this message translates to:
  /// **'当前听写'**
  String get currentDictation;

  /// No description provided for @currentAssistant.
  ///
  /// In zh, this message translates to:
  /// **'当前助手'**
  String get currentAssistant;

  /// No description provided for @modelDetails.
  ///
  /// In zh, this message translates to:
  /// **'模型详情'**
  String get modelDetails;

  /// No description provided for @memoryBadge.
  ///
  /// In zh, this message translates to:
  /// **'{memory}+ 内存'**
  String memoryBadge(String memory);

  /// No description provided for @pleaseWait.
  ///
  /// In zh, this message translates to:
  /// **'请稍候'**
  String get pleaseWait;

  /// No description provided for @modelDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'模型下载失败'**
  String get modelDownloadFailed;

  /// No description provided for @bundledWithApp.
  ///
  /// In zh, this message translates to:
  /// **'随应用提供'**
  String get bundledWithApp;

  /// No description provided for @comingSoon.
  ///
  /// In zh, this message translates to:
  /// **'即将支持'**
  String get comingSoon;

  /// No description provided for @installed.
  ///
  /// In zh, this message translates to:
  /// **'已安装'**
  String get installed;

  /// No description provided for @useForDictation.
  ///
  /// In zh, this message translates to:
  /// **'用于听写'**
  String get useForDictation;

  /// No description provided for @useForAssistant.
  ///
  /// In zh, this message translates to:
  /// **'用于助手'**
  String get useForAssistant;

  /// No description provided for @remove.
  ///
  /// In zh, this message translates to:
  /// **'移除'**
  String get remove;

  /// No description provided for @importFromFile.
  ///
  /// In zh, this message translates to:
  /// **'从文件导入'**
  String get importFromFile;

  /// No description provided for @continueDownload.
  ///
  /// In zh, this message translates to:
  /// **'继续下载'**
  String get continueDownload;

  /// No description provided for @download.
  ///
  /// In zh, this message translates to:
  /// **'下载'**
  String get download;

  /// No description provided for @pauseDownload.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get pauseDownload;

  /// No description provided for @cancelingDownload.
  ///
  /// In zh, this message translates to:
  /// **'正在暂停并保留已下载内容…'**
  String get cancelingDownload;

  /// No description provided for @downloadedResumable.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {amount}，可继续'**
  String downloadedResumable(String amount);

  /// No description provided for @moreActions.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get moreActions;

  /// No description provided for @discardPartialDownload.
  ///
  /// In zh, this message translates to:
  /// **'删除已下载部分'**
  String get discardPartialDownload;

  /// No description provided for @discardPartialDownloadQuestion.
  ///
  /// In zh, this message translates to:
  /// **'删除 {name} 的下载进度？'**
  String discardPartialDownloadQuestion(String name);

  /// No description provided for @discardPartialDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'将删除已下载的 {size}，下次需要从头下载。'**
  String discardPartialDownloadDescription(String size);

  /// No description provided for @discardPartialDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法删除已下载部分，请稍后重试'**
  String get discardPartialDownloadFailed;

  /// No description provided for @connectingDownloadSource.
  ///
  /// In zh, this message translates to:
  /// **'正在连接下载节点{source}'**
  String connectingDownloadSource(String source);

  /// No description provided for @downloadedInstalling.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {size} · 正在完成安装'**
  String downloadedInstalling(String size);

  /// No description provided for @downloadedWaitingInstall.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {size} · 等待安装'**
  String downloadedWaitingInstall(String size);

  /// No description provided for @preparingLocalModelImport.
  ///
  /// In zh, this message translates to:
  /// **'正在准备本地模型文件…'**
  String get preparingLocalModelImport;

  /// No description provided for @estimatedRemainingCompact.
  ///
  /// In zh, this message translates to:
  /// **'剩余 {time}'**
  String estimatedRemainingCompact(String time);

  /// No description provided for @modelDownloadTransfer.
  ///
  /// In zh, this message translates to:
  /// **'模型下载'**
  String get modelDownloadTransfer;

  /// No description provided for @localModelImportTransfer.
  ///
  /// In zh, this message translates to:
  /// **'本地文件导入'**
  String get localModelImportTransfer;

  /// No description provided for @thirdPartyMainlandMirror.
  ///
  /// In zh, this message translates to:
  /// **'第三方国内镜像'**
  String get thirdPartyMainlandMirror;

  /// No description provided for @githubOfficialSource.
  ///
  /// In zh, this message translates to:
  /// **'GitHub 官方源'**
  String get githubOfficialSource;

  /// No description provided for @modelScopeSource.
  ///
  /// In zh, this message translates to:
  /// **'ModelScope 魔搭'**
  String get modelScopeSource;

  /// No description provided for @backgroundTasks.
  ///
  /// In zh, this message translates to:
  /// **'后台任务'**
  String get backgroundTasks;

  /// No description provided for @tasksAndActivity.
  ///
  /// In zh, this message translates to:
  /// **'任务与活动'**
  String get tasksAndActivity;

  /// No description provided for @backgroundTasksPageDescription.
  ///
  /// In zh, this message translates to:
  /// **'集中查看正在执行的操作，以及需要你处理的问题。'**
  String get backgroundTasksPageDescription;

  /// No description provided for @runningTasks.
  ///
  /// In zh, this message translates to:
  /// **'进行中'**
  String get runningTasks;

  /// No description provided for @tasksNeedingAttention.
  ///
  /// In zh, this message translates to:
  /// **'需要处理'**
  String get tasksNeedingAttention;

  /// No description provided for @clearFailedTasks.
  ///
  /// In zh, this message translates to:
  /// **'清除记录'**
  String get clearFailedTasks;

  /// No description provided for @clearFailedTasksQuestion.
  ///
  /// In zh, this message translates to:
  /// **'清除失败任务记录？'**
  String get clearFailedTasksQuestion;

  /// No description provided for @clearFailedTasksDescription.
  ///
  /// In zh, this message translates to:
  /// **'将移除全部失败记录及其临时文件，不会中断正在执行的任务，也不会影响已经保存的内容。'**
  String get clearFailedTasksDescription;

  /// No description provided for @stopTask.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get stopTask;

  /// No description provided for @modelTask.
  ///
  /// In zh, this message translates to:
  /// **'模型与下载'**
  String get modelTask;

  /// No description provided for @attachmentTask.
  ///
  /// In zh, this message translates to:
  /// **'附件导入'**
  String get attachmentTask;

  /// No description provided for @transcriptionTask.
  ///
  /// In zh, this message translates to:
  /// **'音频处理'**
  String get transcriptionTask;

  /// No description provided for @localInferenceTask.
  ///
  /// In zh, this message translates to:
  /// **'本地推理'**
  String get localInferenceTask;

  /// No description provided for @backgroundTaskCount.
  ///
  /// In zh, this message translates to:
  /// **'后台任务 · {count} 项'**
  String backgroundTaskCount(int count);

  /// No description provided for @noBackgroundTasks.
  ///
  /// In zh, this message translates to:
  /// **'当前没有正在运行或需要处理的任务'**
  String get noBackgroundTasks;

  /// No description provided for @backgroundTaskSummary.
  ///
  /// In zh, this message translates to:
  /// **'{active} 项进行中 · {failed} 项需要处理'**
  String backgroundTaskSummary(int active, int failed);

  /// No description provided for @allTasksComplete.
  ///
  /// In zh, this message translates to:
  /// **'所有任务均已完成'**
  String get allTasksComplete;

  /// No description provided for @taskActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'任务操作失败：{error}'**
  String taskActionFailed(String error);

  /// No description provided for @taskProgress.
  ///
  /// In zh, this message translates to:
  /// **'{title}进度'**
  String taskProgress(String title);

  /// No description provided for @audioTranscription.
  ///
  /// In zh, this message translates to:
  /// **'音频转写'**
  String get audioTranscription;

  /// No description provided for @liveDictation.
  ///
  /// In zh, this message translates to:
  /// **'实时听写'**
  String get liveDictation;

  /// No description provided for @readAloud.
  ///
  /// In zh, this message translates to:
  /// **'朗读'**
  String get readAloud;

  /// No description provided for @localInferenceInUse.
  ///
  /// In zh, this message translates to:
  /// **'正在使用本地推理资源'**
  String get localInferenceInUse;

  /// No description provided for @connectingModelSource.
  ///
  /// In zh, this message translates to:
  /// **'正在连接下载源'**
  String get connectingModelSource;

  /// No description provided for @downloadingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在下载模型'**
  String get downloadingModel;

  /// No description provided for @importingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在导入模型'**
  String get importingModel;

  /// No description provided for @waitingToInstall.
  ///
  /// In zh, this message translates to:
  /// **'等待安装资源'**
  String get waitingToInstall;

  /// No description provided for @verifyingAndInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在校验并安装'**
  String get verifyingAndInstalling;

  /// No description provided for @canceling.
  ///
  /// In zh, this message translates to:
  /// **'正在取消'**
  String get canceling;

  /// No description provided for @completed.
  ///
  /// In zh, this message translates to:
  /// **'已完成'**
  String get completed;

  /// No description provided for @failed.
  ///
  /// In zh, this message translates to:
  /// **'失败'**
  String get failed;

  /// No description provided for @canceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消'**
  String get canceled;

  /// No description provided for @modelTaskFailed.
  ///
  /// In zh, this message translates to:
  /// **'模型任务失败'**
  String get modelTaskFailed;

  /// No description provided for @importingAttachment.
  ///
  /// In zh, this message translates to:
  /// **'正在导入附件'**
  String get importingAttachment;

  /// No description provided for @savingToNote.
  ///
  /// In zh, this message translates to:
  /// **'正在保存到笔记'**
  String get savingToNote;

  /// No description provided for @attachmentImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'附件导入失败'**
  String get attachmentImportFailed;

  /// No description provided for @transcriptionFailed.
  ///
  /// In zh, this message translates to:
  /// **'转写失败'**
  String get transcriptionFailed;

  /// No description provided for @preparingTranscription.
  ///
  /// In zh, this message translates to:
  /// **'正在准备转写'**
  String get preparingTranscription;

  /// No description provided for @decodingAudio.
  ///
  /// In zh, this message translates to:
  /// **'正在解码音频'**
  String get decodingAudio;

  /// No description provided for @identifyingSpeakers.
  ///
  /// In zh, this message translates to:
  /// **'正在区分说话人'**
  String get identifyingSpeakers;

  /// No description provided for @recognizingSpeech.
  ///
  /// In zh, this message translates to:
  /// **'正在识别语音'**
  String get recognizingSpeech;

  /// No description provided for @savingTranscript.
  ///
  /// In zh, this message translates to:
  /// **'正在保存转写'**
  String get savingTranscript;

  /// No description provided for @systemAuthentication.
  ///
  /// In zh, this message translates to:
  /// **'使用系统身份验证'**
  String get systemAuthentication;

  /// No description provided for @systemAuthenticationDescription.
  ///
  /// In zh, this message translates to:
  /// **'通过设备已有的指纹、人脸识别或锁屏密码解锁。非空笔记不会读取或保存你的生物特征。'**
  String get systemAuthenticationDescription;

  /// No description provided for @enableAppLock.
  ///
  /// In zh, this message translates to:
  /// **'启用应用锁'**
  String get enableAppLock;

  /// No description provided for @appLockEnabledDescription.
  ///
  /// In zh, this message translates to:
  /// **'打开应用时会验证设备身份'**
  String get appLockEnabledDescription;

  /// No description provided for @appLockDisabledDescription.
  ///
  /// In zh, this message translates to:
  /// **'默认关闭，不影响现有数据'**
  String get appLockDisabledDescription;

  /// No description provided for @autoLockAfterLeaving.
  ///
  /// In zh, this message translates to:
  /// **'离开应用后自动锁定'**
  String get autoLockAfterLeaving;

  /// No description provided for @lockNow.
  ///
  /// In zh, this message translates to:
  /// **'立即锁定'**
  String get lockNow;

  /// No description provided for @appLockLimitDescription.
  ///
  /// In zh, this message translates to:
  /// **'应用锁用于阻止他人在已解锁设备上直接查看内容，不会加密数据库、附件或已经导出的备份。'**
  String get appLockLimitDescription;

  /// No description provided for @privacyProtection.
  ///
  /// In zh, this message translates to:
  /// **'隐私保护'**
  String get privacyProtection;

  /// No description provided for @systemAuthenticationPrivacyFooter.
  ///
  /// In zh, this message translates to:
  /// **'系统身份验证 · 本地内容保持私密'**
  String get systemAuthenticationPrivacyFooter;

  /// No description provided for @waitingForSystemAuthentication.
  ///
  /// In zh, this message translates to:
  /// **'正在等待系统身份验证'**
  String get waitingForSystemAuthentication;

  /// No description provided for @preparingAppLock.
  ///
  /// In zh, this message translates to:
  /// **'正在准备应用锁'**
  String get preparingAppLock;

  /// No description provided for @waitingForSystemVerification.
  ///
  /// In zh, this message translates to:
  /// **'等待系统验证'**
  String get waitingForSystemVerification;

  /// No description provided for @appLocked.
  ///
  /// In zh, this message translates to:
  /// **'应用已锁定'**
  String get appLocked;

  /// No description provided for @loadingLocalSecuritySettings.
  ///
  /// In zh, this message translates to:
  /// **'正在载入本地安全设置'**
  String get loadingLocalSecuritySettings;

  /// No description provided for @completeSystemAuthentication.
  ///
  /// In zh, this message translates to:
  /// **'请在系统弹窗中完成身份验证'**
  String get completeSystemAuthentication;

  /// No description provided for @unlockAppDescription.
  ///
  /// In zh, this message translates to:
  /// **'验证设备身份后继续使用非空笔记'**
  String get unlockAppDescription;

  /// No description provided for @authenticateAndUnlock.
  ///
  /// In zh, this message translates to:
  /// **'验证并解锁'**
  String get authenticateAndUnlock;

  /// No description provided for @contentHidden.
  ///
  /// In zh, this message translates to:
  /// **'内容已隐藏'**
  String get contentHidden;

  /// No description provided for @authenticateToContinue.
  ///
  /// In zh, this message translates to:
  /// **'验证设备身份以继续'**
  String get authenticateToContinue;

  /// No description provided for @authenticateToEnableAppLock.
  ///
  /// In zh, this message translates to:
  /// **'验证设备身份以开启应用锁'**
  String get authenticateToEnableAppLock;

  /// No description provided for @authenticateToDisableAppLock.
  ///
  /// In zh, this message translates to:
  /// **'验证设备身份以关闭应用锁'**
  String get authenticateToDisableAppLock;

  /// No description provided for @useDevicePassword.
  ///
  /// In zh, this message translates to:
  /// **'使用设备密码'**
  String get useDevicePassword;

  /// No description provided for @authenticationCanceled.
  ///
  /// In zh, this message translates to:
  /// **'认证已取消'**
  String get authenticationCanceled;

  /// No description provided for @authenticationFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'身份验证失败，请重试'**
  String get authenticationFailedRetry;

  /// No description provided for @authenticationTemporarilyUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法调用系统身份验证，请稍后重试'**
  String get authenticationTemporarilyUnavailable;

  /// No description provided for @authenticationCredentialsRequired.
  ///
  /// In zh, this message translates to:
  /// **'请先在系统设置中配置锁屏密码、指纹或人脸识别'**
  String get authenticationCredentialsRequired;

  /// No description provided for @authenticationUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前设备无法使用系统身份验证'**
  String get authenticationUnavailable;

  /// No description provided for @authenticationLockedOut.
  ///
  /// In zh, this message translates to:
  /// **'尝试次数过多，请使用设备密码或稍后重试'**
  String get authenticationLockedOut;

  /// No description provided for @authenticationInProgress.
  ///
  /// In zh, this message translates to:
  /// **'系统身份验证正在进行'**
  String get authenticationInProgress;

  /// No description provided for @authenticationUiUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法显示系统身份验证界面'**
  String get authenticationUiUnavailable;

  /// No description provided for @appLockSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'应用锁设置保存失败，请检查设备存储空间'**
  String get appLockSaveFailed;

  /// No description provided for @autoLockSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'自动锁定时间保存失败，请检查设备存储空间'**
  String get autoLockSaveFailed;

  /// No description provided for @back.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get back;

  /// No description provided for @syncMethod.
  ///
  /// In zh, this message translates to:
  /// **'同步方式'**
  String get syncMethod;

  /// No description provided for @saveConfiguration.
  ///
  /// In zh, this message translates to:
  /// **'保存配置'**
  String get saveConfiguration;

  /// No description provided for @testConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get testConnection;

  /// No description provided for @syncing.
  ///
  /// In zh, this message translates to:
  /// **'正在同步…'**
  String get syncing;

  /// No description provided for @syncNow.
  ///
  /// In zh, this message translates to:
  /// **'立即同步'**
  String get syncNow;

  /// No description provided for @manualSyncForegroundHint.
  ///
  /// In zh, this message translates to:
  /// **'同步期间请保持应用在前台。只有手动点击“立即同步”才会连接云端。'**
  String get manualSyncForegroundHint;

  /// No description provided for @serverAddress.
  ///
  /// In zh, this message translates to:
  /// **'服务器地址'**
  String get serverAddress;

  /// No description provided for @username.
  ///
  /// In zh, this message translates to:
  /// **'用户名'**
  String get username;

  /// No description provided for @passwordOrAppPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码或应用专用密码'**
  String get passwordOrAppPassword;

  /// No description provided for @remoteDirectory.
  ///
  /// In zh, this message translates to:
  /// **'远程目录'**
  String get remoteDirectory;

  /// No description provided for @objectPrefix.
  ///
  /// In zh, this message translates to:
  /// **'对象前缀'**
  String get objectPrefix;

  /// No description provided for @pathStyleAddress.
  ///
  /// In zh, this message translates to:
  /// **'Path-style 地址'**
  String get pathStyleAddress;

  /// No description provided for @pathStyleDescription.
  ///
  /// In zh, this message translates to:
  /// **'MinIO、多数兼容 S3 的对象存储通常需要开启'**
  String get pathStyleDescription;

  /// No description provided for @hide.
  ///
  /// In zh, this message translates to:
  /// **'隐藏'**
  String get hide;

  /// No description provided for @show.
  ///
  /// In zh, this message translates to:
  /// **'显示'**
  String get show;

  /// No description provided for @cloudConfigurationSaved.
  ///
  /// In zh, this message translates to:
  /// **'云同步配置已保存在本机'**
  String get cloudConfigurationSaved;

  /// No description provided for @connectionSuccessful.
  ///
  /// In zh, this message translates to:
  /// **'连接成功，云端读写权限正常'**
  String get connectionSuccessful;

  /// No description provided for @syncConflictDetected.
  ///
  /// In zh, this message translates to:
  /// **'检测到同步冲突'**
  String get syncConflictDetected;

  /// No description provided for @syncConflictDescription.
  ///
  /// In zh, this message translates to:
  /// **'本机数据与云端数据都可能有变更。\n\n云端版本：{date}\n请选择要保留的一份；另一份将被覆盖。'**
  String syncConflictDescription(String date);

  /// No description provided for @notNow.
  ///
  /// In zh, this message translates to:
  /// **'暂不处理'**
  String get notNow;

  /// No description provided for @useCloudVersion.
  ///
  /// In zh, this message translates to:
  /// **'使用云端'**
  String get useCloudVersion;

  /// No description provided for @keepLocalVersion.
  ///
  /// In zh, this message translates to:
  /// **'保留本机'**
  String get keepLocalVersion;

  /// No description provided for @syncedLocalToCloud.
  ///
  /// In zh, this message translates to:
  /// **'本机数据已同步到云端'**
  String get syncedLocalToCloud;

  /// No description provided for @updatedFromCloud.
  ///
  /// In zh, this message translates to:
  /// **'已使用云端数据更新本机'**
  String get updatedFromCloud;

  /// No description provided for @cloudAlreadyUpToDate.
  ///
  /// In zh, this message translates to:
  /// **'本机与云端数据已经一致'**
  String get cloudAlreadyUpToDate;

  /// No description provided for @syncConflictUnresolved.
  ///
  /// In zh, this message translates to:
  /// **'同步冲突尚未处理'**
  String get syncConflictUnresolved;

  /// No description provided for @httpsCertificateFailed.
  ///
  /// In zh, this message translates to:
  /// **'HTTPS 证书验证失败，请检查服务器证书'**
  String get httpsCertificateFailed;

  /// No description provided for @cloudConnectionFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法连接云端，请检查网络和服务器地址'**
  String get cloudConnectionFailed;

  /// No description provided for @cloudConnectionTimeout.
  ///
  /// In zh, this message translates to:
  /// **'连接云端超时'**
  String get cloudConnectionTimeout;

  /// No description provided for @manualUserDataSync.
  ///
  /// In zh, this message translates to:
  /// **'仅手动同步用户数据'**
  String get manualUserDataSync;

  /// No description provided for @syncScopeDescription.
  ///
  /// In zh, this message translates to:
  /// **'包含笔记、聊天和附件；不包含模型、缓存、应用锁和云端账号配置。'**
  String get syncScopeDescription;

  /// No description provided for @cloudEncryptionWarning.
  ///
  /// In zh, this message translates to:
  /// **'云端归档不额外加密，请使用 HTTPS 与可信存储。'**
  String get cloudEncryptionWarning;

  /// No description provided for @lastSyncedAt.
  ///
  /// In zh, this message translates to:
  /// **'上次同步：{date}'**
  String lastSyncedAt(String date);

  /// No description provided for @cut.
  ///
  /// In zh, this message translates to:
  /// **'剪切'**
  String get cut;

  /// No description provided for @copy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copy;

  /// No description provided for @details.
  ///
  /// In zh, this message translates to:
  /// **'详情'**
  String get details;

  /// No description provided for @paste.
  ///
  /// In zh, this message translates to:
  /// **'粘贴'**
  String get paste;

  /// No description provided for @selectAll.
  ///
  /// In zh, this message translates to:
  /// **'全选'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In zh, this message translates to:
  /// **'取消全选'**
  String get deselectAll;

  /// No description provided for @share.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get share;

  /// No description provided for @invalidExternalLink.
  ///
  /// In zh, this message translates to:
  /// **'这个链接地址无效或使用了不受支持的协议'**
  String get invalidExternalLink;

  /// No description provided for @openExternalLinkQuestion.
  ///
  /// In zh, this message translates to:
  /// **'打开外部链接？'**
  String get openExternalLinkQuestion;

  /// No description provided for @externalLinkWarning.
  ///
  /// In zh, this message translates to:
  /// **'{destination}\n\n链接将交给系统中的其他应用处理，可能离开非空笔记。'**
  String externalLinkWarning(String destination);

  /// No description provided for @continueOpening.
  ///
  /// In zh, this message translates to:
  /// **'继续打开'**
  String get continueOpening;

  /// No description provided for @noExternalLinkHandler.
  ///
  /// In zh, this message translates to:
  /// **'系统中没有可以打开这个链接的应用'**
  String get noExternalLinkHandler;

  /// No description provided for @externalLinkOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开这个链接'**
  String get externalLinkOpenFailed;

  /// No description provided for @remoteImageBlocked.
  ///
  /// In zh, this message translates to:
  /// **'未加载外部图片：{label}'**
  String remoteImageBlocked(String label);

  /// No description provided for @mathFormulaSemantics.
  ///
  /// In zh, this message translates to:
  /// **'数学公式：{formula}'**
  String mathFormulaSemantics(String formula);

  /// No description provided for @assistantPrivacyDescription.
  ///
  /// In zh, this message translates to:
  /// **'直接告诉 AI 你想做什么。笔记内容只在设备上处理。'**
  String get assistantPrivacyDescription;

  /// No description provided for @processingScope.
  ///
  /// In zh, this message translates to:
  /// **'处理范围'**
  String get processingScope;

  /// No description provided for @scopeSelection.
  ///
  /// In zh, this message translates to:
  /// **'选中文字'**
  String get scopeSelection;

  /// No description provided for @scopeCurrentBlock.
  ///
  /// In zh, this message translates to:
  /// **'当前段落'**
  String get scopeCurrentBlock;

  /// No description provided for @scopeFullNote.
  ///
  /// In zh, this message translates to:
  /// **'整篇笔记'**
  String get scopeFullNote;

  /// No description provided for @chatWithThisNote.
  ///
  /// In zh, this message translates to:
  /// **'和这篇笔记对话'**
  String get chatWithThisNote;

  /// No description provided for @chatWithThisNoteDescription.
  ///
  /// In zh, this message translates to:
  /// **'把所选范围作为上下文，连续追问和整理'**
  String get chatWithThisNoteDescription;

  /// No description provided for @linkedNote.
  ///
  /// In zh, this message translates to:
  /// **'关联笔记'**
  String get linkedNote;

  /// No description provided for @noteSources.
  ///
  /// In zh, this message translates to:
  /// **'笔记来源'**
  String get noteSources;

  /// No description provided for @openSourceNote.
  ///
  /// In zh, this message translates to:
  /// **'打开来源笔记：{title}'**
  String openSourceNote(String title);

  /// No description provided for @sourceNoteUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'这篇来源笔记已不存在'**
  String get sourceNoteUnavailable;

  /// No description provided for @referenceNotes.
  ///
  /// In zh, this message translates to:
  /// **'引用资料库笔记'**
  String get referenceNotes;

  /// No description provided for @referenceNotesDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择多篇笔记作为下一条消息的来源'**
  String get referenceNotesDescription;

  /// No description provided for @recentNotes.
  ///
  /// In zh, this message translates to:
  /// **'最近笔记'**
  String get recentNotes;

  /// No description provided for @selectedNoteCount.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {count} 篇'**
  String selectedNoteCount(int count);

  /// No description provided for @noteReferenceLimit.
  ///
  /// In zh, this message translates to:
  /// **'每次最多引用 {count} 篇笔记'**
  String noteReferenceLimit(int count);

  /// No description provided for @noMatchingNotes.
  ///
  /// In zh, this message translates to:
  /// **'没有找到匹配的笔记'**
  String get noMatchingNotes;

  /// No description provided for @addSelectedNotes.
  ///
  /// In zh, this message translates to:
  /// **'引用所选笔记'**
  String get addSelectedNotes;

  /// No description provided for @removeNoteReference.
  ///
  /// In zh, this message translates to:
  /// **'移除笔记引用'**
  String get removeNoteReference;

  /// No description provided for @assistantProposedAction.
  ///
  /// In zh, this message translates to:
  /// **'待确认的笔记操作'**
  String get assistantProposedAction;

  /// No description provided for @toolCreateNote.
  ///
  /// In zh, this message translates to:
  /// **'创建新笔记'**
  String get toolCreateNote;

  /// No description provided for @toolAppendNote.
  ///
  /// In zh, this message translates to:
  /// **'追加到笔记'**
  String get toolAppendNote;

  /// No description provided for @toolReplaceNote.
  ///
  /// In zh, this message translates to:
  /// **'替换笔记正文'**
  String get toolReplaceNote;

  /// No description provided for @reviewToolAction.
  ///
  /// In zh, this message translates to:
  /// **'预览并确认'**
  String get reviewToolAction;

  /// No description provided for @toolActionCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已执行'**
  String get toolActionCompleted;

  /// No description provided for @toolActionConfirmationNotice.
  ///
  /// In zh, this message translates to:
  /// **'此操作会修改本地笔记，确认前不会写入。'**
  String get toolActionConfirmationNotice;

  /// No description provided for @toolTargetNote.
  ///
  /// In zh, this message translates to:
  /// **'目标笔记'**
  String get toolTargetNote;

  /// No description provided for @toolCurrentContent.
  ///
  /// In zh, this message translates to:
  /// **'当前内容'**
  String get toolCurrentContent;

  /// No description provided for @toolProposedContent.
  ///
  /// In zh, this message translates to:
  /// **'拟写入内容'**
  String get toolProposedContent;

  /// No description provided for @confirmCreateNote.
  ///
  /// In zh, this message translates to:
  /// **'确认创建'**
  String get confirmCreateNote;

  /// No description provided for @confirmAppendNote.
  ///
  /// In zh, this message translates to:
  /// **'确认追加'**
  String get confirmAppendNote;

  /// No description provided for @confirmReplaceNote.
  ///
  /// In zh, this message translates to:
  /// **'确认替换'**
  String get confirmReplaceNote;

  /// No description provided for @toolActionSucceeded.
  ///
  /// In zh, this message translates to:
  /// **'笔记操作已完成'**
  String get toolActionSucceeded;

  /// No description provided for @toolActionTargetMissing.
  ///
  /// In zh, this message translates to:
  /// **'找不到目标笔记，可能已被删除'**
  String get toolActionTargetMissing;

  /// No description provided for @toolActionFailed.
  ///
  /// In zh, this message translates to:
  /// **'笔记操作失败：{error}'**
  String toolActionFailed(String error);

  /// No description provided for @toolProposalFallback.
  ///
  /// In zh, this message translates to:
  /// **'我准备了一个笔记操作，请预览确认后再执行。'**
  String get toolProposalFallback;

  /// No description provided for @toolSearchNoResults.
  ///
  /// In zh, this message translates to:
  /// **'资料库中没有找到与“{query}”匹配的笔记。请直接说明未找到，不要重复搜索。'**
  String toolSearchNoResults(String query);

  /// No description provided for @toolSearchResultsReady.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记已返回“{query}”的笔记搜索结果。请使用来源回答原问题；不要重复搜索。'**
  String toolSearchResultsReady(String query);

  /// No description provided for @toolSearchRetryBlocked.
  ///
  /// In zh, this message translates to:
  /// **'模型未能使用检索结果完成回答，请换个问法重试。'**
  String get toolSearchRetryBlocked;

  /// No description provided for @writeReplyToNote.
  ///
  /// In zh, this message translates to:
  /// **'写入笔记'**
  String get writeReplyToNote;

  /// No description provided for @writeReplyToNoteDescription.
  ///
  /// In zh, this message translates to:
  /// **'预览内容并确认写入位置'**
  String get writeReplyToNoteDescription;

  /// No description provided for @confirmWriteToNote.
  ///
  /// In zh, this message translates to:
  /// **'确认写入'**
  String get confirmWriteToNote;

  /// No description provided for @replyWrittenToNote.
  ///
  /// In zh, this message translates to:
  /// **'回答已写入笔记'**
  String get replyWrittenToNote;

  /// No description provided for @replyWriteToNoteFailed.
  ///
  /// In zh, this message translates to:
  /// **'笔记内容已经变化，请返回笔记后重试'**
  String get replyWriteToNoteFailed;

  /// No description provided for @assistantChatResultHeading.
  ///
  /// In zh, this message translates to:
  /// **'本地助手回答'**
  String get assistantChatResultHeading;

  /// No description provided for @chatNoteEmpty.
  ///
  /// In zh, this message translates to:
  /// **'请先输入笔记内容，再开始对话'**
  String get chatNoteEmpty;

  /// No description provided for @assistantCustomHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：把这些想法整理成一封简洁的英文邮件…'**
  String get assistantCustomHint;

  /// No description provided for @writeWithAi.
  ///
  /// In zh, this message translates to:
  /// **'AI 创作'**
  String get writeWithAi;

  /// No description provided for @inlineAssistantHint.
  ///
  /// In zh, this message translates to:
  /// **'描述你希望 AI 写入的内容…'**
  String get inlineAssistantHint;

  /// No description provided for @inlineAssistantInsertAtCursor.
  ///
  /// In zh, this message translates to:
  /// **'从光标处写入'**
  String get inlineAssistantInsertAtCursor;

  /// No description provided for @inlineAssistantReplaceSelection.
  ///
  /// In zh, this message translates to:
  /// **'替换选中内容'**
  String get inlineAssistantReplaceSelection;

  /// No description provided for @inlineAssistantEditCurrentBlock.
  ///
  /// In zh, this message translates to:
  /// **'修改当前段落'**
  String get inlineAssistantEditCurrentBlock;

  /// No description provided for @inlineAssistantEditFullNote.
  ///
  /// In zh, this message translates to:
  /// **'修改整篇笔记'**
  String get inlineAssistantEditFullNote;

  /// No description provided for @inlineAssistantEditMetadata.
  ///
  /// In zh, this message translates to:
  /// **'更新标题与标签'**
  String get inlineAssistantEditMetadata;

  /// No description provided for @inlineAssistantWriting.
  ///
  /// In zh, this message translates to:
  /// **'正在写入笔记…'**
  String get inlineAssistantWriting;

  /// No description provided for @inlineAssistantLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在准备本地模型…'**
  String get inlineAssistantLoading;

  /// No description provided for @inlineAssistantWritten.
  ///
  /// In zh, this message translates to:
  /// **'笔记内容已更新'**
  String get inlineAssistantWritten;

  /// No description provided for @inlineAssistantMetadataUpdated.
  ///
  /// In zh, this message translates to:
  /// **'笔记信息已更新'**
  String get inlineAssistantMetadataUpdated;

  /// No description provided for @inlineAssistantContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续创作'**
  String get inlineAssistantContinue;

  /// No description provided for @inlineAssistantContinueWriting.
  ///
  /// In zh, this message translates to:
  /// **'续写当前内容'**
  String get inlineAssistantContinueWriting;

  /// No description provided for @inlineAssistantMakeList.
  ///
  /// In zh, this message translates to:
  /// **'整理成清单'**
  String get inlineAssistantMakeList;

  /// No description provided for @inlineAssistantExpandIdea.
  ///
  /// In zh, this message translates to:
  /// **'展开这个想法'**
  String get inlineAssistantExpandIdea;

  /// No description provided for @inlineAssistantGenerateMetadata.
  ///
  /// In zh, this message translates to:
  /// **'生成标题和标签'**
  String get inlineAssistantGenerateMetadata;

  /// No description provided for @inlineAssistantInvalidMetadata.
  ///
  /// In zh, this message translates to:
  /// **'无法识别 AI 返回的标题与标签，请重试'**
  String get inlineAssistantInvalidMetadata;

  /// No description provided for @inlineAssistantNoMetadataChanges.
  ///
  /// In zh, this message translates to:
  /// **'模型没有生成标题或标签修改'**
  String get inlineAssistantNoMetadataChanges;

  /// No description provided for @startGenerating.
  ///
  /// In zh, this message translates to:
  /// **'开始生成'**
  String get startGenerating;

  /// No description provided for @quickActions.
  ///
  /// In zh, this message translates to:
  /// **'快捷操作'**
  String get quickActions;

  /// No description provided for @assistantSummarize.
  ///
  /// In zh, this message translates to:
  /// **'总结笔记'**
  String get assistantSummarize;

  /// No description provided for @assistantSummarizeDescription.
  ///
  /// In zh, this message translates to:
  /// **'提炼核心结论与关键要点'**
  String get assistantSummarizeDescription;

  /// No description provided for @assistantExtractTodos.
  ///
  /// In zh, this message translates to:
  /// **'提取待办'**
  String get assistantExtractTodos;

  /// No description provided for @assistantExtractTodosDescription.
  ///
  /// In zh, this message translates to:
  /// **'找出明确、可执行的事项'**
  String get assistantExtractTodosDescription;

  /// No description provided for @assistantPolish.
  ///
  /// In zh, this message translates to:
  /// **'润色内容'**
  String get assistantPolish;

  /// No description provided for @assistantPolishDescription.
  ///
  /// In zh, this message translates to:
  /// **'保留事实与结构，改善表达'**
  String get assistantPolishDescription;

  /// No description provided for @assistantCustomAction.
  ///
  /// In zh, this message translates to:
  /// **'自定义指令'**
  String get assistantCustomAction;

  /// No description provided for @assistantNoOutput.
  ///
  /// In zh, this message translates to:
  /// **'模型没有生成内容'**
  String get assistantNoOutput;

  /// No description provided for @stopGenerating.
  ///
  /// In zh, this message translates to:
  /// **'停止生成'**
  String get stopGenerating;

  /// No description provided for @regenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get regenerate;

  /// No description provided for @chooseGeneratedContentPlacement.
  ///
  /// In zh, this message translates to:
  /// **'选择如何使用生成内容'**
  String get chooseGeneratedContentPlacement;

  /// No description provided for @placementReplace.
  ///
  /// In zh, this message translates to:
  /// **'替换原内容'**
  String get placementReplace;

  /// No description provided for @placementInsertBelow.
  ///
  /// In zh, this message translates to:
  /// **'插入到段落下方'**
  String get placementInsertBelow;

  /// No description provided for @placementAppend.
  ///
  /// In zh, this message translates to:
  /// **'追加到笔记末尾'**
  String get placementAppend;

  /// No description provided for @useCurrentContent.
  ///
  /// In zh, this message translates to:
  /// **'使用当前内容'**
  String get useCurrentContent;

  /// No description provided for @useGeneratedContent.
  ///
  /// In zh, this message translates to:
  /// **'使用生成内容'**
  String get useGeneratedContent;

  /// No description provided for @generatedContentCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制生成内容'**
  String get generatedContentCopied;

  /// No description provided for @loadingLocalModel.
  ///
  /// In zh, this message translates to:
  /// **'正在加载本地模型…'**
  String get loadingLocalModel;

  /// No description provided for @generatingOnDevice.
  ///
  /// In zh, this message translates to:
  /// **'正在设备上生成…'**
  String get generatingOnDevice;

  /// No description provided for @generationCompleted.
  ///
  /// In zh, this message translates to:
  /// **'生成完成，请检查后使用'**
  String get generationCompleted;

  /// No description provided for @generationLimitReached.
  ///
  /// In zh, this message translates to:
  /// **'已达到输出上限，请检查结果'**
  String get generationLimitReached;

  /// No description provided for @generationStoppedUsable.
  ///
  /// In zh, this message translates to:
  /// **'生成已停止，可复制或插入当前内容'**
  String get generationStoppedUsable;

  /// No description provided for @generationTimedOutUsable.
  ///
  /// In zh, this message translates to:
  /// **'生成超时，可重试或复制当前内容'**
  String get generationTimedOutUsable;

  /// No description provided for @generationIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'本地生成未完成'**
  String get generationIncomplete;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @maybeLater.
  ///
  /// In zh, this message translates to:
  /// **'稍后再说'**
  String get maybeLater;

  /// No description provided for @readNoteAloud.
  ///
  /// In zh, this message translates to:
  /// **'朗读笔记'**
  String get readNoteAloud;

  /// No description provided for @offlineReadAloudModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要离线朗读模型'**
  String get offlineReadAloudModelRequired;

  /// No description provided for @readAloudModelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'Kokoro 中英双语 INT8 首次使用需下载约 140.2 MB。下载后，笔记朗读全程断网可用。'**
  String get readAloudModelDownloadDescription;

  /// No description provided for @manageModels.
  ///
  /// In zh, this message translates to:
  /// **'管理模型'**
  String get manageModels;

  /// No description provided for @noteReadAloudFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法朗读这篇笔记'**
  String get noteReadAloudFailed;

  /// No description provided for @liveDictationIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'实时听写没有完成'**
  String get liveDictationIncomplete;

  /// No description provided for @unsavedDraftFound.
  ///
  /// In zh, this message translates to:
  /// **'发现未保存的草稿'**
  String get unsavedDraftFound;

  /// No description provided for @unsavedDraftDescription.
  ///
  /// In zh, this message translates to:
  /// **'上次编辑可能意外中断。要恢复尚未写入笔记的内容吗？'**
  String get unsavedDraftDescription;

  /// No description provided for @discardDraft.
  ///
  /// In zh, this message translates to:
  /// **'放弃草稿'**
  String get discardDraft;

  /// No description provided for @restore.
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get restore;

  /// No description provided for @liveSpeechModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要实时语音模型'**
  String get liveSpeechModelRequired;

  /// No description provided for @liveSpeechModelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前选择的是{model}，首次使用需下载约 {size}。下载完成后，听写全程断网可用。'**
  String liveSpeechModelDownloadDescription(String model, String size);

  /// No description provided for @placeCursorInText.
  ///
  /// In zh, this message translates to:
  /// **'请先将光标放在文字区域'**
  String get placeCursorInText;

  /// No description provided for @liveDictationStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法开始实时听写'**
  String get liveDictationStartFailed;

  /// No description provided for @localLanguageModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要本地语言模型'**
  String get localLanguageModelRequired;

  /// No description provided for @localLanguageModelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前选择的是 {model}，首次使用需下载约 {size}。下载完成后，笔记内容只在本机处理。'**
  String localLanguageModelDownloadDescription(String model, String size);

  /// No description provided for @assistantReplacedContent.
  ///
  /// In zh, this message translates to:
  /// **'已替换原内容'**
  String get assistantReplacedContent;

  /// No description provided for @assistantInsertedBelow.
  ///
  /// In zh, this message translates to:
  /// **'已插入到当前段落下方'**
  String get assistantInsertedBelow;

  /// No description provided for @assistantAppended.
  ///
  /// In zh, this message translates to:
  /// **'已追加到笔记末尾'**
  String get assistantAppended;

  /// No description provided for @noteChangedRetryAssistant.
  ///
  /// In zh, this message translates to:
  /// **'笔记内容已经变化，请重新发起 AI 操作'**
  String get noteChangedRetryAssistant;

  /// No description provided for @assistantLaunchFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法启动本地助手：{error}'**
  String assistantLaunchFailed(String error);

  /// No description provided for @autosaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'自动保存失败：{error}'**
  String autosaveFailed(String error);

  /// No description provided for @addToNote.
  ///
  /// In zh, this message translates to:
  /// **'添加到笔记'**
  String get addToNote;

  /// No description provided for @camera.
  ///
  /// In zh, this message translates to:
  /// **'拍照'**
  String get camera;

  /// No description provided for @watermarkCamera.
  ///
  /// In zh, this message translates to:
  /// **'水印相机'**
  String get watermarkCamera;

  /// No description provided for @watermarkLocationTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置水印地点'**
  String get watermarkLocationTitle;

  /// No description provided for @watermarkLocationDescription.
  ///
  /// In zh, this message translates to:
  /// **'自动识别当前位置的地点名称，也可以填写你想展示在照片上的地点。'**
  String get watermarkLocationDescription;

  /// No description provided for @useCurrentLocation.
  ///
  /// In zh, this message translates to:
  /// **'当前位置'**
  String get useCurrentLocation;

  /// No description provided for @enterLocationManually.
  ///
  /// In zh, this message translates to:
  /// **'手动填写'**
  String get enterLocationManually;

  /// No description provided for @detectedLocation.
  ///
  /// In zh, this message translates to:
  /// **'已识别地点'**
  String get detectedLocation;

  /// No description provided for @locationNameUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'已获得定位，但暂时没有识别出地点名称。可以重试或改为手动填写。'**
  String get locationNameUnavailable;

  /// No description provided for @customLocationName.
  ///
  /// In zh, this message translates to:
  /// **'地点名称'**
  String get customLocationName;

  /// No description provided for @customLocationHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：上海外滩、公司会议室'**
  String get customLocationHint;

  /// No description provided for @locationNameRequired.
  ///
  /// In zh, this message translates to:
  /// **'请填写要展示在水印中的地点名称'**
  String get locationNameRequired;

  /// No description provided for @continueToCamera.
  ///
  /// In zh, this message translates to:
  /// **'继续拍照'**
  String get continueToCamera;

  /// No description provided for @locatingForWatermark.
  ///
  /// In zh, this message translates to:
  /// **'正在获取当前位置…'**
  String get locatingForWatermark;

  /// No description provided for @locationServiceDisabled.
  ///
  /// In zh, this message translates to:
  /// **'请先开启系统定位服务，再使用水印相机'**
  String get locationServiceDisabled;

  /// No description provided for @locationPermissionRequired.
  ///
  /// In zh, this message translates to:
  /// **'水印相机需要位置权限；系统地理编码服务可能使用位置查询地名。'**
  String get locationPermissionRequired;

  /// No description provided for @locationPermissionPermanentlyDenied.
  ///
  /// In zh, this message translates to:
  /// **'位置权限已被关闭，请前往系统设置开启后重试'**
  String get locationPermissionPermanentlyDenied;

  /// No description provided for @locationUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法获取当前位置，请到开阔处重试'**
  String get locationUnavailable;

  /// No description provided for @chooseVideo.
  ///
  /// In zh, this message translates to:
  /// **'选择视频'**
  String get chooseVideo;

  /// No description provided for @recordVideo.
  ///
  /// In zh, this message translates to:
  /// **'拍摄视频'**
  String get recordVideo;

  /// No description provided for @playVideo.
  ///
  /// In zh, this message translates to:
  /// **'播放视频'**
  String get playVideo;

  /// No description provided for @videoPlaybackFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法播放这段视频'**
  String get videoPlaybackFailed;

  /// No description provided for @attachmentImportTypeFailed.
  ///
  /// In zh, this message translates to:
  /// **'{type}导入失败'**
  String attachmentImportTypeFailed(String type);

  /// No description provided for @editNote.
  ///
  /// In zh, this message translates to:
  /// **'编辑笔记'**
  String get editNote;

  /// No description provided for @newNote.
  ///
  /// In zh, this message translates to:
  /// **'新笔记'**
  String get newNote;

  /// No description provided for @createNoteShort.
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get createNoteShort;

  /// No description provided for @finishEditing.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get finishEditing;

  /// No description provided for @releaseToInsertImages.
  ///
  /// In zh, this message translates to:
  /// **'松开以插入图片'**
  String get releaseToInsertImages;

  /// No description provided for @onlyImagesCanBeDropped.
  ///
  /// In zh, this message translates to:
  /// **'这里只能拖入图片'**
  String get onlyImagesCanBeDropped;

  /// No description provided for @droppedImagesRejected.
  ///
  /// In zh, this message translates to:
  /// **'部分文件不是支持的图片或超过 20 MB'**
  String get droppedImagesRejected;

  /// No description provided for @autosaveEnabled.
  ///
  /// In zh, this message translates to:
  /// **'自动保存已开启'**
  String get autosaveEnabled;

  /// No description provided for @autosavePending.
  ///
  /// In zh, this message translates to:
  /// **'即将自动保存'**
  String get autosavePending;

  /// No description provided for @autosaving.
  ///
  /// In zh, this message translates to:
  /// **'正在自动保存…'**
  String get autosaving;

  /// No description provided for @autosavedLocally.
  ///
  /// In zh, this message translates to:
  /// **'已自动保存到本机'**
  String get autosavedLocally;

  /// No description provided for @autosaveFailedShort.
  ///
  /// In zh, this message translates to:
  /// **'自动保存失败'**
  String get autosaveFailedShort;

  /// No description provided for @savingEllipsis.
  ///
  /// In zh, this message translates to:
  /// **'正在保存…'**
  String get savingEllipsis;

  /// No description provided for @localDraft.
  ///
  /// In zh, this message translates to:
  /// **'本地草稿'**
  String get localDraft;

  /// No description provided for @savedLocally.
  ///
  /// In zh, this message translates to:
  /// **'已保存在本机'**
  String get savedLocally;

  /// No description provided for @characterCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 字'**
  String characterCount(int count);

  /// No description provided for @stopReadAloud.
  ///
  /// In zh, this message translates to:
  /// **'停止朗读'**
  String get stopReadAloud;

  /// No description provided for @moreNoteActions.
  ///
  /// In zh, this message translates to:
  /// **'更多笔记操作'**
  String get moreNoteActions;

  /// No description provided for @unpin.
  ///
  /// In zh, this message translates to:
  /// **'取消置顶'**
  String get unpin;

  /// No description provided for @pin.
  ///
  /// In zh, this message translates to:
  /// **'置顶'**
  String get pin;

  /// No description provided for @addTags.
  ///
  /// In zh, this message translates to:
  /// **'添加标签'**
  String get addTags;

  /// No description provided for @tags.
  ///
  /// In zh, this message translates to:
  /// **'标签'**
  String get tags;

  /// No description provided for @noteContent.
  ///
  /// In zh, this message translates to:
  /// **'笔记内容'**
  String get noteContent;

  /// No description provided for @attachmentItemCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 项附件'**
  String attachmentItemCount(int count);

  /// No description provided for @noteDescriptionHint.
  ///
  /// In zh, this message translates to:
  /// **'添加说明、想法或摘要…'**
  String get noteDescriptionHint;

  /// No description provided for @noteStartHint.
  ///
  /// In zh, this message translates to:
  /// **'开始记录…'**
  String get noteStartHint;

  /// No description provided for @addMediaOrFile.
  ///
  /// In zh, this message translates to:
  /// **'添加图片、录音或文件'**
  String get addMediaOrFile;

  /// No description provided for @editTags.
  ///
  /// In zh, this message translates to:
  /// **'编辑标签'**
  String get editTags;

  /// No description provided for @tagsDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用逗号分隔多个标签，重复标签会自动合并。'**
  String get tagsDescription;

  /// No description provided for @tagsHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：工作, 灵感, 稍后阅读'**
  String get tagsHint;

  /// No description provided for @stopLiveDictation.
  ///
  /// In zh, this message translates to:
  /// **'停止实时听写'**
  String get stopLiveDictation;

  /// No description provided for @liveVoiceInput.
  ///
  /// In zh, this message translates to:
  /// **'实时语音输入'**
  String get liveVoiceInput;

  /// No description provided for @redo.
  ///
  /// In zh, this message translates to:
  /// **'重做'**
  String get redo;

  /// No description provided for @bold.
  ///
  /// In zh, this message translates to:
  /// **'加粗'**
  String get bold;

  /// No description provided for @italic.
  ///
  /// In zh, this message translates to:
  /// **'斜体'**
  String get italic;

  /// No description provided for @underline.
  ///
  /// In zh, this message translates to:
  /// **'下划线'**
  String get underline;

  /// No description provided for @addLink.
  ///
  /// In zh, this message translates to:
  /// **'添加链接'**
  String get addLink;

  /// No description provided for @editLink.
  ///
  /// In zh, this message translates to:
  /// **'编辑链接'**
  String get editLink;

  /// No description provided for @linkPrivacyDescription.
  ///
  /// In zh, this message translates to:
  /// **'链接会保存在 Markdown 中；打开前仍会由非空笔记进行隐私确认。'**
  String get linkPrivacyDescription;

  /// No description provided for @linkText.
  ///
  /// In zh, this message translates to:
  /// **'显示文字'**
  String get linkText;

  /// No description provided for @linkTextHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：了解更多'**
  String get linkTextHint;

  /// No description provided for @linkAddress.
  ///
  /// In zh, this message translates to:
  /// **'链接地址'**
  String get linkAddress;

  /// No description provided for @linkAddressHint.
  ///
  /// In zh, this message translates to:
  /// **'https://example.com'**
  String get linkAddressHint;

  /// No description provided for @removeLink.
  ///
  /// In zh, this message translates to:
  /// **'移除链接'**
  String get removeLink;

  /// No description provided for @organizingLastSentence.
  ///
  /// In zh, this message translates to:
  /// **'正在整理最后一句…'**
  String get organizingLastSentence;

  /// No description provided for @liveDictationFailed.
  ///
  /// In zh, this message translates to:
  /// **'实时听写失败'**
  String get liveDictationFailed;

  /// No description provided for @listening.
  ///
  /// In zh, this message translates to:
  /// **'正在聆听…'**
  String get listening;

  /// No description provided for @liveDictationElapsed.
  ///
  /// In zh, this message translates to:
  /// **'实时听写  {time}'**
  String liveDictationElapsed(String time);

  /// No description provided for @localVoiceInput.
  ///
  /// In zh, this message translates to:
  /// **'本地语音输入'**
  String get localVoiceInput;

  /// No description provided for @cancelDictation.
  ///
  /// In zh, this message translates to:
  /// **'取消听写'**
  String get cancelDictation;

  /// No description provided for @finishDictation.
  ///
  /// In zh, this message translates to:
  /// **'完成听写'**
  String get finishDictation;

  /// No description provided for @paragraph.
  ///
  /// In zh, this message translates to:
  /// **'正文'**
  String get paragraph;

  /// No description provided for @paragraphStyle.
  ///
  /// In zh, this message translates to:
  /// **'段落样式'**
  String get paragraphStyle;

  /// No description provided for @noteOutline.
  ///
  /// In zh, this message translates to:
  /// **'笔记大纲'**
  String get noteOutline;

  /// No description provided for @noteOutlineHint.
  ///
  /// In zh, this message translates to:
  /// **'轻点标题，跳转到对应位置'**
  String get noteOutlineHint;

  /// No description provided for @noteOutlineEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无标题'**
  String get noteOutlineEmpty;

  /// No description provided for @noteOutlineEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'在底部工具栏将段落设为标题 1–6，即可在这里查看笔记大纲。'**
  String get noteOutlineEmptyHint;

  /// No description provided for @preparingReadAloud.
  ///
  /// In zh, this message translates to:
  /// **'正在准备朗读…'**
  String get preparingReadAloud;

  /// No description provided for @readAloudPlaying.
  ///
  /// In zh, this message translates to:
  /// **'正在朗读'**
  String get readAloudPlaying;

  /// No description provided for @headingLevel.
  ///
  /// In zh, this message translates to:
  /// **'标题 {level}'**
  String headingLevel(int level);

  /// No description provided for @quote.
  ///
  /// In zh, this message translates to:
  /// **'引用'**
  String get quote;

  /// No description provided for @codeBlock.
  ///
  /// In zh, this message translates to:
  /// **'代码块'**
  String get codeBlock;

  /// No description provided for @divider.
  ///
  /// In zh, this message translates to:
  /// **'分割线'**
  String get divider;

  /// No description provided for @listsAndIndentation.
  ///
  /// In zh, this message translates to:
  /// **'列表与缩进'**
  String get listsAndIndentation;

  /// No description provided for @todoItem.
  ///
  /// In zh, this message translates to:
  /// **'待办事项'**
  String get todoItem;

  /// No description provided for @bulletList.
  ///
  /// In zh, this message translates to:
  /// **'无序列表'**
  String get bulletList;

  /// No description provided for @numberedList.
  ///
  /// In zh, this message translates to:
  /// **'有序列表'**
  String get numberedList;

  /// No description provided for @decreaseIndent.
  ///
  /// In zh, this message translates to:
  /// **'减少缩进'**
  String get decreaseIndent;

  /// No description provided for @increaseIndent.
  ///
  /// In zh, this message translates to:
  /// **'增加缩进'**
  String get increaseIndent;

  /// No description provided for @moreFormatting.
  ///
  /// In zh, this message translates to:
  /// **'更多格式'**
  String get moreFormatting;

  /// No description provided for @strikethrough.
  ///
  /// In zh, this message translates to:
  /// **'删除线'**
  String get strikethrough;

  /// No description provided for @inlineCode.
  ///
  /// In zh, this message translates to:
  /// **'行内代码'**
  String get inlineCode;

  /// No description provided for @generatingThumbnail.
  ///
  /// In zh, this message translates to:
  /// **'正在生成缩略图…'**
  String get generatingThumbnail;

  /// No description provided for @importingBytes.
  ///
  /// In zh, this message translates to:
  /// **'正在导入 · {bytes}'**
  String importingBytes(String bytes);

  /// No description provided for @importingPercent.
  ///
  /// In zh, this message translates to:
  /// **'正在导入 {percent}% · {bytes}'**
  String importingPercent(int percent, String bytes);

  /// No description provided for @importCompleteSaving.
  ///
  /// In zh, this message translates to:
  /// **'导入完成，正在保存到笔记…'**
  String get importCompleteSaving;

  /// No description provided for @importFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'导入失败，请重试'**
  String get importFailedRetry;

  /// No description provided for @importCanceled.
  ///
  /// In zh, this message translates to:
  /// **'导入已取消'**
  String get importCanceled;

  /// No description provided for @cancelImport.
  ///
  /// In zh, this message translates to:
  /// **'取消导入'**
  String get cancelImport;

  /// No description provided for @chooseTypeAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新选择{type}'**
  String chooseTypeAgain(String type);

  /// No description provided for @adjustAttachment.
  ///
  /// In zh, this message translates to:
  /// **'调整附件'**
  String get adjustAttachment;

  /// No description provided for @moveUp.
  ///
  /// In zh, this message translates to:
  /// **'上移'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In zh, this message translates to:
  /// **'下移'**
  String get moveDown;

  /// No description provided for @referenceInBody.
  ///
  /// In zh, this message translates to:
  /// **'引用到正文'**
  String get referenceInBody;

  /// No description provided for @importFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'导入失败 · {error}'**
  String importFailedDetail(String error);

  /// No description provided for @assistantSummaryHeading.
  ///
  /// In zh, this message translates to:
  /// **'本地助手摘要'**
  String get assistantSummaryHeading;

  /// No description provided for @assistantTodosHeading.
  ///
  /// In zh, this message translates to:
  /// **'本地助手待办'**
  String get assistantTodosHeading;

  /// No description provided for @assistantPolishedHeading.
  ///
  /// In zh, this message translates to:
  /// **'本地助手润色稿'**
  String get assistantPolishedHeading;

  /// No description provided for @assistantGeneratedHeading.
  ///
  /// In zh, this message translates to:
  /// **'AI 生成内容'**
  String get assistantGeneratedHeading;

  /// No description provided for @attachmentReference.
  ///
  /// In zh, this message translates to:
  /// **'附件引用：{path}'**
  String attachmentReference(String path);

  /// No description provided for @markdownTable.
  ///
  /// In zh, this message translates to:
  /// **'Markdown 表格'**
  String get markdownTable;

  /// No description provided for @tableDimensions.
  ///
  /// In zh, this message translates to:
  /// **'{columns} 列 · {rows} 行'**
  String tableDimensions(int columns, int rows);

  /// No description provided for @deleteTable.
  ///
  /// In zh, this message translates to:
  /// **'删除表格'**
  String get deleteTable;

  /// No description provided for @editTable.
  ///
  /// In zh, this message translates to:
  /// **'编辑表格'**
  String get editTable;

  /// No description provided for @invalidMarkdownTable.
  ///
  /// In zh, this message translates to:
  /// **'表格语法不完整，请先检查 Markdown 原文'**
  String get invalidMarkdownTable;

  /// No description provided for @attachmentRemoved.
  ///
  /// In zh, this message translates to:
  /// **'附件已移除'**
  String get attachmentRemoved;

  /// No description provided for @brokenAttachmentReference.
  ///
  /// In zh, this message translates to:
  /// **'这个引用已失效，可以移除引用'**
  String get brokenAttachmentReference;

  /// No description provided for @attachmentReferenceDescription.
  ///
  /// In zh, this message translates to:
  /// **'{type} · {size} · 点击预览'**
  String attachmentReferenceDescription(String type, String size);

  /// No description provided for @removeReference.
  ///
  /// In zh, this message translates to:
  /// **'移除引用'**
  String get removeReference;

  /// No description provided for @tableEditorDescription.
  ///
  /// In zh, this message translates to:
  /// **'{columns} 列 · {rows} 行 · 左右滑动查看全部列'**
  String tableEditorDescription(int columns, int rows);

  /// No description provided for @addColumn.
  ///
  /// In zh, this message translates to:
  /// **'添加列'**
  String get addColumn;

  /// No description provided for @addRow.
  ///
  /// In zh, this message translates to:
  /// **'添加行'**
  String get addRow;

  /// No description provided for @deleteRow.
  ///
  /// In zh, this message translates to:
  /// **'删除第 {row} 行'**
  String deleteRow(int row);

  /// No description provided for @saveTable.
  ///
  /// In zh, this message translates to:
  /// **'保存表格'**
  String get saveTable;

  /// No description provided for @tableHeader.
  ///
  /// In zh, this message translates to:
  /// **'表头'**
  String get tableHeader;

  /// No description provided for @deleteColumn.
  ///
  /// In zh, this message translates to:
  /// **'删除列'**
  String get deleteColumn;

  /// No description provided for @cellAlignment.
  ///
  /// In zh, this message translates to:
  /// **'单元格对齐方式'**
  String get cellAlignment;

  /// No description provided for @alignLeft.
  ///
  /// In zh, this message translates to:
  /// **'左对齐'**
  String get alignLeft;

  /// No description provided for @alignCenter.
  ///
  /// In zh, this message translates to:
  /// **'居中'**
  String get alignCenter;

  /// No description provided for @alignRight.
  ///
  /// In zh, this message translates to:
  /// **'右对齐'**
  String get alignRight;

  /// No description provided for @content.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get content;

  /// No description provided for @untitled.
  ///
  /// In zh, this message translates to:
  /// **'无标题'**
  String get untitled;

  /// No description provided for @timeRibbon.
  ///
  /// In zh, this message translates to:
  /// **'织带'**
  String get timeRibbon;

  /// No description provided for @timeRibbonDescription.
  ///
  /// In zh, this message translates to:
  /// **'沿时间长河回看笔记'**
  String get timeRibbonDescription;

  /// No description provided for @timelinePreview.
  ///
  /// In zh, this message translates to:
  /// **'时间预览'**
  String get timelinePreview;

  /// No description provided for @timelineDayCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 个日期，轻点即可定位'**
  String timelineDayCount(int count);

  /// No description provided for @timelineNoteCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 篇'**
  String timelineNoteCount(int count);

  /// No description provided for @timelineMoreNotes.
  ///
  /// In zh, this message translates to:
  /// **'… 另有 {count} 篇'**
  String timelineMoreNotes(int count);

  /// No description provided for @collapseTimelinePreview.
  ///
  /// In zh, this message translates to:
  /// **'折叠时间预览'**
  String get collapseTimelinePreview;

  /// No description provided for @expandTimelinePreview.
  ///
  /// In zh, this message translates to:
  /// **'展开时间预览'**
  String get expandTimelinePreview;

  /// No description provided for @collapseDayNotes.
  ///
  /// In zh, this message translates to:
  /// **'折叠这一天的笔记'**
  String get collapseDayNotes;

  /// No description provided for @expandDayNotes.
  ///
  /// In zh, this message translates to:
  /// **'展开这一天的笔记'**
  String get expandDayNotes;

  /// No description provided for @constellation.
  ///
  /// In zh, this message translates to:
  /// **'星图'**
  String get constellation;

  /// No description provided for @constellationDescription.
  ///
  /// In zh, this message translates to:
  /// **'在无边星空探索想法'**
  String get constellationDescription;

  /// No description provided for @constellationHint.
  ///
  /// In zh, this message translates to:
  /// **'拖动卡片调整位置，轻点打开，长按建立关联'**
  String get constellationHint;

  /// No description provided for @constellationOverview.
  ///
  /// In zh, this message translates to:
  /// **'全览'**
  String get constellationOverview;

  /// No description provided for @constellationOverviewHint.
  ///
  /// In zh, this message translates to:
  /// **'轻点进入分组，拖动背景调整区域位置'**
  String get constellationOverviewHint;

  /// No description provided for @constellationReturnToOverviewHint.
  ///
  /// In zh, this message translates to:
  /// **'再次轻点底部「星图」返回全览'**
  String get constellationReturnToOverviewHint;

  /// No description provided for @constellationGroupHint.
  ///
  /// In zh, this message translates to:
  /// **'轻点卡片展开预览，拖动可调整位置'**
  String get constellationGroupHint;

  /// No description provided for @groupByTime.
  ///
  /// In zh, this message translates to:
  /// **'按时间'**
  String get groupByTime;

  /// No description provided for @groupByTags.
  ///
  /// In zh, this message translates to:
  /// **'按标签'**
  String get groupByTags;

  /// No description provided for @untaggedStars.
  ///
  /// In zh, this message translates to:
  /// **'未标签'**
  String get untaggedStars;

  /// No description provided for @starRegions.
  ///
  /// In zh, this message translates to:
  /// **'星域'**
  String get starRegions;

  /// No description provided for @starRegionsDescription.
  ///
  /// In zh, this message translates to:
  /// **'用星团、星云或星系整理一组彼此相关的笔记'**
  String get starRegionsDescription;

  /// No description provided for @newStarRegion.
  ///
  /// In zh, this message translates to:
  /// **'新建星域'**
  String get newStarRegion;

  /// No description provided for @editStarRegion.
  ///
  /// In zh, this message translates to:
  /// **'编辑星域'**
  String get editStarRegion;

  /// No description provided for @starRegionEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有星域。把一组笔记收进星团、星云或星系吧。'**
  String get starRegionEmpty;

  /// No description provided for @starRegionName.
  ///
  /// In zh, this message translates to:
  /// **'星域名称'**
  String get starRegionName;

  /// No description provided for @starRegionNameHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：产品灵感'**
  String get starRegionNameHint;

  /// No description provided for @starRegionType.
  ///
  /// In zh, this message translates to:
  /// **'星域类型'**
  String get starRegionType;

  /// No description provided for @starCluster.
  ///
  /// In zh, this message translates to:
  /// **'星团'**
  String get starCluster;

  /// No description provided for @nebula.
  ///
  /// In zh, this message translates to:
  /// **'星云'**
  String get nebula;

  /// No description provided for @galaxy.
  ///
  /// In zh, this message translates to:
  /// **'星系'**
  String get galaxy;

  /// No description provided for @starRegionMembers.
  ///
  /// In zh, this message translates to:
  /// **'成员笔记'**
  String get starRegionMembers;

  /// No description provided for @starRegionMemberCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 颗星'**
  String starRegionMemberCount(int count);

  /// No description provided for @saveStarRegion.
  ///
  /// In zh, this message translates to:
  /// **'保存星域'**
  String get saveStarRegion;

  /// No description provided for @collapseStarRegion.
  ///
  /// In zh, this message translates to:
  /// **'折叠整个星域'**
  String get collapseStarRegion;

  /// No description provided for @expandStarRegion.
  ///
  /// In zh, this message translates to:
  /// **'展开整个星域'**
  String get expandStarRegion;

  /// No description provided for @deleteStarRegion.
  ///
  /// In zh, this message translates to:
  /// **'删除星域'**
  String get deleteStarRegion;

  /// No description provided for @deleteStarRegionQuestion.
  ///
  /// In zh, this message translates to:
  /// **'删除这个星域？'**
  String get deleteStarRegionQuestion;

  /// No description provided for @deleteStarRegionDescription.
  ///
  /// In zh, this message translates to:
  /// **'只会移除分组，笔记和星星关联不会被删除。'**
  String get deleteStarRegionDescription;

  /// No description provided for @editNoteLinks.
  ///
  /// In zh, this message translates to:
  /// **'关联星星'**
  String get editNoteLinks;

  /// No description provided for @editNoteLinksDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择要与「{title}」建立关联的笔记'**
  String editNoteLinksDescription(String title);

  /// No description provided for @linkedStarCount.
  ///
  /// In zh, this message translates to:
  /// **'已关联 {count} 颗星'**
  String linkedStarCount(int count);

  /// No description provided for @noNotesToLink.
  ///
  /// In zh, this message translates to:
  /// **'还没有其他笔记可以关联'**
  String get noNotesToLink;

  /// No description provided for @saveLinks.
  ///
  /// In zh, this message translates to:
  /// **'保存关联'**
  String get saveLinks;

  /// No description provided for @todayAt.
  ///
  /// In zh, this message translates to:
  /// **'今天 {time}'**
  String todayAt(String time);

  /// No description provided for @yesterdayAt.
  ///
  /// In zh, this message translates to:
  /// **'昨天 {time}'**
  String yesterdayAt(String time);

  /// No description provided for @quickNoteTile.
  ///
  /// In zh, this message translates to:
  /// **'随\n笔'**
  String get quickNoteTile;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @mixedAttachmentMetadata.
  ///
  /// In zh, this message translates to:
  /// **'混合 · {count} 项'**
  String mixedAttachmentMetadata(int count);

  /// No description provided for @imageAttachmentMetadata.
  ///
  /// In zh, this message translates to:
  /// **'图片 · {count} 张'**
  String imageAttachmentMetadata(int count);

  /// No description provided for @audioAttachmentMetadata.
  ///
  /// In zh, this message translates to:
  /// **'录音 · {count} 段'**
  String audioAttachmentMetadata(int count);

  /// No description provided for @videoAttachmentMetadata.
  ///
  /// In zh, this message translates to:
  /// **'视频 · {count} 个'**
  String videoAttachmentMetadata(int count);

  /// No description provided for @fileAttachmentMetadata.
  ///
  /// In zh, this message translates to:
  /// **'文件 · {count} 个'**
  String fileAttachmentMetadata(int count);

  /// No description provided for @localLanguageModel.
  ///
  /// In zh, this message translates to:
  /// **'本地语言模型'**
  String get localLanguageModel;

  /// No description provided for @conversationHistory.
  ///
  /// In zh, this message translates to:
  /// **'对话记录'**
  String get conversationHistory;

  /// No description provided for @conversationHistoryHint.
  ///
  /// In zh, this message translates to:
  /// **'选择一段对话继续'**
  String get conversationHistoryHint;

  /// No description provided for @searchConversations.
  ///
  /// In zh, this message translates to:
  /// **'搜索标题和消息内容'**
  String get searchConversations;

  /// No description provided for @noMatchingConversations.
  ///
  /// In zh, this message translates to:
  /// **'没有找到匹配的对话'**
  String get noMatchingConversations;

  /// No description provided for @noMatchingConversationsHint.
  ///
  /// In zh, this message translates to:
  /// **'换个标题或关键词试试'**
  String get noMatchingConversationsHint;

  /// No description provided for @personaManagement.
  ///
  /// In zh, this message translates to:
  /// **'角色管理'**
  String get personaManagement;

  /// No description provided for @moreConversationActions.
  ///
  /// In zh, this message translates to:
  /// **'更多对话操作'**
  String get moreConversationActions;

  /// No description provided for @newConversation.
  ///
  /// In zh, this message translates to:
  /// **'新对话'**
  String get newConversation;

  /// No description provided for @deleteCurrentConversation.
  ///
  /// In zh, this message translates to:
  /// **'删除当前对话'**
  String get deleteCurrentConversation;

  /// No description provided for @jumpToBottom.
  ///
  /// In zh, this message translates to:
  /// **'回到底部'**
  String get jumpToBottom;

  /// No description provided for @generalAssistant.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记助手'**
  String get generalAssistant;

  /// No description provided for @textOnlyRuntimeImageWarning.
  ///
  /// In zh, this message translates to:
  /// **'当前本地运行时仅支持文字输入；图片已经保留在输入区，请移除或等待多模态运行时'**
  String get textOnlyRuntimeImageWarning;

  /// No description provided for @imageConversation.
  ///
  /// In zh, this message translates to:
  /// **'图片对话'**
  String get imageConversation;

  /// No description provided for @chatModelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前选择的是 {model}，首次使用需下载约 {size}。聊天内容只在本机处理。'**
  String chatModelDownloadDescription(String model, String size);

  /// No description provided for @imageKeptUnsupportedModel.
  ///
  /// In zh, this message translates to:
  /// **'图片已保留在输入区；当前模型不支持图片理解，请切换到支持图片的模型'**
  String get imageKeptUnsupportedModel;

  /// No description provided for @voiceInputBusyElsewhere.
  ///
  /// In zh, this message translates to:
  /// **'其他页面正在使用实时语音输入'**
  String get voiceInputBusyElsewhere;

  /// No description provided for @voiceInputFailed.
  ///
  /// In zh, this message translates to:
  /// **'语音输入失败'**
  String get voiceInputFailed;

  /// No description provided for @deleteCurrentConversationQuestion.
  ///
  /// In zh, this message translates to:
  /// **'删除当前对话？'**
  String get deleteCurrentConversationQuestion;

  /// No description provided for @deleteConversationDescription.
  ///
  /// In zh, this message translates to:
  /// **'聊天内容和这个会话的角色设定将无法恢复。'**
  String get deleteConversationDescription;

  /// No description provided for @chatSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法保存聊天记录：{error}'**
  String chatSaveFailed(String error);

  /// No description provided for @today.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In zh, this message translates to:
  /// **'昨天'**
  String get yesterday;

  /// No description provided for @installedState.
  ///
  /// In zh, this message translates to:
  /// **'已安装'**
  String get installedState;

  /// No description provided for @notInstalledState.
  ///
  /// In zh, this message translates to:
  /// **'未安装'**
  String get notInstalledState;

  /// No description provided for @modelRuntimeStandby.
  ///
  /// In zh, this message translates to:
  /// **'待命'**
  String get modelRuntimeStandby;

  /// No description provided for @modelRuntimeStandbyDetail.
  ///
  /// In zh, this message translates to:
  /// **'发送消息时会自动启动；空闲 2 分钟后自动释放，以节省内存。'**
  String get modelRuntimeStandbyDetail;

  /// No description provided for @modelRuntimeStarting.
  ///
  /// In zh, this message translates to:
  /// **'启动中'**
  String get modelRuntimeStarting;

  /// No description provided for @modelRuntimeStartingDetail.
  ///
  /// In zh, this message translates to:
  /// **'正在启动本地模型，首次启动可能需要一点时间。'**
  String get modelRuntimeStartingDetail;

  /// No description provided for @modelRuntimeStartingBackend.
  ///
  /// In zh, this message translates to:
  /// **'{backend} 启动中'**
  String modelRuntimeStartingBackend(String backend);

  /// No description provided for @modelRuntimeSwitchingBackend.
  ///
  /// In zh, this message translates to:
  /// **'加载 {backend}'**
  String modelRuntimeSwitchingBackend(String backend);

  /// No description provided for @modelRuntimeRetryingBackend.
  ///
  /// In zh, this message translates to:
  /// **'{backend} 重试中'**
  String modelRuntimeRetryingBackend(String backend);

  /// No description provided for @modelRuntimeReleasing.
  ///
  /// In zh, this message translates to:
  /// **'释放中'**
  String get modelRuntimeReleasing;

  /// No description provided for @modelRuntimeReleasingDetail.
  ///
  /// In zh, this message translates to:
  /// **'正在释放本地模型占用的内存。'**
  String get modelRuntimeReleasingDetail;

  /// No description provided for @modelRuntimeFailed.
  ///
  /// In zh, this message translates to:
  /// **'启动失败'**
  String get modelRuntimeFailed;

  /// No description provided for @modelRuntimeFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'本地模型暂时无法启动；发送消息时会自动重试。'**
  String get modelRuntimeFailedDetail;

  /// No description provided for @modelRuntimeUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'不可用'**
  String get modelRuntimeUnavailable;

  /// No description provided for @modelRuntimeUnavailableDetail.
  ///
  /// In zh, this message translates to:
  /// **'当前设备暂时无法运行本地模型。'**
  String get modelRuntimeUnavailableDetail;

  /// No description provided for @modelRuntimeGpu.
  ///
  /// In zh, this message translates to:
  /// **'GPU'**
  String get modelRuntimeGpu;

  /// No description provided for @modelRuntimeCpu.
  ///
  /// In zh, this message translates to:
  /// **'CPU'**
  String get modelRuntimeCpu;

  /// No description provided for @modelRuntimeBackendDetail.
  ///
  /// In zh, this message translates to:
  /// **'当前运行后端：{backend}'**
  String modelRuntimeBackendDetail(String backend);

  /// No description provided for @chatEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'你想聊什么？'**
  String get chatEmptyTitle;

  /// No description provided for @chatEmptyDescription.
  ///
  /// In zh, this message translates to:
  /// **'自由输入任何内容。消息和角色设定只保存在本机。'**
  String get chatEmptyDescription;

  /// No description provided for @yourImageMessage.
  ///
  /// In zh, this message translates to:
  /// **'你的图片消息'**
  String get yourImageMessage;

  /// No description provided for @yourMessage.
  ///
  /// In zh, this message translates to:
  /// **'你的消息'**
  String get yourMessage;

  /// No description provided for @aiReplying.
  ///
  /// In zh, this message translates to:
  /// **'AI 正在回复'**
  String get aiReplying;

  /// No description provided for @aiReply.
  ///
  /// In zh, this message translates to:
  /// **'AI 回复'**
  String get aiReply;

  /// No description provided for @stopped.
  ///
  /// In zh, this message translates to:
  /// **'已停止'**
  String get stopped;

  /// No description provided for @copyReply.
  ///
  /// In zh, this message translates to:
  /// **'复制回答'**
  String get copyReply;

  /// No description provided for @replyCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制回答'**
  String get replyCopied;

  /// No description provided for @generating.
  ///
  /// In zh, this message translates to:
  /// **'正在生成…'**
  String get generating;

  /// No description provided for @messageWhileGeneratingHint.
  ///
  /// In zh, this message translates to:
  /// **'可以先输入下一条消息…'**
  String get messageWhileGeneratingHint;

  /// No description provided for @queuedMessages.
  ///
  /// In zh, this message translates to:
  /// **'待处理 · {count}'**
  String queuedMessages(int count);

  /// No description provided for @editQueuedMessage.
  ///
  /// In zh, this message translates to:
  /// **'编辑待处理消息'**
  String get editQueuedMessage;

  /// No description provided for @cancelQueuedMessage.
  ///
  /// In zh, this message translates to:
  /// **'取消这条待处理消息'**
  String get cancelQueuedMessage;

  /// No description provided for @queuedMessageConsumed.
  ///
  /// In zh, this message translates to:
  /// **'这条消息已经开始处理'**
  String get queuedMessageConsumed;

  /// No description provided for @promoteQueuedMessage.
  ///
  /// In zh, this message translates to:
  /// **'插队：当前步骤完成后立即调整执行方向'**
  String get promoteQueuedMessage;

  /// No description provided for @steeringMessages.
  ///
  /// In zh, this message translates to:
  /// **'插队中 · {count}'**
  String steeringMessages(int count);

  /// No description provided for @cancelSteeringMessage.
  ///
  /// In zh, this message translates to:
  /// **'取消插队消息'**
  String get cancelSteeringMessage;

  /// No description provided for @agentFollowUpMessage.
  ///
  /// In zh, this message translates to:
  /// **'补充消息'**
  String get agentFollowUpMessage;

  /// No description provided for @assistantPreparingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在准备本地模型…'**
  String get assistantPreparingModel;

  /// No description provided for @assistantStartingBackend.
  ///
  /// In zh, this message translates to:
  /// **'正在启动 {backend}…'**
  String assistantStartingBackend(String backend);

  /// No description provided for @assistantSwitchingBackend.
  ///
  /// In zh, this message translates to:
  /// **'{previousBackend} 启动失败，正在加载 {backend} 模型…'**
  String assistantSwitchingBackend(String previousBackend, String backend);

  /// No description provided for @assistantRetryingBackend.
  ///
  /// In zh, this message translates to:
  /// **'{backend} 模型已就绪，正在重新处理这条消息…'**
  String assistantRetryingBackend(String backend);

  /// No description provided for @assistantThinking.
  ///
  /// In zh, this message translates to:
  /// **'正在思考…'**
  String get assistantThinking;

  /// No description provided for @assistantUsingNoteTools.
  ///
  /// In zh, this message translates to:
  /// **'正在处理笔记请求…'**
  String get assistantUsingNoteTools;

  /// No description provided for @assistantSearchingNotes.
  ///
  /// In zh, this message translates to:
  /// **'正在搜索笔记：“{query}”…'**
  String assistantSearchingNotes(String query);

  /// No description provided for @assistantComposingWithNotes.
  ///
  /// In zh, this message translates to:
  /// **'正在结合笔记整理回答…'**
  String get assistantComposingWithNotes;

  /// No description provided for @modelDoesNotSupportImages.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不支持图片理解，请切换模型后发送'**
  String get modelDoesNotSupportImages;

  /// No description provided for @takePhoto.
  ///
  /// In zh, this message translates to:
  /// **'拍照'**
  String get takePhoto;

  /// No description provided for @takePhotoUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'拍照（当前模型不支持图片）'**
  String get takePhotoUnsupported;

  /// No description provided for @dictating.
  ///
  /// In zh, this message translates to:
  /// **'正在听写…'**
  String get dictating;

  /// No description provided for @messageOrVoiceHint.
  ///
  /// In zh, this message translates to:
  /// **'发消息或使用语音…'**
  String get messageOrVoiceHint;

  /// No description provided for @stopGeneration.
  ///
  /// In zh, this message translates to:
  /// **'停止生成'**
  String get stopGeneration;

  /// No description provided for @finishVoiceInput.
  ///
  /// In zh, this message translates to:
  /// **'完成语音输入'**
  String get finishVoiceInput;

  /// No description provided for @send.
  ///
  /// In zh, this message translates to:
  /// **'发送'**
  String get send;

  /// No description provided for @voiceInput.
  ///
  /// In zh, this message translates to:
  /// **'语音输入'**
  String get voiceInput;

  /// No description provided for @addImage.
  ///
  /// In zh, this message translates to:
  /// **'添加图片'**
  String get addImage;

  /// No description provided for @addImageUnsupported.
  ///
  /// In zh, this message translates to:
  /// **'添加图片（当前模型不支持）'**
  String get addImageUnsupported;

  /// No description provided for @preparingOfflineSpeech.
  ///
  /// In zh, this message translates to:
  /// **'正在准备语音输入…'**
  String get preparingOfflineSpeech;

  /// No description provided for @dictationTapMicToFinish.
  ///
  /// In zh, this message translates to:
  /// **'请自然说话，内容会实时显示'**
  String get dictationTapMicToFinish;

  /// No description provided for @previewImage.
  ///
  /// In zh, this message translates to:
  /// **'预览图片'**
  String get previewImage;

  /// No description provided for @removeImage.
  ///
  /// In zh, this message translates to:
  /// **'移除图片'**
  String get removeImage;

  /// No description provided for @addMoreImages.
  ///
  /// In zh, this message translates to:
  /// **'继续添加图片'**
  String get addMoreImages;

  /// No description provided for @previewImageNumber.
  ///
  /// In zh, this message translates to:
  /// **'预览图片 {index}'**
  String previewImageNumber(int index);

  /// No description provided for @closePreview.
  ///
  /// In zh, this message translates to:
  /// **'关闭预览'**
  String get closePreview;

  /// No description provided for @imageCannotOpen.
  ///
  /// In zh, this message translates to:
  /// **'图片无法打开'**
  String get imageCannotOpen;

  /// No description provided for @dismissMessage.
  ///
  /// In zh, this message translates to:
  /// **'关闭提示'**
  String get dismissMessage;

  /// No description provided for @readAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新读取'**
  String get readAgain;

  /// No description provided for @switchPersona.
  ///
  /// In zh, this message translates to:
  /// **'切换角色'**
  String get switchPersona;

  /// No description provided for @manage.
  ///
  /// In zh, this message translates to:
  /// **'管理'**
  String get manage;

  /// No description provided for @noSavedConversations.
  ///
  /// In zh, this message translates to:
  /// **'还没有保存的对话'**
  String get noSavedConversations;

  /// No description provided for @conversationMessageCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条消息 · {time}'**
  String conversationMessageCount(int count, String time);

  /// No description provided for @personaDeleteQuestion.
  ///
  /// In zh, this message translates to:
  /// **'删除“{name}”？'**
  String personaDeleteQuestion(String name);

  /// No description provided for @personaDeleteDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用这个角色的对话会切换回非空笔记助手，聊天记录不会删除。'**
  String get personaDeleteDescription;

  /// No description provided for @createPersona.
  ///
  /// In zh, this message translates to:
  /// **'新建角色'**
  String get createPersona;

  /// No description provided for @reload.
  ///
  /// In zh, this message translates to:
  /// **'重新加载'**
  String get reload;

  /// No description provided for @personaManagementDescription.
  ///
  /// In zh, this message translates to:
  /// **'角色决定本地模型回答问题时采用的身份、语气和规则。你可以在聊天中随时切换，所有设定只保存在本机。'**
  String get personaManagementDescription;

  /// No description provided for @builtIn.
  ///
  /// In zh, this message translates to:
  /// **'内置'**
  String get builtIn;

  /// No description provided for @current.
  ///
  /// In zh, this message translates to:
  /// **'当前'**
  String get current;

  /// No description provided for @personaDescriptionMissing.
  ///
  /// In zh, this message translates to:
  /// **'未填写角色说明'**
  String get personaDescriptionMissing;

  /// No description provided for @personaActions.
  ///
  /// In zh, this message translates to:
  /// **'角色操作'**
  String get personaActions;

  /// No description provided for @editPersona.
  ///
  /// In zh, this message translates to:
  /// **'编辑角色'**
  String get editPersona;

  /// No description provided for @deletePersona.
  ///
  /// In zh, this message translates to:
  /// **'删除角色'**
  String get deletePersona;

  /// No description provided for @personaInstructionDescription.
  ///
  /// In zh, this message translates to:
  /// **'角色名称用于切换；系统提示词会在每次请求中作为最高优先级的本地指令。'**
  String get personaInstructionDescription;

  /// No description provided for @personaName.
  ///
  /// In zh, this message translates to:
  /// **'角色名称'**
  String get personaName;

  /// No description provided for @shortDescriptionOptional.
  ///
  /// In zh, this message translates to:
  /// **'简短说明（可选）'**
  String get shortDescriptionOptional;

  /// No description provided for @systemPrompt.
  ///
  /// In zh, this message translates to:
  /// **'系统提示词'**
  String get systemPrompt;

  /// No description provided for @systemPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：你是一位耐心的英语口语教练……'**
  String get systemPromptHint;

  /// No description provided for @savePersona.
  ///
  /// In zh, this message translates to:
  /// **'保存角色'**
  String get savePersona;

  /// No description provided for @microphonePermissionRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要麦克风权限'**
  String get microphonePermissionRequired;

  /// No description provided for @microphonePermissionDescription.
  ///
  /// In zh, this message translates to:
  /// **'录音只会保存在本机。请允许麦克风权限后再开始。'**
  String get microphonePermissionDescription;

  /// No description provided for @openSettings.
  ///
  /// In zh, this message translates to:
  /// **'前往设置'**
  String get openSettings;

  /// No description provided for @recordingStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法开始录音：{error}'**
  String recordingStartFailed(String error);

  /// No description provided for @voiceNoteDefaultTitle.
  ///
  /// In zh, this message translates to:
  /// **'语音笔记 {date} {time}'**
  String voiceNoteDefaultTitle(String date, String time);

  /// No description provided for @recordingSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败：{error}'**
  String recordingSaveFailed(String error);

  /// No description provided for @discardRecordingQuestion.
  ///
  /// In zh, this message translates to:
  /// **'放弃这段录音？'**
  String get discardRecordingQuestion;

  /// No description provided for @discardRecordingDescription.
  ///
  /// In zh, this message translates to:
  /// **'还没有保存的录音将被删除。'**
  String get discardRecordingDescription;

  /// No description provided for @continueEditing.
  ///
  /// In zh, this message translates to:
  /// **'继续编辑'**
  String get continueEditing;

  /// No description provided for @discard.
  ///
  /// In zh, this message translates to:
  /// **'放弃'**
  String get discard;

  /// No description provided for @deviceOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅本机'**
  String get deviceOnly;

  /// No description provided for @recordIdea.
  ///
  /// In zh, this message translates to:
  /// **'记录一段想法'**
  String get recordIdea;

  /// No description provided for @recordingPrivacyDescription.
  ///
  /// In zh, this message translates to:
  /// **'录音默认只保存在本机；仅手动云同步时才会上传。保存后可以继续添加标签和说明。'**
  String get recordingPrivacyDescription;

  /// No description provided for @preparingMicrophone.
  ///
  /// In zh, this message translates to:
  /// **'正在准备麦克风…'**
  String get preparingMicrophone;

  /// No description provided for @startRecording.
  ///
  /// In zh, this message translates to:
  /// **'开始录音'**
  String get startRecording;

  /// No description provided for @paused.
  ///
  /// In zh, this message translates to:
  /// **'已暂停'**
  String get paused;

  /// No description provided for @recording.
  ///
  /// In zh, this message translates to:
  /// **'正在录音'**
  String get recording;

  /// No description provided for @resume.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get resume;

  /// No description provided for @pause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get pause;

  /// No description provided for @finishRecording.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get finishRecording;

  /// No description provided for @savingRecording.
  ///
  /// In zh, this message translates to:
  /// **'正在保存录音…'**
  String get savingRecording;

  /// No description provided for @recordingAdded.
  ///
  /// In zh, this message translates to:
  /// **'录音已添加到笔记'**
  String get recordingAdded;

  /// No description provided for @playRecording.
  ///
  /// In zh, this message translates to:
  /// **'播放录音'**
  String get playRecording;

  /// No description provided for @pauseRecording.
  ///
  /// In zh, this message translates to:
  /// **'暂停播放'**
  String get pauseRecording;

  /// No description provided for @recordingPlaybackFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法播放这段录音'**
  String get recordingPlaybackFailed;

  /// No description provided for @recordingActions.
  ///
  /// In zh, this message translates to:
  /// **'录音操作'**
  String get recordingActions;

  /// No description provided for @recordAgain.
  ///
  /// In zh, this message translates to:
  /// **'重录'**
  String get recordAgain;

  /// No description provided for @saveVoiceNote.
  ///
  /// In zh, this message translates to:
  /// **'保存语音笔记'**
  String get saveVoiceNote;

  /// No description provided for @editTranscript.
  ///
  /// In zh, this message translates to:
  /// **'编辑转写文字'**
  String get editTranscript;

  /// No description provided for @transcriptLocalOnlyDescription.
  ///
  /// In zh, this message translates to:
  /// **'仅修改本地转写文字，原始录音不会改变'**
  String get transcriptLocalOnlyDescription;

  /// No description provided for @transcriptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入转写文字'**
  String get transcriptHint;

  /// No description provided for @transcriptCharacterCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 字'**
  String transcriptCharacterCount(int count);

  /// No description provided for @preparingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在准备模型'**
  String get preparingModel;

  /// No description provided for @recognizedTextCopied.
  ///
  /// In zh, this message translates to:
  /// **'识别文字已复制'**
  String get recognizedTextCopied;

  /// No description provided for @ocrFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'OCR 识别失败：{error}'**
  String ocrFailedDetail(String error);

  /// No description provided for @noClearTextRecognized.
  ///
  /// In zh, this message translates to:
  /// **'未识别到清晰文字'**
  String get noClearTextRecognized;

  /// No description provided for @importOfflineSpeechModel.
  ///
  /// In zh, this message translates to:
  /// **'导入离线识别模型'**
  String get importOfflineSpeechModel;

  /// No description provided for @importSpeechModelDescription.
  ///
  /// In zh, this message translates to:
  /// **'请从解压后的 SenseVoice Small INT8 模型目录中，同时选择 ONNX 模型和 tokens.txt。\n\n模型约 228 MB，只保存在本机，不会进入笔记备份。'**
  String get importSpeechModelDescription;

  /// No description provided for @chooseFiles.
  ///
  /// In zh, this message translates to:
  /// **'选择文件'**
  String get chooseFiles;

  /// No description provided for @importingOfflineModel.
  ///
  /// In zh, this message translates to:
  /// **'正在导入离线模型'**
  String get importingOfflineModel;

  /// No description provided for @offlineSpeechModelImported.
  ///
  /// In zh, this message translates to:
  /// **'离线语音识别模型已导入'**
  String get offlineSpeechModelImported;

  /// No description provided for @modelImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'模型导入失败：{error}'**
  String modelImportFailed(String error);

  /// No description provided for @downloadOfflineSpeechModelQuestion.
  ///
  /// In zh, this message translates to:
  /// **'下载离线识别模型？'**
  String get downloadOfflineSpeechModelQuestion;

  /// No description provided for @downloadSpeechModelDescription.
  ///
  /// In zh, this message translates to:
  /// **'将从 ModelScope 魔搭社区下载约 228 MB，建议使用 Wi-Fi。\n\n模型下载会联网；笔记和音频只会在你手动云同步时上传。中断后可继续下载。'**
  String get downloadSpeechModelDescription;

  /// No description provided for @downloadingFromModelScope.
  ///
  /// In zh, this message translates to:
  /// **'正在从 ModelScope 下载'**
  String get downloadingFromModelScope;

  /// No description provided for @offlineSpeechModelDownloaded.
  ///
  /// In zh, this message translates to:
  /// **'离线语音识别模型下载完成'**
  String get offlineSpeechModelDownloaded;

  /// No description provided for @downloadPausedResumable.
  ///
  /// In zh, this message translates to:
  /// **'已暂停下载，下次会从断点继续'**
  String get downloadPausedResumable;

  /// No description provided for @modelDownloadFailedDetail.
  ///
  /// In zh, this message translates to:
  /// **'模型下载失败：{error}'**
  String modelDownloadFailedDetail(String error);

  /// No description provided for @finishingInstallation.
  ///
  /// In zh, this message translates to:
  /// **'正在完成安装'**
  String get finishingInstallation;

  /// No description provided for @importedAmount.
  ///
  /// In zh, this message translates to:
  /// **'已导入 {amount}'**
  String importedAmount(String amount);

  /// No description provided for @downloadedAmount.
  ///
  /// In zh, this message translates to:
  /// **'已下载 {amount}'**
  String downloadedAmount(String amount);

  /// No description provided for @amountFinishingInstall.
  ///
  /// In zh, this message translates to:
  /// **'{amount} · 正在完成安装'**
  String amountFinishingInstall(String amount);

  /// No description provided for @speedTesting.
  ///
  /// In zh, this message translates to:
  /// **'正在测速…'**
  String get speedTesting;

  /// No description provided for @waitForTranscription.
  ///
  /// In zh, this message translates to:
  /// **'请先等待正在进行的转写结束'**
  String get waitForTranscription;

  /// No description provided for @removeOfflineModelQuestion.
  ///
  /// In zh, this message translates to:
  /// **'移除离线模型？'**
  String get removeOfflineModelQuestion;

  /// No description provided for @removeOfflineModelDescription.
  ///
  /// In zh, this message translates to:
  /// **'将释放约 228 MB 空间。已经保存的转写文字不会被删除。'**
  String get removeOfflineModelDescription;

  /// No description provided for @speakerModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要说话人分离模型'**
  String get speakerModelRequired;

  /// No description provided for @speakerModelDownloadDescription.
  ///
  /// In zh, this message translates to:
  /// **'首次使用需在本地模型中下载约 44.4 MB。模型安装后，分段和转写都完全在设备上完成。'**
  String get speakerModelDownloadDescription;

  /// No description provided for @speakerCount.
  ///
  /// In zh, this message translates to:
  /// **'说话人数量'**
  String get speakerCount;

  /// No description provided for @speakerCountDescription.
  ///
  /// In zh, this message translates to:
  /// **'当前支持最长 30 分钟的录音；人数越准确，分离结果通常越稳定。'**
  String get speakerCountDescription;

  /// No description provided for @estimateAutomatically.
  ///
  /// In zh, this message translates to:
  /// **'自动估算'**
  String get estimateAutomatically;

  /// No description provided for @estimateAutomaticallyDescription.
  ///
  /// In zh, this message translates to:
  /// **'适合不确定人数的录音'**
  String get estimateAutomaticallyDescription;

  /// No description provided for @speakerCountOption.
  ///
  /// In zh, this message translates to:
  /// **'{count} 位说话人'**
  String speakerCountOption(int count);

  /// No description provided for @transcriptCopied.
  ///
  /// In zh, this message translates to:
  /// **'转写文字已复制'**
  String get transcriptCopied;

  /// No description provided for @openWithAnotherApp.
  ///
  /// In zh, this message translates to:
  /// **'用其他应用打开'**
  String get openWithAnotherApp;

  /// No description provided for @editInformation.
  ///
  /// In zh, this message translates to:
  /// **'编辑信息'**
  String get editInformation;

  /// No description provided for @preview.
  ///
  /// In zh, this message translates to:
  /// **'预览'**
  String get preview;

  /// No description provided for @recognizedText.
  ///
  /// In zh, this message translates to:
  /// **'识别文字'**
  String get recognizedText;

  /// No description provided for @transcript.
  ///
  /// In zh, this message translates to:
  /// **'转写文字'**
  String get transcript;

  /// No description provided for @information.
  ///
  /// In zh, this message translates to:
  /// **'信息'**
  String get information;

  /// No description provided for @textInImage.
  ///
  /// In zh, this message translates to:
  /// **'图片中的文字'**
  String get textInImage;

  /// No description provided for @copyAll.
  ///
  /// In zh, this message translates to:
  /// **'复制全部'**
  String get copyAll;

  /// No description provided for @recognizeAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新识别'**
  String get recognizeAgain;

  /// No description provided for @recognizeText.
  ///
  /// In zh, this message translates to:
  /// **'识别文字'**
  String get recognizeText;

  /// No description provided for @noRecognizedText.
  ///
  /// In zh, this message translates to:
  /// **'暂无识别文字'**
  String get noRecognizedText;

  /// No description provided for @ocrOnDemandDescription.
  ///
  /// In zh, this message translates to:
  /// **'需要时可对这张图片进行本地文字识别'**
  String get ocrOnDemandDescription;

  /// No description provided for @recognizing.
  ///
  /// In zh, this message translates to:
  /// **'正在识别…'**
  String get recognizing;

  /// No description provided for @audioTranscript.
  ///
  /// In zh, this message translates to:
  /// **'录音转写'**
  String get audioTranscript;

  /// No description provided for @recognizeAudio.
  ///
  /// In zh, this message translates to:
  /// **'语音识别'**
  String get recognizeAudio;

  /// No description provided for @audioTranscriptionDescription.
  ///
  /// In zh, this message translates to:
  /// **'在本机识别，文字随录音保存，不修改正文'**
  String get audioTranscriptionDescription;

  /// No description provided for @audioTranscriptStartFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法开始识别，请确认笔记已保存后重试'**
  String get audioTranscriptStartFailed;

  /// No description provided for @audioTranscriptSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'转写文字尚未保存，可复制文字或重试'**
  String get audioTranscriptSaveFailed;

  /// No description provided for @audioTranscriptFileMissing.
  ///
  /// In zh, this message translates to:
  /// **'音频文件不存在或已被移除'**
  String get audioTranscriptFileMissing;

  /// No description provided for @noClearSpeechRecognized.
  ///
  /// In zh, this message translates to:
  /// **'未识别到清晰语音，请检查录音后重试'**
  String get noClearSpeechRecognized;

  /// No description provided for @audioTranscriptCopyFailed.
  ///
  /// In zh, this message translates to:
  /// **'复制失败，请重试'**
  String get audioTranscriptCopyFailed;

  /// No description provided for @editText.
  ///
  /// In zh, this message translates to:
  /// **'编辑文字'**
  String get editText;

  /// No description provided for @audioStaysOnDevice.
  ///
  /// In zh, this message translates to:
  /// **'完全在本机处理，音频不会离开设备'**
  String get audioStaysOnDevice;

  /// No description provided for @offlineSpeechModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要离线识别模型'**
  String get offlineSpeechModelRequired;

  /// No description provided for @offlineModelBackupDescription.
  ///
  /// In zh, this message translates to:
  /// **'模型独立保存在本机，不增加笔记备份大小'**
  String get offlineModelBackupDescription;

  /// No description provided for @downloadAbout228Mb.
  ///
  /// In zh, this message translates to:
  /// **'在线下载约 228 MB'**
  String get downloadAbout228Mb;

  /// No description provided for @backgroundTranscriptionHint.
  ///
  /// In zh, this message translates to:
  /// **'可以离开此页面继续使用笔记'**
  String get backgroundTranscriptionHint;

  /// No description provided for @transcriptionIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'转写没有完成'**
  String get transcriptionIncomplete;

  /// No description provided for @tryAgainLater.
  ///
  /// In zh, this message translates to:
  /// **'请稍后重试'**
  String get tryAgainLater;

  /// No description provided for @transcribeAgain.
  ///
  /// In zh, this message translates to:
  /// **'重新转写'**
  String get transcribeAgain;

  /// No description provided for @transcriptionCanceled.
  ///
  /// In zh, this message translates to:
  /// **'已取消转写'**
  String get transcriptionCanceled;

  /// No description provided for @recordingUnaffected.
  ///
  /// In zh, this message translates to:
  /// **'录音文件没有受到影响'**
  String get recordingUnaffected;

  /// No description provided for @noTranscript.
  ///
  /// In zh, this message translates to:
  /// **'暂无转写文字'**
  String get noTranscript;

  /// No description provided for @transcriptionOnDemandDescription.
  ///
  /// In zh, this message translates to:
  /// **'需要时再启动本地识别，不会自动处理录音'**
  String get transcriptionOnDemandDescription;

  /// No description provided for @transcribeOnDevice.
  ///
  /// In zh, this message translates to:
  /// **'本地转写'**
  String get transcribeOnDevice;

  /// No description provided for @speakerDiarizedTranscription.
  ///
  /// In zh, this message translates to:
  /// **'区分说话人转写'**
  String get speakerDiarizedTranscription;

  /// No description provided for @speakerDiarizedTranscriptionModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'区分说话人转写 · 需 44.4 MB 模型'**
  String get speakerDiarizedTranscriptionModelRequired;

  /// No description provided for @manageModelSize.
  ///
  /// In zh, this message translates to:
  /// **'管理模型 · {size}'**
  String manageModelSize(String size);

  /// No description provided for @importFromFiles.
  ///
  /// In zh, this message translates to:
  /// **'从文件导入'**
  String get importFromFiles;

  /// No description provided for @viewAllModels.
  ///
  /// In zh, this message translates to:
  /// **'查看全部模型'**
  String get viewAllModels;

  /// No description provided for @preparingLocalTranscription.
  ///
  /// In zh, this message translates to:
  /// **'正在准备本地转写'**
  String get preparingLocalTranscription;

  /// No description provided for @readingAudio.
  ///
  /// In zh, this message translates to:
  /// **'正在读取音频'**
  String get readingAudio;

  /// No description provided for @separatingSpeakers.
  ///
  /// In zh, this message translates to:
  /// **'正在区分说话人'**
  String get separatingSpeakers;

  /// No description provided for @recognizingOnDevice.
  ///
  /// In zh, this message translates to:
  /// **'正在本地识别'**
  String get recognizingOnDevice;

  /// No description provided for @savingTranscriptText.
  ///
  /// In zh, this message translates to:
  /// **'正在保存转写文字'**
  String get savingTranscriptText;

  /// No description provided for @processing.
  ///
  /// In zh, this message translates to:
  /// **'正在处理'**
  String get processing;

  /// No description provided for @noteInformation.
  ///
  /// In zh, this message translates to:
  /// **'笔记信息'**
  String get noteInformation;

  /// No description provided for @renameAttachment.
  ///
  /// In zh, this message translates to:
  /// **'修改标题'**
  String get renameAttachment;

  /// No description provided for @editAttachmentTitle.
  ///
  /// In zh, this message translates to:
  /// **'修改附件标题'**
  String get editAttachmentTitle;

  /// No description provided for @attachmentTitle.
  ///
  /// In zh, this message translates to:
  /// **'附件标题'**
  String get attachmentTitle;

  /// No description provided for @attachmentTitleHint.
  ///
  /// In zh, this message translates to:
  /// **'输入在笔记中显示的标题'**
  String get attachmentTitleHint;

  /// No description provided for @attachmentTitleDescription.
  ///
  /// In zh, this message translates to:
  /// **'只修改笔记中的显示标题，原文件名和文件内容不会改变。'**
  String get attachmentTitleDescription;

  /// No description provided for @restoreOriginalFileName.
  ///
  /// In zh, this message translates to:
  /// **'恢复原文件名'**
  String get restoreOriginalFileName;

  /// No description provided for @type.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get type;

  /// No description provided for @created.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get created;

  /// No description provided for @updated.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get updated;

  /// No description provided for @fileInformation.
  ///
  /// In zh, this message translates to:
  /// **'文件信息'**
  String get fileInformation;

  /// No description provided for @fileName.
  ///
  /// In zh, this message translates to:
  /// **'文件名'**
  String get fileName;

  /// No description provided for @size.
  ///
  /// In zh, this message translates to:
  /// **'大小'**
  String get size;

  /// No description provided for @imageCopied.
  ///
  /// In zh, this message translates to:
  /// **'图片已复制'**
  String get imageCopied;

  /// No description provided for @imageCopyUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'当前系统不支持复制图片'**
  String get imageCopyUnavailable;

  /// No description provided for @imageCopyFailed.
  ///
  /// In zh, this message translates to:
  /// **'复制图片失败'**
  String get imageCopyFailed;

  /// No description provided for @editImage.
  ///
  /// In zh, this message translates to:
  /// **'编辑图片'**
  String get editImage;

  /// No description provided for @imageActions.
  ///
  /// In zh, this message translates to:
  /// **'操作'**
  String get imageActions;

  /// No description provided for @imageOcrAction.
  ///
  /// In zh, this message translates to:
  /// **'OCR 识别文字'**
  String get imageOcrAction;

  /// No description provided for @imageOcrDescription.
  ///
  /// In zh, this message translates to:
  /// **'在本机识别，文字随图片保存，不修改正文'**
  String get imageOcrDescription;

  /// No description provided for @imageOcrFailed.
  ///
  /// In zh, this message translates to:
  /// **'文字识别暂时不可用，请重试'**
  String get imageOcrFailed;

  /// No description provided for @imageOcrSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'识别文字尚未保存，请重试'**
  String get imageOcrSaveFailed;

  /// No description provided for @imageOcrSourceChanged.
  ///
  /// In zh, this message translates to:
  /// **'图片已更改或删除，请重新打开 OCR'**
  String get imageOcrSourceChanged;

  /// No description provided for @imageOcrCopyFailed.
  ///
  /// In zh, this message translates to:
  /// **'复制失败，请重试'**
  String get imageOcrCopyFailed;

  /// No description provided for @replaceFromGallery.
  ///
  /// In zh, this message translates to:
  /// **'从相册替换'**
  String get replaceFromGallery;

  /// No description provided for @replaceWithCamera.
  ///
  /// In zh, this message translates to:
  /// **'重新拍摄'**
  String get replaceWithCamera;

  /// No description provided for @viewOriginalImage.
  ///
  /// In zh, this message translates to:
  /// **'查看原图'**
  String get viewOriginalImage;

  /// No description provided for @imageDetails.
  ///
  /// In zh, this message translates to:
  /// **'图片详情'**
  String get imageDetails;

  /// No description provided for @imageReplaced.
  ///
  /// In zh, this message translates to:
  /// **'图片已替换'**
  String get imageReplaced;

  /// No description provided for @imageReplaceFailed.
  ///
  /// In zh, this message translates to:
  /// **'替换图片失败'**
  String get imageReplaceFailed;

  /// No description provided for @duration.
  ///
  /// In zh, this message translates to:
  /// **'时长'**
  String get duration;

  /// No description provided for @saveStatus.
  ///
  /// In zh, this message translates to:
  /// **'保存状态'**
  String get saveStatus;

  /// No description provided for @fileMissing.
  ///
  /// In zh, this message translates to:
  /// **'文件不存在'**
  String get fileMissing;

  /// No description provided for @savedInUnifiedDirectory.
  ///
  /// In zh, this message translates to:
  /// **'已保存在统一目录'**
  String get savedInUnifiedDirectory;

  /// No description provided for @description.
  ///
  /// In zh, this message translates to:
  /// **'说明'**
  String get description;

  /// No description provided for @originalFileMissing.
  ///
  /// In zh, this message translates to:
  /// **'原文件不存在'**
  String get originalFileMissing;

  /// No description provided for @missingFileDescription.
  ///
  /// In zh, this message translates to:
  /// **'可以保留笔记信息或永久删除它'**
  String get missingFileDescription;

  /// No description provided for @openWithLocalApp.
  ///
  /// In zh, this message translates to:
  /// **'用本地应用打开'**
  String get openWithLocalApp;

  /// No description provided for @coverSettings.
  ///
  /// In zh, this message translates to:
  /// **'封面设置'**
  String get coverSettings;

  /// No description provided for @noteCover.
  ///
  /// In zh, this message translates to:
  /// **'封面'**
  String get noteCover;

  /// No description provided for @coverSettingsDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择笔记在主页和资料库中的展示方式。'**
  String get coverSettingsDescription;

  /// No description provided for @coverAutomatic.
  ///
  /// In zh, this message translates to:
  /// **'自动选择'**
  String get coverAutomatic;

  /// No description provided for @coverAutomaticDescription.
  ///
  /// In zh, this message translates to:
  /// **'优先使用笔记中的图片或视频，否则显示类型封面'**
  String get coverAutomaticDescription;

  /// No description provided for @coverType.
  ///
  /// In zh, this message translates to:
  /// **'类型封面'**
  String get coverType;

  /// No description provided for @coverTypeDescription.
  ///
  /// In zh, this message translates to:
  /// **'使用统一的笔记、图片、语音、视频或文件图标'**
  String get coverTypeDescription;

  /// No description provided for @hideCover.
  ///
  /// In zh, this message translates to:
  /// **'不显示封面'**
  String get hideCover;

  /// No description provided for @hideCoverDescription.
  ///
  /// In zh, this message translates to:
  /// **'只显示标题、摘要和更新时间'**
  String get hideCoverDescription;

  /// No description provided for @chooseAttachmentCover.
  ///
  /// In zh, this message translates to:
  /// **'从笔记附件中选择'**
  String get chooseAttachmentCover;

  /// No description provided for @setAsCover.
  ///
  /// In zh, this message translates to:
  /// **'设为封面'**
  String get setAsCover;

  /// No description provided for @currentCover.
  ///
  /// In zh, this message translates to:
  /// **'当前封面'**
  String get currentCover;

  /// No description provided for @shareNoteAsImage.
  ///
  /// In zh, this message translates to:
  /// **'分享为图片'**
  String get shareNoteAsImage;

  /// No description provided for @noteHasNoShareableContent.
  ///
  /// In zh, this message translates to:
  /// **'笔记还没有可分享的内容'**
  String get noteHasNoShareableContent;

  /// No description provided for @createShareImage.
  ///
  /// In zh, this message translates to:
  /// **'制作分享图'**
  String get createShareImage;

  /// No description provided for @shareImageStyle.
  ///
  /// In zh, this message translates to:
  /// **'样式'**
  String get shareImageStyle;

  /// No description provided for @shareImageCanvas.
  ///
  /// In zh, this message translates to:
  /// **'画幅'**
  String get shareImageCanvas;

  /// No description provided for @shareImageRatio.
  ///
  /// In zh, this message translates to:
  /// **'图片比例'**
  String get shareImageRatio;

  /// No description provided for @shareImageContent.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get shareImageContent;

  /// No description provided for @shareImageLayout.
  ///
  /// In zh, this message translates to:
  /// **'排版'**
  String get shareImageLayout;

  /// No description provided for @shareTemplateLetter.
  ///
  /// In zh, this message translates to:
  /// **'一封非空来信'**
  String get shareTemplateLetter;

  /// No description provided for @shareTemplatePlain.
  ///
  /// In zh, this message translates to:
  /// **'素笺'**
  String get shareTemplatePlain;

  /// No description provided for @shareTemplateNight.
  ///
  /// In zh, this message translates to:
  /// **'夜读'**
  String get shareTemplateNight;

  /// No description provided for @shareTemplateEditorial.
  ///
  /// In zh, this message translates to:
  /// **'编辑部'**
  String get shareTemplateEditorial;

  /// No description provided for @shareTemplateNewspaper.
  ///
  /// In zh, this message translates to:
  /// **'晨刊'**
  String get shareTemplateNewspaper;

  /// No description provided for @shareTemplateManuscript.
  ///
  /// In zh, this message translates to:
  /// **'方格稿'**
  String get shareTemplateManuscript;

  /// No description provided for @shareTemplateBotanical.
  ///
  /// In zh, this message translates to:
  /// **'草木'**
  String get shareTemplateBotanical;

  /// No description provided for @shareTemplateBlueprint.
  ///
  /// In zh, this message translates to:
  /// **'蓝图'**
  String get shareTemplateBlueprint;

  /// No description provided for @shareTemplateAmber.
  ///
  /// In zh, this message translates to:
  /// **'琥珀'**
  String get shareTemplateAmber;

  /// No description provided for @shareTemplateFilm.
  ///
  /// In zh, this message translates to:
  /// **'胶片'**
  String get shareTemplateFilm;

  /// No description provided for @shareTemplatePostcard.
  ///
  /// In zh, this message translates to:
  /// **'远方明信片'**
  String get shareTemplatePostcard;

  /// No description provided for @shareTemplateGallery.
  ///
  /// In zh, this message translates to:
  /// **'美术馆'**
  String get shareTemplateGallery;

  /// No description provided for @shareTemplateNeon.
  ///
  /// In zh, this message translates to:
  /// **'霓虹'**
  String get shareTemplateNeon;

  /// No description provided for @shareTemplateTide.
  ///
  /// In zh, this message translates to:
  /// **'潮汐'**
  String get shareTemplateTide;

  /// No description provided for @shareTemplateVermilion.
  ///
  /// In zh, this message translates to:
  /// **'朱印'**
  String get shareTemplateVermilion;

  /// No description provided for @shareRatioSquare.
  ///
  /// In zh, this message translates to:
  /// **'1:1 · 方形卡片'**
  String get shareRatioSquare;

  /// No description provided for @shareRatioFourFive.
  ///
  /// In zh, this message translates to:
  /// **'4:5 · 社交竖图'**
  String get shareRatioFourFive;

  /// No description provided for @shareRatioThreeFour.
  ///
  /// In zh, this message translates to:
  /// **'3:4 · 笔记卡片'**
  String get shareRatioThreeFour;

  /// No description provided for @shareRatioNineSixteen.
  ///
  /// In zh, this message translates to:
  /// **'9:16 · 手机全屏'**
  String get shareRatioNineSixteen;

  /// No description provided for @shareRatioSixteenNine.
  ///
  /// In zh, this message translates to:
  /// **'16:9 · 横向展示'**
  String get shareRatioSixteenNine;

  /// No description provided for @shareRatioA4.
  ///
  /// In zh, this message translates to:
  /// **'A4 · 文档比例'**
  String get shareRatioA4;

  /// No description provided for @shareRatioLong.
  ///
  /// In zh, this message translates to:
  /// **'长图 · 单张自适应'**
  String get shareRatioLong;

  /// No description provided for @shareLongImageHint.
  ///
  /// In zh, this message translates to:
  /// **'画布高度随内容延展，全部内容合成一张图片'**
  String get shareLongImageHint;

  /// No description provided for @shareRatioCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义尺寸'**
  String get shareRatioCustom;

  /// No description provided for @portraitOrientation.
  ///
  /// In zh, this message translates to:
  /// **'竖向'**
  String get portraitOrientation;

  /// No description provided for @landscapeOrientation.
  ///
  /// In zh, this message translates to:
  /// **'横向'**
  String get landscapeOrientation;

  /// No description provided for @shareImageWidth.
  ///
  /// In zh, this message translates to:
  /// **'宽度'**
  String get shareImageWidth;

  /// No description provided for @shareImageHeight.
  ///
  /// In zh, this message translates to:
  /// **'高度'**
  String get shareImageHeight;

  /// No description provided for @shareImageQuality.
  ///
  /// In zh, this message translates to:
  /// **'清晰度'**
  String get shareImageQuality;

  /// No description provided for @shareQualityStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准 · 短边 1080 px'**
  String get shareQualityStandard;

  /// No description provided for @shareQualityHigh.
  ///
  /// In zh, this message translates to:
  /// **'高清 · 短边 1440 px'**
  String get shareQualityHigh;

  /// No description provided for @shareQualityUltra.
  ///
  /// In zh, this message translates to:
  /// **'超清 · 短边 2160 px'**
  String get shareQualityUltra;

  /// No description provided for @includeNoteTitle.
  ///
  /// In zh, this message translates to:
  /// **'显示标题'**
  String get includeNoteTitle;

  /// No description provided for @includeNoteDate.
  ///
  /// In zh, this message translates to:
  /// **'显示日期'**
  String get includeNoteDate;

  /// No description provided for @includeNoteTags.
  ///
  /// In zh, this message translates to:
  /// **'显示标签'**
  String get includeNoteTags;

  /// No description provided for @includeNoteImages.
  ///
  /// In zh, this message translates to:
  /// **'显示图片'**
  String get includeNoteImages;

  /// No description provided for @includeNoteAttachments.
  ///
  /// In zh, this message translates to:
  /// **'显示附件'**
  String get includeNoteAttachments;

  /// No description provided for @noteShareSource.
  ///
  /// In zh, this message translates to:
  /// **'来自「非空笔记」'**
  String get noteShareSource;

  /// No description provided for @noteShareSourceAlwaysIncluded.
  ///
  /// In zh, this message translates to:
  /// **'每张分享图均会保留来源标识'**
  String get noteShareSourceAlwaysIncluded;

  /// No description provided for @shareDensityComfortable.
  ///
  /// In zh, this message translates to:
  /// **'舒展'**
  String get shareDensityComfortable;

  /// No description provided for @shareDensityStandard.
  ///
  /// In zh, this message translates to:
  /// **'标准'**
  String get shareDensityStandard;

  /// No description provided for @shareDensityCompact.
  ///
  /// In zh, this message translates to:
  /// **'紧凑'**
  String get shareDensityCompact;

  /// No description provided for @noteShareUntitled.
  ///
  /// In zh, this message translates to:
  /// **'一则笔记'**
  String get noteShareUntitled;

  /// No description provided for @generateAndShare.
  ///
  /// In zh, this message translates to:
  /// **'生成并分享'**
  String get generateAndShare;

  /// No description provided for @previousPage.
  ///
  /// In zh, this message translates to:
  /// **'上一页'**
  String get previousPage;

  /// No description provided for @nextPage.
  ///
  /// In zh, this message translates to:
  /// **'下一页'**
  String get nextPage;

  /// No description provided for @shareImagePageIndicator.
  ///
  /// In zh, this message translates to:
  /// **'第 {current} 页 · 共 {total} 页'**
  String shareImagePageIndicator(int current, int total);

  /// No description provided for @shareImageOutputSummary.
  ///
  /// In zh, this message translates to:
  /// **'将生成 {count} 张 {width} × {height} PNG'**
  String shareImageOutputSummary(int count, int width, int height);

  /// No description provided for @generatingShareImageProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在生成第 {current}/{total} 张图片'**
  String generatingShareImageProgress(int current, int total);

  /// No description provided for @shareNoteImageTitle.
  ///
  /// In zh, this message translates to:
  /// **'分享笔记：{title}'**
  String shareNoteImageTitle(String title);

  /// No description provided for @shareImageGenerationFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法生成分享图片，请稍后重试'**
  String get shareImageGenerationFailed;

  /// No description provided for @moveAttachmentHint.
  ///
  /// In zh, this message translates to:
  /// **'长按并拖动可调整位置'**
  String get moveAttachmentHint;

  /// No description provided for @checkForUpdates.
  ///
  /// In zh, this message translates to:
  /// **'检查更新'**
  String get checkForUpdates;

  /// No description provided for @updatesCheckedAutomatically.
  ///
  /// In zh, this message translates to:
  /// **'启动后自动检查，也可在这里手动检查'**
  String get updatesCheckedAutomatically;

  /// No description provided for @checkingForUpdates.
  ///
  /// In zh, this message translates to:
  /// **'正在检查更新…'**
  String get checkingForUpdates;

  /// No description provided for @latestVersionInstalled.
  ///
  /// In zh, this message translates to:
  /// **'当前已是最新版本'**
  String get latestVersionInstalled;

  /// No description provided for @updateCheckFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法检查更新，请稍后再试'**
  String get updateCheckFailed;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In zh, this message translates to:
  /// **'发现新版本'**
  String get updateAvailableTitle;

  /// No description provided for @updateAvailableDescription.
  ///
  /// In zh, this message translates to:
  /// **'非空笔记 {version} 已可安装'**
  String updateAvailableDescription(String version);

  /// No description provided for @mandatoryUpdate.
  ///
  /// In zh, this message translates to:
  /// **'必须更新'**
  String get mandatoryUpdate;

  /// No description provided for @releaseNotes.
  ///
  /// In zh, this message translates to:
  /// **'更新内容'**
  String get releaseNotes;

  /// No description provided for @releaseNotesUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法读取本次更新说明。'**
  String get releaseNotesUnavailable;

  /// No description provided for @updateNow.
  ///
  /// In zh, this message translates to:
  /// **'立即更新'**
  String get updateNow;

  /// No description provided for @remindMeLater.
  ///
  /// In zh, this message translates to:
  /// **'稍后提醒'**
  String get remindMeLater;

  /// No description provided for @downloadingUpdate.
  ///
  /// In zh, this message translates to:
  /// **'正在下载更新'**
  String get downloadingUpdate;

  /// No description provided for @downloadInBackground.
  ///
  /// In zh, this message translates to:
  /// **'收起，后台下载'**
  String get downloadInBackground;

  /// No description provided for @updateDownloadingInBackground.
  ///
  /// In zh, this message translates to:
  /// **'下载将在后台继续，可在设置中查看更新进度。'**
  String get updateDownloadingInBackground;

  /// No description provided for @updateReadyToInstall.
  ///
  /// In zh, this message translates to:
  /// **'更新安装包已校验，可以安装了。'**
  String get updateReadyToInstall;

  /// No description provided for @installUpdateNow.
  ///
  /// In zh, this message translates to:
  /// **'立即安装'**
  String get installUpdateNow;

  /// No description provided for @viewUpdate.
  ///
  /// In zh, this message translates to:
  /// **'查看更新'**
  String get viewUpdate;

  /// No description provided for @updateDownloadProgress.
  ///
  /// In zh, this message translates to:
  /// **'{percent}% · {downloaded} / {total}'**
  String updateDownloadProgress(int percent, String downloaded, String total);

  /// No description provided for @verifyingUpdate.
  ///
  /// In zh, this message translates to:
  /// **'正在校验安装包'**
  String get verifyingUpdate;

  /// No description provided for @installPermissionRequired.
  ///
  /// In zh, this message translates to:
  /// **'需要安装权限'**
  String get installPermissionRequired;

  /// No description provided for @installPermissionDescription.
  ///
  /// In zh, this message translates to:
  /// **'请在系统设置中允许非空笔记安装未知应用。安装仍需你在系统安装器中确认。'**
  String get installPermissionDescription;

  /// No description provided for @openInstallSettings.
  ///
  /// In zh, this message translates to:
  /// **'前往授权'**
  String get openInstallSettings;

  /// No description provided for @openingInstaller.
  ///
  /// In zh, this message translates to:
  /// **'正在打开系统安装器'**
  String get openingInstaller;

  /// No description provided for @installerOpened.
  ///
  /// In zh, this message translates to:
  /// **'安装包已准备好，请在系统安装器中确认更新。'**
  String get installerOpened;

  /// No description provided for @updateFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新没有完成'**
  String get updateFailed;

  /// No description provided for @updateDownloadFailed.
  ///
  /// In zh, this message translates to:
  /// **'安装包下载失败，请检查网络后重试。'**
  String get updateDownloadFailed;

  /// No description provided for @updateDownloadTimedOut.
  ///
  /// In zh, this message translates to:
  /// **'安装包下载超时，请稍后重试。'**
  String get updateDownloadTimedOut;

  /// No description provided for @updateSizeMismatch.
  ///
  /// In zh, this message translates to:
  /// **'安装包大小与发布信息不一致，已停止安装。'**
  String get updateSizeMismatch;

  /// No description provided for @updateChecksumMismatch.
  ///
  /// In zh, this message translates to:
  /// **'安装包校验失败，文件可能不完整，已停止安装。'**
  String get updateChecksumMismatch;

  /// No description provided for @updatePackageInvalid.
  ///
  /// In zh, this message translates to:
  /// **'安装包的应用标识或签名不匹配，已停止安装。'**
  String get updatePackageInvalid;

  /// No description provided for @updateVersionInvalid.
  ///
  /// In zh, this message translates to:
  /// **'安装包版本与发布信息不匹配，已停止安装。'**
  String get updateVersionInvalid;

  /// No description provided for @updateInstallerUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'系统中没有可用的安装器。'**
  String get updateInstallerUnavailable;

  /// No description provided for @updatePermissionSettingsFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开安装权限设置。'**
  String get updatePermissionSettingsFailed;

  /// No description provided for @updateVerificationFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法验证安装包，已停止安装。'**
  String get updateVerificationFailed;

  /// No description provided for @updateInstallFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开系统安装器，请稍后重试。'**
  String get updateInstallFailed;

  /// No description provided for @privateNotes.
  ///
  /// In zh, this message translates to:
  /// **'隐私笔记'**
  String get privateNotes;

  /// No description provided for @openPrivateNotes.
  ///
  /// In zh, this message translates to:
  /// **'打开隐私空间'**
  String get openPrivateNotes;

  /// No description provided for @releaseForPrivateNotes.
  ///
  /// In zh, this message translates to:
  /// **'松开验证，进入隐私空间'**
  String get releaseForPrivateNotes;

  /// No description provided for @authenticatePrivateNotes.
  ///
  /// In zh, this message translates to:
  /// **'请验证身份以访问非空笔记的隐私空间'**
  String get authenticatePrivateNotes;

  /// No description provided for @authenticatePrivateBackup.
  ///
  /// In zh, this message translates to:
  /// **'此备份可能包含隐私笔记或对话，请验证身份后继续'**
  String get authenticatePrivateBackup;

  /// No description provided for @privateNotesLocked.
  ///
  /// In zh, this message translates to:
  /// **'隐私空间已锁定'**
  String get privateNotesLocked;

  /// No description provided for @privateNotesLockedHint.
  ///
  /// In zh, this message translates to:
  /// **'每次进入或从后台返回，都需要系统认证。应用锁关闭时也会保护隐私笔记。'**
  String get privateNotesLockedHint;

  /// No description provided for @unlockPrivateNotes.
  ///
  /// In zh, this message translates to:
  /// **'验证并解锁'**
  String get unlockPrivateNotes;

  /// No description provided for @exitPrivateNotes.
  ///
  /// In zh, this message translates to:
  /// **'退出隐私空间'**
  String get exitPrivateNotes;

  /// No description provided for @newPrivateNote.
  ///
  /// In zh, this message translates to:
  /// **'新建隐私笔记'**
  String get newPrivateNote;

  /// No description provided for @privateCloudAiNotice.
  ///
  /// In zh, this message translates to:
  /// **'对话包含隐私笔记内容，相关内容将发送至云端 AI。'**
  String get privateCloudAiNotice;

  /// No description provided for @privateAssistant.
  ///
  /// In zh, this message translates to:
  /// **'隐私助手'**
  String get privateAssistant;

  /// No description provided for @noteDataSize.
  ///
  /// In zh, this message translates to:
  /// **'笔记大小'**
  String get noteDataSize;

  /// No description provided for @emptyPrivateNotes.
  ///
  /// In zh, this message translates to:
  /// **'还没有隐私笔记'**
  String get emptyPrivateNotes;

  /// No description provided for @emptyPrivateNotesHint.
  ///
  /// In zh, this message translates to:
  /// **'在这里新建笔记，或在主页长按笔记后设为隐私。隐私笔记不会出现在普通搜索、日历和标签分组中。'**
  String get emptyPrivateNotesHint;

  /// No description provided for @makeNotesPrivate.
  ///
  /// In zh, this message translates to:
  /// **'设为隐私'**
  String get makeNotesPrivate;

  /// No description provided for @makeNotesPublic.
  ///
  /// In zh, this message translates to:
  /// **'移出隐私'**
  String get makeNotesPublic;

  /// No description provided for @notesMadePrivate.
  ///
  /// In zh, this message translates to:
  /// **'已移入隐私空间'**
  String get notesMadePrivate;

  /// No description provided for @notesMadePublic.
  ///
  /// In zh, this message translates to:
  /// **'已移回普通笔记'**
  String get notesMadePublic;

  /// No description provided for @privateNotesExportNotice.
  ///
  /// In zh, this message translates to:
  /// **'完整备份包含隐私笔记、隐私对话及附件，导出或上传前需要系统认证。备份文件本身未加密，请妥善保管。'**
  String get privateNotesExportNotice;

  /// No description provided for @agentTitle.
  ///
  /// In zh, this message translates to:
  /// **'智能体助手'**
  String get agentTitle;

  /// No description provided for @agentSettings.
  ///
  /// In zh, this message translates to:
  /// **'智能体设置'**
  String get agentSettings;

  /// No description provided for @agentSettingsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在线模型、自带 Key 与远程工具'**
  String get agentSettingsSubtitle;

  /// No description provided for @agentProfiles.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get agentProfiles;

  /// No description provided for @agentLocal.
  ///
  /// In zh, this message translates to:
  /// **'本地推理'**
  String get agentLocal;

  /// No description provided for @agentOnline.
  ///
  /// In zh, this message translates to:
  /// **'在线推理'**
  String get agentOnline;

  /// No description provided for @agentAddModel.
  ///
  /// In zh, this message translates to:
  /// **'添加在线模型'**
  String get agentAddModel;

  /// No description provided for @agentProfileName.
  ///
  /// In zh, this message translates to:
  /// **'配置名称'**
  String get agentProfileName;

  /// No description provided for @agentProtocol.
  ///
  /// In zh, this message translates to:
  /// **'接口协议'**
  String get agentProtocol;

  /// No description provided for @agentEndpoint.
  ///
  /// In zh, this message translates to:
  /// **'服务地址'**
  String get agentEndpoint;

  /// No description provided for @agentModelId.
  ///
  /// In zh, this message translates to:
  /// **'模型标识'**
  String get agentModelId;

  /// No description provided for @agentApiKey.
  ///
  /// In zh, this message translates to:
  /// **'API Key'**
  String get agentApiKey;

  /// No description provided for @agentKeyHint.
  ///
  /// In zh, this message translates to:
  /// **'留空保留已有 Key；仅保存在系统安全存储'**
  String get agentKeyHint;

  /// No description provided for @agentByokSummary.
  ///
  /// In zh, this message translates to:
  /// **'在线服务会接收你发送的消息和已授权内容。'**
  String get agentByokSummary;

  /// No description provided for @agentByokNotice.
  ///
  /// In zh, this message translates to:
  /// **'保存后，智能体会在任务需要时把当前空间的输入、笔记上下文和工具结果发送到该服务。隐私空间需系统认证，使用隐私笔记时会持续显示云端提示，不逐轮弹窗；供应商的数据政策仍然适用，Key 仅保存在系统安全存储。'**
  String get agentByokNotice;

  /// No description provided for @agentCapabilities.
  ///
  /// In zh, this message translates to:
  /// **'能力与兼容选项'**
  String get agentCapabilities;

  /// No description provided for @agentContextTokens.
  ///
  /// In zh, this message translates to:
  /// **'上下文容量（token）'**
  String get agentContextTokens;

  /// No description provided for @agentToolCalling.
  ///
  /// In zh, this message translates to:
  /// **'结构化工具调用'**
  String get agentToolCalling;

  /// No description provided for @agentImageInput.
  ///
  /// In zh, this message translates to:
  /// **'图片输入'**
  String get agentImageInput;

  /// No description provided for @agentServerSearch.
  ///
  /// In zh, this message translates to:
  /// **'供应商内置搜索'**
  String get agentServerSearch;

  /// No description provided for @agentThinking.
  ///
  /// In zh, this message translates to:
  /// **'启用协议思考选项'**
  String get agentThinking;

  /// No description provided for @agentUsageOption.
  ///
  /// In zh, this message translates to:
  /// **'请求流式用量信息'**
  String get agentUsageOption;

  /// No description provided for @agentStatelessOption.
  ///
  /// In zh, this message translates to:
  /// **'Responses：不保存会话并回传加密续传项'**
  String get agentStatelessOption;

  /// No description provided for @agentTestConnection.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get agentTestConnection;

  /// No description provided for @agentTestNotice.
  ///
  /// In zh, this message translates to:
  /// **'测试会向所选服务发送一条不含笔记的短请求，可能产生少量费用。'**
  String get agentTestNotice;

  /// No description provided for @agentConnectionOk.
  ///
  /// In zh, this message translates to:
  /// **'连接成功；具体能力仍以供应商支持为准'**
  String get agentConnectionOk;

  /// No description provided for @agentUseModel.
  ///
  /// In zh, this message translates to:
  /// **'设为当前模型'**
  String get agentUseModel;

  /// No description provided for @agentNoTools.
  ///
  /// In zh, this message translates to:
  /// **'该模型未启用工具调用，可生成回答和改写建议。'**
  String get agentNoTools;

  /// No description provided for @agentMcp.
  ///
  /// In zh, this message translates to:
  /// **'远程 MCP 工具'**
  String get agentMcp;

  /// No description provided for @agentAddMcp.
  ///
  /// In zh, this message translates to:
  /// **'添加 MCP 服务'**
  String get agentAddMcp;

  /// No description provided for @agentMcpDiscover.
  ///
  /// In zh, this message translates to:
  /// **'连接并发现工具'**
  String get agentMcpDiscover;

  /// No description provided for @agentMcpToken.
  ///
  /// In zh, this message translates to:
  /// **'访问令牌（可选）'**
  String get agentMcpToken;

  /// No description provided for @agentMcpSummary.
  ///
  /// In zh, this message translates to:
  /// **'HTTP MCP 服务可在任务中提供远程工具。'**
  String get agentMcpSummary;

  /// No description provided for @agentMcpNotice.
  ///
  /// In zh, this message translates to:
  /// **'仅支持 HTTP MCP。保存并启用后，智能体会按任务需要直接调用其中的工具；可在智能体设置中关闭，也可开启逐次审批。服务器不能自行访问本地文件或调用模型。'**
  String get agentMcpNotice;

  /// No description provided for @agentMcpReadOnly.
  ///
  /// In zh, this message translates to:
  /// **'我确认此工具只读取数据'**
  String get agentMcpReadOnly;

  /// No description provided for @agentTasks.
  ///
  /// In zh, this message translates to:
  /// **'智能体统计'**
  String get agentTasks;

  /// No description provided for @agentStatisticsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'使用频率、本地与在线模型用量'**
  String get agentStatisticsSubtitle;

  /// No description provided for @agentStatisticsPrivacy.
  ///
  /// In zh, this message translates to:
  /// **'统计仅在本机汇总，帮助你了解使用频率和模型用量，不读取或展示任务内容。'**
  String get agentStatisticsPrivacy;

  /// No description provided for @agentStatisticsRecent.
  ///
  /// In zh, this message translates to:
  /// **'近 7 天使用'**
  String get agentStatisticsRecent;

  /// No description provided for @agentStatisticsTokens.
  ///
  /// In zh, this message translates to:
  /// **'累计 Token'**
  String get agentStatisticsTokens;

  /// No description provided for @agentStatisticsLocalRuns.
  ///
  /// In zh, this message translates to:
  /// **'本地推理'**
  String get agentStatisticsLocalRuns;

  /// No description provided for @agentStatisticsOnlineRuns.
  ///
  /// In zh, this message translates to:
  /// **'在线推理'**
  String get agentStatisticsOnlineRuns;

  /// No description provided for @agentStatisticsModels.
  ///
  /// In zh, this message translates to:
  /// **'模型使用'**
  String get agentStatisticsModels;

  /// No description provided for @agentStatisticsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'还没有统计数据'**
  String get agentStatisticsEmpty;

  /// No description provided for @agentStatisticsEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'使用智能体完成任务后，这里会显示汇总。'**
  String get agentStatisticsEmptyHint;

  /// No description provided for @agentStatisticsModelUsage.
  ///
  /// In zh, this message translates to:
  /// **'使用 {executions} 次 · {tokens} token'**
  String agentStatisticsModelUsage(int executions, String tokens);

  /// No description provided for @agentEmptyTasks.
  ///
  /// In zh, this message translates to:
  /// **'暂无任务'**
  String get agentEmptyTasks;

  /// No description provided for @agentTaskDetails.
  ///
  /// In zh, this message translates to:
  /// **'任务详情'**
  String get agentTaskDetails;

  /// No description provided for @agentTaskHistoryHint.
  ///
  /// In zh, this message translates to:
  /// **'查看任务状态和结果摘要；点击记录可查看完整回复、处理过程及操作记录。'**
  String get agentTaskHistoryHint;

  /// No description provided for @agentPermissionTitle.
  ///
  /// In zh, this message translates to:
  /// **'确认本次任务的数据范围'**
  String get agentPermissionTitle;

  /// No description provided for @agentPermissionBody.
  ///
  /// In zh, this message translates to:
  /// **'读取、在线发送、联网工具和写入分别授权。已授权的操作默认直接执行，也可选择逐次审批。'**
  String get agentPermissionBody;

  /// No description provided for @agentAutomaticTaskHint.
  ///
  /// In zh, this message translates to:
  /// **'使用当前模型和已配置工具直接开始；只有私密内容会单独验证。'**
  String get agentAutomaticTaskHint;

  /// No description provided for @agentScopeNone.
  ///
  /// In zh, this message translates to:
  /// **'不读取笔记'**
  String get agentScopeNone;

  /// No description provided for @agentScopeSelected.
  ///
  /// In zh, this message translates to:
  /// **'选定的笔记 / 当前上下文'**
  String get agentScopeSelected;

  /// No description provided for @agentScopeAll.
  ///
  /// In zh, this message translates to:
  /// **'全部普通笔记'**
  String get agentScopeAll;

  /// No description provided for @agentChooseNotes.
  ///
  /// In zh, this message translates to:
  /// **'选择笔记'**
  String get agentChooseNotes;

  /// No description provided for @agentOnlineConsent.
  ///
  /// In zh, this message translates to:
  /// **'允许把本次输入、上下文和工具结果发给上述服务'**
  String get agentOnlineConsent;

  /// No description provided for @agentNetworkConsent.
  ///
  /// In zh, this message translates to:
  /// **'允许网页搜索、读取及已配置的 MCP 工具'**
  String get agentNetworkConsent;

  /// No description provided for @agentWriteConsent.
  ///
  /// In zh, this message translates to:
  /// **'允许修改笔记'**
  String get agentWriteConsent;

  /// No description provided for @agentExternalConsent.
  ///
  /// In zh, this message translates to:
  /// **'允许外部工具操作'**
  String get agentExternalConsent;

  /// No description provided for @agentPrivateConsent.
  ///
  /// In zh, this message translates to:
  /// **'包含私密笔记，需要重新验证'**
  String get agentPrivateConsent;

  /// No description provided for @agentPrivateOnlineConsent.
  ///
  /// In zh, this message translates to:
  /// **'明确允许把私密内容发送到上述在线服务 / 网络工具'**
  String get agentPrivateOnlineConsent;

  /// No description provided for @agentPrivateHidden.
  ///
  /// In zh, this message translates to:
  /// **'此任务含私密内容。解锁并重新授权后查看或继续。'**
  String get agentPrivateHidden;

  /// No description provided for @agentPrivateUnlock.
  ///
  /// In zh, this message translates to:
  /// **'验证私密笔记访问权限'**
  String get agentPrivateUnlock;

  /// No description provided for @agentPrivateSendTitle.
  ///
  /// In zh, this message translates to:
  /// **'发送私密内容'**
  String get agentPrivateSendTitle;

  /// No description provided for @agentPrivateSendBody.
  ///
  /// In zh, this message translates to:
  /// **'本次任务会把私密内容发送给 {target} 或已启用的网络工具。该授权仅本次有效，继续前需要验证身份。'**
  String agentPrivateSendBody(String target);

  /// No description provided for @agentSkill.
  ///
  /// In zh, this message translates to:
  /// **'任务模板'**
  String get agentSkill;

  /// No description provided for @agentBudget.
  ///
  /// In zh, this message translates to:
  /// **'任务限制'**
  String get agentBudget;

  /// No description provided for @agentMaxRequests.
  ///
  /// In zh, this message translates to:
  /// **'最多模型请求次数'**
  String get agentMaxRequests;

  /// No description provided for @agentMaxTokens.
  ///
  /// In zh, this message translates to:
  /// **'累计 token 上限'**
  String get agentMaxTokens;

  /// No description provided for @agentMaxOutput.
  ///
  /// In zh, this message translates to:
  /// **'单次输出 token 上限'**
  String get agentMaxOutput;

  /// No description provided for @agentMaxMinutes.
  ///
  /// In zh, this message translates to:
  /// **'活跃执行分钟数'**
  String get agentMaxMinutes;

  /// No description provided for @agentRequestSeconds.
  ///
  /// In zh, this message translates to:
  /// **'单次请求超时秒数'**
  String get agentRequestSeconds;

  /// No description provided for @agentStart.
  ///
  /// In zh, this message translates to:
  /// **'开始任务'**
  String get agentStart;

  /// No description provided for @agentPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get agentPause;

  /// No description provided for @agentStop.
  ///
  /// In zh, this message translates to:
  /// **'停止'**
  String get agentStop;

  /// No description provided for @agentContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get agentContinue;

  /// No description provided for @agentRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get agentRetry;

  /// No description provided for @agentRegenerate.
  ///
  /// In zh, this message translates to:
  /// **'重新生成'**
  String get agentRegenerate;

  /// No description provided for @agentReview.
  ///
  /// In zh, this message translates to:
  /// **'审核修改'**
  String get agentReview;

  /// No description provided for @agentApprove.
  ///
  /// In zh, this message translates to:
  /// **'确认执行'**
  String get agentApprove;

  /// No description provided for @agentReject.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get agentReject;

  /// No description provided for @agentBefore.
  ///
  /// In zh, this message translates to:
  /// **'修改前'**
  String get agentBefore;

  /// No description provided for @agentAfter.
  ///
  /// In zh, this message translates to:
  /// **'修改后'**
  String get agentAfter;

  /// No description provided for @agentAdjustPreview.
  ///
  /// In zh, this message translates to:
  /// **'按所选项目重新生成预览'**
  String get agentAdjustPreview;

  /// No description provided for @agentEditProposal.
  ///
  /// In zh, this message translates to:
  /// **'调整正文'**
  String get agentEditProposal;

  /// No description provided for @agentUndo.
  ///
  /// In zh, this message translates to:
  /// **'撤销这组修改'**
  String get agentUndo;

  /// No description provided for @agentUndone.
  ///
  /// In zh, this message translates to:
  /// **'已撤销'**
  String get agentUndone;

  /// No description provided for @agentUndoConfirm.
  ///
  /// In zh, this message translates to:
  /// **'撤销会检查笔记版本，不会覆盖后续编辑。停止任务不会自动撤销已提交的修改。'**
  String get agentUndoConfirm;

  /// No description provided for @agentSources.
  ///
  /// In zh, this message translates to:
  /// **'来源'**
  String get agentSources;

  /// No description provided for @agentVisitedWebSources.
  ///
  /// In zh, this message translates to:
  /// **'本轮访问的网页'**
  String get agentVisitedWebSources;

  /// No description provided for @agentNoteChanges.
  ///
  /// In zh, this message translates to:
  /// **'笔记变更'**
  String get agentNoteChanges;

  /// No description provided for @agentNoteCreated.
  ///
  /// In zh, this message translates to:
  /// **'已新建'**
  String get agentNoteCreated;

  /// No description provided for @agentNoteEdited.
  ///
  /// In zh, this message translates to:
  /// **'已编辑'**
  String get agentNoteEdited;

  /// No description provided for @agentNoteAppended.
  ///
  /// In zh, this message translates to:
  /// **'已追加'**
  String get agentNoteAppended;

  /// No description provided for @agentNoteMetadataUpdated.
  ///
  /// In zh, this message translates to:
  /// **'已更新信息'**
  String get agentNoteMetadataUpdated;

  /// No description provided for @agentNoteDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已删除'**
  String get agentNoteDeleted;

  /// No description provided for @agentPlan.
  ///
  /// In zh, this message translates to:
  /// **'任务计划'**
  String get agentPlan;

  /// No description provided for @agentActions.
  ///
  /// In zh, this message translates to:
  /// **'执行记录'**
  String get agentActions;

  /// No description provided for @agentChildren.
  ///
  /// In zh, this message translates to:
  /// **'子任务'**
  String get agentChildren;

  /// No description provided for @agentEstimatedUsage.
  ///
  /// In zh, this message translates to:
  /// **'用量含估算'**
  String get agentEstimatedUsage;

  /// No description provided for @agentOfflineNotice.
  ///
  /// In zh, this message translates to:
  /// **'严格离线：推理、压缩和子任务都不联网'**
  String get agentOfflineNotice;

  /// No description provided for @agentLocalNetworkNotice.
  ///
  /// In zh, this message translates to:
  /// **'本地推理，允许联网工具'**
  String get agentLocalNetworkNotice;

  /// No description provided for @agentReconcile.
  ///
  /// In zh, this message translates to:
  /// **'核实外部操作结果'**
  String get agentReconcile;

  /// No description provided for @agentReconcileNotice.
  ///
  /// In zh, this message translates to:
  /// **'请先在外部服务核实是否已执行。不要仅凭超时判断失败；FKNotes 不会自动重试这一步。'**
  String get agentReconcileNotice;

  /// No description provided for @agentEffectDone.
  ///
  /// In zh, this message translates to:
  /// **'我已核实：已执行'**
  String get agentEffectDone;

  /// No description provided for @agentEffectNone.
  ///
  /// In zh, this message translates to:
  /// **'我已核实：未执行'**
  String get agentEffectNone;

  /// No description provided for @agentVerificationNote.
  ///
  /// In zh, this message translates to:
  /// **'核实依据'**
  String get agentVerificationNote;

  /// No description provided for @agentDeleteTask.
  ///
  /// In zh, this message translates to:
  /// **'删除任务记录（不撤销操作）'**
  String get agentDeleteTask;

  /// No description provided for @agentLegacyProposal.
  ///
  /// In zh, this message translates to:
  /// **'旧提案将交给当前智能体重新生成安全预览。'**
  String get agentLegacyProposal;

  /// No description provided for @agentClearHistory.
  ///
  /// In zh, this message translates to:
  /// **'清空智能体执行记录'**
  String get agentClearHistory;

  /// No description provided for @agentClearHistoryNotice.
  ///
  /// In zh, this message translates to:
  /// **'这会删除所有智能体执行记录和恢复信息，不会撤销已修改的笔记或外部操作。'**
  String get agentClearHistoryNotice;

  /// No description provided for @agentError.
  ///
  /// In zh, this message translates to:
  /// **'{code, select, authentication{API Key 无效或没有访问权限，请检查模型配置。} endpointNotFound{找不到模型接口，请检查服务地址和接口协议。} invalidRequest{模型服务不接受本次请求，请检查模型名称、上下文长度或接口兼容性。} rateLimited{请求过于频繁或额度不足，请稍后重试。} requestTimeout{模型服务响应超时，请稍后重试。} serviceUnavailable{模型服务暂时不可用，请稍后重试。} contextOverflow{本次上下文超过模型限制，请缩短内容或调高模型上下文长度。} modelTransport{无法读取模型响应，请检查网络、接口协议和模型配置。} httpError{模型服务返回异常响应，请稍后重试。} other{操作未完成，请检查相关设置后重试。}}'**
  String agentError(String code);

  /// No description provided for @agentUsage.
  ///
  /// In zh, this message translates to:
  /// **'运行 {requests} 轮 · {tokens} token'**
  String agentUsage(int requests, String tokens);

  /// No description provided for @agentRunSummary.
  ///
  /// In zh, this message translates to:
  /// **'{status} · 运行 {rounds} 轮 · 工具调用 {tools} 次 · 用时 {duration}'**
  String agentRunSummary(String status, int rounds, int tools, String duration);

  /// No description provided for @agentRunSummaryWithoutTools.
  ///
  /// In zh, this message translates to:
  /// **'{status} · 运行 {rounds} 轮 · 用时 {duration}'**
  String agentRunSummaryWithoutTools(
    String status,
    int rounds,
    String duration,
  );

  /// No description provided for @agentReasoningRound.
  ///
  /// In zh, this message translates to:
  /// **'第 {round} 轮思考'**
  String agentReasoningRound(int round);

  /// No description provided for @agentModelRounds.
  ///
  /// In zh, this message translates to:
  /// **'智能体运行 · {rounds} 轮'**
  String agentModelRounds(int rounds);

  /// No description provided for @agentStageExplanation.
  ///
  /// In zh, this message translates to:
  /// **'阶段说明'**
  String get agentStageExplanation;

  /// No description provided for @agentPlanUpdated.
  ///
  /// In zh, this message translates to:
  /// **'计划更新'**
  String get agentPlanUpdated;

  /// No description provided for @agentPlanCurrent.
  ///
  /// In zh, this message translates to:
  /// **'正在进行：{title}'**
  String agentPlanCurrent(String title);

  /// No description provided for @agentPlanNext.
  ///
  /// In zh, this message translates to:
  /// **'接下来：{title}'**
  String agentPlanNext(String title);

  /// No description provided for @agentPlanCompleted.
  ///
  /// In zh, this message translates to:
  /// **'计划已完成'**
  String get agentPlanCompleted;

  /// No description provided for @agentLoadingModel.
  ///
  /// In zh, this message translates to:
  /// **'正在加载本地模型'**
  String get agentLoadingModel;

  /// No description provided for @agentCompressingContext.
  ///
  /// In zh, this message translates to:
  /// **'正在整理较早的任务上下文'**
  String get agentCompressingContext;

  /// No description provided for @agentWebSearchUsed.
  ///
  /// In zh, this message translates to:
  /// **'已完成网页搜索'**
  String get agentWebSearchUsed;

  /// No description provided for @agentOpeningWebPage.
  ///
  /// In zh, this message translates to:
  /// **'正在打开网页…'**
  String get agentOpeningWebPage;

  /// No description provided for @agentWebPageOpened.
  ///
  /// In zh, this message translates to:
  /// **'已打开网页'**
  String get agentWebPageOpened;

  /// No description provided for @agentFindingInWebPage.
  ///
  /// In zh, this message translates to:
  /// **'正在页内查找…'**
  String get agentFindingInWebPage;

  /// No description provided for @agentWebPageFindCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已完成页内查找'**
  String get agentWebPageFindCompleted;

  /// No description provided for @agentWebSearchContent.
  ///
  /// In zh, this message translates to:
  /// **'搜索内容'**
  String get agentWebSearchContent;

  /// No description provided for @agentWebPageAddress.
  ///
  /// In zh, this message translates to:
  /// **'网页地址'**
  String get agentWebPageAddress;

  /// No description provided for @agentWebFindContent.
  ///
  /// In zh, this message translates to:
  /// **'查找内容'**
  String get agentWebFindContent;

  /// No description provided for @agentWebSearchResults.
  ///
  /// In zh, this message translates to:
  /// **'搜索结果'**
  String get agentWebSearchResults;

  /// No description provided for @agentWebRelatedSources.
  ///
  /// In zh, this message translates to:
  /// **'相关来源'**
  String get agentWebRelatedSources;

  /// No description provided for @agentWebSearchNoResults.
  ///
  /// In zh, this message translates to:
  /// **'未找到相关结果'**
  String get agentWebSearchNoResults;

  /// No description provided for @agentWebSearchProviderManaged.
  ///
  /// In zh, this message translates to:
  /// **'搜索结果已提供给模型，但服务商未向客户端公开明细'**
  String get agentWebSearchProviderManaged;

  /// No description provided for @agentWebPageProviderManaged.
  ///
  /// In zh, this message translates to:
  /// **'页面内容已提供给模型，但服务商未向客户端公开明细'**
  String get agentWebPageProviderManaged;

  /// No description provided for @agentWebSearchDetailsUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'服务商未提供可展示的结果明细'**
  String get agentWebSearchDetailsUnavailable;

  /// No description provided for @agentWebPageDetailsUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'服务商未提供可展示的页面摘要'**
  String get agentWebPageDetailsUnavailable;

  /// No description provided for @agentWebSearchFailed.
  ///
  /// In zh, this message translates to:
  /// **'搜索结果获取失败'**
  String get agentWebSearchFailed;

  /// No description provided for @agentPlanSteps.
  ///
  /// In zh, this message translates to:
  /// **'规划了 {count} 个步骤'**
  String agentPlanSteps(int count);

  /// No description provided for @agentSubtaskCount.
  ///
  /// In zh, this message translates to:
  /// **'运行了 {count} 个子任务'**
  String agentSubtaskCount(int count);

  /// No description provided for @agentRunFinished.
  ///
  /// In zh, this message translates to:
  /// **'{time} 完成 · 用时 {duration}'**
  String agentRunFinished(String time, String duration);

  /// No description provided for @agentRunFinishedAt.
  ///
  /// In zh, this message translates to:
  /// **'{time} 完成'**
  String agentRunFinishedAt(String time);

  /// No description provided for @agentRunningTool.
  ///
  /// In zh, this message translates to:
  /// **'正在执行：{action}'**
  String agentRunningTool(String action);

  /// No description provided for @agentSearchingWeb.
  ///
  /// In zh, this message translates to:
  /// **'正在搜索网页…'**
  String get agentSearchingWeb;

  /// No description provided for @agentThinkingNow.
  ///
  /// In zh, this message translates to:
  /// **'正在思考…'**
  String get agentThinkingNow;

  /// No description provided for @agentToolInput.
  ///
  /// In zh, this message translates to:
  /// **'调用参数'**
  String get agentToolInput;

  /// No description provided for @agentToolResult.
  ///
  /// In zh, this message translates to:
  /// **'执行结果'**
  String get agentToolResult;

  /// No description provided for @agentToolSearchQuery.
  ///
  /// In zh, this message translates to:
  /// **'搜索“{query}”'**
  String agentToolSearchQuery(String query);

  /// No description provided for @agentToolFoundNotes.
  ///
  /// In zh, this message translates to:
  /// **'找到 {count} 篇笔记'**
  String agentToolFoundNotes(int count);

  /// No description provided for @agentToolReadNotes.
  ///
  /// In zh, this message translates to:
  /// **'读取 {count} 篇笔记'**
  String agentToolReadNotes(int count);

  /// No description provided for @agentToolChangedNotes.
  ///
  /// In zh, this message translates to:
  /// **'处理 {count} 篇笔记'**
  String agentToolChangedNotes(int count);

  /// No description provided for @agentStatus.
  ///
  /// In zh, this message translates to:
  /// **'{status, select, queued{等待执行} running{执行中} waitingApproval{等待审批} paused{已暂停} interrupted{可恢复} cancelling{正在停止} completed{已完成} cancelled{已停止} failed{未完成} needsReconciliation{等待核实} other{未知状态}}'**
  String agentStatus(String status);

  /// No description provided for @agentSkillName.
  ///
  /// In zh, this message translates to:
  /// **'{skill, select, assistant{通用助手} summarize{总结笔记} rewrite{改写} tasks{提取待办} organize{整理专题} other{通用助手}}'**
  String agentSkillName(String skill);

  /// No description provided for @agentActionName.
  ///
  /// In zh, this message translates to:
  /// **'{action, select, search_notes{检索笔记} read_notes{读取笔记} propose_note_changes{笔记修改} web_fetch{读取网页} update_plan{更新计划} delegate{委派只读子任务} other{外部工具}}'**
  String agentActionName(String action);

  /// No description provided for @agentIncludeHistory.
  ///
  /// In zh, this message translates to:
  /// **'带上当前对话历史'**
  String get agentIncludeHistory;

  /// No description provided for @agentHistoryScopeHint.
  ///
  /// In zh, this message translates to:
  /// **'历史中引用的笔记也需要授权；关闭后不发送之前的上下文。'**
  String get agentHistoryScopeHint;

  /// No description provided for @agentSkipApproval.
  ///
  /// In zh, this message translates to:
  /// **'跳过逐次审批'**
  String get agentSkipApproval;

  /// No description provided for @agentApprovalDefaultHint.
  ///
  /// In zh, this message translates to:
  /// **'默认开启，已授权操作直接执行。关闭后每次修改前先确认；仅影响新任务。'**
  String get agentApprovalDefaultHint;

  /// No description provided for @agentApprovalTaskHint.
  ///
  /// In zh, this message translates to:
  /// **'开启后直接执行已授权的笔记修改与外部操作，不扩大读取或联网权限。'**
  String get agentApprovalTaskHint;

  /// No description provided for @agentApprovalAutomatic.
  ///
  /// In zh, this message translates to:
  /// **'已授权操作自动执行'**
  String get agentApprovalAutomatic;

  /// No description provided for @agentApprovalManual.
  ///
  /// In zh, this message translates to:
  /// **'修改前逐次审批'**
  String get agentApprovalManual;

  /// No description provided for @agentModelLimits.
  ///
  /// In zh, this message translates to:
  /// **'模型长度限制'**
  String get agentModelLimits;

  /// No description provided for @agentModelLimitsSummary.
  ///
  /// In zh, this message translates to:
  /// **'长度单位为 token，请按服务商规格填写。'**
  String get agentModelLimitsSummary;

  /// No description provided for @agentTokenUnits.
  ///
  /// In zh, this message translates to:
  /// **'单位为 token，支持整数或 K / M：1K = 1024，1M = 1048576。'**
  String get agentTokenUnits;

  /// No description provided for @agentModelLimitsHint.
  ///
  /// In zh, this message translates to:
  /// **'上下文包含输入、历史、工具与输出；输出上限应小于上下文。新任务默认使用这些值，实际能力以供应商为准。'**
  String get agentModelLimitsHint;

  /// No description provided for @agentModelLimitsError.
  ///
  /// In zh, this message translates to:
  /// **'上下文需在 1024–2097152 token 之间；输出上限必须大于 0 且小于上下文。可填写整数、K 或 M。'**
  String get agentModelLimitsError;

  /// No description provided for @agentSharedKeyHint.
  ///
  /// In zh, this message translates to:
  /// **'本服务的所有模型共用此 Key；留空保留已有 Key，仅存于系统安全存储。'**
  String get agentSharedKeyHint;

  /// No description provided for @agentServiceModels.
  ///
  /// In zh, this message translates to:
  /// **'服务中的模型'**
  String get agentServiceModels;

  /// No description provided for @agentServiceModelsSummary.
  ///
  /// In zh, this message translates to:
  /// **'可获取或批量填写模型 ID；能力与长度仍需逐个确认。'**
  String get agentServiceModelsSummary;

  /// No description provided for @agentCatalogNotice.
  ///
  /// In zh, this message translates to:
  /// **'填写地址与 Key 后可获取模型列表，不发送笔记或生成内容。列表不保证兼容当前协议，长度与能力仍需按模型设置。'**
  String get agentCatalogNotice;

  /// No description provided for @agentFetchModels.
  ///
  /// In zh, this message translates to:
  /// **'从接口获取模型列表'**
  String get agentFetchModels;

  /// No description provided for @agentCatalogFailed.
  ///
  /// In zh, this message translates to:
  /// **'未获取到可用列表（{code}）。可重试，或直接手动添加，不影响保存。'**
  String agentCatalogFailed(String code);

  /// No description provided for @agentBatchModelIds.
  ///
  /// In zh, this message translates to:
  /// **'手动添加模型标识'**
  String get agentBatchModelIds;

  /// No description provided for @agentBatchModelHint.
  ///
  /// In zh, this message translates to:
  /// **'支持一次粘贴多个，每行一个或用逗号分隔；自动去重，也可以添加接口未列出的模型。每个服务最多保存 100 个。'**
  String get agentBatchModelHint;

  /// No description provided for @agentAddModelsToList.
  ///
  /// In zh, this message translates to:
  /// **'添加到模型列表'**
  String get agentAddModelsToList;

  /// No description provided for @agentEditingModel.
  ///
  /// In zh, this message translates to:
  /// **'当前模型（已添加 {count} 个）'**
  String agentEditingModel(int count);

  /// No description provided for @agentRemoveModelFromList.
  ///
  /// In zh, this message translates to:
  /// **'从列表移除此模型'**
  String get agentRemoveModelFromList;

  /// No description provided for @agentPerModelHint.
  ///
  /// In zh, this message translates to:
  /// **'下方设置与连接测试只作用于当前模型，可切换后分别调整。新增模型使用默认参数；保存时保留列表中所有模型。'**
  String get agentPerModelHint;

  /// No description provided for @agentModelListError.
  ///
  /// In zh, this message translates to:
  /// **'请添加 1–100 个模型标识，每行一个或用逗号分隔；标识内不能有空格，每个最多 200 个字符。'**
  String get agentModelListError;

  /// No description provided for @agentSelectCatalogModels.
  ///
  /// In zh, this message translates to:
  /// **'选择要添加的模型'**
  String get agentSelectCatalogModels;

  /// No description provided for @agentSearchModels.
  ///
  /// In zh, this message translates to:
  /// **'搜索模型或服务名称'**
  String get agentSearchModels;

  /// No description provided for @agentSelectVisibleModels.
  ///
  /// In zh, this message translates to:
  /// **'选中搜索结果（最多 100 个）'**
  String get agentSelectVisibleModels;

  /// No description provided for @agentModelAlreadyAdded.
  ///
  /// In zh, this message translates to:
  /// **'已在本服务中'**
  String get agentModelAlreadyAdded;

  /// No description provided for @agentAddSelectedModels.
  ///
  /// In zh, this message translates to:
  /// **'添加所选模型（{count}）'**
  String agentAddSelectedModels(int count);

  /// No description provided for @agentDeleteService.
  ///
  /// In zh, this message translates to:
  /// **'删除此服务及其模型'**
  String get agentDeleteService;

  /// No description provided for @agentDeleteServiceHint.
  ///
  /// In zh, this message translates to:
  /// **'将移除此服务的所有模型配置和已保存的 Key，不会删除笔记或任务记录。'**
  String get agentDeleteServiceHint;

  /// No description provided for @agentSwitchModel.
  ///
  /// In zh, this message translates to:
  /// **'切换模型'**
  String get agentSwitchModel;

  /// No description provided for @done.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get done;

  /// No description provided for @agentExecution.
  ///
  /// In zh, this message translates to:
  /// **'执行'**
  String get agentExecution;

  /// No description provided for @agentNoMcpServers.
  ///
  /// In zh, this message translates to:
  /// **'尚未添加 MCP 服务'**
  String get agentNoMcpServers;

  /// No description provided for @agentConnection.
  ///
  /// In zh, this message translates to:
  /// **'连接'**
  String get agentConnection;

  /// No description provided for @agentModelParameters.
  ///
  /// In zh, this message translates to:
  /// **'模型参数'**
  String get agentModelParameters;

  /// No description provided for @agentKeyStored.
  ///
  /// In zh, this message translates to:
  /// **'已安全保存'**
  String get agentKeyStored;

  /// No description provided for @agentManageLocalModels.
  ///
  /// In zh, this message translates to:
  /// **'管理本地模型'**
  String get agentManageLocalModels;

  /// No description provided for @agentServiceModelCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个模型'**
  String agentServiceModelCount(int count);

  /// No description provided for @fmTitle.
  ///
  /// In zh, this message translates to:
  /// **'文件'**
  String get fmTitle;

  /// No description provided for @fmSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'把资料好好收在一起'**
  String get fmSubtitle;

  /// No description provided for @fmAllFiles.
  ///
  /// In zh, this message translates to:
  /// **'全部文件'**
  String get fmAllFiles;

  /// No description provided for @fmRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近打开'**
  String get fmRecent;

  /// No description provided for @fmFavorites.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get fmFavorites;

  /// No description provided for @fmTrash.
  ///
  /// In zh, this message translates to:
  /// **'回收站'**
  String get fmTrash;

  /// No description provided for @fmImport.
  ///
  /// In zh, this message translates to:
  /// **'导入文件'**
  String get fmImport;

  /// No description provided for @fmNewFolder.
  ///
  /// In zh, this message translates to:
  /// **'新建文件夹'**
  String get fmNewFolder;

  /// No description provided for @fmSearch.
  ///
  /// In zh, this message translates to:
  /// **'搜索文件和文件夹'**
  String get fmSearch;

  /// No description provided for @fmAllTypes.
  ///
  /// In zh, this message translates to:
  /// **'全部类型'**
  String get fmAllTypes;

  /// No description provided for @fmDocuments.
  ///
  /// In zh, this message translates to:
  /// **'文档'**
  String get fmDocuments;

  /// No description provided for @fmSpreadsheets.
  ///
  /// In zh, this message translates to:
  /// **'表格'**
  String get fmSpreadsheets;

  /// No description provided for @fmPresentations.
  ///
  /// In zh, this message translates to:
  /// **'演示文稿'**
  String get fmPresentations;

  /// No description provided for @fmImages.
  ///
  /// In zh, this message translates to:
  /// **'图片'**
  String get fmImages;

  /// No description provided for @fmAudio.
  ///
  /// In zh, this message translates to:
  /// **'音频'**
  String get fmAudio;

  /// No description provided for @fmVideo.
  ///
  /// In zh, this message translates to:
  /// **'视频'**
  String get fmVideo;

  /// No description provided for @fmText.
  ///
  /// In zh, this message translates to:
  /// **'文本'**
  String get fmText;

  /// No description provided for @fmArchives.
  ///
  /// In zh, this message translates to:
  /// **'压缩包'**
  String get fmArchives;

  /// No description provided for @fmOther.
  ///
  /// In zh, this message translates to:
  /// **'其他文件'**
  String get fmOther;

  /// No description provided for @fmFolder.
  ///
  /// In zh, this message translates to:
  /// **'文件夹'**
  String get fmFolder;

  /// No description provided for @fmSort.
  ///
  /// In zh, this message translates to:
  /// **'排序'**
  String get fmSort;

  /// No description provided for @fmSortName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get fmSortName;

  /// No description provided for @fmSortModified.
  ///
  /// In zh, this message translates to:
  /// **'修改时间'**
  String get fmSortModified;

  /// No description provided for @fmSortSize.
  ///
  /// In zh, this message translates to:
  /// **'文件大小'**
  String get fmSortSize;

  /// No description provided for @fmSortType.
  ///
  /// In zh, this message translates to:
  /// **'文件类型'**
  String get fmSortType;

  /// No description provided for @fmAscending.
  ///
  /// In zh, this message translates to:
  /// **'升序'**
  String get fmAscending;

  /// No description provided for @fmDescending.
  ///
  /// In zh, this message translates to:
  /// **'降序'**
  String get fmDescending;

  /// No description provided for @fmGrid.
  ///
  /// In zh, this message translates to:
  /// **'网格视图'**
  String get fmGrid;

  /// No description provided for @fmList.
  ///
  /// In zh, this message translates to:
  /// **'列表视图'**
  String get fmList;

  /// No description provided for @fmSelect.
  ///
  /// In zh, this message translates to:
  /// **'选择文件'**
  String get fmSelect;

  /// No description provided for @fmSelected.
  ///
  /// In zh, this message translates to:
  /// **'已选择 {count} 项'**
  String fmSelected(int count);

  /// No description provided for @fmItems.
  ///
  /// In zh, this message translates to:
  /// **'{count} 项'**
  String fmItems(int count);

  /// No description provided for @fmFileCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个文件'**
  String fmFileCount(int count);

  /// No description provided for @fmLocalStorage.
  ///
  /// In zh, this message translates to:
  /// **'本地文件 · {size}'**
  String fmLocalStorage(String size);

  /// No description provided for @fmEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'给文件一个整齐的家'**
  String get fmEmptyTitle;

  /// No description provided for @fmEmptyBody.
  ///
  /// In zh, this message translates to:
  /// **'导入文档、图片、音视频等任意文件，按文件夹整理，随时打开。'**
  String get fmEmptyBody;

  /// No description provided for @fmFolderEmpty.
  ///
  /// In zh, this message translates to:
  /// **'文件夹还是空的'**
  String get fmFolderEmpty;

  /// No description provided for @fmNoResults.
  ///
  /// In zh, this message translates to:
  /// **'没有找到匹配的文件'**
  String get fmNoResults;

  /// No description provided for @fmNoResultsBody.
  ///
  /// In zh, this message translates to:
  /// **'试试其他名称，或清除类型筛选。'**
  String get fmNoResultsBody;

  /// No description provided for @fmNoFavorites.
  ///
  /// In zh, this message translates to:
  /// **'还没有收藏'**
  String get fmNoFavorites;

  /// No description provided for @fmNoFavoritesBody.
  ///
  /// In zh, this message translates to:
  /// **'把常用文件或文件夹加入收藏，方便下次找到。'**
  String get fmNoFavoritesBody;

  /// No description provided for @fmNoRecent.
  ///
  /// In zh, this message translates to:
  /// **'还没有打开过文件'**
  String get fmNoRecent;

  /// No description provided for @fmNoRecentBody.
  ///
  /// In zh, this message translates to:
  /// **'打开的文件会显示在这里。'**
  String get fmNoRecentBody;

  /// No description provided for @fmTrashEmpty.
  ///
  /// In zh, this message translates to:
  /// **'回收站是空的'**
  String get fmTrashEmpty;

  /// No description provided for @fmTrashHint.
  ///
  /// In zh, this message translates to:
  /// **'删除的文件会保留在这里，可恢复或永久删除。'**
  String get fmTrashHint;

  /// No description provided for @fmRename.
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get fmRename;

  /// No description provided for @fmMove.
  ///
  /// In zh, this message translates to:
  /// **'移动到'**
  String get fmMove;

  /// No description provided for @fmCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制到'**
  String get fmCopy;

  /// No description provided for @fmMoveHere.
  ///
  /// In zh, this message translates to:
  /// **'移动到这里'**
  String get fmMoveHere;

  /// No description provided for @fmCopyHere.
  ///
  /// In zh, this message translates to:
  /// **'复制到这里'**
  String get fmCopyHere;

  /// No description provided for @fmFavorite.
  ///
  /// In zh, this message translates to:
  /// **'加入收藏'**
  String get fmFavorite;

  /// No description provided for @fmUnfavorite.
  ///
  /// In zh, this message translates to:
  /// **'取消收藏'**
  String get fmUnfavorite;

  /// No description provided for @fmDetails.
  ///
  /// In zh, this message translates to:
  /// **'详细信息'**
  String get fmDetails;

  /// No description provided for @fmShare.
  ///
  /// In zh, this message translates to:
  /// **'分享'**
  String get fmShare;

  /// No description provided for @fmExport.
  ///
  /// In zh, this message translates to:
  /// **'另存到本机'**
  String get fmExport;

  /// No description provided for @fmOpenSystem.
  ///
  /// In zh, this message translates to:
  /// **'用其他应用打开'**
  String get fmOpenSystem;

  /// No description provided for @fmRestore.
  ///
  /// In zh, this message translates to:
  /// **'恢复'**
  String get fmRestore;

  /// No description provided for @fmDelete.
  ///
  /// In zh, this message translates to:
  /// **'移入回收站'**
  String get fmDelete;

  /// No description provided for @fmDeleteForever.
  ///
  /// In zh, this message translates to:
  /// **'永久删除'**
  String get fmDeleteForever;

  /// No description provided for @fmEmptyTrash.
  ///
  /// In zh, this message translates to:
  /// **'清空回收站'**
  String get fmEmptyTrash;

  /// No description provided for @fmDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'永久删除所选的 {count} 项及其内容？此操作无法撤销。'**
  String fmDeleteConfirm(int count);

  /// No description provided for @fmTrashed.
  ///
  /// In zh, this message translates to:
  /// **'已移入回收站'**
  String get fmTrashed;

  /// No description provided for @fmUndo.
  ///
  /// In zh, this message translates to:
  /// **'撤销'**
  String get fmUndo;

  /// No description provided for @fmCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get fmCancel;

  /// No description provided for @fmConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get fmConfirm;

  /// No description provided for @fmName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get fmName;

  /// No description provided for @fmCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建'**
  String get fmCreate;

  /// No description provided for @fmCreated.
  ///
  /// In zh, this message translates to:
  /// **'创建时间'**
  String get fmCreated;

  /// No description provided for @fmModified.
  ///
  /// In zh, this message translates to:
  /// **'修改时间'**
  String get fmModified;

  /// No description provided for @fmSize.
  ///
  /// In zh, this message translates to:
  /// **'大小'**
  String get fmSize;

  /// No description provided for @fmType.
  ///
  /// In zh, this message translates to:
  /// **'类型'**
  String get fmType;

  /// No description provided for @fmLocation.
  ///
  /// In zh, this message translates to:
  /// **'所在位置'**
  String get fmLocation;

  /// No description provided for @fmImporting.
  ///
  /// In zh, this message translates to:
  /// **'正在导入 {current}/{total}'**
  String fmImporting(int current, int total);

  /// No description provided for @fmImportCancelled.
  ///
  /// In zh, this message translates to:
  /// **'取消导入'**
  String get fmImportCancelled;

  /// No description provided for @fmErrorLoad.
  ///
  /// In zh, this message translates to:
  /// **'无法读取文件库，请重试。'**
  String get fmErrorLoad;

  /// No description provided for @fmErrorOperation.
  ///
  /// In zh, this message translates to:
  /// **'操作未完成，请检查可用空间和文件访问权限后重试。'**
  String get fmErrorOperation;

  /// No description provided for @fmErrorImport.
  ///
  /// In zh, this message translates to:
  /// **'部分文件未能导入，已导入的文件已保留。请重新选择失败的文件。'**
  String get fmErrorImport;

  /// No description provided for @fmErrorName.
  ///
  /// In zh, this message translates to:
  /// **'名称不能为空，不能含路径或特殊字符，且最多 240 个字符。'**
  String get fmErrorName;

  /// No description provided for @fmErrorExists.
  ///
  /// In zh, this message translates to:
  /// **'此位置已有同名文件或文件夹。'**
  String get fmErrorExists;

  /// No description provided for @fmErrorDestination.
  ///
  /// In zh, this message translates to:
  /// **'此文件夹不可用，请选择其他位置。'**
  String get fmErrorDestination;

  /// No description provided for @fmErrorCycle.
  ///
  /// In zh, this message translates to:
  /// **'不能放入自身或自己的子文件夹。'**
  String get fmErrorCycle;

  /// No description provided for @fmRetry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get fmRetry;

  /// No description provided for @fmPreviewUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'此格式需要兼容的应用预览'**
  String get fmPreviewUnavailable;

  /// No description provided for @fmOfficeHint.
  ///
  /// In zh, this message translates to:
  /// **'使用本机的 Office、WPS 或其他兼容应用查看完整排版。'**
  String get fmOfficeHint;

  /// No description provided for @fmPreviewHint.
  ///
  /// In zh, this message translates to:
  /// **'可用其他应用打开，也可以分享或另存文件。'**
  String get fmPreviewHint;

  /// No description provided for @fmOpenFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法打开文件，请确认本机安装了支持此格式的应用。'**
  String get fmOpenFailed;

  /// No description provided for @fmPreviewFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法预览此文件'**
  String get fmPreviewFailed;

  /// No description provided for @fmPreviewLarge.
  ///
  /// In zh, this message translates to:
  /// **'文件较大，请使用其他应用查看完整内容。'**
  String get fmPreviewLarge;

  /// No description provided for @fmSaved.
  ///
  /// In zh, this message translates to:
  /// **'文件已另存到所选位置'**
  String get fmSaved;

  /// No description provided for @fmTextTruncated.
  ///
  /// In zh, this message translates to:
  /// **'仅显示前 20 万个字符，可用其他应用查看完整内容。'**
  String get fmTextTruncated;

  /// No description provided for @fmPlay.
  ///
  /// In zh, this message translates to:
  /// **'播放'**
  String get fmPlay;

  /// No description provided for @fmPause.
  ///
  /// In zh, this message translates to:
  /// **'暂停'**
  String get fmPause;

  /// No description provided for @fmArchiveHint.
  ///
  /// In zh, this message translates to:
  /// **'压缩包内容（只读）'**
  String get fmArchiveHint;

  /// No description provided for @fmArchiveLimit.
  ///
  /// In zh, this message translates to:
  /// **'内容过多，仅显示前 1,000 项。'**
  String get fmArchiveLimit;

  /// No description provided for @fmMissing.
  ///
  /// In zh, this message translates to:
  /// **'文件不存在或无法读取，请恢复备份或重新导入。'**
  String get fmMissing;

  /// No description provided for @fmLocalHint.
  ///
  /// In zh, this message translates to:
  /// **'导入的文件保存在应用内，原文件不受影响。'**
  String get fmLocalHint;

  /// No description provided for @fmMore.
  ///
  /// In zh, this message translates to:
  /// **'更多操作'**
  String get fmMore;

  /// No description provided for @materialRecent.
  ///
  /// In zh, this message translates to:
  /// **'手边资料'**
  String get materialRecent;

  /// No description provided for @materialFavorites.
  ///
  /// In zh, this message translates to:
  /// **'收藏资料'**
  String get materialFavorites;

  /// No description provided for @materialImages.
  ///
  /// In zh, this message translates to:
  /// **'图片记录'**
  String get materialImages;

  /// No description provided for @materialContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续记录'**
  String get materialContinue;

  /// No description provided for @materialCategories.
  ///
  /// In zh, this message translates to:
  /// **'资料分类'**
  String get materialCategories;

  /// No description provided for @materialAllFiles.
  ///
  /// In zh, this message translates to:
  /// **'全部资料'**
  String get materialAllFiles;

  /// No description provided for @materialWrite.
  ///
  /// In zh, this message translates to:
  /// **'记一笔'**
  String get materialWrite;

  /// No description provided for @materialContinueNote.
  ///
  /// In zh, this message translates to:
  /// **'继续笔记'**
  String get materialContinueNote;

  /// No description provided for @materialPreview.
  ///
  /// In zh, this message translates to:
  /// **'预览资料'**
  String get materialPreview;

  /// No description provided for @materialPickFavorites.
  ///
  /// In zh, this message translates to:
  /// **'挑选资料'**
  String get materialPickFavorites;

  /// No description provided for @materialOpenImages.
  ///
  /// In zh, this message translates to:
  /// **'全部图片'**
  String get materialOpenImages;

  /// No description provided for @materialEmptyRecentTitle.
  ///
  /// In zh, this message translates to:
  /// **'把值得记录的资料，留在手边。'**
  String get materialEmptyRecentTitle;

  /// No description provided for @materialEmptyRecentBody.
  ///
  /// In zh, this message translates to:
  /// **'从一份文档、一张图片开始。'**
  String get materialEmptyRecentBody;

  /// No description provided for @materialEmptyFavoritesTitle.
  ///
  /// In zh, this message translates to:
  /// **'常看的资料，随时接着写。'**
  String get materialEmptyFavoritesTitle;

  /// No description provided for @materialEmptyFavoritesBody.
  ///
  /// In zh, this message translates to:
  /// **'从文件库挑选常用资料，加入收藏。'**
  String get materialEmptyFavoritesBody;

  /// No description provided for @materialEmptyImagesTitle.
  ///
  /// In zh, this message translates to:
  /// **'让一张图片，成为记录的起点。'**
  String get materialEmptyImagesTitle;

  /// No description provided for @materialEmptyImagesBody.
  ///
  /// In zh, this message translates to:
  /// **'导入图片后，可在这里预览和记笔记。'**
  String get materialEmptyImagesBody;

  /// No description provided for @materialEmptyContinueTitle.
  ///
  /// In zh, this message translates to:
  /// **'留一点想法，下次接着写。'**
  String get materialEmptyContinueTitle;

  /// No description provided for @materialEmptyContinueBody.
  ///
  /// In zh, this message translates to:
  /// **'从资料点“记一笔”，相关笔记会出现在这里。'**
  String get materialEmptyContinueBody;

  /// No description provided for @materialLoading.
  ///
  /// In zh, this message translates to:
  /// **'正在读取资料…'**
  String get materialLoading;

  /// No description provided for @materialLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法读取资料'**
  String get materialLoadFailed;

  /// No description provided for @materialLinked.
  ///
  /// In zh, this message translates to:
  /// **'已有相关笔记'**
  String get materialLinked;

  /// No description provided for @materialRecentlyOpened.
  ///
  /// In zh, this message translates to:
  /// **'最近打开'**
  String get materialRecentlyOpened;

  /// No description provided for @materialRecentlyImported.
  ///
  /// In zh, this message translates to:
  /// **'最近导入'**
  String get materialRecentlyImported;

  /// No description provided for @materialSavedLayoutFailed.
  ///
  /// In zh, this message translates to:
  /// **'暂时无法记住卡片选择，可稍后重试。'**
  String get materialSavedLayoutFailed;

  /// No description provided for @materialPage.
  ///
  /// In zh, this message translates to:
  /// **'{name}，第 {page} 张，共 {total} 张'**
  String materialPage(String name, int page, int total);

  /// No description provided for @materialSaveFavorites.
  ///
  /// In zh, this message translates to:
  /// **'保存收藏'**
  String get materialSaveFavorites;

  /// No description provided for @materialFileCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个文件'**
  String materialFileCount(int count);

  /// No description provided for @fileReferences.
  ///
  /// In zh, this message translates to:
  /// **'文件引用'**
  String get fileReferences;

  /// No description provided for @shareFileReferencesContinued.
  ///
  /// In zh, this message translates to:
  /// **'文件引用（续）'**
  String get shareFileReferencesContinued;

  /// No description provided for @shareImageUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'图片暂无法显示'**
  String get shareImageUnavailable;

  /// No description provided for @fileReferenceCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个文件'**
  String fileReferenceCount(int count);

  /// No description provided for @fileReferencesHint.
  ///
  /// In zh, this message translates to:
  /// **'点击查看完整引用列表'**
  String get fileReferencesHint;

  /// No description provided for @fileReferenceUnavailable.
  ///
  /// In zh, this message translates to:
  /// **'文件已移除或在回收站'**
  String get fileReferenceUnavailable;

  /// No description provided for @fileReferencesRemove.
  ///
  /// In zh, this message translates to:
  /// **'移除引用卡片'**
  String get fileReferencesRemove;

  /// No description provided for @fileReferencesChoose.
  ///
  /// In zh, this message translates to:
  /// **'选择要引用的文件'**
  String get fileReferencesChoose;

  /// No description provided for @fileReferencesAdd.
  ///
  /// In zh, this message translates to:
  /// **'引用所选文件（{count}）'**
  String fileReferencesAdd(int count);

  /// No description provided for @fileReferencesEmpty.
  ///
  /// In zh, this message translates to:
  /// **'从文件库选择，或导入文件后引用到笔记'**
  String get fileReferencesEmpty;

  /// No description provided for @fileReferencesSelect.
  ///
  /// In zh, this message translates to:
  /// **'引用文件'**
  String get fileReferencesSelect;

  /// No description provided for @moveFileReferencesHint.
  ///
  /// In zh, this message translates to:
  /// **'长按拖动引用卡片以调整位置'**
  String get moveFileReferencesHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
