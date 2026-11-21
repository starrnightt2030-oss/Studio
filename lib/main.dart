import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/storage/key_store.dart';
import 'core/storage/local_db.dart';
import 'data/azure/azure_tts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDb.init();

  final container = ProviderContainer();
  await container.read(apiKeyProvider.notifier).load();
  await container.read(azureConfigProvider.notifier).load();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));

  runApp(UncontrolledProviderScope(container: container, child: const StudioApp()));
}
