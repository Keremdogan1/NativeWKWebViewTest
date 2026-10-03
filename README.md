# NativeWKWebViewTest (V3 Modular Browser-Engine Architecture)

Bağımsız, saf Swift ve `WebKit.framework` (`WKWebView`) yerel tarayıcı motoru test harness'ı ve modüler tarayıcı motoru soyutlaması.

Bu projenin temel amacı, **Windows PC'den GitHub → Codemagic CI/CD → macOS/Xcode → iPadOS** zinciri üzerinden derlenip, ileride Obsidian için geliştirilecek native browser overlay mimarisinin teknik fizibilitesini canlı iPad üzerinde doğrulamaktır.

---

## 1. V3 Modüler Mimari Genel Bakış

V3 sürümü ile birlikte monolitik `ViewController.swift` yapısı, gelecekte Obsidian Community Plugin (JS/Capacitor Bridge) ile doğrudan entegre edilebilecek temiz bir **Browser Engine** katmanına dönüştürülmüştür.

```text
Obsidian Community Plugin (Gelecekteki hedef)
        │
        │ JS / Native Bridge
        ▼
   NativeBrowser (V3 Çekirdeği)
   ├── BrowserState (Konsolide Equatable State)
   ├── BrowserNavigationDelegate (Ağ, Güvenlik, Header Denetimi)
   ├── BrowserUIDelegate (Popup Yakalama, JS Dialogları)
   └── BrowserLogger (Filtrelenebilir Teşhis Sistemi)
        │
        ▼
    WKWebView (WebKit / UIKit)
```

---

## 2. Dizin Yapısı

```text
NativeWKWebViewTest/
├── NativeWKWebViewTest.xcodeproj/
│   ├── project.pbxproj                           # Xcode proje dosyası (Modüler Browser grubu ekli)
│   └── xcshareddata/
│       └── xcschemes/
│           └── NativeWKWebViewTest.xcscheme      # CI/CD için paylaşımlı build şeması
├── NativeWKWebViewTest/
│   ├── Browser/                                  # V3 Modüler Tarayıcı Motoru
│   │   ├── NativeBrowser.swift                   # WKWebView sarmalayıcı ve public API
│   │   ├── BrowserState.swift                    # BrowserState, BrowserEvent, Politikalar
│   │   ├── BrowserNavigationDelegate.swift       # WKNavigationDelegate implementasyonu
│   │   ├── BrowserUIDelegate.swift               # WKUIDelegate implementasyonu & Dialog protokolü
│   │   └── BrowserLogger.swift                   # Thread-safe teşhis loglama motoru
│   ├── AppDelegate.swift                         # iOS uygulama yaşam döngüsü
│   ├── SceneDelegate.swift                       # Programmatik UIWindow & NavigationController
│   ├── ViewController.swift                      # Test Harness UI (NativeBrowser tüketicisi)
│   └── Info.plist                                # Güvenlik & Scene tanımları
├── codemagic.yaml                                # Codemagic macOS M2 build konfigürasyonu
├── CODEMAGIC_SETUP.md                            # Codemagic paneli adım adım kurulum rehberi
└── README.md                                     # Proje dokümantasyonu
```

---

## 3. NativeBrowser Public API

`NativeBrowser` sınıfı, `WKWebView`'ı doğrudan UI koduna bağımlı olmaktan çıkarır ve şu temiz arayüzü sunar:

```swift
// Gezinme ve Kontrol
open(url: URL)
open(urlString: String)
close()
back()
forward()
reload()
getState() -> BrowserState

// Yerleşim ve Görünürlük (Gelecekteki Obsidian Overlay için)
setFrame(_ frame: CGRect)
setVisible(_ visible: Bool)

// Politikalar
setTargetBlankPolicy(_ policy: TargetBlankPolicy) // .rerouteSameView | .block
setCustomSchemePolicy(_ policy: CustomSchemePolicy) // .observeOnly | .blockExternal

// İki Yönlü Etkileşim & Depolama
evaluateJavaScript(script, completion:)
inspectCookies(completion:)
clearWebsiteData(completion:)

// Reaktif Durum ve Olay Dinleyicileri
var onStateChanged: ((BrowserState) -> Void)?
var onEvent: ((BrowserEvent) -> Void)?
```

---

## 4. Korunan WKWebView Davranışları ve Sınır Durumlar

1. **Ağ ve Güvenlik Denetimi (`BrowserNavigationDelegate`):**
   * İstek tipi ayrıştırması (`linkActivated`, `formSubmitted`, `backForward`, `reload`, `formResubmitted`, `other`).
   * HTTP yanıt kodu (`200`, `301`, `302`, `404` vb.) ve MIME type loglaması.
   * Sunucu güvenlik başlıkları (`X-Frame-Options`, `Content-Security-Policy`, `Set-Cookie`) denetimi. *(X-Frame-Options ve CSP frame-ancestors direktifleri yalnızca bir dokümanın iframe/frame içine embed edilmesini kısıtlar; top-level browsing context navigasyonunda bu kısıtlamalar semantik olarak işletilmez. Bu log, iframe ile top-level WKWebView arasındaki temel mimari farkı somut olarak belgeler).*
   * Sunucu yönlendirme takibi (`didReceiveServerRedirectForProvisionalNavigation`).
   * SSL & Sunucu sertifikası kimlik doğrulama zorlukları (`didReceive challenge`).

2. **Çöküş Dayanıklılığı (Crash Resiliency):**
   * `webContentProcessDidTerminate` yakalanır.
   * İlk OOM/çöküşte otomatik `reload()` denenir.
   * 3 saniye içinde peş peşe çöküş yaşanırsa CPU/çöküş kilitlenmesini engellemek için otomatik yeniden yükleme durdurulur (`RAPID CRASH LOOP DETECTED`).

3. **Popup (`target="_blank"`, `window.open()`) Yakalama ve Sınırlamaları:**
   * `BrowserUIDelegate.createWebViewWith` yeni sekme isteklerini yakalar ve `rerouteSameView` modunda isteği mevcut sayfada açar.
   * **Önemli Sınır Durum:** Bu yaklaşım standart GET navigasyonları için eksiksiz çalışır; ancak dinamik script ile açılan (`window.open('', '_blank')`) veya `POST` gövdesi içeren form popup'larında form verileri kaybolabilir. Gelecekte tam tab yönetimi gerektiğinde bu istekler ayrı bir `WKWebView` örneğine yönlendirilmelidir.

---

## 5. Mac Olmadan Doğrulanabilenler vs. Gerçek iPad Gerektirenler

### Mac Olmadan (Windows + Codemagic) Doğrulanabilenler:
* ✅ Xcode proje yapısının (`.pbxproj`) ve yeni `Browser` modül grubunun sözdizimsel geçerliliği.
* ✅ Swift kodlarının Apple `clang`/`swiftc` derleyicisinde sıfır hata ile derlenmesi.
* ✅ Codemagic üzerinde ARM64 mimarisi için derleme başarısı.
* ✅ Üretilen `NativeWKWebViewTest.ipa` arşivinin geçerli Mach-O ARM64 ikilisi ve unsigned paket yapısı içermesi.

### Yalnızca Gerçek iPad'de Doğrulanabilecek Davranışlar:
* 🔍 **Universal Link Handoff:** `youtube.com` üzerinde bir videoya tıklandığında iOS SpringBoard'un native YouTube uygulamasını açıp açmayacağı veya webview içinde tutup tutamayacağı.
* 🔍 **Google Oturumu:** Google hesap girişinde WebKit'in güvenlik denetimi (`disallowed_useragent` uyarısı verip vermeyeceği).
* 🔍 **Mega.nz Kripto İndirme:** WebCrypto API ve Blob indirme yeteneklerinin WebKit üzerinde iPadOS'ta nasıl tepki verdiği.
* 🔍 **Donanım Hızlandırma:** Video oynatımı, tam ekran ve bellek kullanımının stabilitesi.

---

## 6. Codemagic Build Alma

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
