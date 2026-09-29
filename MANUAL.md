# Run the exercise

1. From the repository root, open the project:

   ```sh
   open lab.ios.SecureCommunication.xcodeproj
   ```

2. In Xcode, select the `lab.ios.SecureCommunication` scheme.
3. Select an installed iPhone Simulator running iOS 17 or newer.
4. Run the app with `⌘R`.
5. Run the included tests with `⌘U`.

The checked-in hosted configuration is ready to use. Do not create or select
`Config/Local.xcconfig` unless the trainer instructs you to use a local server.

## If a build fails

The app folder uses Xcode buildable folders, so the project file lists folders
rather than sources and does not change when files are added, renamed, or
removed. An Xcode session that was open while the file set changed, or that was
used with a different branch or revision, can keep referring to files that are
gone and fail at the build phase.

Clean and rebuild:

Product → Clean Build Folder (⇧⌘K)

Closing and reopening the project re-enumerates the folders as well. If the
error survives both, delete the project's DerivedData folder and rebuild.
