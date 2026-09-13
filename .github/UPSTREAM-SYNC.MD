# Tägliche Upstream-Synchronisierung

Der Workflow `Sync upstream` übernimmt täglich um 02:17 UTC alle neuen Commits
aus `sm0svx/svxlink`, Branch `master`, in `criede/svxlink-db9cr`, Branch `master`.
Das entspricht 03:17 Uhr im Winter und 04:17 Uhr im Sommer in Deutschland.
Andere Branches, Tags und GitHub-Releases werden nicht synchronisiert.

Auch `.github/workflows/` ist vollständig von der Übernahme ausgeschlossen:
Vor dem Merge-Commit wird dieser Ordner auf den eigenen Stand vor dem Merge
zurückgesetzt. Dadurch werden weder neue Upstream-Workflows hinzugefügt noch
eigene Workflows geändert oder gelöscht. Dies gilt auch bei einem ansonsten
möglichen Fast-Forward. Der eigene Sync und die CodeQL-Deaktivierung bleiben erhalten.

Eigene Commits bleiben durch einen Git-Merge erhalten. Bei inhaltlichen Konflikten
hat die Version unseres `master` Vorrang (`git merge -X ours`). Konfliktfreie
Upstream-Änderungen werden auch innerhalb derselben Datei übernommen. Verbleibende
Dateikonflikte, etwa Ändern/Löschen, werden mit dem Dateistand unseres `master`
aufgelöst; eigene Löschungen bleiben dabei erhalten. Anschließend wird der Merge
abgeschlossen und gepusht. Konfliktbehaftete Upstream-Anteile werden dadurch
bewusst verworfen und bei späteren Läufen nicht erneut angeboten.

Mit eigenen Änderungen sind die auf GitHub in `master` eingecheckten Änderungen
gemeint. Nicht gepushte Änderungen auf einem lokalen Rechner kennt der Workflow
nicht. Technische Fehler brechen den Lauf weiterhin ab. Bei zwischenzeitlichen
Änderungen am Zielbranch wird kein Force-Push ausgeführt; der Workflow kann
anschließend erneut starten.

## Daily-Paket für Raspberry Pi OS

Nach jedem erfolgreichen Sync läuft ein nativer arm64-Build in einem
`debian:trixie-slim`-Container. Ziel ist Raspberry Pi OS 64 Bit auf Debian 13
Trixie. Gebaut wird exakt der vom Sync ausgegebene Commit, auch wenn keine neuen
Upstream-Commits vorhanden waren. Der Server-Build enthält kein Qtel und keine
Sprachdateien; diese müssen passend zur Station installiert werden.

Die Debian-Version folgt dem Schema
`26.05.1+daily20260912.42.1.g0123456789ab-1~trixie`: Projektversion aus
`src/versions`, UTC-Datum, Workflow-Laufnummer, Versuch und Commit-Kürzel.
Sie steigt innerhalb einer Projektversion mit jedem neuen Daily-Lauf an;
die nächste höhere Projektversion sortiert danach. `Release` als CMake-Bautyp
bedeutet nur optimierten Maschinencode, keine stabile Veröffentlichung.

Nach Paketprüfung und Installationstest in einem frischen Trixie-Container
werden `.deb` und `SHA256SUMS` direkt mit der GitHub CLI in ein eigenes Daily-
Prerelease hochgeladen. Der Tag verweist auf den gebauten Commit. Das Prerelease
wird nicht als „Latest“ markiert. Es gibt keine Actions-Artefakte und keinen
Build-Cache; temporäre Dateien werden nach dem Upload entfernt. Fehlgeschlagene
Builds veröffentlichen kein neues Prerelease. Die Hardware wird in CI nicht getestet.

Das Skript `.github/scripts/build-daily-deb.sh` ermittelt Architektur
(`dpkg --print-architecture`) und Distributions-Codename (`VERSION_CODENAME`
aus `/etc/os-release`) aus dem jeweiligen Build-Container selbst. Ein
zusätzlicher Job für eine weitere Raspberry-Pi-OS-/Debian-/Ubuntu-Version oder
-Architektur ruft daher dasselbe Skript einfach mit einem anderen
`--platform`/Basis-Image auf (z. B. `debian:bookworm-slim` für Debian 12,
`ubuntu:24.04` für Ubuntu Noble, oder mit `--platform linux/arm/v7` bzw.
`linux/amd64` für andere Architekturen); Versionsschema, Conflicts und die
anschließende Veröffentlichung passen sich automatisch an.

## APT-Repository auf GitHub Pages

Im Anschluss an das Daily-Prerelease veröffentlicht derselbe Job das Paket
zusätzlich in einem eigenen APT-Repository im Branch `gh-pages`, sodass es
sich mit `apt install` beziehen und automatisch aktualisieren lässt (siehe
„Einbindung in Raspberry Pi OS“ unten).

Aufbau des Repositorys, nach Suite (Debian-/Ubuntu-Codename) und Architektur
getrennt — das entspricht dem üblichen Debian-Repository-Layout (wie es z. B.
auch `reprepro` erzeugt) und lässt sich dadurch verlustfrei um weitere
Raspberry-Pi-OS-/Debian-/Ubuntu-Versionen und Architekturen ergänzen, ohne
bestehende Pfade zu berühren:

```
dists/<suite>/InRelease
dists/<suite>/Release
dists/<suite>/Release.gpg
dists/<suite>/main/binary-<arch>/Packages[.gz]
pool/<suite>/main/<buchstabe>/<paketname>/<paket>.deb
pubkey.gpg                                   # öffentlicher Signaturschlüssel
```

`<suite>` ist der Distributions-Codename (aktuell `trixie`), `<arch>` die
Debian-Architektur (aktuell `arm64`). Ein späterer Build für z. B. Debian 12
Bookworm oder eine 32-Bit-Architektur legt einfach einen weiteren
`dists/bookworm/…` bzw. `binary-armhf`-Zweig an; bestehende Suiten/
Architekturen bleiben unverändert. Separate Pfade sind notwendig, weil ein
`.deb` jeweils nur zu genau einer Distributionsversion und Architektur passt
und APT-Clients Pakete nur aus dem für sie passenden `dists/<suite>/…/binary-
<arch>`-Zweig laden.

Das Skript `.github/scripts/publish-apt-repo.sh` übernimmt Ablage im Pool,
Neuaufbau von `Packages`/`Packages.gz` mit `dpkg-scanpackages`, Neuaufbau und
Signieren von `Release`/`InRelease` mit `apt-ftparchive` bzw. `gpg` sowie das
Vorhalten des öffentlichen Schlüssels als `pubkey.gpg`. Damit der `gh-pages`-
Branch nicht unbegrenzt wächst, werden je Paket/Suite/Architektur nur die
letzten 14 Tagesversionen aufgehoben (Parameter `RETENTION` im Skript); ältere
`.deb`-Dateien werden vor dem Neuaufbau des Index entfernt. Ein
fehlgeschlagener Build veröffentlicht auch hier nichts.

### Signaturschlüssel

Damit APT dem Repository vertraut, ist `Release` mit einem GPG-Schlüssel
signiert (`Release.gpg` als abgetrennte Signatur sowie `InRelease` als
inline signierte Variante; APT akzeptiert beide Formen). Der private
Schlüssel liegt ausschließlich als Repository-Secret **APT_SIGNING_KEY**
(ASCII-armored, `gpg --export-secret-keys --armor <fingerprint>`) vor und
wird im Workflow-Lauf importiert, verwendet und am Ende wieder aus dem
`GNUPGHOME` des Runners entfernt. Der Schlüssel wurde bewusst ohne
Passphrase erzeugt, damit die Signatur unbeaufsichtigt in CI funktioniert;
Schutz bietet dafür ausschließlich die Zugriffskontrolle auf das GitHub-
Secret. Wer eine Passphrase bevorzugt, muss den Import-Schritt im Workflow
um `--pinentry-mode loopback --passphrase-fd 0` und ein zusätzliches Secret
für die Passphrase erweitern.

Einen neuen Schlüssel erzeugt man lokal z. B. mit:

```sh
gpg --batch --gen-key <<'EOF'
%no-protection
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: SvxLink DB9CR APT Repository
Name-Comment: Daily package signing key
Expire-Date: 3y
%commit
EOF
gpg --list-secret-keys --keyid-format=long "SvxLink DB9CR APT Repository"
```

Anschließend den privaten Schlüssel als Secret hinterlegen (Fingerprint aus
der vorherigen Ausgabe einsetzen) und die lokale Exportdatei danach löschen:

```sh
gpg --export-secret-keys --armor <FINGERPRINT> > apt-signing-key-private.asc
gh secret set APT_SIGNING_KEY --repo criede/svxlink-db9cr < apt-signing-key-private.asc
rm apt-signing-key-private.asc
```

Der öffentliche Schlüssel muss nicht separat hinterlegt werden: Der Workflow
exportiert ihn bei jedem Lauf frisch aus dem importierten privaten Schlüssel
nach `pubkey.gpg` im Repository-Wurzelverzeichnis. Ein Schlüsselwechsel (z. B.
nach Ablauf oder Kompromittierung) erzeugt automatisch eine neue
`pubkey.gpg`; Nutzer müssen den Schlüssel dann erneut importieren (siehe
unten).

## Einbindung in Raspberry Pi OS

Sobald GitHub Pages für den Branch `gh-pages` aktiviert ist (siehe
„Einrichtung“), lässt sich das Repository auf einem Raspberry Pi OS Trixie
(64 Bit) mit folgenden Befehlen einbinden:

```sh
# Öffentlichen Signaturschlüssel importieren
curl -fsSL https://criede.github.io/svxlink-db9cr/pubkey.gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/svxlink-db9cr.gpg

# Repository-Quelle anlegen, auf den Schlüssel beschränkt und auf die
# passende Codename/Architektur-Kombination eingeschränkt
echo 'deb [signed-by=/usr/share/keyrings/svxlink-db9cr.gpg arch=arm64] https://criede.github.io/svxlink-db9cr trixie main' | \
  sudo tee /etc/apt/sources.list.d/svxlink-db9cr.list

sudo apt update
sudo apt install svxlink
```

Danach liefert ein gewöhnliches `sudo apt upgrade` automatisch die jeweils
neueste Tagesversion. Für eine andere Distributionsversion oder Architektur
(sobald vorhanden) einfach `trixie` bzw. `arch=arm64` in der Zeile oben
anpassen. Es handelt sich um tägliche Entwicklungs-Builds, keine stabilen
Veröffentlichungen — siehe Hinweise oben zu Umfang und Testabdeckung.

## Admin-Anpassungen an den TCL-Event-Skripten

Die TCL-Dateien unter `/usr/share/svxlink` (`events.tcl`,
`events.d/*.tcl`, `modules.d/*.tcl`) werden wie die `.conf`-Dateien unter
`/etc` als dpkg-`conffiles` installiert (`install_files_if_not_exists` in den
jeweiligen `CMakeLists.txt`, analog zur bestehenden `install_if_not_exists`-
Funktion für Konfigurationsdateien). Editiert ein Administrator eine dieser
Dateien direkt, überschreibt ein späteres Paket-Upgrade die Änderung nicht
mehr kommentarlos: dpkg erkennt die lokale Abweichung vom zuletzt
ausgelieferten Stand und fragt beim Upgrade nach (oder behält bei
unbeaufsichtigten Upgrades den lokalen Stand), statt die Datei stillschweigend
zu ersetzen. Unveränderte Dateien werden weiterhin normal aktualisiert. Davon
unberührt bleibt der ohnehin empfohlene Weg über `events.d/local/*.tcl` für
eigene Ergänzungen, da neue, vom Paket nicht mitgelieferte Dateien von dpkg
nie angefasst werden.

## Einrichtung

1. Den Workflow auf den Standardbranch des GitHub-Repositories pushen.
2. GitHub Actions im Repository aktivieren, falls noch nicht geschehen.
3. Repository-Secret **APT_SIGNING_KEY** anlegen (siehe „Signaturschlüssel“
   oben) — ohne dieses Secret schlägt der `daily-deb`-Job beim Signieren
   des APT-Repositorys fehl.
4. Unter **Settings → Pages** als Quelle **Deploy from a branch** und den
   Branch `gh-pages` (Verzeichnis `/`) einstellen. Der Branch wird beim
   ersten erfolgreichen `daily-deb`-Lauf automatisch angelegt; die
   Einstellung kann daher auch erst nach diesem Lauf vorgenommen werden.
5. Unter **Actions → Sync upstream → Run workflow** einen ersten Lauf starten.

Standardmäßig nutzt der Workflow den automatisch bereitgestellten `GITHUB_TOKEN`
mit `contents: write`. Branch-Regeln müssen diesen direkten Push erlauben,
auch für den Branch `gh-pages`. Pushes mit diesem Token lösen keine weiteren
Push-Workflows aus.

Damit auch Änderungen an `.github/workflows/` übernommen werden können, bei
Bedarf ein Repository-Secret **UPSTREAM_SYNC_TOKEN** hinterlegen: ein auf dieses
Repository beschränktes Fine-grained Personal Access Token mit **Contents: Read
and write** und **Workflows: Read and write**. Der Workflow verwendet dieses
Secret bevorzugt. Ohne ausreichende Berechtigung kann GitHub den Push mit
Workflow-Änderungen ablehnen. Ein PAT kann auch nachfolgende Push-Workflows auslösen.
Tokenwerte ausschließlich in GitHub Secrets speichern.

GitHub kann geplante Läufe verzögern und deaktiviert geplante Workflows in
öffentlichen Repositories nach 60 Tagen ohne Repository-Aktivität. Bei Forks
können geplante Workflows zunächst deaktiviert sein. Bei Bedarf unter **Actions**
wieder aktivieren. Der Zeitplan setzt voraus, dass die Datei auf dem Standardbranch
liegt.

## Quellen

- [GitHub: Workflow-Ereignisse und Zeitpläne](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [GitHub: GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)
- [GitHub: Berechtigungen für Workflow-Änderungen](https://github.github.com/gh-aw/reference/safe-outputs-pull-requests/)
- [GitHub Pages: Deploy from a branch](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
- [Debian Wiki: SecureApt](https://wiki.debian.org/SecureApt)
- [Debian Repository Format](https://wiki.debian.org/DebianRepository/Format)
- [Debian Policy Manual: conffiles](https://www.debian.org/doc/debian-policy/ch-files.html#configuration-files)
