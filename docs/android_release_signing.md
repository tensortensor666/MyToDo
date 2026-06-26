# Android Release Signing

Android only allows APK updates when the new APK is signed with the same
certificate as the installed APK.

Older MyTodo GitHub release APKs were signed with the CI runner debug key, so
their certificate can change between releases. When switching to the stable
release key below, users who installed those older APKs must uninstall once and
install the first stable-signed APK. After that, future release APKs can update
in place.

## Create A Stable Release Key

Run from the repository root on Windows:

```powershell
.\scripts\create_android_release_keystore.ps1
```

To replace a bad or partially copied key before any stable-signed APK has been
published:

```powershell
.\scripts\create_android_release_keystore.ps1 -Force
```

The script creates `android/signing/mytodo-release.jks` and prints four GitHub
repository secrets:

- `MYTODO_ANDROID_KEYSTORE_BASE64`
- `MYTODO_ANDROID_KEYSTORE_PASSWORD`
- `MYTODO_ANDROID_KEY_ALIAS`
- `MYTODO_ANDROID_KEY_PASSWORD`

Add them in GitHub:

`Settings` -> `Secrets and variables` -> `Actions` -> `New repository secret`.

Keep the `.jks` file and passwords backed up. Losing them means future APKs
cannot update already installed apps.

## CI Behavior

The release workflow refuses to build Android APKs unless all signing secrets
are present. This prevents publishing APKs with unstable debug signatures.
