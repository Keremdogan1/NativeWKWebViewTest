# NativeWKWebViewTest

Bağımsız, yerel (native) Swift ve `WebKit.framework` (`WKWebView`) test uygulaması.

Bu projenin temel amacı, **Windows PC'den GitHub → Codemagic CI/CD → macOS/Xcode → iPadOS** zincirini test etmek ve ileride geliştirilecek Obsidian tarayıcı mimarisi için gerçek bir cihaz üzerinde WebKit'in gezinme, yönlendirme ve Universal Link davranışlarını deneysel olarak gözlemlemektir.

---

## 1. Proje Amacı ve Kapsamı

* **Obsidian'dan Bağımsız:** Mevcut Obsidian kurulumuna veya eklentilerine (`mobile-link-opener`, `runtime-inspector`) hiçbir müdahalede bulunmaz.
* **Saf Native Swift:** Hibrit framework (Flutter, React Native vb.) veya harici CocoaPods bağımlılığı içermez.
* **Deneysel Gözlem Aracı:** `WKNavigationDelegate` ve `WKUIDelegate` mekanizmalarını kullanarak şu eylemleri canlı olarak ekranda loglar:
  * `linkActivated`
  * `formSubmitted`
  * `backForward`
  * `reload`
  * `formResubmitted`
  * `other`
  * URL Şemaları (`http`, `https`, `vnd.youtube:`, `googlesearch:` vb.)
  * `target="_blank"` ve `window.open()` yakalama ve aynı webview'e yönlendirme.

---

## 2. Dizin Yapısı

```text
NativeWKWebViewTest/
├── NativeWKWebViewTest.xcodeproj/
│   ├── project.pbxproj                           # Windows'ta elle üretilmiş saf Xcode proje dosyası
│   └── xcshareddata/
│       └── xcschemes/
│           └── NativeWKWebViewTest.xcscheme      # CI/CD için paylaşımlı build şeması
├── NativeWKWebViewTest/
│   ├── AppDelegate.swift                         # iOS uygulama yaşam döngüsü
│   ├── SceneDelegate.swift                       # Programmatik UIWindow & NavigationController
│   ├── ViewController.swift                      # WKWebView + Toolbar + Canlı Log Konsolu
│   └── Info.plist                                # Güvenlik & Scene tanımları
├── codemagic.yaml                                # Codemagic macOS M2 build konfigürasyonu
├── CODEMAGIC_SETUP.md                            # Codemagic paneli adım adım kurulum rehberi
└── README.md                                     # Proje dokümantasyonu
```

---

## 3. Windows Ortamında Geliştirme Yaklaşımı

* Proje, macOS veya Xcode GUI kurulu olmayan bir Windows ortamında geliştirilmiştir.
* `.storyboard` veya `.xib` gibi Xcode sürüm farklılıklarında kırılabilen görsel dosyalar yerine, `ViewController.swift` içinde **%100 saf programmatik UIKit (AutoLayout)** kullanılmıştır.
* `NativeWKWebViewTest.xcodeproj/project.pbxproj` dosyası, Xcode 14/15/16 ile uyumlu standart PBX formatında (Sources, Resources, Frameworks, Shared Schemes) hatasız olarak yapılandırılmıştır.

---

## 4. Codemagic Üzerinde Build Alma

Proje, Codemagic'in ücretsiz planında yer alan **macOS M2 (`mac_mini_m2`)** sanal makinelerinde `xcodebuild` ile derlenir:

```bash
xcodebuild build \
  -project "NativeWKWebViewTest.xcodeproj" \
  -scheme "NativeWKWebViewTest" \
  -sdk iphoneos \
  -configuration Release \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Ardından üretilen `.app` paketi, `Payload` klasörüne kopyalanıp zip'lenerek kuruluma hazır bir **unsigned `.ipa` (`NativeWKWebViewTest.ipa`)** haline getirilir ve Codemagic Artifacts bölümünden indirilebilir.

---

## 5. Apple Developer Hesabı ve iPad'e Yükleme Yöntemleri

> **Önemli Gerçek:** Bu PoC'yi fiziksel iPad'inize yüklemek için **99$/yıl olan Ücretli Apple Developer Hesabı GEREKMEZ.**

### Yükleme Seçenekleri (Windows PC Kullanarak):

1. **Sideloadly (Önerilen - En Kolay):**
   * Windows bilgisayarınıza [Sideloadly](https://sideloadly.io/) kurun.
   * iPad'inizi USB kablosuyla bilgisayara bağlayın.
   * Codemagic'ten indirdiğiniz `NativeWKWebViewTest.ipa` dosyasını Sideloadly penceresine sürükleyin.
   * Ücretsiz Apple ID'nizi girip "Start" butonuna basın.
   * Sideloadly uygulamayı ücretsiz 7 günlük geliştirici sertifikasıyla imzalar ve doğrudan iPad'inize kurar.
   * iPad'de: *Ayarlar -> Genel -> VPN ve Aygıt Yönetimi* yolundan sertifikaya güven verin.
2. **AltServer / AltStore:**
   * Alternatif olarak ücretsiz Apple ID ile Windows üzerinden kablosuz kurulum sağlar.
3. **TrollStore:**
   * Desteklenen iOS sürümlerinde (CoreTrust açığı olan cihazlar) sertifika süresi olmadan kalıcı kurulum sağlar.

---

## 6. Canlı Cihazda Test Edilecek Kontrol Listesi

Uygulama iPad'de açıldığında alt kısımdaki yeşil renkli **Canlı Log Konsolu** izlenerek şu testler yapılacaktır:

| Test Senaryosu | Eylem | İncelenecek Gözlem |
| :--- | :--- | :--- |
| **T1: Google Arama** | `google.com` butonuna bas -> Bir arama yap | Arama sonuçları açılıyor mu? Logda `formSubmitted` veya `linkActivated` görünüyor mu? |
| **T2: YouTube Videosu** | `youtube.com` butonuna bas -> Bir videoya dokun | **En kritik test:** Video doğrudan WKWebView içinde oynatılıyor mu yoksa iPad'deki YouTube uygulaması mı açılıyor? |
| **T3: Mega İndirme** | `mega.nz` butonuna bas | WebCrypto, Blob ve arayüz render edilebiliyor mu? |
| **T4: target="_blank"** | Yeni sekme açan bir linke dokun | `[WKUIDelegate]` logu düşüp sayfayı aynı webview içinde tutuyor mu? |
| **T5: Geri / İleri** | `◀` ve `▶` butonlarını kullan | WebKit geçmişi (`canGoBack`, `canGoForward`) doğru işliyor mu? |
