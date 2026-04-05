import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/config/app_config.dart';

class GoogleLoginTokens {
  const GoogleLoginTokens({
    required this.googleIdToken,
    required this.firebaseIdToken,
  });

  final String googleIdToken;
  final String firebaseIdToken;
}

class FirebaseAuthService {
  GoogleSignIn _googleSignIn() => GoogleSignIn(
        serverClientId: AppConfig.hasGoogleClientId
            ? AppConfig.googleFallbackClientId
            : null,
      );

  Future<GoogleLoginTokens?> signInWithGoogleTokens() async {
    if (Firebase.apps.isEmpty) {
      throw Exception(
        'Firebase is not initialized for this build. Run FlutterFire configure '
        'and relaunch the app.',
      );
    }

    final googleSignIn = _googleSignIn();
    await googleSignIn.signOut();

    final account = await googleSignIn.signIn();
    if (account == null) {
      return null;
    }

    final googleAuth = await account.authentication;
    final googleIdToken = googleAuth.idToken ?? '';
    final googleAccessToken = googleAuth.accessToken ?? '';
    if (googleIdToken.isEmpty && googleAccessToken.isEmpty) {
      throw Exception(
        'Google sign-in did not return usable credentials. Check that Google '
        'Auth is enabled in Firebase and the Android app SHA-1 is registered.',
      );
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential =
        await FirebaseAuth.instance.signInWithCredential(credential);
    final firebaseIdToken = await userCredential.user?.getIdToken(true);

    if ((firebaseIdToken ?? '').isEmpty) {
      throw Exception(
          'Firebase did not return an authenticated session token.');
    }

    return GoogleLoginTokens(
      googleIdToken: googleIdToken,
      firebaseIdToken: firebaseIdToken!,
    );
  }

  Future<String?> signInWithGoogle() async {
    final tokens = await signInWithGoogleTokens();
    return tokens?.firebaseIdToken;
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    await _googleSignIn().signOut();
  }
}
