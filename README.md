# NativeWKWebViewTest (V4.1 Modular Browser-Engine Architecture)

Bağımsız, saf Swift ve `WebKit.framework` (`WKWebView`) yerel tarayıcı motoru test harness'ı ve modüler tarayıcı motoru soyutlaması.

Bu projenin temel amacı, **Windows PC'den GitHub → Codemagic CI/CD → macOS/Xcode → iPadOS** zinciri üzerinden derlenip, ileride Obsidian için geliştirilecek native browser overlay mimarisinin teknik fizibilitesini canlı iPad üzerinde doğrulamaktır.

---

## 1. V4.1 Güvenlik İzolasyonu ve Mimari Genel Bakış

V4.1 sürümü, WebKit'in gelişmiş **`WKContentWorld`** izolasyon yeteneklerini devreye alarak web sitelerinin native kod ve gelecekteki Obsidian köprüsüyle olan etkileşimini güvenlik altına alır:

```text
Untrusted Web Sayfası (.page World)
    │
    ├─► console.log / warn / error  ──► [diagnosticConsole] ──► BrowserLogger
    │
    X  (Sayfa JS'i window.webkit.messageHandlers.nativeBridge'i GÖREMEZ)
    │
NativeBridge World (.world(name: "NativeBridge"))
    │
    └─► window.NativeEngine.postMessage() ──► [nativeBridge] ──► Frame & Origin Validation ──► NativeBrowser
```

### V4.1 Temel Güvenlik ve Konfigürasyon İlkeleri:
1. **`WKContentWorld` İzolasyonu:**
   * Sayfa içi logları yakalayan `diagnosticConsole` script'i `.page` dünyasında çalışır ve web sayfasının kendi `console` fonksiyonlarının çalışmasını bozmaz.
   * Native köprü (`window.NativeEngine`) ve `nativeBridge` message handler'ı yalnızca izole `WKContentWorld.world(name: "NativeBridge")` içinde tanımlıdır. Web sitesindeki üçüncü taraf JS scriptleri bu handler'ı tespit edemez veya doğrudan çağıramaz.
2. **Güvenlik Doğrulaması (Origin & Frame Validation):**
   * Message handler'a gelen her mesajda `message.world == nativeBridgeWorld`, `message.frameInfo.isMainFrame` ve `message.frameInfo.securityOrigin` kontrol edilir. Beklenmeyen bir frame veya dünyadan gelen mesajlar doğrudan reddedilir (`SECURITY REJECTED`).
3. **Merkezi Konfigürasyon:**
   * **Pencereler:** `preferences.javaScriptCanOpenWindowsAutomatically = true` ile açılır pencerelerin motor seviyesinde engellenmeyip `WKUIDelegate` tarafından yakalanması sağlandı.
   * **Tam Ekran:** iOS 15.4+ için `preferences.isElementFullscreenEnabled = true` etkinleştirildi.
   * **Sayfa Tercihleri:** `defaultWebpagePreferences.allowsContentJavaScript = true` ile modern web desteği korundu.
   * **Medya:** `allowsInlineMediaPlayback = true` ve `mediaTypesRequiringUserActionForPlayback = []` ile HTML5 video ve ses desteği güvenceye alındı.
   * **Depolama:** `WKWebsiteDataStore.default()` ile kalıcı çerez ve yerel depolama oturumları sürdürüldü.

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
│   ├── Browser/                                  # V4.1 Modüler Tarayıcı Motoru
│   │   ├── NativeBrowser.swift                   # WKWebView sarmalayıcı, WKContentWorld & public API
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
├── V4_WEBKIT_RESEARCH.md                         # Kapsamlı V4 araştırma ve yol haritası dokümanı
└── README.md                                     # Proje dokümantasyonu
```

---

## 3. NativeBrowser Public API

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
evaluateJavaScript(script, in: contentWorld, completion:)
inspectCookies(completion:)
clearWebsiteData(completion:)

// Reaktif Durum ve Olay Dinleyicileri
var onStateChanged: ((BrowserState) -> Void)?
var onEvent: ((BrowserEvent) -> Void)?
```

---

## 4. Korunan Davranışlar ve Sınır Durumlar

1. **Ağ ve Güvenlik Denetimi (`BrowserNavigationDelegate`):**
   * İstek tipi ayrıştırması (`linkActivated`, `formSubmitted`, `backForward`, `reload`, `formResubmitted`, `other`).
   * HTTP yanıt kodu (`200`, `301`, `302`, `404` vb.) ve MIME type loglaması.
   * Sunucu güvenlik başlıkları (`X-Frame-Options`, `Content-Security-Policy`, `Set-Cookie`) denetimi.
   * SSL & Sunucu sertifikası kimlik doğrulama zorlukları (`didReceive challenge`).
2. **Çöküş Dayanıklılığı (Crash Resiliency):**
   * `webContentProcessDidTerminate` yakalanır; ilk crash'te reload, 3 saniye içinde peş peşe crash yaşanırsa CPU kilidini engellemek için durdurma.
3. **Popup (`target="_blank"`, `window.open()`) Yakalama:**
   * `createWebViewWith` yeni sekme isteklerini yakalar; `rerouteSameView` modunda mevcut sayfada açar.
   * Dinamik script (`window.open('', '_blank')`) veya form POST verilerinin tam korunması V4.3 Multi-Tab havuzunda ele alınacaktır.
4. **Universal Links & App Handoff Durumu:**
   * Bu sürümde (V4.1) Universal Link bypass mekanizması henüz implement edilmemiştir; V4.4 kapsamında gerçek iPad üzerinde test edilecektir. Doğrulanmamış hiçbir varsayım kesin kabul edilmemiştir.

---

## 5. Codemagic Build Alma

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
