import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import 'ai_control_bar.dart';

@Preview(name: 'AI control • desktop', size: Size(900, 100))
@Preview(name: 'AI control • compact', size: Size(360, 160))
Widget aiControlPreview() => MaterialApp(
  home: Scaffold(
    body: AiControlBar(
      active: true,
      paused: false,
      onStop: () {},
      onOpenSettings: () {},
    ),
  ),
);
