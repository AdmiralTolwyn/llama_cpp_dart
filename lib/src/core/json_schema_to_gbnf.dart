/// Converts JSON Schema objects into GBNF (GGML BNF) grammar strings
/// for constrained output generation.
///
/// Mirrors llama.rn's `response_format: { type: "json_schema", json_schema: ... }`
/// which internally converts to GBNF before passing to the sampler.
///
/// Usage:
/// ```dart
/// final grammar = JsonSchemaToGbnf.convert({
///   'type': 'object',
///   'properties': {
///     'VERDICT': {'type': 'string', 'enum': ['TRADE', 'NO TRADE', 'WATCH']},
///     'STRATEGY': {'type': 'string'},
///     'CONVICTION': {'type': 'integer', 'minimum': 1, 'maximum': 10},
///     'RATIONALE': {'type': 'string'},
///   },
///   'required': ['VERDICT', 'STRATEGY', 'CONVICTION', 'RATIONALE'],
/// });
/// samplerParams.grammarStr = grammar;
/// samplerParams.grammarRoot = 'root';
/// ```
class JsonSchemaToGbnf {
  final Map<String, String> _rules = {};
  int _ruleCounter = 0;

  JsonSchemaToGbnf._();

  /// Convert a JSON Schema to a GBNF grammar string.
  static String convert(Map<String, dynamic> schema) {
    final converter = JsonSchemaToGbnf._();
    converter._addPrimitiveRules();
    final rootRule = converter._visitSchema(schema);
    converter._rules['root'] = rootRule;
    return converter._buildGrammar();
  }

  void _addPrimitiveRules() {
    _rules['ws'] = r'[ \t\n]*';
    _rules['string'] = r'"' "string-chars" r'"';
    _rules['string-chars'] = r'([^"\\] | "\\" ["\\/bfnrt] | "\\u" [0-9a-fA-F]{4})*';
    _rules['number'] = r'"-"? ("0" | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [+-]? [0-9]+)?';
    _rules['integer'] = r'"-"? ("0" | [1-9] [0-9]*)';
    _rules['boolean'] = r'("true" | "false")';
    _rules['null'] = r'"null"';
  }

  String _newRuleName(String hint) {
    return '${hint}-${_ruleCounter++}';
  }

  String _visitSchema(Map<String, dynamic> schema) {
    // Handle \$ref (not supported — treat as any value)
    if (schema.containsKey('\$ref')) return _visitAnyValue();

    // Handle enum
    if (schema.containsKey('enum')) {
      return _visitEnum(schema['enum'] as List);
    }

    // Handle const
    if (schema.containsKey('const')) {
      return _visitConst(schema['const']);
    }

    // Handle oneOf / anyOf
    if (schema.containsKey('oneOf')) {
      return _visitOneOf(schema['oneOf'] as List);
    }
    if (schema.containsKey('anyOf')) {
      return _visitOneOf(schema['anyOf'] as List);
    }

    final type = schema['type'];
    if (type == null) return _visitAnyValue();

    return switch (type) {
      'object' => _visitObject(schema),
      'array' => _visitArray(schema),
      'string' => _visitString(schema),
      'number' || 'integer' => _visitNumber(type as String, schema),
      'boolean' => 'boolean',
      'null' => 'null',
      _ => _visitAnyValue(),
    };
  }

  String _visitObject(Map<String, dynamic> schema) {
    final properties = schema['properties'] as Map<String, dynamic>?;
    final required = (schema['required'] as List?)?.cast<String>().toSet() ?? {};

    if (properties == null || properties.isEmpty) {
      // Generic object
      final name = _newRuleName('obj');
      _rules[name] = r'"{" ws (string ws ":" ws value (ws "," ws string ws ":" ws value)*)? ws "}"';
      return name;
    }

    final name = _newRuleName('obj');
    final parts = <String>[];
    final optionalParts = <String>[];

    for (final entry in properties.entries) {
      final key = entry.key;
      final propSchema = entry.value as Map<String, dynamic>;
      final propRule = _visitSchema(propSchema);
      final propName = _newRuleName('kv');

      _rules[propName] = '"${_escapeStr('"$key"')}" ws ":" ws $propRule';

      if (required.contains(key)) {
        parts.add(propName);
      } else {
        optionalParts.add(propName);
      }
    }

    // Build the object rule
    // Required fields always present, optional fields may appear
    final buf = StringBuffer();
    buf.write('"{" ws ');

    if (parts.isNotEmpty) {
      buf.write(parts.join(' ws "," ws '));
    }

    // Optional fields: each can appear or not (simplified — they appear in order)
    for (final opt in optionalParts) {
      if (parts.isNotEmpty || optionalParts.indexOf(opt) > 0) {
        buf.write(' (ws "," ws $opt)?');
      } else {
        buf.write(' ($opt)?');
      }
    }

    buf.write(' ws "}"');
    _rules[name] = buf.toString();
    return name;
  }

  String _visitArray(Map<String, dynamic> schema) {
    final items = schema['items'] as Map<String, dynamic>?;
    final name = _newRuleName('arr');

    if (items != null) {
      final itemRule = _visitSchema(items);
      _rules[name] = '"[" ws ($itemRule (ws "," ws $itemRule)*)? ws "]"';
    } else {
      _rules[name] = r'"[" ws (value (ws "," ws value)*)? ws "]"';
    }

    return name;
  }

  String _visitString(Map<String, dynamic> schema) {
    if (schema.containsKey('enum')) {
      return _visitEnum(schema['enum'] as List);
    }
    // Pattern constraint not supported in GBNF — fall back to generic string
    return 'string';
  }

  String _visitNumber(String type, Map<String, dynamic> schema) {
    // GBNF can't enforce min/max constraints — just use the type
    return type == 'integer' ? 'integer' : 'number';
  }

  String _visitEnum(List values) {
    final name = _newRuleName('enum');
    final alts = values.map((v) {
      if (v is String) return '"${_escapeStr('"$v"')}"';
      if (v is num) return '"$v"';
      if (v is bool) return v ? '"true"' : '"false"';
      if (v == null) return '"null"';
      return '"${_escapeStr('"$v"')}"';
    }).join(' | ');
    _rules[name] = '($alts)';
    return name;
  }

  String _visitConst(dynamic value) {
    final name = _newRuleName('const');
    if (value is String) {
      _rules[name] = '"${_escapeStr('"$value"')}"';
    } else {
      _rules[name] = '"$value"';
    }
    return name;
  }

  String _visitOneOf(List schemas) {
    final name = _newRuleName('oneof');
    final alts = schemas.map((s) {
      if (s is Map<String, dynamic>) return _visitSchema(s);
      return _visitAnyValue();
    }).join(' | ');
    _rules[name] = '($alts)';
    return name;
  }

  String _visitAnyValue() {
    if (!_rules.containsKey('value')) {
      _rules['value'] = 'string | number | boolean | null | object | array';
      _rules['object'] = r'"{" ws (string ws ":" ws value (ws "," ws string ws ":" ws value)*)? ws "}"';
      _rules['array'] = r'"[" ws (value (ws "," ws value)*)? ws "]"';
    }
    return 'value';
  }

  String _escapeStr(String s) {
    return s
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"');
  }

  String _buildGrammar() {
    final buf = StringBuffer();
    // Root rule first
    if (_rules.containsKey('root')) {
      buf.writeln('root ::= ${_rules['root']}');
    }
    // Then all other rules in order
    for (final entry in _rules.entries) {
      if (entry.key == 'root') continue;
      buf.writeln('${entry.key} ::= ${entry.value}');
    }
    return buf.toString();
  }

  /// Convenience: generate a GBNF grammar for a flat JSON object with
  /// string keys and specified value types. Good for simple structured output.
  static String simpleObject(Map<String, String> fields) {
    final props = <String, dynamic>{};
    for (final entry in fields.entries) {
      props[entry.key] = {'type': entry.value};
    }
    return convert({
      'type': 'object',
      'properties': props,
      'required': fields.keys.toList(),
    });
  }
}
