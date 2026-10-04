# Mitarbeit

Für den Einstieg [README](README.md), [Architektur](docs/architecture.md) und
[Roadmap](docs/roadmap.md) lesen. macOS 15+ und Swift 6 werden benötigt.

## Lokal prüfen

```bash
swift test --package-path apps/macos
./scripts/build-macos.sh
git diff --check
```

Neue Provider implementieren einen Vertrag aus `FridayCore` und werden in
`AssistantViewModel` verdrahtet. Die Demo-Provider für Entwicklung ohne API-Keys
behalten. Für Routingänderungen die Tests um den konkreten Fehlerpfad erweitern.

Der aktuelle `PreviewToolExecutor` simuliert alle Aktionen. Bei echten Tools
Validierung und Ausführung getrennt halten; keine freien Modellantworten als
Shell-Strings ausführen. Audio und Zugangsdaten nicht in Git einchecken.

Der vorhandene Python-Starter ist ein separates Veranstalter-Beispiel.
Anpassungen daran separat dokumentieren. Build-Ausgaben, Modelle und lokale
Einstellungen bleiben unversioniert.
