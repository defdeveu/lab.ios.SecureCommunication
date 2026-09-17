# Secure Communication lab

An iOS teaching application that sends a signed, application-encrypted message
through the shared HiPinSeCo HTTPS service and displays both the encrypted wire
response and its authenticated plaintext interpretation.

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

The fixed bundled credentials are classroom material. They demonstrate
protocol mechanics and do not represent production per-user or per-device
identity. Detailed protocol, server, and key-operations documentation is kept
in the private `lab.ios.HiPinSeCo.server` repository.
