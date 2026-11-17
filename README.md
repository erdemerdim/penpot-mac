# Penpot — Mac'te Docker'sız

[Penpot](https://penpot.app) tasarım aracını Docker kullanmadan, kendi penceresinde açılan bir Mac
uygulaması olarak çalıştırır. Bu depo kişisel kullanım içindir: aynı kurulumu birden fazla Mac'te
kurmak ve Mac'ler arasında güncel tutmak için.

Penpot'un resmî bir ürünü değildir; Penpot ekibiyle bağlantısı yoktur.

- **Gerekenler:** Apple Silicon (M1/M2/M3/M4…) Mac, macOS 13 veya üstü, ~3 GB boş alan, internet.
- **Depoda olanlar:** Yalnızca bizim yazdığımız betikler, yamalar ve uygulama kaynak kodu.
  Java, PostgreSQL, Penpot vb. bileşenler kurulumda indirilir ya da derlenir (depoya girmez).
- **Tasarımlarınız** GitHub üzerinden **taşınmaz**. Mac'ler arasında taşımak için aşağıdaki
  "Tasarımları başka Mac'e taşıma" bölümüne bakın.

## Basitçe: Bu ne, nasıl çalışıyor?

**Bu bir sunucu (server) değil.** Penpot her Mac'te ayrı ayrı, o Mac'in içinde çalışır.
İnternet ya da GitHub kapalı olsa bile Penpot açılır.

GitHub'daki bu depo bir **tarif defteri** gibidir. İçinde Penpot'un kendisi ya da tasarımlarınız
yoktur; Penpot'un bir Mac'e nasıl kurulacağını anlatan betikler vardır. Yeni bir Mac'te bu tarifi
indirip `kurulum.sh` ile çalıştırırsınız; Penpot o Mac'e kurulur.

| | Nerede durur | Mac'ler arasında paylaşılır mı? |
|---|---|---|
| Kurulum betikleri ve uygulama kodu | GitHub (bu depo) | Evet, `gonder.sh` / `Penpot Güncelle` ile |
| Penpot programı (Java, veritabanı…) | Her Mac'te `Sistem/` klasörü | Hayır, her Mac kendisi indirir |
| Tasarımlarınız ve hesabınız | Her Mac'te `Sistem/data/` | Hayır, `.penpot` dosyasıyla elle taşınır |

**Gerçek bir sunucu** olsaydı Penpot tek bir bilgisayarda (ya da internette) çalışır, bütün
Mac'ler aynı tasarımları tarayıcıdan açardı. Bu, ileride yapılabilecek ayrı bir adımdır.

### İndirmenin iki yolu

- **ZIP ile (fotokopi gibi):** GitHub sayfasında yeşil **Code** düğmesi → **Download ZIP**.
  Bir kez kopyalarsınız, sonra GitHub'la bağı kalmaz. Bu Mac'te yapılan değişiklikler o Mac'e
  gelmez. ZIP'i açıp klasörün adını `Penpot` yapın, Belgeler'e taşıyın ve
  `bash ~/Documents/Penpot/kurulum.sh` çalıştırın.
- **git clone ile (iCloud gibi, önerilen):** İki Mac de GitHub'daki aynı kopyaya bağlı kalır.
  Birinde `gonder.sh` ile gönderilen değişiklik, diğerinde `Penpot Güncelle` ile gelir.

Terimler:
- **git:** Dosyaları GitHub'la eşitleyen program (Xcode Komut Satırı Araçları ile gelir).
- **git clone:** "Bu depoyu bilgisayarıma bağlı olarak indir" komutu.
- **gh:** GitHub'a giriş yapmaya yarayan araç. Depo gizli olduğu için önce "bu benim"
  demek gerekir; bir kez yapılır.

### Kısa yol: yeni Mac'te 4 komut

Terminal'i açın, sırayla yapıştırın:

```bash
xcode-select --install
```
(Açılan pencerede "Yükle"ye basın, bitmesini bekleyin.)

```bash
mkdir -p ~/.local/bin && cd /tmp && curl -fsSLO https://github.com/cli/cli/releases/download/v2.104.0/gh_2.104.0_macOS_arm64.zip && unzip -oq gh_2.104.0_macOS_arm64.zip && cp gh_2.104.0_macOS_arm64/bin/gh ~/.local/bin/ && cd ~
```
(GitHub giriş aracını indirir.)

```bash
~/.local/bin/gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key && ~/.local/bin/gh auth setup-git
```
(Ekranda bir kod çıkar. Tarayıcıda github.com/login/device adresine o kodu girip **Authorize**.)

```bash
git clone https://github.com/erdemerdim/penpot-mac.git ~/Documents/Penpot && ~/Documents/Penpot/kurulum.sh
```
(Penpot'u indirir ve kurar, 15–25 dk.) Bitince **Belgeler → Penpot → Penpot.app**'i açın.

Aşağıda aynı adımların ayrıntılı hâli var.

## Yeni bir Mac'e kurulum (ayrıntılı)

1. **Terminal**'i açın (Uygulamalar → İzlenceler → Terminal).
2. Xcode Komut Satırı Araçları yoksa kurun (varsa "already installed" der):
   ```bash
   xcode-select --install
   ```
3. Depo gizli olduğu için önce GitHub oturumu açın. GitHub CLI'ı (`gh`) kurun:
   ```bash
   mkdir -p ~/.local/bin && cd /tmp && curl -fsSLO https://github.com/cli/cli/releases/download/v2.104.0/gh_2.104.0_macOS_arm64.zip && unzip -oq gh_2.104.0_macOS_arm64.zip && cp gh_2.104.0_macOS_arm64/bin/gh ~/.local/bin/ && cd ~
   ```
   Sonra oturum açın. Çıkan kodu tarayıcıda github.com/login/device adresine girip
   **Authorize** deyin:
   ```bash
   ~/.local/bin/gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key
   ```
   ```bash
   ~/.local/bin/gh auth setup-git
   ```
4. Depoyu `Belgeler/Penpot` klasörüne indirin:
   ```bash
   git clone https://github.com/erdemerdim/penpot-mac.git ~/Documents/Penpot
   ```
   Değişiklikleri o Mac'ten de göndermek için bir kez adınızı tanıtın:
   ```bash
   cd ~/Documents/Penpot && git config user.name "Erdem Erdim" && git config user.email "65260790+erdemerdim@users.noreply.github.com"
   ```
5. Kurulumu başlatın (15–25 dk; PostgreSQL ve Valkey bu Mac'te derlenir):
   ```bash
   ~/Documents/Penpot/kurulum.sh
   ```
6. Finder'da `Belgeler/Penpot/Penpot.app`'i çift tıklayın. İsterseniz Dock'a sürükleyin.
7. Penpot ekranında **Hesap oluştur** ile bir hesap açın. Hesaplar her Mac'e özeldir.

Kurulum betiği gizli değerleri (`PENPOT_SECRET_KEY`, veritabanı şifresi) bu Mac için yeniden
üretir ve `Sistem/penpot.env` dosyasına yazar. Bu dosya depoya gönderilmez.

### macOS'un soracağı izinler

- **"Penpot, Belgeler klasörünüzdeki dosyalara erişmek istiyor"** → **İzin Ver**.
  Uygulama imzasız (yalnızca yerel/ad-hoc imzalı) olduğu için, uygulama **her yeniden
  derlendiğinde** (kurulumda, ya da Penpot Güncelle uygulama kodunda değişiklik aldığında)
  bu soru bir kez daha gelir. Normaldir; yine İzin Ver deyin.
- Uygulama hiç açılmazsa ya da "doğrulanamadı" uyarısı çıkarsa:
  **Sistem Ayarları → Gizlilik ve Güvenlik** → aşağıda Penpot için **Yine de Aç**.

## Kullanım

| Ne | Nasıl |
|---|---|
| Penpot'u açmak | `Penpot.app` (servisleri kendisi başlatır) |
| Kapatmak | Pencereyi kapatın ya da Cmd+Q. Servisler arkada durdurulur. |
| Güncellemek | `Penpot Güncelle.app` (aşağıya bakın) |
| Terminal'den durdurmak | `~/Documents/Penpot/Sistem/stop.sh` |
| Kayıtlar | `Sistem/logs/` (`app.log`, `backend.log`, `stop.log`…) |

Dışa aktarma (PNG, JPG, WEBP, SVG, PDF) çalışır. E-posta gönderimi ve kendi yazı tipi dosyanızı
yükleme bu kurulumda yoktur; Google yazı tipleri çalışır.

## Mac'ler arasında güncel tutma

**Değişiklikleri GitHub'a göndermek** (betik, yama ya da uygulama kodunu değiştirdiğiniz Mac'te):
```bash
~/Documents/Penpot/gonder.sh "ne değişti"
```

**Diğer Mac'te almak:** `Penpot Güncelle.app`'i açın. Sırasıyla:
1. Depodaki değişiklikleri alır (`git pull`). Uygulama kodu değiştiyse `Penpot.app`'i yeniden
   derler; `Sistem/surumler.env` değiştiyse (ör. yeni Java sürümü) yalnızca o bileşeni yeniler.
2. Yeni bir Penpot sürümü var mı bakar; varsa onayınızla kurar. Önce veritabanı yedeklenir.
   Güncellenen sürüm `Sistem/surumler.env` dosyasına yazılır; `gonder.sh` ile gönderince
   diğer Mac de aynı sürüme geçer.

Terminal'den aynı işler: `Sistem/tools/depo-guncelle.sh` ve `Sistem/update.sh`.
Güncellemeden sonra sorun çıkarsa: `Sistem/rollback.sh` (eski sürüme ve yedeğe döner).

> `Penpot Güncelle` "depo güncellenemedi" derse, o Mac'te gönderilmemiş değişiklik vardır:
> önce `gonder.sh` çalıştırın.

## Tasarımları başka Mac'e taşıma

Tasarımlar her Mac'in kendi veritabanında (`Sistem/data`) durur ve depoya gönderilmez.
Taşımak için Penpot'un kendi dışa/içe aktarma özelliğini kullanın:

1. **Eski Mac:** Penpot'ta proje listesinde dosyanın üzerinde sağ tık (ya da `⋯` menüsü) →
   **Dışa aktar** → **Penpot dosyası (.penpot)**. Birden fazla dosyayı seçip birlikte de
   aktarabilirsiniz. Dosya İndirilenler klasörüne kaydedilir.
2. `.penpot` dosyalarını diğer Mac'e taşıyın (AirDrop, iCloud Drive, USB…).
3. **Yeni Mac:** Penpot'ta bir projeye girin → sağ üstteki `⋯` menüsü → **Penpot dosyasını içe
   aktar** → dosyaları seçin.

Paylaşılan kütüphaneler ve bileşenler de bu yolla taşınır (kütüphaneyi kullanan dosyalarla
birlikte dışa aktarın).

## Klasör yapısı

```
Penpot/
├── kurulum.sh              yeni Mac'te kurulum (ve --guncelle)
├── gonder.sh               değişiklikleri GitHub'a gönderir
├── Penpot.app              (derlenir) Penpot penceresi
├── Penpot Güncelle.app     (derlenir) depo + Penpot güncelleyici
└── Sistem/
    ├── start.sh, stop.sh   servisleri başlatır/durdurur
    ├── update.sh           Penpot sürüm güncellemesi, rollback.sh geri alma
    ├── proxy.mjs           arayüzü sunan yerel sunucu (nginx yerine)
    ├── penpot.env.example  ayar şablonu (penpot.env kurulumda üretilir, gizli)
    ├── surumler.env        indirilecek bileşen sürümleri
    ├── patches/            macOS düzeltmeleri ve hızlı açılış
    ├── bin/convert         ImageMagick yerine geçen yardımcı (magick, pdfunite derlenir)
    └── tools/              uygulama kaynakları, derleme ve indirme betikleri
```

Bileşenler (kurulumda indirilir): Java (Azul Zulu 25), Node.js, PostgreSQL 15 (kaynaktan,
`uuid-ossp` ile), Valkey 8 (kaynaktan), Penpot backend/frontend/exporter/MCP (Penpot'un resmî
Docker imajlarından Docker olmadan çıkarılır), dışa aktarma için Chromium (Playwright).

## Lisans

Bu depodaki dosyalar [MPL-2.0](LICENSE) lisanslıdır (Penpot ile aynı). Kurulumda indirilen
bileşenlerin lisansları için [NOTICE.md](NOTICE.md)'ye bakın.
