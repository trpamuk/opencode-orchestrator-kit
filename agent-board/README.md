# Ajan Panosu

OpenCode 2.x için canlı, yerel ajan ve görev panosu.

- URL: http://127.0.0.1:43124
- Sunucu: `server.mjs`
- Arayüz: `index.html`
- Sessiz başlatma: `start.vbs`
- Otomatik başlangıç: Windows Startup içindeki `Ajan Panosu.lnk`

## Ne gösterir?

- Seçili projedeki tüm oturumlar: resmi ajan adı, `#ajan-id`, model, ana/alt oturum, oturum kimliği, proje, süre, son işlem, token ve maliyet.
- **Alt Görevler**: oturum içinde çalışan `subagent`/`task` tool çağrıları; alt oturum oluşmasa bile görünür.
- **takıldı?** durumu: ayarlanabilir eşikten (varsayılan 15 dk) sonra oturum veya alt görev kırmızı işaretlenir.
- **Durdur** butonu: takılı kartlarda görünür; onay ister ve sadece ilgili oturumun mevcut çalışmasını keser. Dosya/board değiştirmez.
- **Modeller** butonu: oturum modeli, belirli model, birincil + yedek model, variant, model testi, `session`/`opencode-go` preset geçişi ve **Bu proje için** proje profili. Değişiklik öncesi yedek alınır; provider API key'leri tarayıcıya gönderilmez.
- **Detay** butonu: son tool çağrıları, hata, model, token/maliyet, canlı yenileme, tool filtresi, hata kopyalama, oturum ağacı ve **Yeniden dene**. Hassas anahtarlar redakte edilir.
- **Ayarlar**: takılma eşiği, opt-in otomatik durdurma, Web Bildirimleri ve diagnostic indirme.
- **Analitik**: agent bazlı oturum/başarı/hata/süre/token/maliyet/stuck tablosu.
- **Guard**: Board Guard log görüntüleyici. **Arşivle**: aktif board'u arşive taşır.
- Sürüm rozeti ve GitHub güncelleme kontrolü.
- OpenCode'da varsayılan model yoksa üstte uyarı bandı çıkar.
- Ajan görselleri: OMO-slim'in resmi ajan görsellerinden üretilmiş 128 px avatarlar.
- Ajan rehberi: orchestrator, explorer, fixer, designer, oracle, observer, arbiter, paladin, proctor, hunter, build, plan.
- Görevler: proje alanındaki her board ayrı kart olarak gösterilir; `current.md` legacy/index ise gizlenir.
- 1.2 saniyede bir otomatik yenilenir; manuel refresh gerekmez.

## Proje ve board izolasyonu

- Panel proje bazlıdır. Üstteki seçiciden proje değiştirilir; iki projenin ajanları veya board'ları aynı görünümde karışmaz.
- Her projenin board alanı `.opencode/plans/` altındadır.
- İlgisiz her görev silsilesi için ayrı board: `.opencode/plans/boards/<slug>.md`.
- `current.md` proje indeksi/legacy board olarak kalabilir; panel onu görev tablosu değilse gizler.
- Worktree'ler ayrı board açmaz; ana projenin board'unda `Worktree / Branch` kolonuyla görünür.

## Board guard

`%USERPROFILE%\.config\opencode\plugins\board-guard.js` global plugin'i:

- board yazımını yalnızca projenin `.opencode/plans/current.md` veya `.opencode/plans/boards/*.md` alanına izin verir,
- başka proje/worktree board'larını reddeder,
- alt ajanların board yazmasını reddeder; yalnızca `orchestrator` ve `build` yazabilir,
- reddedilen denemeleri `agent-board/guard.log` dosyasına yazar.

Plugin değişikliği OpenCode yeniden başlatıldığında etkinleşir.

## Desktop tarayıcı

- Panel OpenCode Review pane'inde açık bir sekmede çalışır.
- OpenCode'un yerleşik tarayıcı sekmesini dışarıdan, uygulama açılırken otomatik açan resmi bir plugin/API yoktur; browser tool yalnızca ajan oturumuna açıktır.
- Desktop native sekme geri yüklemesi panel sekmesini geri getirirse otomatik görünür. Gelmezse masaüstündeki `Ajan Panosu.url` kısayolu veya `http://127.0.0.1:43124` kullanılabilir.
- Tamamen içeride ve garanti otomatik bir yan panel için OCDX desktop-extension yolu ayrı bir OpenCode kanalı gerektirir; mevcut oturum/config ile drop-in değildir.

## Notlar

- Panel yalnızca `127.0.0.1` üzerinde dinler; OpenCode API parolası tarayıcıya gönderilmez.
- Görev tablosu dosyadaki değişiklikleri otomatik alır; OpenCode Desktop'ın markdown görüntüleyicisindeki önbellek sorununu atlatır.
- Port 43124 doluysa sunucu hata vermeden çıkar; mevcut sunucu kullanılmaya devam eder.
