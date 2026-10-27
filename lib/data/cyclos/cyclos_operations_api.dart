import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/dio_factory.dart';
import '../models/models.dart';

/// Cyclos custom operations (MoMo top-up / cash-out, loans, DailySaver…),
/// run the way the official frontend does (cyclos4-ui
/// run-operation-helper.service.ts):
///  * user-scope operations: /self/operations/{op}/data-for-run and /run
///  * internal actions (e.g. the "Confirm" on a preview) and system ones:
///    /operations/{op}/data-for-run and /run
///  * RunOperation body: {formParameters, confirmationPassword}
class CyclosOperationsApi {
  CyclosOperationsApi(this._dio);
  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  String _base(String scope) => scope == 'user' ? '/self/operations' : '/operations';

  /// GET /self/operations — operations the member can run.
  Future<List<OperationDef>> list() => _guard(() async {
        final res = await _dio.get<List<dynamic>>('/self/operations');
        return (res.data ?? const [])
            .map((e) => OperationDef.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  Future<OperationForm> dataForRun(String op, {String scope = 'user'}) =>
      _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
            '${_base(scope)}/${Uri.encodeComponent(op)}/data-for-run');
        return OperationForm.fromJson(res.data!);
      });

  Future<OperationResult> run(
    String op, {
    String scope = 'user',
    Map<String, String> formParameters = const {},
    String? confirmationPassword,
  }) =>
      _guard(() async {
        final res = await _dio.post<dynamic>(
          '${_base(scope)}/${Uri.encodeComponent(op)}/run',
          data: {
            'formParameters': formParameters,
            if (confirmationPassword != null) 'confirmationPassword': confirmationPassword,
          },
        );
        final data = res.data;
        return OperationResult.fromJson(
            data is Map ? data.cast<String, dynamic>() : {'content': '$data'});
      });
}

final cyclosOperationsApiProvider =
    Provider<CyclosOperationsApi>((ref) => CyclosOperationsApi(ref.watch(cyclosDioProvider)));

// ---------------------------------------------------------------------------

/// Cyclos `Operation`.
class OperationDef {
  OperationDef({
    required this.id,
    required this.name,
    this.internalName,
    this.label,
    this.scope = 'user',
    this.resultType,
    this.requireConfirmationPassword = false,
    this.confirmationText,
  });

  final String id;
  final String name;
  final String? internalName;
  final String? label;
  final String scope; // user | internal | system | ...
  final String? resultType;
  final bool requireConfirmationPassword;
  final String? confirmationText;

  /// What to put in URLs: internal name when defined, else id.
  String get key => internalName ?? id;

  factory OperationDef.fromJson(Map<String, dynamic> j) => OperationDef(
        id: j['id'].toString(),
        name: (j['name'] ?? j['label'] ?? '').toString(),
        internalName: j['internalName']?.toString(),
        label: j['label']?.toString(),
        scope: (j['scope'] ?? 'user').toString(),
        resultType: j['resultType']?.toString(),
        requireConfirmationPassword: j['requireConfirmationPassword'] == true,
        confirmationText: j['confirmationText']?.toString(),
      );
}

/// One form parameter (Cyclos CustomFieldDetailed), simplified.
class OperationField {
  OperationField({
    required this.key,
    required this.name,
    required this.type,
    this.required = false,
    this.defaultValue,
    this.informationText,
    this.options = const [],
    this.decimalDigits,
  });

  final String key; // internal name or id
  final String name;
  final String type; // string, integer, decimal, text, boolean, singleSelection, date...
  final bool required;
  final String? defaultValue;
  final String? informationText;

  /// (value sent, label shown) for selections.
  final List<(String, String)> options;
  final int? decimalDigits;

  bool get looksLikePhone {
    final k = '$key $name'.toLowerCase();
    return k.contains('phone') || k.contains('msisdn') || k.contains('mobile') || k.contains('tel');
  }

  factory OperationField.fromJson(Map<String, dynamic> j) {
    final options = <(String, String)>[];
    for (final v in (j['possibleValues'] as List?) ?? const []) {
      if (v is Map) {
        options.add(((v['internalName'] ?? v['id']).toString(), (v['value'] ?? '').toString()));
      }
    }
    for (final v in (j['dynamicValues'] as List?) ?? const []) {
      if (v is Map) {
        options.add((v['value'].toString(), (v['label'] ?? v['value']).toString()));
      }
    }
    for (final v in (j['stringValues'] as List?) ?? const []) {
      options.add((v.toString(), v.toString()));
    }
    return OperationField(
      key: (j['internalName'] ?? j['id']).toString(),
      name: (j['name'] ?? '').toString(),
      type: (j['type'] ?? 'string').toString(),
      required: j['required'] == true,
      defaultValue: j['defaultValue']?.toString(),
      informationText: j['informationText']?.toString(),
      options: options,
      decimalDigits: (j['decimalDigits'] as num?)?.toInt(),
    );
  }
}

/// Cyclos `OperationDataForRun`.
class OperationForm {
  OperationForm({
    required this.def,
    this.informationText,
    this.submitLabel,
    this.fields = const [],
    this.confirmation,
  });

  final OperationDef def;
  final String? informationText;
  final String? submitLabel;
  final List<OperationField> fields;
  final ConfirmationInput? confirmation;

  factory OperationForm.fromJson(Map<String, dynamic> j) => OperationForm(
        def: OperationDef.fromJson(j),
        informationText: j['informationText']?.toString(),
        submitLabel: j['customSubmitLabel']?.toString(),
        fields: [
          for (final f in (j['formParameters'] as List?) ?? const [])
            if (f is Map) OperationField.fromJson(f.cast<String, dynamic>()),
        ],
        confirmation: ConfirmationInput.fromJson(j['confirmationPasswordInput']),
      );
}

/// A follow-up action offered by a result (e.g. "Confirm" on a preview).
class OperationAction {
  OperationAction({required this.op, required this.parameters, this.primary = false});
  final OperationDef op;
  final Map<String, String> parameters;
  final bool primary;

  factory OperationAction.fromJson(Map<String, dynamic> j) => OperationAction(
        op: OperationDef.fromJson(((j['action'] as Map?) ?? const {}).cast<String, dynamic>()),
        parameters: {
          for (final e in ((j['parameters'] as Map?) ?? const {}).entries)
            e.key.toString(): '${e.value}',
        },
        primary: j['primary'] == true,
      );
}

/// Cyclos `RunOperationResult`.
class OperationResult {
  OperationResult({
    this.resultType,
    this.title,
    this.content,
    this.notification,
    this.notificationLevel,
    this.url,
    this.actions = const [],
    this.backToRoot = false,
    this.columns = const [],
    this.rows = const [],
    this.autoRunActionId,
  });

  final String? resultType;
  final String? title;
  final String? content;
  final String? notification;
  final String? notificationLevel; // information | warning | error
  final String? url;
  final List<OperationAction> actions;
  final bool backToRoot;

  /// resultPage: (property, header) and rows keyed by property.
  final List<(String, String)> columns;
  final List<Map<String, dynamic>> rows;
  final String? autoRunActionId;

  bool get isError => notificationLevel == 'error';

  factory OperationResult.fromJson(Map<String, dynamic> j) => OperationResult(
        resultType: j['resultType']?.toString(),
        title: j['title']?.toString(),
        content: j['content']?.toString(),
        notification: j['notification']?.toString(),
        notificationLevel: j['notificationLevel']?.toString(),
        url: j['url']?.toString(),
        actions: [
          for (final a in (j['actions'] as List?) ?? const [])
            if (a is Map) OperationAction.fromJson(a.cast<String, dynamic>()),
        ],
        backToRoot: j['backToRoot'] == true,
        columns: [
          for (final c in (j['columns'] as List?) ?? const [])
            if (c is Map) ((c['property'] ?? '').toString(), (c['header'] ?? '').toString()),
        ],
        rows: [
          for (final r in (j['rows'] as List?) ?? const [])
            if (r is Map) r.cast<String, dynamic>(),
        ],
        autoRunActionId: j['autoRunActionId']?.toString(),
      );
}

/// Turns Cyclos rich text (HTML) into readable plain text.
String htmlToText(String html) {
  var s = html
      .replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<\s*hr[^>]*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</\s*(p|div|tr|li|h\d|table|ul|ol)\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '• ')
      .replaceAll(RegExp(r'</\s*td\s*>', caseSensitive: false), '   ')
      .replaceAll(RegExp(r'<[^>]+>'), '');
  s = decodeHtmlEntities(s);
  return s
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ').trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

const _namedEntities = {
  'nbsp': '\u00a0', 'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'",
  'eacute': 'é', 'egrave': 'è', 'ecirc': 'ê', 'euml': 'ë', 'agrave': 'à',
  'acirc': 'â', 'ccedil': 'ç', 'icirc': 'î', 'iuml': 'ï', 'ocirc': 'ô',
  'ugrave': 'ù', 'ucirc': 'û', 'uuml': 'ü', 'Eacute': 'É', 'Egrave': 'È',
  'Agrave': 'À', 'Ccedil': 'Ç', 'laquo': '«', 'raquo': '»', 'euro': '€',
  'bull': '•', 'middot': '·', 'ndash': '–', 'mdash': '—', 'hellip': '…',
  'rsquo': '’', 'lsquo': '‘', 'rdquo': '”', 'ldquo': '“', 'deg': '°',
};

/// Decodes named (French accents included) and numeric HTML entities.
String decodeHtmlEntities(String s) => s.replaceAllMapped(
      RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'),
      (m) {
        final e = m.group(1)!;
        int? code;
        if (e.startsWith('#x') || e.startsWith('#X')) {
          code = int.tryParse(e.substring(2), radix: 16);
        } else if (e.startsWith('#')) {
          code = int.tryParse(e.substring(1));
        }
        if (code != null && code > 0 && code <= 0x10FFFF) {
          return String.fromCharCode(code);
        }
        return _namedEntities[e] ?? m.group(0)!;
      },
    );
