# Penpot for Mac

Ücretsiz ve açık kaynak tasarım aracı **[Penpot](https://penpot.app)**'u Mac'inizde, internete
bağlı olmadan kendi penceresinde çalıştıran uygulama. Hesap açmanız ya da bir şey kurmanız
gerekmez: indirin, Uygulamalar klasörüne sürükleyin, açın.

> Bu, Penpot'un resmî uygulaması değildir; Penpot ekibiyle bir bağlantısı yoktur.
> Penpot'un kendisini olduğu gibi içerir.

**Gerekenler:** Apple Silicon işlemcili Mac (M1, M2, M3, M4…), macOS 13 Ventura veya daha yenisi,
yaklaşık 2 GB boş alan.
Mac'inizin işlemcisini görmek için:  → **Bu Mac Hakkında** → "Çip" satırında "Apple M…" yazmalı.

## İndirme

**[⬇ Penpot'u indir (DMG)](https://github.com/erdemerdim/penpot-mac/releases/latest)**

Açılan sayfada **Assets** başlığının altındaki `Penpot-….dmg` dosyasına tıklayın (yaklaşık 600 MB).

## Kurulum

1. İndirilenler klasöründeki **Penpot-….dmg** dosyasını çift tıklayın.
2. Açılan pencerede **Penpot** simgesini yanındaki **Uygulamalar** klasörüne sürükleyin.
3. Pencereyi kapatın. Masaüstünde ya da Finder'ın kenarında görünen **Penpot** diskini çıkarın
   (sağ tık → Çıkar). DMG dosyasını silebilirsiniz.

## İlk açılış (yalnızca bir kez)

Uygulama Apple'a ücretli olarak kaydettirilmediği için macOS ilk açılışta bir uyarı gösterir.
Bu normaldir; bir kez izin vermeniz yeterli:

1. **Uygulamalar** klasöründe **Penpot**'u çift tıklayın.
   "Penpot açılamadı" / "Apple doğrulayamadı" gibi bir uyarı çıkar → **Bitti**'ye basın.
2. **Sistem Ayarları**'nı açın ( → Sistem Ayarları) → soldan **Gizlilik ve Güvenlik**.
3. Sayfayı aşağı kaydırın. "Penpot, Mac'inizi korumak için engellendi" yazısının yanındaki
   **Yine de Aç** düğmesine basın ve Mac parolanızı girin.
4. Çıkan pencerede yine **Yine de Aç**'a basın.

Bundan sonra Penpot normal bir uygulama gibi açılır. İsterseniz Dock'a sürükleyin.

İlk açılışta Penpot kendini hazırlar (yaklaşık 15–30 saniye). Sonraki açılışlar birkaç saniye sürer.

## Kullanım

- **Hesap:** Penpot ekranında **Hesap oluştur**'a tıklayın; ad, e-posta ve bir parola girin.
  Hesap yalnızca bu Mac'te tutulur, e-postanıza bir şey gönderilmez.
- **Kapatmak:** Pencereyi kapatın ya da `Cmd + Q`. Penpot arka planda da tamamen kapanır.
- **Dışa aktarma:** PNG, JPG, WEBP, SVG ve PDF çalışır. Bir öğe seçin → sağ paneldeki
  **Dışa aktar** → **+** → **Dışa aktar**. Dosya **İndirilenler** klasörüne kaydedilir.
- **Yazı tipleri:** Google yazı tipleri çalışır (internet gerekir). Kendi yazı tipi dosyanızı
  yükleme ve e-posta ile davet gönderme bu sürümde yoktur.

## Tasarımlarınız nerede?

Tasarımlarınız Mac'inizde şu klasörde durur:
`~/Library/Application Support/Penpot`
(Finder'da **Git → Klasöre Git…** menüsüne bu yolu yapıştırarak açabilirsiniz.)

Penpot'un yeni bir sürümünü kurduğunuzda tasarımlarınız **kaybolmaz**.

**Başka bir Mac'e taşımak için:** Penpot'ta proje listesinde dosyanın üzerinde sağ tık →
**Dışa aktar** → **Penpot dosyası (.penpot)**. Bu dosyayı diğer Mac'e (AirDrop, iCloud, USB…)
taşıyın; orada Penpot'ta bir projeye girin → sağ üstteki **⋯** menüsü → **Penpot dosyasını
içe aktar**.

## Yeni sürüm

Yeni bir sürüm çıktığında [indirme sayfasından](https://github.com/erdemerdim/penpot-mac/releases/latest)
yeni DMG'yi indirin ve Penpot'u Uygulamalar klasörüne yeniden sürükleyin (**Değiştir** deyin).
Tasarımlarınız yerinde kalır. Önce Penpot'u kapatmayı unutmayın.

## Kaldırma

1. Penpot'u kapatın, **Uygulamalar** klasöründeki **Penpot**'u Çöp Sepeti'ne atın.
2. Tasarımlarınızı da silmek istiyorsanız `~/Library/Application Support/Penpot` klasörünü silin.
   (Bu geri alınamaz; önce önemli dosyalarınızı dışa aktarın.)

## Sık sorulanlar

**"Penpot hasarlı, Çöp Sepeti'ne taşıyın" diyor.**
DMG eksik inmiş olabilir; yeniden indirin. Sorun sürerse Terminal'de şunu çalıştırıp tekrar açın:
```bash
xattr -dr com.apple.quarantine /Applications/Penpot.app
```

**"Penpot'u Uygulamalar klasörüne taşıyın" diyor.**
Penpot'u DMG penceresinin içinden açtınız. Önce Uygulamalar klasörüne sürükleyin, oradan açın.

**Açılmıyor, "Penpot başlatılamadı" yazıyor.**
Bilgisayarda başka bir Penpot ya da PostgreSQL çalışıyor olabilir (aynı bağlantı noktaları:
9001, 6060, 5432, 6379). Onları kapatıp tekrar deneyin. Ayrıntılar:
`~/Library/Application Support/Penpot/Sistem/logs` klasöründe.

**İnternet gerekiyor mu?**
Hayır. Yalnızca Google yazı tipleri ve Penpot'un örnek dosyaları internetten gelir.

**Intel işlemcili Mac'te ya da Windows'ta çalışır mı?**
Hayır, şimdilik yalnızca Apple Silicon Mac.

---

Geliştiriciler için (kaynaktan kurulum, birden fazla Mac'i git ile eşitleme, DMG oluşturma):
[GELISTIRICI.md](GELISTIRICI.md). Lisans: [MPL-2.0](LICENSE); içerdiği bileşenlerin lisansları:
[NOTICE.md](NOTICE.md).
