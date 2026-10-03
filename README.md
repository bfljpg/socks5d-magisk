# socks5d: U30 Air SOCKS5 proxy ve reverse tunnel rehberi

Oct 3, 2026 · @Emir

## Genel bakış

socks5d, root'lu U30 Air'ın mobil hattını kendi VDS'inin üzerinden kullanabileceğin, şifreli bir SOCKS5 proxy'ye çevirir. Modül iki parçadan oluşur: cihazda çalışan SOCKS5 sunucusu ve bu sunucuyu VDS'e açan SSH reverse tunnel.

Mobil operatörler çoğunlukla CGNAT kullandığı için dışarıdan U30'a doğrudan bağlanılamaz. Bu yüzden bağlantıyı U30 kurar: VDS'te `127.0.0.1:1080` dinlenir ve oraya gelen trafik tünelle cihaza taşınır. Proxy VDS'in dışına açılmaz, ona kendi makinenden `ssh -L` ile erişirsin.

&#91;embedded content: mimari akış · 5 durak, 1 reverse tunnel\]

Okuma yönü soldan sağadır, tek istisna tünel: onu VDS değil U30 açar, bu yüzden CGNAT arkasındaki cihaza ulaşılabilir.

## Gereksinimler

Modül yalnızca Magisk'li, arm64 bir Android cihazda çalışır. VDS tarafında OpenSSH yeterlidir.

- **Cihaz:** root'lu (Magisk 20.4 ya da üzeri) U30 Air. Kurulum betiği arm64 dışındaki mimarilerde durur.
- **VDS:** SSH'a açık bir Linux sunucu. Rehberdeki ayarlar OpenSSH 9.9 ile denendi. `permitlisten` seçeneği için OpenSSH 7.8 ve üzeri gerekir.
- **PC:** adb (USB hata ayıklama açık) ve bir SSH istemcisi.
- **Mobil veri:** U30'da etkin bir SIM hattı. Proxy trafiği bu hattın kotasından düşer.

Windows kullanıcıları için iki kural: komutlarda `curl` yerine `curl.exe` yazılır, çünkü PowerShell'deki `curl`, `Invoke-WebRequest` takma adıdır. İçinde `|` ya da `&&` bulunan adb komutları `adb shell "su -c '...'"` biçiminde yazılır, yoksa operatörü PC tarafındaki kabuk yorumlar.

## U30'a kurulum

Kurulum üç adımdır: zip'i Magisk'ten yükle, kurulum çıktısını kaydet, cihazı yeniden başlat.

1. `socks5d-magisk-v1.1.zip` dosyasını cihaza kopyala: `adb push socks5d-magisk-v1.1.zip /sdcard/`
2. Magisk uygulamasında Modüller bölümünden "Diskten yükle" ile zip'i seç.
3. Kurulum çıktısını kaydet. İlk kurulumda üç şey yazılır: kullanıcı adı (`proxy`), rastgele üretilen şifre ve tünel için üretilen **public key** (`ssh-ed25519 AAAA...`). Anahtar üretilemezse çıktı, elle üretme komutunu verir.
4. Cihazı yeniden başlat. Magisk modül dosyalarını yalnızca yeniden başlatmada devreye alır, `service.sh` de açılıştan yaklaşık 10 saniye sonra çalışır.

Kurulumu doğrulamak için:

```powershell
adb shell su -c 'ls -l /data/adb/modules/socks5d/'
```

Listede `socks5d`, `dbclient`, `dropbearkey`, `service.sh`, `module.prop` ve `uninstall.sh` görünmeli. `dbclient` yoksa yeniden başlatmamışsındır: güncelleme dosyaları yeniden başlatmaya kadar `/data/adb/modules_update/socks5d/` altında bekler.

Public key'i sonradan yeniden almak için:

```powershell
adb shell su -c '/data/adb/modules/socks5d/dropbearkey -y -f /data/adb/socks5d/id_ed25519'
```

## VDS hazırlığı

Tünel için VDS'te ayrı, kabuksuz bir kullanıcı aç ve U30'un public key'ini kısıtlı bir satırla ekle. Ana hesabını kullanmak da çalışır, ama satırda bir hata olursa zarar çok daha büyük olur.

1. Root olarak kullanıcıyı oluştur: `adduser --disabled-password --shell /usr/sbin/nologin tunel`
2. Home dizininin var olduğunu doğrula: `getent passwd tunel | cut -d: -f6` çıktısındaki dizin mevcut ve sahibi `tunel` olmalı.
3. `.ssh` dizinini ve `authorized_keys` dosyasını elle oluştur, `adduser` bunları açmaz:

```sh
install -d -m 700 -o tunel -g tunel /home/tunel/.ssh
cat > /home/tunel/.ssh/authorized_keys <<'EOF'
restrict,port-forwarding,permitlisten="127.0.0.1:1080",permitopen="192.0.2.1:9" ssh-ed25519 AAAA...U30_PUBLIC_KEY
EOF
chown tunel:tunel /home/tunel/.ssh/authorized_keys
chmod 600 /home/tunel/.ssh/authorized_keys
```

Seçenekler, anahtar ve yorum tek satırda olmalı. Satırı kontrol etmek için `cut -c1-120 /home/tunel/.ssh/authorized_keys` çalıştır.

| Seçenek | Etkisi |
| --- | --- |
| `restrict` | Shell, PTY, agent ve X11 dahil her şeyi kapatır. |
| `port-forwarding` | Yalnızca port yönlendirmeyi yeniden açar. |
| `permitlisten="127.0.0.1:1080"` | Anahtar sadece VDS'in loopback 1080 portunu dinleyebilir (`-R`). |
| `permitopen="192.0.2.1:9"` | `-L` ve `-D` ile açılabilecek tek hedef, hiçbir yere gitmeyen bir adrestir. |

İki tuzak bu kurulumda yaşandı:

- `permitopen="none"` `authorized_keys`'te geçersizdir. sshd anahtarı tamamen yok sayar ve `bad key options: invalid permission port` yazar. `none` yalnızca `sshd_config`'teki `PermitOpen` için geçerlidir.
- `permitlisten` değeri `127.0.0.1:1080` olmalı. `0.0.0.0:1080` yazılırsa tünel istemcisinin isteği eşleşmez.

sshd ayarlarını kontrol et:

```sh
sshd -t && sshd -T | grep -iE 'allowusers|allowgroups|allowtcpforwarding|pubkeyauthentication'
```

`pubkeyauthentication yes` ve `allowtcpforwarding yes` (ya da `remote`) görünmeli. `allowusers` ya da `allowgroups` tanımlıysa `tunel` listede olmalı. `Match` blokları ayarı kullanıcı bazında değiştirebilir: `sshd -T -C user=tunel,host=x,addr=<U30'un mobil IP'si>` ile gerçek sonucu gör. SSH portunu IP ile kısıtlıyorsan (güvenlik duvarı, fail2ban), mobil IP değiştiğinde tünel kopabilir.

## Yapılandırma

Tüm ayarlar cihazdaki `/data/adb/socks5d/config` dosyasında durur. Dosya `ALAN=değer` biçimindedir, eşittir işaretinin çevresinde boşluk olmaz.

| Alan | Varsayılan | Açıklama |
| --- | --- | --- |
| `BIND` | `0.0.0.0` | Proxy'nin dinlediği adres. Tünel kullanıyorsan `127.0.0.1` yap. |
| `PORT` | `1080` | Cihazda dinlenen port. |
| `USER` | `proxy` | Proxy kullanıcı adı. |
| `PASS` | kurulumda üretilen 32 karakter | Proxy şifresi. |
| `DNS` | `1.1.1.1:53` | İstemcinin istediği alan adlarını çözen DNS sunucusu (`host:port`). |
| `TUNNEL` | `0` | `1` yapılınca reverse tunnel başlar. |
| `TUN_HOST` | boş | VDS adresi. |
| `TUN_PORT` | `22` | VDS'in SSH portu. |
| `TUN_USER` | boş | VDS'teki tünel kullanıcısı (`tunel`). |
| `TUN_REMOTE_PORT` | `1080` | VDS'in loopback'inde açılacak port. |
| `VERBOSE` | `0` | `1` olunca her başarılı bağlantı `socks5d.log`'a yazılır. |

Tünel kullanımı için en az şu satırlar değişmeli:

```sh
BIND=127.0.0.1
TUNNEL=1
TUN_HOST=vds.adresin
TUN_USER=tunel
```

Cihazda editör yok. En kolayı dosyayı PC'ye çekip düzenlemek:

```powershell
adb shell "su -c 'cp /data/adb/socks5d/config /sdcard/config'"
adb pull /sdcard/config .
# config dosyasını düzenle ve kaydet
adb push config /sdcard/config
adb shell "su -c 'cp /sdcard/config /data/adb/socks5d/config && chmod 600 /data/adb/socks5d/config && rm /sdcard/config'"
```

Dosyada proxy şifren var. Son komut `/sdcard`'taki kopyayı siler, PC'deki `config` kopyasını da işin bitince sil.

Değişiklik şöyle devreye girer:

- **Proxy ayarları** (`BIND`, `PORT`, `USER`, `PASS`, `DNS`, `VERBOSE`): `adb shell "su -c 'pkill socks5d'"` ile süreci sonlandır, watchdog 5 saniyede yeni ayarla başlatır.
- **Tünel ayarları:** tünel kapalıyken en geç 30 saniyede devreye girer. Çalışan tüneli yenilemek için `adb shell "su -c 'pkill dbclient'"` yeterli, 10 saniyede yeniden kurulur.

## Doğrulama

Çalıştığını üç yerden doğrularsın: cihaz, VDS ve uçtan uca bir istek. Sonuncusu dönen IP'nin U30'un mobil IP'si olduğunu gösteren tek kanıttır.

### Cihazda

```powershell
adb shell "su -c 'ps -A | grep socks5d'"
adb shell "su -c 'ps -A | grep dbclient'"
adb shell "su -c 'netstat -tln | grep 1080'"
adb shell "su -c 'tail -n 5 /data/adb/socks5d/watchdog.log'"
```

- `socks5d` süreci görünmeli. `TUNNEL=1` ise `dbclient` de görünmeli.
- `BIND=127.0.0.1` ise 1080 `127.0.0.1` ile listelenir. `0.0.0.0` ise `tcp6 [::]:1080` gibi görünür ve proxy hotspot tarafına da açıktır.
- `watchdog.log`'da `starting socks5d on ...` ve `starting tunnel to ...` satırları olmalı. Arka arkaya `tunnel exited` satırları tünelin kurulamadığını gösterir, nedeni `tunnel.log`'da yazar.

### VDS'te

```sh
ss -ltn | grep 1080
journalctl -u ssh --since "5 min ago" --no-pager | grep -E 'Accepted publickey|tunel' | tail -5
```

Beklenen: `127.0.0.1:1080` için bir `LISTEN` satırı ve `Accepted publickey for tunel ... ED25519` kaydı.

### Uçtan uca

VDS'te proxy'yi dene. Şifre komut geçmişine düşmesin diye `read` ile girilir:

```sh
read -rs PW; echo
curl --socks5-hostname "proxy:$PW@127.0.0.1:1080" https://api.ipify.org; echo
unset PW
```

Dönen IP, VDS'inkinden farklı ve U30'un mobil IP'si olmalı. Karşılaştırmak için proxy'siz `curl https://api.ipify.org` çalıştır. Yanlış şifreyle aynı komut `User was rejected by the SOCKS5 server` hatası vermeli.

### Yeniden başlatma testi

U30'u yeniden başlat, bir dakika bekle ve VDS'te `ss -ltn | grep 1080` komutunu tekrarla. Port geri geliyorsa açılışta otomatik başlatma ve tünel zincirinin tamamı kalıcıdır.

## Günlük kullanım

Proxy'ye kendi makinenden, VDS'e açtığın bir SSH yerel yönlendirmesiyle bağlanırsın. Tünel U30'dan VDS'e açık olduğu sürece bu tek komut yeterlidir:

```sh
ssh -N -L 1080:127.0.0.1:1080 kullanici@vds.adresin
```

`kullanici` kendi hesabındır, tünel kullanıcısı değil: tünel anahtarı zaten kabuk vermez. Komut açıkken makinendeki `127.0.0.1:1080`, U30'un proxy'sine bağlanır.

Uygulamalarda şu ayarları gir:

- Tür SOCKS5, adres `127.0.0.1`, port `1080`.
- Kullanıcı `proxy`, şifre config'teki `PASS`.
- Alan adı çözümünü U30 tarafında yaptırmak için uzak DNS seçeneğini aç (curl'de `--socks5-hostname`, bazı uygulamalarda `socks5h`). Kapalıysa DNS sorguları makinenden çıkar.

Hızlı deneme (Windows):

```powershell
curl.exe --socks5-hostname proxy:SIFRE@127.0.0.1:1080 https://api.ipify.org
```

Dönen IP U30'un mobil IP'si olmalı. Loopback adresinde test ederken dikkat: `no_proxy` ya da `NO_PROXY` ortam değişkeni loopback'i kapsıyorsa curl proxy'yi hiç kullanmaz. Doğru şifre, yanlış şifre ve ölü port aynı sonucu verir, test anlamsızlaşır. Şüphede bu değişkenleri kaldırıp dene.

Tünelsiz iki alternatif de var:

- **USB üzerinden:** `adb forward tcp:1080 tcp:1080` komutundan sonra proxy yine `127.0.0.1:1080`'dir. Cihazda `BIND` fark etmez.
- **Cihazın Wi-Fi ağından:** `BIND=0.0.0.0` iken U30'un hotspot'una bağlı bir makine, cihazın ağ geçidi adresine bağlanır (çoğunlukla `192.168.0.1:1080`). Proxy tüm hotspot istemcilerine açık olur, şifre tek savunmadır.

## Dosyalar ve loglar

Modülün dosyaları `/data/adb/modules/socks5d/` altında, ayarlar ve loglar `/data/adb/socks5d/` altındadır. Sorun olduğunda önce bu loglara bakılır.

| Yol | İçerik |
| --- | --- |
| `/data/adb/modules/socks5d/` | Modül dosyaları: `socks5d`, `dbclient`, `dropbearkey`, `service.sh`. |
| `/data/adb/socks5d/config` | Ayarlar ve proxy şifresi (izin 600). |
| `/data/adb/socks5d/id_ed25519` | Tünelin özel anahtarı (izin 600, parolasız). |
| `/data/adb/socks5d/.ssh/known_hosts` | Güvenilen VDS host anahtarı, ilk bağlantıda kaydedilir. |
| `/data/adb/socks5d/socks5d.log` | Proxy logu: auth hataları ve bağlanılamayan hedefler. 1 MB'ta `socks5d.log.1` olarak döner. Saatler UTC. |
| `/data/adb/socks5d/tunnel.log` | `dbclient` çıktısı: host anahtarı kabulü ve bağlantı hataları. 256 KB'ı aşınca son 64 KB'a kırpılır. |
| `/data/adb/socks5d/watchdog.log` | Başlatma ve yeniden başlatma kayıtları, cihazın yerel saatiyle. Aynı kırpma kuralı. |

Hangi log neyi söyler:

- **Proxy cevap vermiyor:** `watchdog.log` süreç çıkışlarını, `socks5d.log` nedenini gösterir.
- **Tünel kurulmuyor:** `tunnel.log` hata mesajını verir, sunucu tarafının nedeni VDS'teki `journalctl -u ssh` çıktısındadır.
- **Hedefe bağlanılamıyor:** `socks5d.log`'da `connect HOST:PORT failed: ...` satırı çıkar.
- **Kim bağlanıyor:** config'e `VERBOSE=1` yazınca her başarılı bağlantı da loglanır.

Log okuma örneği:

```powershell
adb shell "su -c 'tail -n 20 /data/adb/socks5d/tunnel.log'"
```

## Sorun giderme

Aşağıdaki belirtilerin hepsi bu modülün kurulumunda gerçekten yaşandı. Önce `tunnel.log` ve `watchdog.log`'a bak, sonra tablodaki satırı bul.

| Belirti | Neden | Çözüm |
| --- | --- | --- |
| `which ssh dbclient` hiçbir şey yazmıyor | Modülün binary'leri `PATH`'te değil | Tam yolu kullan: `/data/adb/modules/socks5d/dbclient`. Varlığını `ls -l /data/adb/modules/socks5d/` ile kontrol et. |
| `dbclient: inaccessible or not found` (ps ve grep'li adb komutunda) | PowerShell tırnakları yuttu, cihaz kabuğu komutu iki parçaya böldü | Dıştaki tırnağı çift, içtekini tek yaz: `adb shell "su -c '...'"`. Grep desenini tek kelime tut. |
| PowerShell'de `--socks5-hostname` hata veriyor | `curl`, `Invoke-WebRequest` takma adıdır | `curl.exe` yaz. |
| Doğru şifre, yanlış şifre ve ölü port aynı sonucu veriyor | `no_proxy` loopback'i kapsıyor, curl proxy'yi hiç kullanmıyor | `no_proxy` ve `NO_PROXY` değişkenlerini kaldırıp tekrar dene. |
| `curl: (56) schannel: server closed abruptly (missing close_notify)` | Proxy üzerinden `ifconfig.me`'de bir kez görüldü, sonraki denemelerde geçti. Nedeni belirlenemedi: site ya da Windows schannel olabilir. | Tekrar dene, test için `https://api.ipify.org` kullan. Tekrarlarsa `VERBOSE=1` ile `socks5d.log`'a bak. |
| `tunnel.log`: `No auth methods could be used` | Sunucu anahtarı kabul etmedi ya da `authorized_keys` satırı geçersiz olduğu için yok sayıldı | VDS'te sshd logunu ayrıntılı aç (tablonun altı). |
| VDS logu: `bad key options: invalid permission port` | `authorized_keys` satırında geçersiz seçenek var, örneğin `permitopen="none"` | Satırı "VDS hazırlığı" bölümündeki gibi düzelt. |
| `Connection refused` ya da zaman aşımı | `TUN_HOST` ya da `TUN_PORT` yanlış, SSH kapalı veya güvenlik duvarı engelliyor | Adresi ve portu doğrula, mobil IP'leri engelleyen bir kural olup olmadığına bak. |
| `host key mismatch` | VDS'in host anahtarı değişti (yeniden kurulum) ya da araya biri girdi | Değişikliğin meşru olduğunu doğrula, sonra `/data/adb/socks5d/.ssh/known_hosts` içindeki eski kaydı sil. |
| `Warning: failed to identify current user` | Android'de root için passwd kaydı yok | Zararsız, tünelin çalışmasını etkilemez. |
| VDS'te `Accepted publickey` var ama 1080 dinlenmiyor | `permitlisten` isteği reddediyor ya da port başka bir süreçte | `permitlisten="127.0.0.1:1080"` yazdığını kontrol et, `ss -ltnp` ile portu kimin tuttuğuna bak. `permitlisten="1080"` de bir seçenek, ama bu varyasyon denenmedi. |
| `watchdog.log`'da tünel satırı yok | `TUNNEL` değeri 1 değil ya da `TUN_HOST` veya `TUN_USER` boş | Config'i düzelt, en geç 30 saniyede devreye girer. |
| `Can't complete SOCKS5 connection ... (5)` | Proxy çalışıyor ama U30 hedefe ya da DNS'e ulaşamıyor | Mobil verinin açık olduğunu kontrol et, `socks5d.log`'daki `connect ... failed` satırına ve `DNS` ayarına bak. |
| Güncellemeden sonra `dbclient` yok | Cihaz yeniden başlatılmadı | Yeniden başlat, dosyalar o zamana kadar `modules_update` altında bekler. |

VDS'te reddin gerçek nedenini görmek için sshd logunu geçici olarak ayrıntılı aç:

```sh
echo 'LogLevel DEBUG1' > /etc/ssh/sshd_config.d/99-debug.conf
systemctl reload ssh
sleep 25
journalctl -u ssh --since "1 min ago" --no-pager | grep -E 'tunel|userauth|pubkey|authorized|key' | tail -40
rm /etc/ssh/sshd_config.d/99-debug.conf && systemctl reload ssh
```

Son satır ayarı geri alır, atlama. `userauth_pubkey: publickey test pkalg ssh-ed25519 ...` satırı istemcinin anahtarı sunduğunu gösterir. Ardından gelen `trying public key file`, `bad key options` ya da `Could not open ...` satırları reddin nedenini söyler. Dizin ve servis adı Ubuntu'ya göredir, başka dağıtımlarda servis `sshd` olabilir.

## Güvenlik notları

Proxy'nin tek savunması şifre, tünel anahtarının tek savunması ise `authorized_keys` satırındaki kısıtlamalardır. İkisi de doğru kurulmalı.

- **Proxy'yi dışarı açma:** Tünel kullanıyorsan `BIND=127.0.0.1` yap. `0.0.0.0` iken U30'un hotspot'una bağlanan herkes portu görür. Başarısız şifre denemeleri 1 saniye bekletilir ve `socks5d.log`'a yazılır.
- **Yetki sınırı yok:** Proxy'de erişim listesi yoktur. Şifreyi bilen herkes U30'un mobil kotasını kullanır ve hedeflere U30'un IP'siyle çıkar.
- **Özel anahtar:** `/data/adb/socks5d/id_ed25519` cihazda parolasız durur. Cihaz kaybolur ya da ele geçirilirse anahtar çıkarılabilir. VDS'teki satırın kısıtlı ve ayrı kullanıcıya bağlı olmasının nedeni budur.
- **Host anahtarı:** İlk bağlantıda VDS'in anahtarı kabul edilip kaydedilir (`accept-new`), bu yüzden ilk bağlantıyı güvenmediğin bir ağda yapma. Sonradan anahtar değişirse istemci bağlantıyı reddeder.
- **Erişimi iptal etme:** VDS'te `authorized_keys` satırını sil, tünel bir sonraki denemede reddedilir. Proxy şifresini yenilemek için config'te `PASS` değerini değiştirip `pkill socks5d` çalıştır.
- **22 portundaki gürültü:** VDS loglarında internetten gelen parola denemeleri görürsün (`guest`, `root` gibi kullanıcılara). Bunun tünelle ilgisi yok, ama `PasswordAuthentication no` ve fail2ban düşünmeye değer.

## Güncelleme ve kaldırma

Yeni sürümü eskisinin üstüne kurmak ayarlarını ve anahtarını korur. Kaldırmak ise `/data/adb/socks5d/` dizinindeki her şeyi siler.

- **Güncelleme:** Zip'i Magisk'ten tekrar yükle ve yeniden başlat. Mevcut `config` ve `id_ed25519` dosyalarına dokunulmaz. v1.0'dan geliyorsan kurulum config'e tünel alanlarını ekler, tünel anahtarını üretir ve public key'i çıktıda gösterir.
- **Tüneli geçici durdurma:** Config'te `TUNNEL=0` yap ve çalışan istemciyi `adb shell "su -c 'pkill dbclient'"` ile sonlandır. Tünel döngüsü bunu en geç 30 saniyede görür ve bekler.
- **Kaldırma:** Magisk'te modülü kaldırıp yeniden başlat. `uninstall.sh` config'i, tünel anahtarını, `known_hosts` dosyasını ve logları siler. Gerekirse önce `config`'i yedekle.
- **VDS temizliği:** `authorized_keys` satırını sil. Kullanıcıyı da kaldırmak istersen `userdel -r tunel` çalıştır.

## Sınırlamalar ve bilinenler

Modül bir TCP proxy'si olarak tasarlandı ve bilinçli kısıtları var.

- **Protokol:** Yalnızca SOCKS5 `CONNECT`. UDP (`UDP ASSOCIATE`) ve `BIND` desteklenmez.
- **Sunucu gost değil:** socks5d bu modül için yazılmış, yalnızca standart kütüphaneyle derlenen küçük bir sunucudur. Derleme ortamında gost indirilemediği için bu yol seçildi. Kullanıcı/şifre dışında erişim kuralı ya da zincirleme gibi özellikleri yok.
- **Mimari:** Yalnızca arm64. 32-bit ARM cihazlarda çalışmaz. MF286R bu gruba giriyor gibi görünüyor ama doğrulanmadı. O cihazda ayrıca Magisk da olmadığı için başka bir başlatıcı gerekir.
- **Tek tünel:** Tek VDS ve tek uzak port desteklenir.
- **Kopma süresi:** VDS'ten yanıt gelmezse istemci 90 saniye sonra (3 × 30 sn keepalive) çıkar, watchdog 10 saniye sonra yeniden dener. Mobil IP değişince kısa bir kesinti olur.
- **Saatler:** `socks5d.log` UTC, `watchdog.log` cihazın yerel saatindedir.
- **Test kapsamı:** Proxy ve tünel mantığı önce yerelde bir Dropbear sunucusuyla, sonra gerçek U30 ve OpenSSH 9.9'lu bir VDS ile uçtan uca doğrulandı. Tabloda "denenmedi" diye işaretlenen varyasyonlar doğrulanmış değildir.

## Hızlı komut özeti

Günlük işlerin komutları burada toplu. `SIFRE`, `vds.adresin` ve `kullanici` yerine kendi değerlerini yaz.

### Cihaz (PC'den adb ile)

```powershell
# durum
adb shell "su -c 'ps -A | grep socks5d'"
adb shell "su -c 'netstat -tln | grep 1080'"
adb shell "su -c 'tail -n 20 /data/adb/socks5d/tunnel.log'"
adb shell "su -c 'tail -n 5 /data/adb/socks5d/watchdog.log'"

# yeniden başlat
adb shell "su -c 'pkill socks5d'"
adb shell "su -c 'pkill dbclient'"

# şifre ve public key
adb shell su -c 'cat /data/adb/socks5d/config'
adb shell su -c '/data/adb/modules/socks5d/dropbearkey -y -f /data/adb/socks5d/id_ed25519'
```

### VDS

```sh
ss -ltn | grep 1080
journalctl -u ssh --since "5 min ago" --no-pager | grep -E 'Accepted publickey|tunel' | tail -5
cut -c1-120 /home/tunel/.ssh/authorized_keys
```

### Kendi makinen

```sh
ssh -N -L 1080:127.0.0.1:1080 kullanici@vds.adresin
```

```powershell
curl.exe --socks5-hostname proxy:SIFRE@127.0.0.1:1080 https://api.ipify.org
```
