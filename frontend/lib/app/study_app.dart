import 'package:flutter/material.dart';

import '../features/shell/study_shell.dart';
import 'theme/meta_theme.dart';

class StudyApp extends StatelessWidget {
  const StudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Character Study',
      debugShowCheckedModeBanner: false,
      theme: MetaTheme.light(),
      home: const StudyShell(),
    );
  }
}
