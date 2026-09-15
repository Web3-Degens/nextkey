package li.nextkey.app

import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * FlutterFragmentActivity, not FlutterActivity.
 *
 * `local_auth` shows the system BiometricPrompt, which needs a FragmentActivity
 * to attach to. With the default FlutterActivity the app builds, installs, runs
 * — and throws the first time somebody tries to unlock, which is the one moment
 * it must not.
 */
class MainActivity : FlutterFragmentActivity()
