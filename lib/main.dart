import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'data/local_delivery_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The one place storage is chosen. Swapping in an API-backed
  // DeliveryRepository later is a change to this line and nothing else.
  final database = await AppDatabase.open();
  runApp(LogisticsApp(repository: LocalDeliveryRepository(database)));
}
