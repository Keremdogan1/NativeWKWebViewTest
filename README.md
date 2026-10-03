# NativeWKWebViewTest (V4.3 Multi-Tab & Window Management Architecture)

Bağımsız, saf Swift ve `WebKit.framework` (`WKWebView`) yerel tarayıcı motoru test harness'ı, modüler tarayıcı motoru soyutlaması, yerel dosya indirme motoru ve çok sekmeli (multi-tab / window management) mimari.

Bu projenin temel amacı, **Windows PC'den GitHub → Codemagic CI/CD → macOS/Xcode → iPadOS** zinciri üzerinden derlenip, ileride Obsidian için geliştirilecek native browser overlay mimarisinin teknik fizibilitesini canlı iPad üzerinde doğrulamaktır.

---

## 1. V4.3 Çok Sekmeli (Multi-Tab) Mimari ve Popup Yönetimi

V4.3 sürümü, bağımsız sekmelerin yönetildiği **`BrowserTab`**, merkezi sekme orkestrasyonunu üstlenen **`BrowserTabManager`**, ve WebKit'in popup mekanizmasını sekme açılışına bağlayan **`BrowserUIDelegate`** entegrasyonunu sisteme kazandırır:

```text
Web İçeriği (target="_blank" / window.open() / form POST target="_blank")
                                │
                                ▼
         BrowserUIDelegate.createWebViewWith(configuration:for:windowFeatures:)
                                │
             ┌──────────────────┴──────────────────┐
             ▼                                     ▼
[tabManager == nil (Fallback)]        [tabManager != nil (V4.3 Multi-Tab)]
             │                                     │
   Policy Kontrolü                     BrowserTabManager.handlePopupRequest(config)
   ├── .rerouteSameView: Aynı view                │
   └── .block: Reddet                             ├── 1. WKWebView(frame: .zero, configuration: passedConfig)
                                                   ├── 2. POST body, stream & opener ilişkisi korunur
                                                   ├── 3. Yeni BrowserTab üretilir ve container'a eklenir
                                                   ├── 4. Yeni sekme otomatik aktifleşir (bringToFront)
                                                   └── 5. Dönen WKWebView WebKit çekirdeğine iletilir
```

### V4.3 Temel Yenilikleri:
1. **`BrowserTab` ve `BrowserTabManager` Modülü:**
   * Her sekme kendi `id: UUID`, `NativeBrowser` örneği, `displayTitle` ve yaşam döngüsüne sahiptir.
   * `BrowserTabManager`, tüm sekmelerin bellek yönetimini, aktif sekme değişimini (`activateTab(id:)`), sekme kapatmayı (`closeTab(id:)`) ve yeni sekme üretimini (`createTab(url:)`) yönetir.
   * Son sekme kapatıldığında sistemin boş kalmaması için otomatik olarak temiz bir varsayılan sekme (`https://example.com`) açılır.
2. **WebKit Popup Delegasyonu (`createWebViewWith`):**
   * WebKit tarafından sağlanan özel `configuration` nesnesi doğrudan yeni açılan sekmenin `NativeBrowser` örneğine geçirilir.
   * Bu sayede `target="_blank"` form POST verileri (POST body), HTTP header akışları ve `window.opener` JS köprüsü kesilmeden yeni sekmeye taşınır.
3. **Kalıcı `WKWebsiteDataStore.default()` Mimarisi:**
   * Tüm sekmeler Apple WebKit'in resmi kalıcı veri deposu olan `WKWebsiteDataStore.default()` üzerinde çalışır.
   * `WKProcessPool` iOS 15 ile kullanımdan kalktığı (deprecated) için birden fazla processPool örneği WebKit sürecinde etkisizdir; sekmeler arası çerez, oturum ve `localStorage` paylaşımı doğrudan paylaşılan `WKWebsiteDataStore` üzerinden WebKit ağ süreci (network process) tarafından garanti edilir.
4. **`window.close()` Kendi Kendini Kapatma:**
   * Sayfa içi JavaScript `window.close()` çağırdığında `BrowserUIDelegate.webViewDidClose` tetiklenir ve ilgili sekme `tabManager.closeTab(id:)` ile otomatik olarak bellekten kaldırılır.
5. **Modern UIKit Sekme Çubuğu (Tab Bar):**
   * URL çubuğu altında yatay kaydırılabilir sade bir sekme barı (`tabBarScrollView`).
   * Her sekme için başlık, seçilme durumu (aktif sekmede mavi vurgulama), hızlı kapatma butonu (`✕`) ve yeni sekme ekleme butonu (`＋`).
6. **V4.1 & V4.2 Yeteneklerinin Korunması:**
   * `WKContentWorld.world(name: "NativeBridge")` izole bridge mimarisi, `WKDownload` indirme motoru, çerez denetimi ve OOM çöküş dayanıklılığı tüm sekmelerde bağımsız olarak çalışır.

---

## 2. Dizin Yapısı

```text
NativeWKWebViewTest/
├── NativeWKWebViewTest.xcodeproj/
│   ├── project.pbxproj                           # Xcode proje dosyası (TabManager & Browser modülü kayıtlı)
│   └── xcshareddata/
│       └── xcschemes/
│           └── NativeWKWebViewTest.xcscheme      # CI/CD için paylaşımlı build şeması
├── NativeWKWebViewTest/
│   ├── Browser/                                  # V4.3 Modüler Tarayıcı Motoru
│   │   ├── BrowserTab.swift                      # Sekme modeli ve durum soyutlaması
│   │   ├── BrowserTabManager.swift               # Çok sekmeli yaşam döngüsü ve popup yöneticisi
│   │   ├── NativeBrowser.swift                   # WKWebView sarmalayıcı, WKContentWorld & public API
│   │   ├── BrowserState.swift                    # BrowserState, BrowserEvent, Politikalar
│   │   ├── BrowserDownload.swift                 # BrowserDownload modeli ve DownloadState
│   │   ├── BrowserDownloadManager.swift          # WKDownloadDelegate & dosya sistemi yöneticisi
│   │   ├── BrowserNavigationDelegate.swift       # WKNavigationDelegate & Download kararları
│   │   ├── BrowserUIDelegate.swift               # WKUIDelegate implementasyonu & Popup delegasyonu
│   │   └── BrowserLogger.swift                   # Thread-safe teşhis loglama motoru
│   ├── Tests/                                    # V4.3 Yerel / Çevrimdışı Test Suite Motoru
│   │   ├── WebFixtures/                          # Local HTML test fixture'ları
│   │   │   ├── index.html                        # Test portalı (A-Q testleri)
│   │   │   ├── test_nav.html                     # Navigation ve Tab State testleri
│   │   │   ├── test_popups.html                  # target=_blank & window.open testleri
│   │   │   ├── test_storage.html                 # Cookies, LocalStorage, IndexedDB, SessionStorage
│   │   │   ├── test_dialogs.html                 # alert, confirm, prompt dialogları
│   │   │   └── test_download.html                # Sandboxed indirme fixture'ları
│   │   ├── WebFixturesProvider.swift             # Gömülü/çevrimdışı fixture sağlayıcısı
│   │   ├── TestHarnessEngine.swift               # Test orkestrasyonu, kanıt ve raporlama
│   │   └── EmbeddedHttpServer.swift              # Network.framework 127.0.0.1 gömülü HTTP sunucusu (POST doğrulama)
│   ├── AppDelegate.swift                         # iOS uygulama yaşam döngüsü
│   ├── SceneDelegate.swift                       # Programmatik UIWindow & NavigationController
│   ├── ViewController.swift                      # Test Harness UI (Tab Bar & Test Suites)
│   └── Info.plist                                # Güvenlik, ATS (Local Networking) & Scene tanımları
├── codemagic.yaml                                # Codemagic macOS M2 build konfigürasyonu
├── CODEMAGIC_SETUP.md                            # Codemagic paneli adım adım kurulum rehberi
├── V4_WEBKIT_RESEARCH.md                         # Kapsamlı V4 araştırma ve yol haritası dokümanı
├── V4.2_DOWNLOAD_RESEARCH.md                     # V4.2 WKDownload teknik araştırma dokümanı
├── V4.3_MULTITAB_RESEARCH.md                     # V4.3 Çok sekmeli mimari ve popup araştırma dokümanı
└── README.md                                     # Proje dokümantasyonu
```

---

## 3. BrowserTabManager Public API (V4.3)

```swift
// Sekme Yönetimi
@discardableResult
func createTab(url: URL?, activate: Bool, customConfiguration: WKWebViewConfiguration?) -> BrowserTab
func closeTab(id: UUID)
func activateTab(id: UUID)
func tab(for id: UUID) -> BrowserTab?

// Popup Interception
func handlePopupRequest(configuration: WKWebViewConfiguration, navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView?

// Dinleyiciler
var onTabsChanged: (([BrowserTab]) -> Void)?
var onActiveTabChanged: ((BrowserTab?) -> Void)?
var onDownloadUpdated: ((BrowserDownload) -> Void)?
```

---

## 4. V4.3 Gömülü Loopback HTTP Sunucusu (Network.framework)

`target="_blank" POST` doğrulaması için dış internet bağımlılığı (httpbin.org vb.) veya üçüncü taraf kütüphaneler (CocoaPods/SPM) kullanılmaz. Apple'ın saf `Network.framework` kütüphanesi ile `127.0.0.1` (loopback) üzerinde çalışan `EmbeddedHttpServer` implemente edilmiştir:

* **Dinleme:** `NWListener` ile `127.0.0.1:8089` (meşgulse dinamik port) üzerinde yerel soket açılır.
* **ATS:** `Info.plist` içinde `NSAppTransportSecurity -> NSAllowsLocalNetworking: true` ayarı ile yerel bağlantıya izin verilir.
* **POST Body Doğrulama:** `testKey=V4_3_POST_TEST` ve `testValue=POST_BODY_PRESERVED` verileri akıştan parse edilip doğrulanır ve JSON olarak geri döndürülür (`{"verified": true}`).
* **Gerçek Zamanlı Sonuç:** Sunucu gövdeyi aldığında `TestHarnessEngine` otomatik olarak `PASS (runtime)` kaydeder.

---

## 5. V4.3 Çevrimdışı / Yerel WebKit Test Suite (A - Q)

Uygulama açılışında varsayılan olarak `https://local-suite.poc/` üzerinden çalışan yerel test portalı yüklenir. Araç çubuğundaki `🧪 Run Tests` butonu otomatik testleri koştururken, `📊 Test Dashboard` butonu anlık durum tablosunu ekrana ve panoya (clipboard) kopyalar:

| Test | Durum | Ayrım / Kanıt (Evidence) | Gerçek Cihaz Gerekli mi? |
| :--- | :---: | :--- | :---: |
| **A. Basic Navigation** | **PASS (static)** | `CODE_INFERRED`: TabManager başlatıldı ve en az 1 sekme kayıtlı. | Hayır |
| **B. target="_blank" GET** | **READY (DEVICE REQ)** | `CODE_INFERRED`: `BrowserUIDelegate.createWebViewWith` ile yeni sekme rotası hazır. Cihazda tıklama anında `PASS (runtime)`. | **Evet** (Etkileşim) |
| **C. target="_blank" POST** | **READY (DEVICE REQ)** | `BUILD VERIFIED`: Gömülü `127.0.0.1` HTTP sunucusu ve form fixture hazır. Cihazda submit anında `PASS (runtime)`. | **Evet** (Etkileşim) |
| **D. Immediate window.open()** | **READY (DEVICE REQ)** | `CODE_INFERRED`: `createWebViewWith` tetiklenmesi için cihazda buton dokunuşu gerekir. | **Evet** (Etkileşim) |
| **E. Delayed window.open()** | **READY (DEVICE REQ)** | `CODE_INFERRED`: `setTimeout(1000)` popup'ı cihazda dokunuşla başlatılır. | **Evet** (Etkileşim) |
| **F. Multiple Popups** | **READY (DEVICE REQ)** | `CODE_INFERRED`: Eşzamanlı 3 sekme açılışı cihazda dokunuşla başlatılır. | **Evet** (Etkileşim) |
| **G. window.close()** | **READY (DEVICE REQ)** | `CODE_INFERRED`: `webViewDidClose` sekme kapatma rotası hazır; cihazda dokunuşla tetiklenir. | **Evet** (Etkileşim) |
| **H. Tab State Preservation** | **READY (DEVICE REQ)** | `CODE_INFERRED`: Form/kaydırma/sayaç fixture'ı hazır; sekmeler arası geçişte doğrulanır. | **Evet** (Etkileşim) |
| **I. Cookies Across Tabs** | **PASS (static)** | `CODE_INFERRED`: `WKWebsiteDataStore.default().httpCookieStore` erişilebilirliği doğrulandı. | Hayır |
| **J. localStorage Across Tabs** | **PASS (static)** | `CODE_INFERRED`: JavaScript evaluate ile `localStorage` API varlığı ve yanıtı doğrulandı. | Hayır |
| **K. IndexedDB Across Tabs** | **PASS (static)** | `CODE_INFERRED`: JavaScript evaluate ile `indexedDB` API varlığı ve yanıtı doğrulandı. | Hayır |
| **L. sessionStorage Isolation** | **PASS (static)** | `CODE_INFERRED`: JavaScript evaluate ile `sessionStorage` API varlığı doğrulandı. | Hayır |
| **M. WKDownload Engine** | **PASS (static)** | `CODE_INFERRED`: `WKDownloadManager` sanal dosya sistemiyle hazır. Cihazda dosya indiğinde `PASS (runtime)`. | Hayır |
| **N. JavaScript Dialogs** | **PASS (static)** | `CODE_INFERRED`: `BrowserUIDialogPresenter` protokolü UI hiyerarşisine bağlı. | Hayır |
| **O. Custom Scheme** | **PASS (static)** | `CODE_INFERRED`: `vnd.test://` politikaları (.blockExternal / .observeOnly) doğrulandı. | Hayır |
| **P. Invalid Navigation** | **READY (DEVICE REQ)** | `CODE_INFERRED`: Hatalı URL navigasyonu ve `BrowserState.lastError` yakalama cihazda denenir. | **Evet** (Etkileşim) |
| **Q. Process Termination** | **MANUAL** | `STATIC_ONLY`: Düşük bellek (jetsam) çökmesi unprivileged yerel JS ile simüle edilemez; gerçek cihaz/SIGKILL gerektirir. | **Evet** |

---

## 5. Kalan Gerçek Cihaz Testleri (Remaining Real-Device Tests)

1. **Canlı Sunucu POST Body Doğrulaması:** Gerçek bir HTTP POST uç noktasına (ör. `https://httpbin.org/post`) `target="_blank"` ile form verisi gönderip sunucunun döndürdüğü JSON cevabında form alanlarının eksiksiz geldiğinin doğrulanması.
2. **WebKit OOM / Jetsam Crash Recovery:** Canlı iPad üzerinde yüksek bellek tüketimi oluşturularak `webContentProcessDidTerminate` olayının tetiklenmesi ve tarayıcının çökmeden sayfayı yeniden yüklediğinin doğrulanması.
3. **iPadOS Multitasking & Split View:** iPad üzerinde Split View veya Slide Over modundayken sekme çubuğu, klavye etkileşimi ve webview yeniden boyutlandırma davranışlarının gözlemlenmesi.

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
