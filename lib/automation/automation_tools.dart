const automationInstructions = '''
Control the running Faust CAD document. Lengths are millimetres; camera angles
are degrees. Coordinates are independent of the user's viewport. Call cad_begin
before editing; use its sessionId until cad_finish. Always finish in a finally
step. Stop AI revokes the session. Do not automatically restart a stopped session.
Each successful modeling call is one undo step. Failed drafts do not change the
model. Supply a new requestId for each intended mutation; reuse that exact ID and
arguments after a lost response. Read the current revision before a new edit.
Profile IDs are snapshot-local: use cad_get_profiles and its revision immediately
before cad_extrude. Select the region with a hole to preserve a bore; selecting
the inner disk too fills it. Model simplified gears with polygon segments and a
circle, then extrude. No gear generator, motion validation or print export exists.
''';

Map<String, Object?> _object(
  Map<String, Object?> properties, [
  List<String> required = const [],
]) => {
  'type': 'object',
  'properties': properties,
  'required': required,
  'additionalProperties': false,
};
const _string = {'type': 'string', 'minLength': 1, 'maxLength': 120};
const _number = {'type': 'number', 'minimum': -10000, 'maximum': 10000};
const _positive = {'type': 'number', 'exclusiveMinimum': 0, 'maximum': 10000};
const _revision = {'type': 'integer', 'minimum': 0};
Map<String, Object?> _array(Object items, int max) => {
  'type': 'array',
  'items': items,
  'maxItems': max,
};

Map<String, Object?> _tool(
  String name,
  String description,
  Map<String, Object?> schema, {
  bool readOnly = false,
}) => {
  'name': name,
  'description': description,
  'inputSchema': schema,
  'annotations': {'readOnlyHint': readOnly, 'openWorldHint': false},
};

final automationTools = <Map<String, Object?>>[
  _tool(
    'cad_delete_feature',
    'Delete one feature if the remaining document evaluates successfully. One undo step.',
    _object(
      {..._editFields, 'featureId': _string},
      [..._editRequired, 'featureId'],
    ),
  ),
  _tool(
    'cad_get_document',
    'Read features, parameters, outputs, units, revision and history.',
    _object({}),
    readOnly: true,
  ),
  _tool(
    'cad_begin',
    'Acquire exclusive AI editing. Fails while a human is editing or after Stop AI until re-enabled.',
    _object({}),
  ),
  _tool(
    'cad_finish',
    'Release AI editing, keeping completed steps.',
    _object({'sessionId': _string}, ['sessionId']),
  ),
  _tool(
    'cad_get_profiles',
    'List bounded sketch regions with areas and hole counts. IDs require the returned revision.',
    _object({'sketchId': _string}, ['sketchId']),
    readOnly: true,
  ),
  _tool(
    'cad_set_sketch',
    'Create or replace a sketch on a principal plane. Shared endpoint IDs join segments. Circle radius is half the bore diameter. One undo step.',
    _object(
      {
        ..._editFields,
        'featureId': _string,
        'name': _string,
        'plane': {
          'type': 'string',
          'enum': ['xy', 'xz', 'yz'],
        },
        'points': _array(
          _object(
            {'id': _string, 'x': _number, 'y': _number},
            ['id', 'x', 'y'],
          ),
          256,
        ),
        'segments': _array(
          _object(
            {'id': _string, 'start': _string, 'end': _string},
            ['id', 'start', 'end'],
          ),
          256,
        ),
        'circles': _array(
          _object(
            {'id': _string, 'center': _string, 'radius': _positive},
            ['id', 'center', 'radius'],
          ),
          16,
        ),
      },
      [..._editRequired, 'featureId', 'plane', 'points', 'segments', 'circles'],
    ),
  ),
  _tool(
    'cad_extrude',
    'Create a linked extrusion from selected current profile IDs. Positive distance follows the sketch normal unless reverse=true.',
    _object(
      {
        ..._editFields,
        'featureId': _string,
        'name': _string,
        'sketchId': _string,
        'regionIds': {..._array(_string, 32), 'minItems': 1},
        'distance': _positive,
        'reverse': {'type': 'boolean'},
      },
      [..._editRequired, 'featureId', 'sketchId', 'regionIds', 'distance'],
    ),
  ),
  _tool(
    'cad_set_extrusion',
    'Change an existing extrusion distance/reverse, retaining its profile references. One undo step.',
    _object(
      {
        ..._editFields,
        'featureId': _string,
        'distance': _positive,
        'reverse': {'type': 'boolean'},
      },
      [..._editRequired, 'featureId', 'distance'],
    ),
  ),
  _tool(
    'cad_undo',
    'Undo one modeling step while retaining exclusive AI control.',
    _object(_editFields, _editRequired),
  ),
  _tool(
    'cad_redo',
    'Redo one modeling step while retaining exclusive AI control.',
    _object(_editFields, _editRequired),
  ),
  _tool(
    'cad_render',
    'Return a PNG of document bodies using an independent camera. Does not move the user camera. target is [x,y,z] in mm.',
    _object({
      'target': {..._array(_number, 3), 'minItems': 3},
      'distance': _positive,
      'yaw': _number,
      'pitch': {'type': 'number', 'minimum': -90, 'maximum': 90},
      'width': {'type': 'integer', 'minimum': 128, 'maximum': 1024},
      'height': {'type': 'integer', 'minimum': 128, 'maximum': 1024},
    }),
    readOnly: true,
  ),
];

const _editFields = <String, Object?>{
  'sessionId': _string,
  'requestId': _string,
  'expectedRevision': _revision,
};
const _editRequired = ['sessionId', 'requestId', 'expectedRevision'];

/// Validates the bounded schema subset used by the automation tools.
void validateAutomationArguments(String name, Map<String, Object?> arguments) {
  final tool = automationTools.where((t) => t['name'] == name).firstOrNull;
  if (tool == null) throw ArgumentError('Unknown tool: $name');
  _validate(
    tool['inputSchema'] as Map<String, Object?>,
    arguments,
    'arguments',
  );
}

void _validate(Map<String, Object?> schema, Object? value, String path) {
  final valid = switch (schema['type']) {
    'object' => value is Map<String, Object?>,
    'array' => value is List,
    'string' => value is String,
    'number' => value is num && value.isFinite,
    'integer' => value is int,
    'boolean' => value is bool,
    _ => false,
  };
  if (!valid) throw ArgumentError('$path: expected ${schema['type']}');
  if (schema['enum'] case List choices) {
    if (!choices.contains(value)) throw ArgumentError('$path: invalid value');
  }
  if (value is Map<String, Object?>) {
    final props = schema['properties'] as Map<String, Object?>;
    for (final key in schema['required'] as List) {
      if (!value.containsKey(key)) {
        throw ArgumentError('$path.$key is required');
      }
    }
    for (final entry in value.entries) {
      if (!props.containsKey(entry.key)) {
        throw ArgumentError('$path.${entry.key}: unknown field');
      }
      _validate(
        props[entry.key] as Map<String, Object?>,
        entry.value,
        '$path.${entry.key}',
      );
    }
  }
  if (value is List) {
    if (value.length < (schema['minItems'] as int? ?? 0) ||
        value.length > (schema['maxItems'] as int)) {
      throw ArgumentError('$path: invalid item count');
    }
    for (final item in value) {
      _validate(schema['items'] as Map<String, Object?>, item, '$path[]');
    }
  }
  if (value is String &&
      (value.trim().isEmpty ||
          value.length > (schema['maxLength'] as int? ?? 120))) {
    throw ArgumentError('$path: invalid string length');
  }
  if (value is num) {
    if ((schema['minimum'] != null && value < (schema['minimum'] as num)) ||
        (schema['maximum'] != null && value > (schema['maximum'] as num)) ||
        (schema['exclusiveMinimum'] != null &&
            value <= (schema['exclusiveMinimum'] as num))) {
      throw ArgumentError('$path: value out of range');
    }
  }
}
