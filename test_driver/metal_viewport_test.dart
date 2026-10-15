import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    final images = data?.remove('images') as Map<String, dynamic>? ?? {};
    final directory = Directory('build/metal_images')
      ..createSync(recursive: true);
    for (final entry in images.entries) {
      File('${directory.path}/${entry.key}.png')
          .writeAsBytesSync(base64Decode(entry.value as String));
    }
    File('build/metal_report.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  },
);
