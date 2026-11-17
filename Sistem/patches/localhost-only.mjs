// Exporter, "http-server-host" ayarını yok sayıp tüm ağ arayüzlerinde dinliyor.
// Bu dosya node --import ile yüklenir ve yalnızca port verilen listen() çağrılarını
// 127.0.0.1'e bağlar; böylece exporter'a sadece bu bilgisayardan erişilebilir.
import http from "node:http";

const originalListen = http.Server.prototype.listen;
http.Server.prototype.listen = function (...args) {
  const port = args[0];
  const isPort = typeof port === "number" || (typeof port === "string" && /^\d+$/.test(port));
  if (isPort && (args.length === 1 || typeof args[1] === "function")) {
    return originalListen.call(this, Number(port), "127.0.0.1", ...args.slice(1));
  }
  return originalListen.apply(this, args);
};
