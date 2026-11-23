// Firebase project nchemty-d07fd (the same project the published Nchemty apps
// used). Values from google-services.json (Android, com.nchemty.ebank) and
// GoogleService-Info.plist (iOS). These are client identifiers, shipped in
// every copy of the app; they are not secrets.
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';

class NchemtyFirebaseOptions {
  static FirebaseOptions? get currentPlatform {
    if (Platform.isAndroid) return android;
    if (Platform.isIOS) return ios;
    return null;
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyChwI-qqJL8nxsK9U5Mcnt916TdgZx1orQ',
    appId: '1:993880655885:android:745b3048383ab085346d44',
    messagingSenderId: '993880655885',
    projectId: 'nchemty-d07fd',
    storageBucket: 'nchemty-d07fd.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyA-b9hJMtly4wZ0dyvipn-NbkAxp_8eBbo',
    appId: '1:993880655885:ios:6b89ef5ca63a8611346d44',
    messagingSenderId: '993880655885',
    projectId: 'nchemty-d07fd',
    storageBucket: 'nchemty-d07fd.firebasestorage.app',
    iosBundleId: 'com.nchemty.ebank',
  );
}
