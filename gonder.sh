#!/usr/bin/env bash
# Bu Mac'te yaptığınız değişiklikleri (betikler, uygulama kaynakları) GitHub'a gönderir.
# Kullanım: ./gonder.sh "ne değişti"
# Tasarımlar, veritabanı ve indirilen bileşenler gönderilmez (.gitignore).
set -euo pipefail
cd "$(dirname "$0")"
git add -A
if git diff --cached --quiet; then
  echo "Gönderilecek değişiklik yok."
else
  git status --short
  git commit -q -m "${1:-Güncelleme ($(scutil --get ComputerName 2>/dev/null || hostname -s), $(date '+%Y-%m-%d %H:%M'))}"
fi
git pull --rebase -q
git push -q
echo "Gönderildi: $(git log -1 --format='%h %s')"
