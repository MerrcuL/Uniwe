import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/grades.dart';
import '../models/lecture_details.dart';
import '../models/person_details.dart';
import '../models/timetable_event.dart';
import '../utils/cookies.dart';
import 'exceptions.dart';
import 'log_service.dart';
import 'lsf_parser.dart';

class LsfScraperService {
  static const Duration _timeout = Duration(seconds: 15);
  static const String _userAgent = 'Mozilla/5.0 (Windows NT 10.0)';
  static const String _baseUrl = 'https://lsf.htw-berlin.de/qisserver/rds';
  static const String _loginUrl =
      '$_baseUrl?state=user&type=1&category=auth.login&startpage=portal.vm';

  final LogService _logger;
  final http.Client _client;
  final Map<String, String> _cookies = {};

  /// Lecture details rarely change; keep them for the lifetime of a session
  /// so re-opening an event is instant.
  final Map<String, LectureDetails> _detailsCache = {};
  final Map<String, PersonDetails> _personCache = {};

  /// The `asi` token of the current session, needed by the grade and
  /// document pages. Tied to the session, so dropped with it.
  String? _asi;

  LsfScraperService(this._logger, {http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get cookies => Map.unmodifiable(_cookies);

  bool get hasSession => _cookies.isNotEmpty;

  /// Drops the session and everything fetched with it.
  void clearCookies() {
    _cookies.clear();
    _detailsCache.clear();
    _personCache.clear();
    _asi = null;
  }

  void dispose() => _client.close();

  /// Returns true if the credentials were accepted. Throws on network errors
  /// and when LSF itself is unavailable, so that callers never mistake an
  /// outage for wrong credentials (or for a successful login).
  Future<bool> login(String username, String password) async {
    final request = http.Request('POST', Uri.parse(_loginUrl))
      ..headers['User-Agent'] = _userAgent
      ..bodyFields = {
        'asdf': username,
        'fdsa': password,
        'submit': 'Anmelden',
      };

    if (_cookies.isNotEmpty) {
      request.headers['Cookie'] = cookieHeader(_cookies);
    }

    _logger.debug('POST login for $username');
    final streamedResponse = await _client.send(request).timeout(_timeout);
    final response =
        await http.Response.fromStream(streamedResponse).timeout(_timeout);

    if (response.statusCode >= 500) {
      _logger.warning('LSF login unavailable (HTTP ${response.statusCode})');
      throw HttpStatusException(response.statusCode, 'LSF login');
    }

    mergeSetCookie(response.headers['set-cookie'], _cookies);
    _asi = null;

    if (isLsfLoginPage(response.body)) {
      _logger.warning(
          'LsfScraperService.login: authentication failed for user $username');
      return false;
    }
    _logger.info(
        'LsfScraperService.login: authentication successful for user $username');
    return true;
  }

  /// GETs an LSF page with the session cookies and returns its HTML.
  Future<String> _getAuthenticated(String url, String what) async {
    if (_cookies.isEmpty) {
      _logger.warning('Session expired (no cookies) while fetching $what');
      throw SessionExpiredException();
    }

    final response = await _client.get(
      Uri.parse(url),
      headers: {
        'User-Agent': _userAgent,
        'Cookie': cookieHeader(_cookies),
      },
    ).timeout(_timeout);

    mergeSetCookie(response.headers['set-cookie'], _cookies);

    if (response.statusCode >= 500) {
      _logger.warning('LSF unavailable (HTTP ${response.statusCode}) for $what');
      throw HttpStatusException(response.statusCode, what);
    }

    final html = response.body;
    if (isLsfLoginPage(html)) {
      _logger.warning(
          'Session expired (login form returned) while fetching $what');
      throw SessionExpiredException();
    }
    _logger.info('Fetched $what (${response.bodyBytes.length} bytes)');
    return html;
  }

  Future<List<TimetableEvent>> fetchTimetable(String targetWeek) async {
    _logger.debug('GET timetable for week $targetWeek');
    final html = await _getAuthenticated(
      '$_baseUrl?state=wplan&week=$targetWeek&act=show&pool=&show=plan&P.vx=mittel&P.Print=',
      'timetable for $targetWeek',
    );
    return compute(parseTimetableHtml, html);
  }

  Future<LectureDetails> fetchLectureDetails(String publishId) async {
    final cached = _detailsCache[publishId];
    if (cached != null) return cached;

    final html = await _getAuthenticated(
      '$_baseUrl?state=verpublish&status=init&vmfile=no&publishid=$publishId&moduleCall=webInfo&publishConfFile=webInfo&publishSubDir=veranstaltung',
      'lecture details for $publishId',
    );
    final details = await compute(parseLectureDetailsHtml, (publishId, html));
    _detailsCache[publishId] = details;
    return details;
  }

  Future<PersonDetails> fetchPersonDetails(String personId) async {
    final cached = _personCache[personId];
    if (cached != null) return cached;

    final html = await _getAuthenticated(
      '$_baseUrl?state=verpublish&status=init&vmfile=no&moduleCall=webInfo&publishConfFile=webInfoPerson&publishSubDir=personal&keep=y&personal.pid=$personId',
      'person details for $personId',
    );
    final details = await compute(parsePersonDetailsHtml, (personId, html));
    _personCache[personId] = details;
    return details;
  }

  static const String _documentsMenuUrl =
      '$_baseUrl?state=change&type=1&moduleParameter=studyPOSReportMenu&nextdir=change&next=menu.vm&subdir=applications&xml=menu&purge=y&navigationPosition=functions%2Cdoc&breadcrumb=documents&topitem=functions&subitem=doc';

  /// Fetches the documents menu, which also carries the session's `asi`.
  /// A page without one means the session is not signed in.
  Future<List<LsfDocument>> fetchDocuments() async {
    final html = await _getAuthenticated(_documentsMenuUrl, 'documents menu');
    final asi = parseLsfAsi(html);
    if (asi == null) {
      _logger.warning('Session expired (no asi) while fetching documents');
      throw SessionExpiredException();
    }
    _asi = asi;
    return compute(parseDocumentsMenuHtml, html);
  }

  Future<String> _sessionAsi() async {
    final asi = _asi;
    if (asi != null) return asi;
    await fetchDocuments();
    return _asi!;
  }

  /// GETs an LSF page of the signed-in session, with the current `asi`.
  /// A page without the token means the token or session went stale.
  Future<String> _getWithAsi(Uri url, String what) async {
    final asi = await _sessionAsi();
    final withAsi =
        url.replace(queryParameters: {...url.queryParameters, 'asi': asi});
    final html = await _getAuthenticated(withAsi.toString(), what);
    if (parseLsfAsi(html) == null) {
      _asi = null;
      throw SessionExpiredException();
    }
    return html;
  }

  static final Uri _gradeTreeUrl = Uri.parse(_baseUrl).replace(
    queryParameters: {
      'state': 'notenspiegelStudent',
      'next': 'tree.vm',
      'nextdir': 'qispos/notenspiegel/student',
      'navigationPosition': 'functions,notenspiegelStudent',
      'breadcrumb': 'notenKlassenSpiegel',
      'topitem': 'functions',
      'subitem': 'notenspiegelStudent',
    },
  );

  static final Uri _achievementUrl = Uri.parse(_baseUrl).replace(
    queryParameters: {
      'state': 'htmlbesch',
      'application': 'sospos',
      'moduleParameter': 'Student',
      'navigationPosition': 'functions,notenspiegel',
      'breadcrumb': 'leistungsstand',
      'topitem': 'functions',
      'subitem': 'notenspiegel',
    },
  );

  /// The grades of every degree programme ("Noten- und Klassenspiegel").
  Future<GradeReport> fetchGrades() async {
    final tree = await _getWithAsi(_gradeTreeUrl, 'grade overview');
    final lists = await compute(parseGradeTreeHtml, tree);
    if (lists.isEmpty) {
      // A single programme may be shown right away.
      final report = await compute(parseGradeListHtml, tree);
      _logger.info('Grade overview without programme selection '
          '(${report.results.length} results)');
      return report;
    }

    final reports = <GradeReport>[];
    for (final list in lists) {
      final html = await _getWithAsi(list, 'grade list');
      reports.add(await compute(parseGradeListHtml, html));
    }
    if (reports.length == 1) return reports.single;
    final averages = reports.map((r) => r.average).nonNulls.toSet();
    final credits = reports.map((r) => r.credits).nonNulls.toSet();
    return GradeReport(
      programs: [for (final r in reports) ...r.programs],
      results: [for (final r in reports) ...r.results],
      groups: [for (final r in reports) ...r.groups],
      // Several programmes have no common average or credit total.
      average: averages.length == 1 ? averages.single : null,
      credits: credits.length == 1 ? credits.single : null,
    );
  }

  /// How everyone who took [result]'s exam did, or null if LSF has no
  /// distribution for it.
  Future<GradeDistribution?> fetchDistribution(ExamResult result) async {
    final url = result.distributionUrl;
    if (url == null) return null;
    final html = await _getWithAsi(url, 'grade distribution');
    return compute(parseGradeDistributionHtml, html);
  }

  /// Per-semester records of achievement and transcripts.
  Future<AchievementDocuments> fetchAchievementDocuments() async {
    final html = await _getWithAsi(_achievementUrl, 'achievement documents');
    return compute(parseAchievementDocumentsHtml, html);
  }

  /// Lets LSF generate [document] for this session and returns the PDF.
  Future<Uint8List> downloadDocument(LsfDocument document) async {
    if (_cookies.isEmpty) throw SessionExpiredException();
    final asi = await _sessionAsi();
    final url = document.url.replace(
      queryParameters: {...document.url.queryParameters, 'asi': asi},
    );
    _logger.debug('GET document ${document.url.queryParameters['moduleCall']}');
    final response = await _client.get(url, headers: {
      'User-Agent': _userAgent,
      'Cookie': cookieHeader(_cookies),
    }).timeout(const Duration(seconds: 60));
    mergeSetCookie(response.headers['set-cookie'], _cookies);

    if (response.statusCode >= 500) {
      throw HttpStatusException(response.statusCode, 'document');
    }
    final bytes = response.bodyBytes;
    if (isPdf(bytes)) {
      _logger.info('Downloaded document (${bytes.length} bytes)');
      return bytes;
    }
    _logger.warning('Document request returned no PDF '
        '(HTTP ${response.statusCode}, ${response.headers['content-type']})');
    // A page of the signed-in session (it carries the token): LSF has no
    // such document for this student. Anything else is the login or error
    // page of a lost session.
    final html = response.body;
    if (!isLsfLoginPage(html) && parseLsfAsi(html) == asi) {
      throw DocumentUnavailableException();
    }
    _asi = null;
    throw SessionExpiredException();
  }

  static bool isPdf(List<int> bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 && // %PDF
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46;
}
