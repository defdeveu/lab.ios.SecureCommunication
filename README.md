# Secure Communication lab

An iOS teaching application that sends an encrypted, signed message through the
shared HiPinSeco HTTPS service and displays both the raw server response and its
decrypted acknowledgment.

## Requirements

- Xcode 27 or newer on Apple silicon;
- iOS 17 or newer;
- access to the trainer-provided `zsk.labs.def.dev` service.

Open `lab.ios.SecureCommunication.xcodeproj` and run the
`lab.ios.SecureCommunication` scheme. The checked-in configuration uses:

`https://zsk.labs.def.dev/secure-communication/request`

For an instructor-managed local service, copy `Config/Local.example.xcconfig`
to the ignored `Config/Local.xcconfig` and select it as the app target's base
configuration.

The bundled keys are shared classroom material rather than per-device
credentials. Protocol, server, and key-operations documentation is kept in the
private `labs.server.HiPinSeco` repository.
