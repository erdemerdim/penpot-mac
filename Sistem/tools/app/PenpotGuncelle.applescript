set L to (do shell script "dirname " & quoted form of (POSIX path of (path to me))) & "/Sistem"
set upd to quoted form of (L & "/update.sh")
-- 1) GitHub deposundaki betik/uygulama değişikliklerini al (depo bağlıysa)
set depoMsg to ""
try
	set depoOut to do shell script "/bin/bash " & quoted form of (L & "/tools/depo-guncelle.sh") & " 2> /dev/null | tail -1"
	if depoOut starts with "DEPO: güncellendi" then set depoMsg to "Depodaki değişiklikler alındı: " & (text 19 thru -1 of depoOut) & return & return
on error errMsg
	display dialog "Depodan güncelleme alınamadı." & return & return & errMsg & return & return & "Penpot sürüm kontrolüne devam edilecek." buttons {"Tamam"} default button 1 with icon caution with title "Penpot Güncelle"
end try
-- 2) Yeni Penpot sürümü var mı?
try
	set out to do shell script "/bin/bash " & upd & " --check"
on error errMsg
	display dialog "Güncelleme kontrolü yapılamadı. İnternet bağlantınızı kontrol edin." & return & return & errMsg buttons {"Tamam"} default button 1 with icon stop with title "Penpot Güncelle"
	return
end try
set cur to ""
set lat to ""
repeat with ln in paragraphs of out
	if ln starts with "Kurulu sürüm: " then set cur to text 15 thru -1 of ln
	if ln starts with "En son sürüm: " then set lat to text 15 thru -1 of ln
end repeat
if cur is lat then
	display dialog depoMsg & "Penpot güncel." & return & return & "Kurulu sürüm: " & cur buttons {"Tamam"} default button 1 with title "Penpot Güncelle"
	return
end if
set r to display dialog depoMsg & "Yeni Penpot sürümü var." & return & return & "Kurulu sürüm: " & cur & return & "Yeni sürüm: " & lat & return & return & "Güncelleme birkaç dakika sürer. Önce verileriniz yedeklenir; bu sırada Penpot kapalı olur." buttons {"Şimdi değil", "Güncelle"} default button "Güncelle" with title "Penpot Güncelle"
if button returned of r is not "Güncelle" then return
display notification "Penpot " & lat & " indiriliyor ve kuruluyor. Bitince haber verilecek." with title "Penpot Güncelle"
try
	do shell script "/bin/bash " & upd & " --yes > " & quoted form of (L & "/logs/update.log") & " 2>&1"
	display dialog "Penpot " & lat & " sürümüne güncellendi." & return & return & "Penpot penceresi açıksa sayfayı yenileyin (Cmd + R)." buttons {"Tamam"} default button 1 with title "Penpot Güncelle"
on error
	display dialog "Güncelleme tamamlanamadı. Ayrıntılar: " & L & "/logs/update.log" & return & return & "Eski sürüme dönmek için Terminal'de şunu çalıştırın:" & return & L & "/rollback.sh" buttons {"Tamam"} default button 1 with icon stop with title "Penpot Güncelle"
end try

