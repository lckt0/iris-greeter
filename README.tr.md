# iris-greeter

[English](README.md) · **Türkçe**

Bir iris tarayıcı animasyonu etrafında kurulmuş, tam siyah bir SDDM giriş
ekranı, Plasma 6 kilit ekranı ve açılış ekranı. Zemin saf `#000000`'dır (OLED
paneller düşünülerek) ve üstündeki her şey birkaç farklı opaklıkta tek bir
beyazdır.

![Giriş ekranı](screenshots/login.png)

> **Başlamadan önce küçük bir not:** iris-greeter en başta kendi kullanımım için tasarlandı; başkalarının da işine yarayabilir diye paylaşıyorum. Kendi ihtiyaçlarım ve tercihlerim doğrultusunda şekillendiği için herkese hitap etmeyebilir. Öneri ve geri bildirimlerinizi memnuniyetle karşılarım.

Ortadaki göz profil resminin yerini tutar. Boştayken kırpıştırır;
[howdy](https://github.com/boltgolt/howdy) ile yüz tanıma kuruluysa
`pam_howdy` tararken canlanır ve PAM'in bildirdiğini gösterir.

| Taranıyor | Eşleşti |
|---|---|
| ![Taranıyor](screenshots/login-scanning.png) | ![Eşleşti](screenshots/login-matched.png) |

| Kilit ekranı, beklemede | Kilit ekranı, tanınmadı |
|---|---|
| ![Kilit ekranı beklemede](screenshots/lock-resting.png) | ![Kilit ekranı başarısız](screenshots/lock-not-recognised.png) |

## İçindekiler

| Parça | Kurulduğu yer | Not |
|---|---|---|
| SDDM teması | `/usr/share/sddm/themes/iris` | giriş ekranı |
| Plasma kabuk paketi | `/usr/share/plasma/shells/iris` | kilit ekranı (isteğe bağlı, aşağıya bakın) |
| Duvar kağıdı eklentisi | `~/.local/share/plasma/wallpapers/org.lckt0.iris` | stok kilit ekranının altında aynı arka plan |
| Açılış ekranı | `~/.local/share/plasma/look-and-feel/org.lckt0.iris` | yalnızca açılış ekranı, genel tema değil |

Giriş ve kilit ekranları aynı QML bileşenlerini (`shared/`) kullanır; saat,
tarayıcı, parola alanı ve alt şerit iki ekranda da aynı yerdedir.

## Kurulum

### Gereksinimler

- KDE Plasma 6 ve Qt 6 karşılayıcısıyla (`sddm-greeter-qt6`) SDDM
- Sistem geneline kurulmuş [JetBrainsMono Nerd Font](https://www.nerdfonts.com/)
  (ör. `/usr/local/share/fonts` altında), böylece `sddm` kullanıcısı da okuyabilir
- İsteğe bağlı: yüzle giriş için howdy. Olmadan tema normal bir parola ekranı
  olarak çalışır.

Tema renklerini kendi içinde tanımlar ve simgelerini yazı tipinden çizer; bu
yüzden ev dizininizdeki bir renk şemasına ya da simge temasına bağlı değildir.

### Arch Linux

Henüz bir AUR paketi yok. Yazı tipini kurup kurulum betiğini çalıştırın:

```sh
sudo pacman -S --needed ttf-jetbrains-mono-nerd
git clone https://github.com/lckt0/iris-greeter.git
cd iris-greeter
./install.sh
```

### Kurulum betiği

```sh
./install.sh                  # her şeyi kurar; giriş ekranını, kilit arka planını ve açılış ekranını seçer
./install.sh --sddm           # yalnızca giriş ekranı
./install.sh --lock           # yalnızca kilit ekranı dosyaları
./install.sh --no-select      # dosyaları kurar, mevcut seçimleri korur
./install.sh --no-splash      # açılış ekranına dokunmaz
./install.sh --activate-lock  # kilit ekranını da iris kabuk paketine geçirir
```

Betik sistem dizinleri için `sudo` kullanır. Önce `tools/check.sh`'i (lint ve
ekransız test çalıştırmaları) çalıştırır, ardından seçmeden önce kurulan SDDM
temasını gerçek karşılayıcıyla ekransız platformda doğrular. Önceki seçimleri
`~/.local/share/iris-greeter/previous.conf` dosyasına kaydeder; `uninstall.sh`
bunları geri yükler.

Sol üst köşedeki yazı varsayılan olarak `kullanıcı@makine` biçimindedir;
`IRIS_CAPTION="..." ./install.sh` ile değiştirebilirsiniz.

Paketleri kopyalamanın yanında normal bir kurulumun değiştirdikleri:

```
/etc/sddm.conf.d/kde_settings.conf   [Theme] Current=iris
~/.config/kscreenlockerrc            [Greeter] WallpaperPlugin=org.lckt0.iris (+ başlık)
~/.config/ksplashrc                  [KSplash] Theme=org.lckt0.iris
```

### Elle kurulum

```sh
sudo install -d /usr/share/sddm/themes/iris
sudo install -m644 sddm/*.qml sddm/metadata.desktop sddm/theme.conf sddm/preview.png /usr/share/sddm/themes/iris/

sudo install -d /usr/share/plasma/shells/iris/contents/lockscreen
sudo install -m644 lockscreen/metadata.json /usr/share/plasma/shells/iris/
sudo install -m644 lockscreen/contents/lockscreen/*.qml lockscreen/contents/lockscreen/qmldir \
    lockscreen/contents/lockscreen/config.xml /usr/share/plasma/shells/iris/contents/lockscreen/

mkdir -p ~/.local/share/plasma/wallpapers/org.lckt0.iris ~/.local/share/plasma/look-and-feel/org.lckt0.iris
cp -rL wallpaper/. ~/.local/share/plasma/wallpapers/org.lckt0.iris/
cp -rL splash/. ~/.local/share/plasma/look-and-feel/org.lckt0.iris/
```

(`install` ve `cp -L`, `shared/` dizinine giden sembolik bağları izler.)
Başlığı `/usr/share/sddm/themes/iris/theme.conf` ve
`/usr/share/plasma/shells/iris/contents/lockscreen/Caption.qml` içinde ayarlayın.

Ardından parçaları seçin:

- **Giriş ekranı:** Sistem Ayarları → Renkler ve Temalar → Giriş Ekranı (SDDM) → **iris**
  ya da `sudo kwriteconfig6 --file /etc/sddm.conf.d/kde_settings.conf --group Theme --key Current iris`.
- **Kilit ekranı arka planı:** Sistem Ayarları → Ekran Kilitleme → Görünüm → duvar kağıdı türü **iris**.
- **Açılış ekranı:** Sistem Ayarları → Renkler ve Temalar → Açılış Ekranı → **iris**.

### Kilit ekranını etkinleştirme

Plasma'da kilit ekranı QML'i için bir yapılandırma anahtarı yoktur; Wayland'de
KWin'in `PLASMA_DEFAULT_SHELL` ortam değişkeninden okunur. `--activate-lock`
ile betik şu systemd kullanıcı eklentisini yazar (elle de oluşturup
`systemctl --user daemon-reload` çalıştırabilirsiniz):

```
~/.config/systemd/user/plasma-kwin_wayland.service.d/iris.conf
    [Service]
    Environment=PLASMA_DEFAULT_SHELL=iris
```

Bir sonraki girişte etkin olur. Değişkeni yalnızca KWin alır; masaüstü ve
panel düzeni etkilenmez. Kilit ekranı arayüzü bir gün yüklenemezse
`LockScreen.qml`, yalnızca QtQuick'e bağlı sade bir parola ekranına döner. En
kötü durumda bir TTY'ye geçip şunu çalıştırın:

```sh
rm ~/.config/systemd/user/plasma-kwin_wayland.service.d/iris.conf
loginctl unlock-session
```

## Kaldırma

```sh
./uninstall.sh              # her şeyi kaldırır, önceki seçimleri geri yükler
./uninstall.sh --lock-only  # yalnızca kilit ekranı eklentisini kaldırır
```

`uninstall.sh` kilit ekranı eklentisini kaldırır; SDDM'i, kilit ekranı duvar
kağıdını ve açılış ekranını kurulumdan önceki seçimlere döndürür (kayıt yoksa
Breeze, `org.kde.image` ve `org.kde.breeze.desktop`) ve kurulan paketleri
siler.

Aynısını elle yapmak için:

```sh
rm -f ~/.config/systemd/user/plasma-kwin_wayland.service.d/iris.conf
systemctl --user daemon-reload

sudo kwriteconfig6 --file /etc/sddm.conf.d/kde_settings.conf --group Theme --key Current breeze
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image
kwriteconfig6 --file ksplashrc --group KSplash --key Theme org.kde.breeze.desktop

sudo rm -rf /usr/share/sddm/themes/iris /usr/share/plasma/shells/iris
rm -rf ~/.local/share/plasma/wallpapers/org.lckt0.iris \
       ~/.local/share/plasma/look-and-feel/org.lckt0.iris \
       ~/.local/share/iris-greeter
```

Giriş ekranı bir sonraki karşılayıcıda, kilit ekranı bir sonraki girişte değişir.

## howdy notları

- **Giriş ekranı:** SDDM parolayı PAM'e en başta verdiği için yüz taraması
  istek üzerine başlar: boş alanda Enter'a basın ya da göz düğmesine tıklayın.
  Kendiliğinden başlamaz, çünkü başarısız bir tarama `pam_unix`'e düşer ve
  `pam_faillock` tarafından başarısız deneme sayılır.
- **Kilit ekranı:** ekran uyandırıldığında (herhangi bir tuş) tarama
  kendiliğinden başlar. Fareyi oynatmak ekranı uyandırmaz.
- İlerleme halkası `shared/Tokens.qml` içindeki `scanMs` kadar sürer; bunu
  `/etc/howdy/config.ini` içindeki `[video] timeout` değerine eşitleyin.
- Ekrandaki iletiler "face" yerine "iris" / "eye" der; ileti tablosu
  `shared/ScanStatus.qml` içindedir.

## Geliştirme

```sh
./tools/check.sh
```

Paketleri hazırlar, `qmllint` çalıştırır, giriş ve kilit ekranlarını sahte
SDDM / kscreenlocker nesneleriyle ekransız çizer ve kilit ekranının tuş
davranışı testlerini `qmltestrunner` ile çalıştırır. Gerçek karşılayıcı
ikililerini başlatan adımları atlamak için `IRIS_SKIP_GREETER=1` ayarlayın.

Yukarıdaki ekran görüntüleri `tools/mock.py` ve `tools/mock-lock.py` ile
oluşturulan sahte ortamlardan alındı:

```sh
python3 tools/mock.py /tmp/iris-mock file:///tmp/iris-shots
QT_QPA_PLATFORM=offscreen qml6 /tmp/iris-mock/Main.qml
```

Düzen:

```
shared/      Tokens, Caption, Backdrop, IrisScanner, ScanStatus,
             PasswordField, GlyphButton
sddm/        Main.qml, theme.conf, metadata.desktop   (shared/ içine sembolik bağlar)
lockscreen/  LockScreen, LockScreenUi, FallbackUi, PasswordSync
wallpaper/   stok kilit ekranı için arka plan
splash/      açılış ekranı
tools/       denetimler, sahte ortamlar ve testler
```

## Lisans

LGPL-2.0-or-later. Bkz. [LICENSE](LICENSE).
