# NativeWKWebViewTest (V4.2 Modular Browser-Engine Architecture)

Bağımsız, saf Swift ve `WebKit.framework` (`WKWebView`) yerel tarayıcı motoru test harness'ı, modüler tarayıcı motoru soyutlaması ve yerel dosya indirme motoru.

Bu projenin temel amacı, **Windows PC'den GitHub → Codemagic CI/CD → macOS/Xcode → iPadOS** zinciri üzerinden derlenip, ileride Obsidian için geliştirilecek native browser overlay mimarisinin teknik fizibilitesini canlı iPad üzerinde doğrulamaktır.

---

## 1. V4.2 Yerel İndirme Motoru ve Mimari Genel Bakış

V4.2 sürümü, WebKit'in resmi **`WKDownload`** API ailesini ve izole **`BrowserDownloadManager`** katmanını sisteme kazandırır:

```text
Kullanıcı Linke Tıklar / Sunucu Dosya Sunar
               │
               ▼
BrowserNavigationDelegate: decidePolicyFor navigationResponse
  ├── canShowMIMEType == false ?
  ├── Content-Disposition: attachment ?
  └── Binary dosya uzantıları (.zip, .pdf, .bin vb.) ?
               │
               ├─► [Standart Sayfa]      ──► decisionHandler(.allow)
               │
               └─► [İndirilebilir Dosya] ──► decisionHandler(.download)
                                                   │
                                                   ▼
                                     BrowserDownloadManager (WKDownloadDelegate)
                                       ├── Filename Sanitization & Path Traversal Koruması
                                       ├── Hedef: Documents/Downloads (Güvenli Sandbox)
                                       ├── Çakışma Önleme (notes.txt -> notes (1).txt)
                                       ├── Progress KVO Observation (\.fractionCompleted)
                                       ├── HTTP Redirection & Auth Challenge Desteği
                                       └── BrowserEvent (.downloadStarted / .downloadCompleted vb.)
```

### V4.2 Temel Yenilikleri:
1. **`WKDownload` & `WKDownloadDelegate` Entegrasyonu:**
   * `decidePolicyFor navigationResponse` içinde WebKit'in doğrudan render edemediği MIME tipleri veya `Content-Disposition: attachment` başlığı taşıyan yanıtlar otomatik olarak `decisionHandler(.download)` kararıyla yakalanır.
   * `webView(_:navigationResponse:didBecome:)` delegasyonu üzerinden gelen `WKDownload` nesnesi `BrowserDownloadManager` tarafından yönetilir.
2. **iOS Sandbox ve Dosya Güvenliği:**
   * Dosyalar güvenli `<App_Home>/Documents/Downloads/` dizinine yazılır.
   * Path traversal saldırılarına (`../`, `..\`) ve null byte enjeksiyonlarına karşı sıkı dosya adı sanitizasyonu uygulanır.
   * Çakışan dosya isimlerinde otomatik indeksleme (`dosya (1).ext`) yapılır; mevcut dosyaların üzerine kazara yazılmaz.
   * Nihai hedefin sandboxed indirme dizini dışına taşmadığı `standardizedFileURL.path` ile doğrulanır.
3. **İlerleme Takibi ve İptal:**
   * `WKDownload.progress` (`Progress`) üzerinden KVO ile anlık yüzde hesaplanır.
   * `cancelDownload(id:)` API'si ile devam eden indirmeler iptal edilebilir ve yarım kalan dosyalar temizlenir.
4. **V4.1 Güvenlik İzolasyonunun Korunması:**
   * `WKContentWorld.world(name: "NativeBridge")` ve `.page` dünyası ayrımı, `frameInfo.securityOrigin` kontrolleri ve kalıcı çerez/depolama mimarisi aynen korunmaktadır.

---

## 2. Dizin Yapısı

```text
NativeWKWebViewTest/
├── NativeWKWebViewTest.xcodeproj/
│   ├── project.pbxproj                           # Xcode proje dosyası (Browser modülü ve Download motoru kayıtlı)
│   └── xcshareddata/
│       └── xcschemes/
│           └── NativeWKWebViewTest.xcscheme      # CI/CD için paylaşımlı build şeması
├── NativeWKWebViewTest/
│   ├── Browser/                                  # V4.2 Modüler Tarayıcı Motoru
│   │   ├── NativeBrowser.swift                   # WKWebView sarmalayıcı, WKContentWorld & public API
│   │   ├── BrowserState.swift                    # BrowserState, BrowserEvent, Politikalar
│   │   ├── BrowserDownload.swift                 # BrowserDownload modeli ve DownloadState
│   │   ├── BrowserDownloadManager.swift          # WKDownloadDelegate & dosya sistemi yöneticisi
│   │   ├── BrowserNavigationDelegate.swift       # WKNavigationDelegate & Download kararları
│   │   ├── BrowserUIDelegate.swift               # WKUIDelegate implementasyonu & Dialog protokolü
│   │   └── BrowserLogger.swift                   # Thread-safe teşhis loglama motoru
│   ├── AppDelegate.swift                         # iOS uygulama yaşam döngüsü
│   ├── SceneDelegate.swift                       # Programmatik UIWindow & NavigationController
│   ├── ViewController.swift                      # Test Harness UI (NativeBrowser & Download testleri)
│   └── Info.plist                                # Güvenlik & Scene tanımları
├── codemagic.yaml                                # Codemagic macOS M2 build konfigürasyonu
├── CODEMAGIC_SETUP.md                            # Codemagic paneli adım adım kurulum rehberi
├── V4_WEBKIT_RESEARCH.md                         # Kapsamlı V4 araştırma ve yol haritası dokümanı
├── V4.2_DOWNLOAD_RESEARCH.md                     # V4.2 WKDownload teknik araştırma dokümanı
└── README.md                                     # Proje dokümantasyonu
```

---

## 3. NativeBrowser Public API (V4.2)

```swift
// Gezinme ve Kontrol
open(url: URL)
open(urlString: String)
close()
back()
forward()
reload()
getState() -> BrowserState

// İndirme Motoru Kontrolleri
var downloadManager: BrowserDownloadManager { get }
getDownloads() -> [BrowserDownload]
cancelDownload(id: UUID)

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
   * Sunucu güvenlik başlıkları (`X-Frame-Options`, `Content-Security-Policy`, `Set-Cookie`, `Content-Disposition`) denetimi.
   * SSL & Sunucu sertifikası kimlik doğrulama zorlukları (`didReceive challenge`).
2. **Çöküş Dayanıklılığı (Crash Resiliency):**
   * `webContentProcessDidTerminate` yakalanır; ilk crash'te reload, 3 saniye içinde peş peşe crash yaşanırsa CPU kilidini engellemek için durdurma.
3. **Popup (`target="_blank"`, `window.open()`) Yakalama:**
   * `createWebViewWith` yeni sekme isteklerini yakalar; `rerouteSameView` modunda mevcut sayfada açar.
4. **Universal Links & App Handoff Durumu:**
   * Bu sürümde (V4.2) Universal Link bypass mekanizması henüz implement edilmemiştir; V4.4 kapsamında gerçek iPad üzerinde test edilecektir.

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
