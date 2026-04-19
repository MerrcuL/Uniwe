import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import '../models/timetable_event.dart';
import 'log_service.dart';
import 'exceptions.dart';

class LsfScraperService {
  final LogService _logger;
  final http.Client _client = http.Client();
  final Map<String, String> _cookies = {};

  Map<String, String> get cookies => _cookies;

  LsfScraperService(this._logger);

  static const String _loginUrl = 'https://lsf.htw-berlin.de/qisserver/rds?state=user&type=1&category=auth.login&startpage=portal.vm';

  void _updateCookies(http.BaseResponse response) {
    String? rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      // Split by comma to handle multiple cookies but safely preserving date commas
      var cookieParts = rawCookie.split(RegExp(r',\s*(?=[a-zA-Z0-9_-]+\=)'));
      for (var c in cookieParts) {
        int index = c.indexOf(';');
        String cookieKeyValue = (index == -1) ? c : c.substring(0, index);
        int eqIndex = cookieKeyValue.indexOf('=');
        if (eqIndex != -1) {
          String key = cookieKeyValue.substring(0, eqIndex).trim();
          String value = cookieKeyValue.substring(eqIndex + 1).trim();
          _cookies[key] = value;
        }
      }
    }
  }

  String get _cookieHeader {
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  Future<bool> login(String username, String password) async {
    final request = http.Request('POST', Uri.parse(_loginUrl))
      ..headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0)'
      ..bodyFields = {
        'asdf': username,
        'fdsa': password,
        'submit': 'Anmelden'
      };

    if (_cookies.isNotEmpty) {
      request.headers['Cookie'] = _cookieHeader;
    }

    _logger.debug('POST login for $username');
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    
    _updateCookies(response);

    final html = response.body;
    if (!_isLoggedIn(html)) {
      _logger.warning('LsfScraperService.login: authentication failed for user $username');
      return false;
    }
    _logger.info('LsfScraperService.login: authentication successful for user $username');
    return true;
  }

  bool _isLoggedIn(String html) {
    // If the LSF login form is still present, authentication failed.
    // LSF uses 'asdf' for the username field name.
    return !html.contains('name="asdf"');
  }

  Future<List<TimetableEvent>> fetchTimetable(String targetWeek) async {
    final scheduleUrl = 'https://lsf.htw-berlin.de/qisserver/rds?state=wplan&week=$targetWeek&act=show&pool=&show=plan&P.vx=mittel&P.Print=';
    
    
    final request = http.Request('GET', Uri.parse(scheduleUrl))
      ..headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0)';
    
    if (_cookies.isEmpty) {
      _logger.warning('Session expired (no cookies) while fetching timetable for $targetWeek');
      throw SessionExpiredException();
    }

    request.headers['Cookie'] = _cookieHeader;

    _logger.debug('GET timetable for week $targetWeek');
    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    
    _updateCookies(response);
    _logger.info('Fetched timetable for $targetWeek (${response.bodyBytes.length} bytes)');

    final html = response.body;

    final document = parser.parse(html);
    final scheduleData = <TimetableEvent>[];

    final eventCells = document.querySelectorAll('td').where((element) {
      final className = element.className;
      if (!className.startsWith('plan')) return false;
      const ignoredClasses = ['plan_rahmen', 'plan5', 'plan6', 'plan7', 'plan9'];
      return !ignoredClasses.contains(className);
    });

    for (var cell in eventCells) {
      final titleTags = cell.querySelectorAll('a.ver');
      if (titleTags.isEmpty) continue;

      final bool isOverlapping = titleTags.length > 1;

      for (var titleTag in titleTags) {
        final title = titleTag.text.trim();
        String? publishId;
        final href = titleTag.attributes['href'] ?? '';
        final uri = Uri.tryParse(href.replaceAll('&amp;', '&'));
        if (uri != null && uri.queryParameters.containsKey('publishid')) {
          publishId = uri.queryParameters['publishid'];
        }

        // Find the event container (nearest parent table or the cell itself)
        // LSF wraps individual overlapping events in their own nested <table>.
        var eventContainer = cell;
        var current = titleTag.parent;
        while (current != null && current != cell) {
          if (current.localName == 'table') {
            eventContainer = current;
            break;
          }
          current = current.parent;
        }

        String? day;
        String? time;
        String? room;
        String? type;
        String? frequency;

        // Extract details from notiz cells specifically for this event
        final notizCells = eventContainer.querySelectorAll('td.notiz');
        for (var nCell in notizCells) {
          final text = nCell.text.replaceAll('\n', ' ').replaceAll('\r', '').trim();
          
          if (text.contains('Raum:')) {
            final parts = text.split('Raum:');
            room = parts[1].trim();
            
            final typeParts = parts[0].split(',');
            if (typeParts.isNotEmpty) {
              type = typeParts[0].trim();
            }
          } else if (text.contains(':') && text.contains('-') && text.contains(',')) {
            final timeParts = text.split(',');
            if (timeParts.length >= 2) {
              day = timeParts[0].trim();
              time = timeParts[1].trim();
            }
            if (timeParts.length >= 3) {
              frequency = timeParts[2].trim();
            }
          }
        }

        // Detect exam status specifically for this event
        bool isExam = false;
        final warnungSpans = eventContainer.querySelectorAll('span.warnung');
        for (var span in warnungSpans) {
          if (span.text.contains('Prüfung')) {
            isExam = true;
            break;
          }
        }

        scheduleData.add(TimetableEvent(
          title: title,
          day: day ?? '',
          time: time ?? '',
          room: room ?? '',
          type: type ?? '',
          frequency: frequency ?? '',
          publishId: publishId,
          isExam: isExam,
          isOverlapping: isOverlapping,
        ));
      }
    }

    return scheduleData;
  }

  Future<Map<String, dynamic>?> fetchLectureDetails(String publishId) async {
    final detailUrl = 'https://lsf.htw-berlin.de/qisserver/rds?state=verpublish&status=init&vmfile=no&publishid=$publishId&moduleCall=webInfo&publishConfFile=webInfo&publishSubDir=veranstaltung';
    
    
    final request = http.Request('GET', Uri.parse(detailUrl))
      ..headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0)';
    
    if (_cookies.isEmpty) {
      _logger.warning('Session expired (no cookies) while fetching lecture details for $publishId');
      throw SessionExpiredException();
    }

    request.headers['Cookie'] = _cookieHeader;

    final streamedResponse = await _client.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    _updateCookies(response);

    final html = response.body;

    final document = parser.parse(html);
    final details = <String, dynamic>{
      'publishId': publishId,
      'credits': null,
      'sws': null,
      'teachers': <String>[],
      'exam_dates': <Map<String, String>>[]
    };

    final thTds = document.querySelectorAll('th, td');
    for (var i = 0; i < thTds.length; i++) {
        final text = thTds[i].text.trim();
        if (text == "Credits") {
            var next = thTds[i].nextElementSibling;
            if (next != null && next.localName == 'td') {
                details['credits'] = next.text.trim();
            }
        } else if (text == "SWS") {
            var next = thTds[i].nextElementSibling;
            if (next != null && next.localName == 'td') {
                details['sws'] = next.text.trim();
            }
        }
    }

    final tables = document.querySelectorAll('table');
    for (var table in tables) {
        final headersRaw = table.querySelectorAll('th');
        final headers = headersRaw.map((e) => e.text.trim()).toList();
        
        if (headers.contains('Lehrperson')) {
            int dayIdx = headers.indexOf('Tag');
            int timeIdx = headers.indexOf('Zeit');
            int durationIdx = headers.indexOf('Dauer');
            int teacherIdx = headers.indexOf('Lehrperson');
            int remarkIdx = headers.indexOf('Bemerkung');

            if (dayIdx == -1 || timeIdx == -1 || durationIdx == -1 || teacherIdx == -1 || remarkIdx == -1) continue;

            final rows = table.querySelectorAll('tr');
            for (var row in rows) {
                final cells = row.querySelectorAll('td');
                if (cells.length > dayIdx && cells.length > timeIdx && cells.length > durationIdx && cells.length > teacherIdx && cells.length > remarkIdx) {
                    final teacher = cells[teacherIdx].text.trim();
                    final remark = cells[remarkIdx].text.trim();
                    
                    if (teacher.isNotEmpty && !(details['teachers'] as List).contains(teacher)) {
                        (details['teachers'] as List).add(teacher);
                    }
                    
                    if (remark.contains('Prüfung')) {
                        final examInfo = {
                            'day': cells[dayIdx].text.trim(),
                            'time': cells[timeIdx].text.trim(),
                            'date': cells[durationIdx].text.trim().replaceAll('am ', ''),
                        };
                        bool exists = false;
                        for(var ex in (details['exam_dates'] as List)){
                            if(ex['day'] == examInfo['day'] && ex['time'] == examInfo['time'] && ex['date'] == examInfo['date']){
                                exists = true;
                                break;
                            }
                        }
                        if(!exists){
                            (details['exam_dates'] as List).add(examInfo);
                        }
                    }
                }
            }
        }
    }
    return details;
  }
}
