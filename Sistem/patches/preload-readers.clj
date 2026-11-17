;; Hızlı açılış (önceden derlenmiş Penpot kodu) için gerekli:
;; Penpot'un ayarlarında #penpot/cron gibi etiketler var. Derlenmiş kodda bu etiketler,
;; app.main yüklenirken hemen çalıştırılır; ait oldukları kod önceden yüklenmemişse
;; "Attempting to call unbound fn" hatası verir. Burada hepsini app.main'den önce yüklüyoruz.
;; Kaynak: penpot.jar içindeki data_readers.clj ve data_readers.cljc.
(doseq [ns-sym '[app.common.time datoteka.fs app.common.types.tokens-lib cheshire.core
                 app.common.geom.matrix linked.map linked.set app.util.cron app.common.types.path
                 app.common.geom.point flatland.ordered.set flatland.ordered.map]]
  (try (require ns-sym)
       (catch Throwable e
         (println "[penpot-local] UYARI: ön yükleme başarısız:" ns-sym (.getMessage e)))))
