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
│   ├── AppDelegate.swift                         # iOS uygulama yaşam döngüsü
│   ├── SceneDelegate.swift                       # Programmatik UIWindow & NavigationController
│   ├── ViewController.swift                      # Test Harness UI (Tab Bar & Test Suites)
│   └── Info.plist                                # Güvenlik & Scene tanımları
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

## 4. V4.3 Çok Sekmeli Test Sayfası Özellikleri

`📑 Test Multi-Tab` butonu tıklandığında aşağıdaki test senaryolarını içeren özel yerel harness yüklenir:
1. **Standart `target="_blank"`:** Bağlantının yeni bir sekmede açılması.
2. **`window.open()` (Anlık):** Kullanıcı tıklamasıyla senkron popup sekmesi oluşturma.
3. **`window.open()` (1000ms Gecikmeli):** Asenkron zamanlayıcı (`setTimeout`) ardından WebKit popup yakalama kontrolü.
4. **Form POST to New Tab:** `method="POST"` ve `target="_blank"` ile gönderilen form verisinin (POST body) yeni sekmeye taşınması.
5. **Shared Storage & Cookies:** Bir sekmede yazılan `localStorage` ve `document.cookie` verisinin diğer sekmelerde okunabilmesi.
6. **`window.close()`:** Sayfa içi script ile aktif sekmenin kendini kapatabilmesi.

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
