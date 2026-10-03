# NativeWKWebViewTest (V2 Browser-Engine PoC)

Bağımsız, saf Swift ve `WebKit.framework` (`WKWebView`) yerel tarayıcı motoru test harness'ı.

Bu projenin temel amacı, **Windows PC'den GitHub → Codemagic CI/CD → macOS/Xcode → iPadOS** zinciri üzerinden derlenip, ileride Obsidian için geliştirilecek native browser overlay mimarisinin teknik fizibilitesini canlı iPad üzerinde doğrulamaktır.

---

## 1. V2 Browser-Engine Yenilikleri

Bu sürüm (V2), basit bir webview açılışının ötesine geçerek native WebKit tarayıcı motoru yeteneklerini sistematik olarak denetleyen eksiksiz bir test harness'ına dönüştürülmüştür:

1. **Derin Ağ ve HTTP Yanıt Denetimi (`WKNavigationDelegate`):**
   * İstek tipi ayrıştırması (`linkActivated`, `formSubmitted`, `backForward`, `reload`, `formResubmitted`, `other`).
   * HTTP yanıt kodu (`200`, `301`, `302`, `404` vb.) ve MIME type loglaması.
   * Sunucu güvenlik başlıkları (`X-Frame-Options`, `Content-Security-Policy`, `Set-Cookie`) denetimi. *(X-Frame-Options ve CSP frame-ancestors direktifleri yalnızca bir dokümanın iframe/frame içine embed edilmesini kısıtlar; top-level browsing context navigasyonunda bu kısıtlamalar semantik olarak işletilmez. Bu log, iframe ile top-level WKWebView arasındaki temel mimari farkı somut olarak belgeler).*
   * Sunucu yönlendirme takibi (`didReceiveServerRedirectForProvisionalNavigation`).
   * SSL & Sunucu sertifikası kimlik doğrulama zorlukları (`didReceive challenge`).
   * WebContent işlem çökmesi ve bellek tükenmesi kurtarması (`webContentProcessDidTerminate`).

2. **Çoklu Pencere ve İletişim Denetimi (`WKUIDelegate`):**
   * `target="_blank"` ve `window.open()` çağrılarını yakalayıp sayfayı zorla mevcut `WKWebView` içinde tutma (`createWebViewWith -> return nil`).
   * JavaScript `alert()`, `confirm()` ve `prompt()` pencerelerinin native UIKit `UIAlertController` ile karşılanması.
   * `window.close()` tespiti.

3. **İki Yönlü JavaScript Köprüsü (`WKScriptMessageHandler`):**
   * Sayfa başlangıcında (`atDocumentStart`) enjekte edilen teşhis scripti.
   * Ziyaret edilen sayfanın `console.log`, `console.warn` ve `console.error` çıktılarını native konsola aktarma (`[JS-CONSOLE]`).
   * `window.NativeEngine.postMessage(...)` ile web sayfasından native katmana doğrudan mesaj alma.
   * Native arayüzden sayfada canlı JavaScript çalıştırma (**Eval JS**).

4. **Kalıcı Çerez ve Depolama Yönetimi (`WKWebsiteDataStore`):**
   * `WKWebsiteDataStore.default()` ile kalıcı çerez ve oturum tutma.
   * **Inspect Cookies:** Aktif çerezleri (`domain`, `name`, `isSecure`, `isHTTPOnly`) konsola dökme.
   * **Clear Cache:** Çerezleri ve tüm web depolamasını temizleyip soğuk (cold) başlatma testi yapabilme.

5. **Harici URL Şemaları ve Universal Links:**
   * `vnd.youtube:`, `googlesearch:`, `twitter:`, `fb:` vb. özel şemaların yakalanması ve isteğe göre engellenmesi.
   * `mailto:`, `tel:` sistem şemalarının izlenmesi.

6. **Kategorize Edilmiş ve Filtrelenebilir Canlı Konsol:**
   * `[NAV]`, `[RESP]`, `[UI]`, `[JS]`, `[COOKIE]`, `[SCHEME]`, `[ERROR]`, `[STATE]` etiketleriyle renklendirilmiş canlı log.
   * Filtre butonu ile yalnızca ilgilenilen kategoriyi (örneğin sadece `[COOKIE]` veya sadece `[NAV]`) ekranda gösterme.

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
│   ├── ViewController.swift                      # V2 Browser Engine + Toolbar + Console
│   └── Info.plist                                # Güvenlik & Scene tanımları
├── codemagic.yaml                                # Codemagic macOS M2 build konfigürasyonu
├── CODEMAGIC_SETUP.md                            # Codemagic paneli adım adım kurulum rehberi
└── README.md                                     # Proje dokümantasyonu
```

---

## 3. Dahili Test Süitleri (Tek Dokunuşla Test)

Uygulamanın eylem çubuğunda (Action Toolbar) hazır bulunan yerel HTML testleri:

| Test Butonu | Test Edilen Senaryo | Doğrulanan Davranış |
| :--- | :--- | :--- |
| **`Test _blank`** | `<a href="..." target="_blank">` | Yeni sekme isteğinin `createWebViewWith` tarafından yakalanıp aynı ekranda açılması. |
| **`Test window.open`** | `window.open('...')` ve console/alert | JS üzerinden pencere açmanın ve console log yakalamanın doğrulanması. |
| **`Test Schemes`** | `vnd.youtube://` ve `mailto:` | Harici uygulama şemalarının yakalanması ve loglanması. |
| **`Test Storage`** | `document.cookie` ve `localStorage` | Çerez ve yerel depolama yazma/okuma döngüsü. |
| **`Inspect Cookies`** | `WKHTTPCookieStore` API | Tarayıcıda saklanan tüm çerezlerin dökümünün alınması. |
| **`Eval JS`** | `evaluateJavaScript` | Çalışan sayfada anlık kod yürütme (Örn. `document.title`). |
| **`Clear Cache`** | `WKWebsiteDataStore.removeData` | Çerezlerin ve önbelleğin sıfırlanması. |

---

## 4. Mac Olmadan Doğrulanabilenler vs. Gerçek iPad Gerektirenler

### Mac Olmadan (Windows + Codemagic) Doğrulanabilenler:
* ✅ Xcode proje yapısının (`.pbxproj`) sözdizimsel ve mimari geçerliliği.
* ✅ Swift kodlarının Apple `clang`/`swiftc` derleyicisinde sıfır hata ile derlenmesi.
* ✅ Codemagic üzerinde ARM64 mimarisi için derleme başarısı.
* ✅ Üretilen `NativeWKWebViewTest.ipa` arşivinin geçerli Mach-O ARM64 ikilisi ve unsigned paket yapısı içermesi.

### Yalnızca Gerçek iPad'de Doğrulanabilecek Davranışlar:
* 🔍 **Universal Link Handoff:** `youtube.com` üzerinde bir videoya tıklandığında iOS SpringBoard'un native YouTube uygulamasını açıp açmayacağı veya webview içinde tutup tutamayacağı.
* 🔍 **Google Oturumu:** Google hesap girişinde WebKit'in güvenlik denetimi (`disallowed_useragent` uyarısı verip vermeyeceği).
* 🔍 **Mega.nz Kripto İndirme:** WebCrypto API ve Blob indirme yeteneklerinin WebKit üzerinde iPadOS'ta nasıl tepki verdiği.
* 🔍 **Donanım Hızlandırma:** Video oynatımı, tam ekran ve bellek kullanımının stabilitesi.

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

Üretilen `.ipa` dosyası Codemagic **Artifacts** sekmesinden indirilip Sideloadly veya AltStore ile iPad'e yüklenebilir.
