class AppConstants {
  const AppConstants._();

  // Business Rules (Chapter 3: BR-7, BR-8, NFR-1)
  static const Duration qrRotationInterval = Duration(seconds: 10);
  static const Duration qrMaxTokenAge = Duration(seconds: 20);
  static const double maxAllowedDistanceMeters = 100.0;

  // Firestore Collections (matching firestore.rules)
  static const String usersCollection = 'users';
  static const String subjectsCollection = 'subjects';
  static const String groupsCollection = 'groups';
  static const String sessionsCollection = 'sessions';
  static const String uniqueKeysCollection = 'unique_keys';
  static const String secretSubcollection = 'secret';
  static const String secretDocId = 'current';
  static const String presencesSubcollection = 'presences';
}