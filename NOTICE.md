# Bildirimler ve üçüncü taraf lisansları

Bu depodaki betikler, yamalar ve uygulama kaynak kodu Mozilla Public License 2.0 ([LICENSE](LICENSE))
ile lisanslıdır.

Bu proje Penpot'un resmî bir dağıtımı değildir ve Penpot / Kaleidos ile bağlantısı yoktur.
"Penpot" adı ve logosu sahiplerine aittir.

**DMG sürümü** (GitHub Releases) aşağıdaki bileşenleri değiştirmeden, uygulama paketinin içinde
(`Penpot.app/Contents/Resources/runtime/`) taşır; lisans metinleri aynı klasörlerdedir.

Depo yalnızca kaynak dosyalarımızı içerir. Aşağıdaki bileşenler `kurulum.sh` tarafından her
Mac'te doğrudan kaynağından indirilir ya da derlenir ve kendi lisanslarıyla gelir. Lisans
metinleri kurulumdan sonra belirtilen klasörlerde bulunur.

| Bileşen | Kaynak | Lisans | Lisans metni (kurulumda `Sistem/`, DMG'de `runtime/` altında) |
|---|---|---|---|
| Penpot (backend, frontend, exporter, MCP) | [penpot/penpot](https://github.com/penpot/penpot), resmî Docker imajları `penpotapp/*` | MPL-2.0 | `Sistem/backend/LICENSE`, `Sistem/mcp/LICENSE` |
| Java (Azul Zulu OpenJDK 25) | [azul.com](https://www.azul.com/downloads/) | GPLv2 + Classpath Exception | `Sistem/jdk/Contents/Home/legal/`, `.../LICENSE` |
| Node.js | [nodejs.org](https://nodejs.org) | MIT (+ bağımlılık lisansları) | `Sistem/node/LICENSE` |
| PostgreSQL 15 | [postgresql.org](https://www.postgresql.org) (kaynaktan derlenir) | PostgreSQL License | [postgresql.org/about/licence](https://www.postgresql.org/about/licence/) |
| Valkey 8 | [valkey-io/valkey](https://github.com/valkey-io/valkey) (kaynaktan derlenir) | BSD-3-Clause | [COPYING](https://github.com/valkey-io/valkey/blob/unstable/COPYING) |
| Chromium headless shell | Playwright üzerinden | BSD-3-Clause + üçüncü taraf | `Sistem/browsers/chromium_headless_shell-*/*/LICENSE.headless_shell` |
| Playwright | exporter içinde | Apache-2.0 | `Sistem/exporter/node_modules/playwright/LICENSE` |
| sharp / libvips | MCP içinde, npm | Apache-2.0 / LGPL-3.0 | `Sistem/mcp/node_modules/.pnpm/@img+*/` |

## Penpot kaynak kodu

Kurulan Penpot sürümünün kaynak kodu: <https://github.com/penpot/penpot> (sürüm etiketi
`Sistem/surumler.env` içindeki `PENPOT_VERSION`). Bu depodaki yamalar (`Sistem/patches/`)
Penpot dosyalarını değiştirmez; açılışta ek olarak yüklenir.
