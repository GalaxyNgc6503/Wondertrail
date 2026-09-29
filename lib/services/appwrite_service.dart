import 'package:appwrite/appwrite.dart';

import 'appwrite_config.dart';

/// One shared Appwrite client for the app. Import `AppwriteService.databases`
/// / `AppwriteService.storage` wherever you need them — no need to
/// re-construct the client per call.
class AppwriteService {
  AppwriteService._();

  static final Client client = Client()
    ..setEndpoint(AppwriteConfig.endpoint)
    ..setProject(AppwriteConfig.projectId);

  static final Databases databases = Databases(client);
  static final Storage storage = Storage(client);
}
