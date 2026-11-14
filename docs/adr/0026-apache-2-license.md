# ADR-0026: Apache License 2.0

- **Status:** Accepted
- **Date:** 2026-11-14
- **Decided by:** Henrich Neuschl

## Context

Minutes will be a public repository on GitHub (ADR-0022). Without a license, other people may not use, change or share the code. Softverse owns the project and its name.

## Options

1. **MIT** – short and simple. Compatible with GPLv2. It says nothing about patents, trademarks or contributions.
2. **Apache License 2.0** – longer. It gives a patent license and ends it for a person who starts a patent claim. It does not give rights to the name. Contributions are under the same license. Not compatible with GPLv2.

## Decision

We select option 2, Apache License 2.0.

- The license text is in `LICENSE`. The copyright holder is Softverse, spol. s r. o., in `NOTICE`.
- The name "Minutes", the name "Softverse" and the app icon are not licensed (section 6 of the license).
- Compatibility with GPLv2 is not important for a macOS app.

## Consequences

- Any person can use, change and distribute the code, also commercially.
- A person who distributes a changed version must keep `LICENSE` and `NOTICE` and mark the changed files.
- Contributions are under Apache License 2.0. We do not need a separate contributor agreement.
- The release `.dmg` contains WhisperKit (MIT). We must verify that the app shows the third-party licenses.
