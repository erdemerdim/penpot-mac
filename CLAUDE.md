# CLAUDE.md — Penpot for Mac geliştirici notları

Bu depo, Penpot tasarım aracını **Docker'sız**, yerel bir Mac uygulaması olarak çalıştırır.
Kullanıcı Türkçe konuşur; yanıtlar, betik mesajları ve belgeler Türkçe yazılır.
Son kullanıcı belgesi `README.md`, kaynaktan kurulum/eşitleme `GELISTIRICI.md`, lisanslar `NOTICE.md`.
Bu dosya, bu depoda daha önce konuşmaları görmeden çalışacak bir geliştirici (ya da Claude) içindir.

## Kurallar (önce bunları okuyun)

- **Kullanıcının tasarımları kutsaldır.** `Sistem/data/` (özellikle `data/pg` veritabanı ve
  `data/assets` görseller), `Sistem/penpot.env` (gizli anahtar), `Sistem/backups/` ve
  `~/Library/Application Support/Penpot/` asla silinmez, taşınmaz, üzerine yazılmaz, depoya girmez.
  `.gitignore` bunları dışarıda tutar; `git add -A` öncesi `git status` ile kontrol edin.
- **Yayınlamadan / göndermeden önce kullanıcıya sorun:** `git push`, `gh release create`,
  depo görünürlüğü, Release silme/düzenleme.
- **Testleri kullanıcının kurulumunda yapmayın.** Geliştirme kurulumu `~/Documents/Penpot`'tur ve
  kullanıcı onu her gün kullanır. Test için ayrı klasöre `git clone` + `kurulum.sh` ya da DMG'yi
  ayrı bir klasöre kopyalayın. **Bütün kurulumlar aynı portları kullanır**: testten önce
  kullanıcının Penpot'unun kapalı olduğunu (`lsof -iTCP:9001 -sTCP:LISTEN`) kontrol edin; açıksa
  kullanıcıya sorun, kendiniz kapatmayın.
- Testte oluşturduğunuz `~/Library/Application Support/Penpot` klasörünü yalnızca **önceden
  yokken** siz oluşturduysanız silin (kullanıcı DMG sürümünü kullanıyorsa orada gerçek verisi vardır).
- Uygulama ad-hoc imzalıdır (Apple Developer hesabı yok). **Her yeniden derlemede** macOS,
  geliştirme kurulumunda Belgeler klasörü iznini yeniden sorar; DMG sürümü ilk açılışta
  "Yine de Aç" ister. Kullanıcıyı önceden uyarın.

## Mimari

### İki kurulum şekli, aynı betikler

1. **Geliştirme kurulumu** (`~/Documents/Penpot`, bu deponun çalışma kopyası):
   `Penpot.app` + `Penpot Güncelle.app` yan yana, bileşenler ve veriler `Sistem/` içinde.
   `kurulum.sh` bileşenleri indirir/derler. Uygulama kendi yanındaki `Sistem/` klasörünü kullanır.
2. **Tek parça uygulama (DMG, GitHub Releases)**: bileşenler `Penpot.app/Contents/Resources/runtime/`
   içinde (salt okunur). Her açılışta `runtime/hazirla.sh`,
   `~/Library/Application Support/Penpot/Sistem/` altında `data/`, `logs/`, `penpot.env` (gizli
   değerler ilk açılışta üretilir) oluşturur ve bileşenlere **sembolik bağlantı** kurar. Böylece
   `start.sh`/`stop.sh` iki şekilde de değişmeden çalışır. `PenpotApp.swift`, paketin içinde
   `runtime/start.sh` varsa bu kipe geçer (`isStandalone`).

### `Sistem/` yapısı

| Yol | Ne | Depoda mı |
|---|---|---|
| `start.sh`, `stop.sh` | Servisleri başlatır/durdurur | evet |
| `update.sh`, `rollback.sh` | Penpot sürüm güncellemesi (Docker Hub'dan, Docker'sız) / geri alma | evet |
| `proxy.mjs` | nginx yerine: statik arayüz + API/WebSocket/exporter/MCP proxy | evet |
| `penpot.env.example` → `penpot.env` | Ayarlar; `penpot.env` gizli, kurulumda üretilir | şablon |
| `surumler.env` | Bileşen sürümleri + SHA-256, `APP_VERSION`, `UPDATE_REPO` | evet |
| `patches/` | Penpot'a dokunmadan açılışta yüklenen düzeltmeler | evet |
| `bin/convert` (node), `bin/magick`, `bin/pdfunite` (Swift'ten derlenir) | ImageMagick/poppler yerine | kaynak |
| `tools/` | `aot-compile.sh`, `pull_image.sh`, `mcp-sharp-macos.sh`, `depo-guncelle.sh`, `mcp-call.mjs`, `*.swift` | evet |
| `tools/app/` | `PenpotApp.swift`, `Guncelleme.swift`, `build.sh`, `build-all.sh`, `dmg-olustur.sh`, `hazirla.sh`, `PenpotGuncelle.applescript`, `Penpot.icns` | evet |
| `jdk/ node/ pgsql/ valkey/ backend/ frontend/ exporter/ browsers/ mcp/` | Bileşenler | hayır |
| `data/ logs/ backups/ chrome-profile/` | Kişisel/üretilen veri | **asla** |

### Bileşenler ve kaynakları (`kurulum.sh`)

- Java: Azul Zulu 25 (arm64 tar.gz, SHA-256 doğrulamalı).
- Node.js 24 (nodejs.org, `Sistem/node`; geliştirme Mac'inde sistem node'u da PATH'te).
- PostgreSQL 15: kaynaktan, `--without-icu --without-readline --with-uuid=e2fs`, contrib dahil
  (`uuid-ossp`). Derleme sonrası kütüphaneler `@rpath`'e çevrilir ve yeniden ad-hoc imzalanır
  (`pg_relocatable`) — klasör taşınabilir, Homebrew'a bağlı değil.
- Valkey 8: kaynaktan, `MALLOC=libc BUILD_TLS=no`.
- Penpot backend/frontend/exporter/mcp: resmî `penpotapp/*` Docker imajlarının linux/arm64
  katmanları `tools/pull_image.sh` ile Docker'sız indirilip açılır.
- Chromium headless shell: exporter'ın Playwright'ı ile (`browsers/`).
- MCP'nin `sharp` kütüphanesi imajda yalnızca Linux için gelir → `tools/mcp-sharp-macos.sh`
  npm'den darwin-arm64 paketlerini (bütünlük doğrulamalı) indirip bağlar.

### Portlar (hepsi yalnızca 127.0.0.1)

| Port | Servis |
|---|---|
| 9001 | `proxy.mjs` — arayüz, `PENPOT_PUBLIC_URI=http://localhost:9001` |
| 6060 | backend (Java) |
| 6061 | exporter (node + Chromium) |
| 5432 | PostgreSQL (`-k /tmp`) |
| 6379 | Valkey |
| 4401 / 4402 | Penpot MCP (HTTP `/mcp/stream`, WebSocket `/mcp/ws` proxy üzerinden) |

## Komutlar

```bash
# Geliştirme kurulumu (yeni Mac ya da test klasörü)
git clone https://github.com/erdemerdim/penpot-mac.git <klasör> && <klasör>/kurulum.sh
<klasör>/kurulum.sh --guncelle            # yalnızca surumler.env'de değişen bileşenler + uygulamalar

# Servisler (Penpot.app bunları kendisi çağırır)
Sistem/start.sh ; Sistem/stop.sh          # kayıtlar: Sistem/logs/*.log, kapanış adımları logs/stop.log

# Uygulamaları derle (Penpot.app + Penpot Güncelle.app)
Sistem/tools/app/build-all.sh "$PWD"

# Hızlı açılış derlemesi (Penpot güncellenince start.sh bunu kendisi arka planda çalıştırır)
Sistem/tools/aot-compile.sh

# Penpot sürüm güncellemesi (geliştirme kurulumu); geri alma
Sistem/update.sh --check | --yes | <sürüm> ; Sistem/rollback.sh

# İki Mac arasında eşitleme
./gonder.sh "mesaj"                       # git add/commit/pull --rebase/push
Sistem/tools/depo-guncelle.sh             # git pull + gerekirse kurulum.sh --guncelle / build-all
```

### Yeni DMG ve Release yayınlama

1. `Sistem/surumler.env` içinde `APP_VERSION`'ı artırın (ör. `1.0.0` → `1.0.1`; Penpot sürümü
   değiştiyse en az ikinci hane). Release etiketi **her zaman** `v<APP_VERSION>` olmalı; uygulamanın
   güncelleme bildirimi `tag_name` ile `CFBundleShortVersionString`'i sayısal karşılaştırır.
2. `Sistem/tools/app/dmg-olustur.sh` → `dist/Penpot-<APP_VERSION>.dmg`. Betik kişisel veri ve
   `$HOME` yolu sızıntısını kontrol eder, uygulamayı ad-hoc imzalar.
3. Test (kullanıcının Penpot'u kapalıyken, kullanıcıya sorarak): DMG'yi bağlayın, uygulamayı ayrı
   bir klasöre `ditto` ile kopyalayın, indirme taklidi için `Contents/Resources` altına
   `com.apple.quarantine` ekleyin, `open` ile açın; hesap → dosya → PNG dışa aktarma → kapanışta
   portların kapandığını → yeniden açılışta verinin durduğunu kontrol edin. DMG içinden açınca
   "Uygulamalar klasörüne taşıyın" uyarısı çıkmalı.
4. Kullanıcı onayıyla:
   `~/.local/bin/gh release create v<APP_VERSION> dist/Penpot-<APP_VERSION>.dmg --title "Penpot <APP_VERSION> (Penpot <PENPOT_VERSION>)" --notes-file notlar.md --latest`
   Notların ilk ~500 karakteri uygulamadaki güncelleme penceresinde görünür; kısa ve kullanıcıya
   yönelik yazın. Dosya başına 2 GB sınırı var (DMG ~590 MB).
5. `gh` bu Mac'te `~/.local/bin/gh` (PATH'te değil). Güncelleme denetimi kimlik doğrulamasız
   GitHub API kullanır: **depo açık olmalı**, gizli depoda bildirim çalışmaz.

## Çözülmüş sorunlar — geri almayın

| Ne | Neden |
|---|---|
| `JAVA_OPTS`'ta `-Duser.language=en -Duser.country=US` | Türkçe sistem dilinde Java, büyük/küçük harf dönüşümü (`i`/`İ`) yüzünden ortam değişkeni adlarını yanlış okuyordu; Penpot ayarları hiç uygulanmıyordu. |
| `patches/macos-tmp.clj` | macOS'ta `/tmp` = `/private/tmp`. Penpot yüklenen dosyanın gerçek yolunun `/tmp/...` ile başlamasını şart koşuyor; görsel yüklemeleri reddediliyordu. Açılışta `-i` ile yüklenip `/private/tmp/...` önekleri izinli listeye eklenir. |
| `bin/magick`, `bin/convert`, `bin/pdfunite` | ImageMagick/poppler kurulu değil. `magick` ve `pdfunite` macOS'un kendi ImageIO/PDFKit'ini kullanan Swift programları; `convert` MCP'deki sharp ile WEBP/PPM üretir. |
| `proxy.mjs` Google Fonts isteklerinde Linux Chrome 113 user-agent | Tanınmayan tarayıcı kimliğinde Google yalnızca temel Latin alt kümesini veriyor; Türkçe `ğ ş İ` harfleri bozuk çıkıyordu. nginx yapılandırmasındaki kimliğin aynısı. |
| `patches/localhost-only.mjs` | Exporter host ayarını yok sayıp tüm arayüzlerde dinliyordu; `listen()` 127.0.0.1'e zorlanır. |
| Hızlı açılış 1: `tools/aot-compile.sh` → `data/penpot-classes.jar` + `penpot-classes.stamp` | Penpot jar'ı yalnızca Clojure kaynak kodu içeriyor; her açılışta derleniyordu. Önceden derlenmiş sınıflar jar olarak tutulur; `stamp` = `penpot.jar`'ın `boyut-mtime`'ı, eşleşmezse `start.sh` eski yolla açar ve arka planda yeniden derler. |
| `patches/preload-readers.clj` | Derlenmiş kodda `#penpot/cron` gibi okuyucu etiketleri `app.main` yüklenirken hemen çalışır; ait oldukları ad alanları önceden yüklenmezse "Attempting to call unbound fn" hatası. |
| Hızlı açılış 2: Java AOT cache (`data/penpot-fast.aot` / `penpot-src.aot`) | JDK 25 AOT önbelleği sınıf yolunda **klasör kabul etmez**, yalnızca jar — bu yüzden derlenmiş sınıflar jar'a paketlenir. Önbellek ilk kapanışta yazılır; `stop.sh` backend'e 30 sn tanır. `start.sh`'de `AOT_OPT` bir **dizi** olmalı (Application Support yolundaki boşluk yüzünden). |
| Proxy API isteklerini bekletir | Arayüz Java hazır olmadan yüklenir (hızlı görünüm); proxy `/api` isteklerini `readyz` 200 dönene kadar tutar. |
| Uygulama: anında kapanış | Pencere hemen kapanır, `stop.sh` arka planda çalışır; `data/stopping.lock` varken yeni açılış bekler. |
| `window.isReleasedWhenClosed = false` | Varsayılan `true` iken kapanış kodu serbest bırakılmış pencereye erişip çöküyordu. |
| `PenpotWindow.noResponder` | Penpot boşluk vb. tuşları işleyip tarayıcıya bildirmiyor; macOS "bip" çalıyordu. |
| Arayüzü Penpot başlığı değişince göster | Önceden beyaz sayfa yanıp sönüyordu; `index.html` başlığı ("Penpot \| Full-stack design") değişince web görünümü açılır. |
| WebKit SPI ayarları + App Nap kapalı | Pencere arka plandayken zamanlayıcılar yavaşlıyor, MCP bağlantısı kopuyordu. `setPrivateBool` yoksa sessizce geçer. |
| `stop.sh`/`start.sh` süreç desenleri klasör yolunu içerir (`$LRE`) | Başka klasördeki bir Penpot kurulumunu (ör. test kurulumu) durdurmasın diye. **Dikkat:** `pkill -f` komut satırında aynı metni içeren kabukları da öldürür — test komutlarını bir dosyaya yazıp oradan çalıştırın, desen metnini tek satırlık komutlara koymayın. |
| MCP 1 sn sonra zorla kapatılır | MCP sunucusu açık bağlantı varken SIGTERM'i yok sayıyor; durumsuz olduğu için güvenli. |
| `start.sh` `config.js`'i yalnızca gerekirse yazar | DMG'de `frontend/` paketin içinde; yazmak imzayı bozar. DMG betiği `config.js`'i hazır yazar. |
| `proxy.mjs` `PP_HOME`'u kullanır | Node ana betiğin sembolik bağlantısını çözer; DMG kipinde `data/assets` paket yerine veri klasöründen okunmalı. |
| DMG uygulaması karantina işaretini kaldırır | İnternetten inen dosyalarda `com.apple.quarantine` varken paket içindeki Java/PostgreSQL gibi ikililer macOS tarafından öldürülür (exit 137). Kullanıcı "Yine de Aç" dedikten sonra uygulama `xattr -dr` ile kendi paketini temizler. DMG içinden ya da App Translocation konumundan açılırsa taşıma uyarısı gösterir. |

## Uygulama (Swift)

- `build.sh` iki dosyayı derler (`PenpotApp.swift` geçici olarak `main.swift` adıyla + `Guncelleme.swift`).
  Ortam değişkenleri: `PENPOT_BUNDLE_ID` (geliştirme: `local.penpot.desktop`, DMG:
  `io.github.erdemerdim.penpot-mac`), `PENPOT_APP_VERSION`, `PENPOT_VERSION_INFO` (Info.plist
  `PenpotVersion`), `PENPOT_UPDATE_REPO` (Info.plist `PenpotUpdateRepo`; yoksa güncelleme denetimi kapalı).
- Menü: "Penpot Hakkında" (sürüm + Penpot sürümü), devre dışı "Sürüm X (Penpot Y)" satırı,
  "Güncellemeleri Denetle…" (yalnızca DMG).
- Güncelleme bildirimi (`Guncelleme.swift`): açılıştan 8 sn sonra; ağdan günde en fazla bir kez;
  bulunan son sürüm `UserDefaults`'ta saklanır, "Daha Sonra" her açılışta yeniden hatırlatır,
  "Bu Sürümü Atla" o etiketi saklar, "İndir" Release sayfasını tarayıcıda açar. İnternet/API hatası
  sessiz geçer; elle denetleme her zaman ağa sorar. Test: `PENPOT_APP_VERSION=0.9.0` ve ayrı bir
  `PENPOT_BUNDLE_ID` ile derleyip açın; sonra `defaults delete <bundle id>`.
- Geliştirme kurulumunda `Penpot Güncelle.app` (AppleScript, `tools/app/PenpotGuncelle.applescript`)
  önce `depo-guncelle.sh` ile depoyu çeker, sonra `update.sh --check` ile Penpot sürümüne bakar.

## Bilinen eksikler / sonraki adımlar

- Penpot "Sizi tanımamıza yardımcı olun" tanıtım soruları `disable-onboarding-questions` bayrağına
  rağmen 2.18'de çıkıyor (Penpot kaynaklı).
- E-posta gönderimi ve özel yazı tipi yükleme yok.
- Ortak sunucu (birden fazla kişinin aynı tasarımları açması) kapsam dışı; ileride ayrı iş.
- Intel Mac ve Windows desteklenmiyor.
- Apple Developer imzası/notarization yok; olursa "Yine de Aç" adımı ve karantina temizliği gereksizleşir.
