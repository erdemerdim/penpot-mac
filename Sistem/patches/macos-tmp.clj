;; macOS düzeltmesi: /tmp aslında /private/tmp klasörüne bir kısayoldur.
;; Penpot yüklenen dosyaların gerçek yolunun /tmp/... ile başlamasını şart koşuyor;
;; macOS'ta yol /private/tmp/... olduğu için yüklemeler reddediliyordu.
;; Bu dosya Penpot başlarken yüklenir ve /private/tmp yollarını da izinli listeye ekler.
;; Gelecekteki bir sürümde ilgili kod değişirse sadece uyarı yazar, Penpot'un açılmasını engellemez.
(try
  (require 'app.media.validation)
  (if-let [v (resolve 'app.media.validation/allowed-upload-prefixes)]
    (do (alter-var-root v (fn [prefixes]
                            (vec (distinct (concat prefixes ["/private/tmp/undertow/" "/private/tmp/penpot/"])))))
        (println "[penpot-local] macOS /private/tmp düzeltmesi uygulandı"))
    (println "[penpot-local] UYARI: allowed-upload-prefixes bulunamadı, macOS düzeltmesi uygulanmadı"))
  (catch Throwable e
    (println "[penpot-local] UYARI: macOS düzeltmesi yüklenemedi:" (.getMessage e))))
