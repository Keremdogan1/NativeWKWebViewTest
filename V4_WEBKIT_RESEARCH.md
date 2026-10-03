# V4 WebKit Kapsamlı Teknik Araştırma ve Tarayıcı Yol Haritası
**Repository:** `NativeWKWebViewTest`  
**Referans Baseline:** `e1afc31` (V3 Modüler Mimari)  
**Tarih:** Ekim 2026  
**Hedef:** Bağımsız native iOS `WKWebView` motorunu Safari benzeri, güvenli, bağımsız ve ileride Obsidian Leaf/Overlay mimarisine kusursuz uyum sağlayacak seviyeye taşımak.

---

## 1. WKWebViewConfiguration Audit

`WKWebViewConfiguration`, bir `WKWebView` oluşturulurken verilen ve webview belleğe yüklendikten sonra (runtime sırasında) değiştirilemeyen **kurucu konfigürasyon** nesnesidir.

| API | Ne işe yarıyor? | Bizim Browser için Gerekli mi? | Obsidian Entegrasyonunda Gerekli mi? | iOS Sürüm Gereksinimi | V3'e Göre Değişiklik Gerekiyor mu? |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`WKWebViewConfiguration`** | Webview'ın tüm motor, depolama, medya ve script ayarlarını barındıran temel nesne. | **Evet** (Temel) | **Evet** (Temel) | iOS 8.0+ | Hayır, mevcut kullanım doğru. |
| **`WKWebsiteDataStore`** | Çerezler, disk/bellek önbelleği, IndexedDB, WebSQL ve LocalStorage alanını yönetir. | **Evet** | **Evet** | iOS 9.0+ | `default()` kalıcı depolama korunmalı. |
| **`WKPreferences`** | JavaScript açılır pencere izni (`javaScriptCanOpenWindowsAutomatically`), tam ekran (`isElementFullscreenEnabled`) vb. genel motor ayarları. | **Evet** | **Evet** | iOS 8.0+ (bazı özellikler 15.4+) | `javaScriptCanOpenWindowsAutomatically = true` ve `isElementFullscreenEnabled = true` eklenmeli. |
| **`WKProcessPool`** | Birden çok `WKWebView` arasında WebContent alt sürecini (bellek ve ağ havuzunu) paylaşmayı sağlar. | **Kısmen** (Çoklu sekmede) | **Evet** (Obsidian çoklu tab için) | iOS 8.0+ | Tekil webview için gerekmez; çoklu sekme (TabManager) için tek havuz atanmalı. |
| **`WKUserContentController`** | Sayfalara JS enjeksiyonu (`addUserScript`) ve sayfadan Swift'e mesaj alma (`addScriptMessageHandler`) yöneticisi. | **Evet** (Kritik) | **Evet** (Kritik) | iOS 8.0+ | `WKContentWorld` izolasyonu eklenmeli. |
| **`WKUserScript`** | Belgenin başlangıcında (`atDocumentStart`) veya bitiminde (`atDocumentEnd`) DOM'a otomatik enjekte edilen JavaScript kodu. | **Evet** | **Evet** | iOS 8.0+ | Konsol yakalama ve köprü betikleri için mevcut kullanım korunmalı. |
| **`WKContentWorld`** | Enjekte edilen script'lerin ve mesaj yöneticilerinin web sayfasının kendi JS ortamından tamamen izole bir dünyada çalışmasını sağlar. | **Evet** (Güvenlik) | **Evet** (Kritik Güvenlik) | iOS 14.0+ | **V4'te kesinlikle eklenmeli.** Sayfa script'leri native bridge'e erişememeli. |
| **`WKWebpagePreferences`** | Sayfa bazında Desktop/Mobile görünüm (`preferredContentMode`) ve sayfa JS izni (`allowsContentJavaScript`) ayarlar. | **Evet** | **Evet** | iOS 13.0+ | iPadOS'ta masaüstü/mobil mod geçişi için eklenmeli. |
| **`allowsInlineMediaPlayback`** | Videoların tam ekrana zorlanmadan sayfa düzeni içinde (inline) oynatılmasını sağlar. | **Evet** | **Evet** (Note içinde) | iOS 10.0+ | Zaten `true`, korunmalı. |
| **`mediaTypesRequiringUserActionForPlayback`** | Medya oynatımı için kullanıcı dokunuşu şartını belirler (Otomatik oynatma kontrolü). | **Evet** | **Evet** | iOS 10.0+ | Zaten `[]` (otomatik oynatma serbest), korunmalı. |
| **`dataDetectorTypes`** | Metin içindeki telefon, tarih, adres ve linklerin otomatik algılanıp algılanmayacağını belirler. | İsteğe bağlı | İsteğe bağlı | iOS 10.0+ | `[]` veya `all` olarak konfigüre edilebilir. |
| **`setURLSchemeHandler(_:forURLScheme:)`** | `http`/`https` dışındaki özel şemaları (`obsidian://`, `app-local://`) yerel Swift kodunda yakalayıp yanıt dönmeyi sağlar. | Hayır | **Evet** (Obsidian vault linkleri) | iOS 11.0+ | V4'te prototip şema desteği için tasarlanmalı. |
| **`limitsNavigationsToAppBoundDomains`** | Webview'ı yalnızca `Info.plist` içinde tanımlı alan adlarıyla kısıtlar (In-App Browser kısıtlaması). | **HAYIR (Engellenmeli)** | **HAYIR** | iOS 14.0+ | `false` kalmalı; aksi halde genel internette serbest dolaşım engellenir. |
| **Persistent vs Non-Persistent DataStore** | `WKWebsiteDataStore.default()` (Kalıcı disk) vs `WKWebsiteDataStore.nonPersistent()` (Private/Gizli mod). | **Evet** | **Evet** | iOS 9.0+ | Varsayılan `default()` kalmalı, istendiğinde "Incognito" için `nonPersistent()` seçilebilmeli. |

---

## 2. Navigation Audit (Ağ, Yönlendirme ve Delegasyon)

Mevcut `BrowserNavigationDelegate` Apple'ın WebKit delegasyon sözleşmesine tam uygundur.

### `decidePolicyFor navigationAction` vs `decidePolicyFor navigationResponse`

| Kriter | `decidePolicyFor navigationAction` | `decidePolicyFor navigationResponse` |
| :--- | :--- | :--- |
| **Tetiklenme Zamanı** | İstek ağa çıkmadan **önce** (Pre-flight). | Sunucudan HTTP yanıt başlıkları (Headers) geldikten sonra, gövde (body) inmeden **önce**. |
| **Erişilebilen Veriler** | Hedef URL, HTTP Metodu (`GET`/`POST`), `navigationType` (`linkActivated`, `reload` vb.), `targetFrame` (`nil` ise popup), kullanıcı tıklaması (`event`). | HTTP Durum Kodu (`200`, `302`, `404`), MIME Type (`text/html`, `application/pdf`), Sunucu Başlıkları (`Set-Cookie`, `Content-Disposition`, `X-Frame-Options`, `CSP`). |
| **Verilebilecek Kararlar** | `.allow`, `.cancel`, `.download` (iOS 14.5+) | `.allow`, `.cancel`, `.download` (iOS 14.5+) |
| **Kullanım Amacı** | Özel şemaları (`vnd.youtube:`) engellemek, Universal Link politikasını belirlemek, `target="_blank"` isteklerini tespit etmek. | Dosya indirmelerini (`Content-Disposition: attachment` veya `.pdf`/`.zip`) yakalamak, HTTP hata durumlarını yakalamak, güvenlik başlıklarını denetlemek. |

### Navigasyon Olaylarının Kontrol Edilebilirliği

1. **Normal / `linkActivated` / `reload` / `backForward`:** %100 kontrol edilebilir (`navigationAction.navigationType`).
2. **Redirects (Sunucu & İstemci):**
   * **Sunucu Yönlendirmeleri (301/302):** `didReceiveServerRedirectForProvisionalNavigation` ile %100 yakalanır.
   * **İstemci Yönlendirmeleri (`meta refresh` / `location.href`):** Yeni bir `navigationAction` (`type = .other`) olarak tetiklenir, tam kontrol altındadır.
3. **Provisional vs Committed Navigation Failure:**
   * `didFailProvisionalNavigation`: DNS çözülemediğinde, internet bağlantısı olmadığında veya SSL sertifikası geçersiz olduğunda tetiklenir.
   * `didFail`: Sayfa HTML'i inmeye başladıktan sonra (sayfa ortasında) bağlantı koptuğunda tetiklenir.
4. **TLS / SSL Authentication Challenge:**
   * `didReceive challenge:completionHandler:` ile %100 yakalanır. `.performDefaultHandling` ile sistem güvenliği işletilir veya self-signed sertifikalar için özel bypass politikası uygulanabilir.

---

## 3. Popup / Window / `target="_blank"` Audit

### Mevcut Durum (`e1afc31`)
* `BrowserUIDelegate.createWebViewWith`: `navigationAction.targetFrame == nil` olduğunda isteği yakalar.
* `rerouteSameView` modunda: `webView.load(navigationAction.request)` çağrılır ve `return nil` yapılır.

### POST Form ve JavaScript Popup Sınır Durumları
1. **Dinamik JS Popup (`window.open('', '_blank')`):**
   * Web siteleri bazen boş bir pencere açıp içine JS ile `document.write()` yapar.
   * `return nil` yapıldığında WebKit bu pencereyi **anında yok eder**. `load()` çağrılacak bir URL dahi bulunamaz.
2. **Form POST + `target="_blank"`:**
   * `navigationAction.request` bir `POST` isteği içeriyorsa, HTTP gövdesi (`httpBody`) WebKit güvenlik modeli nedeniyle çoğu zaman Swift tarafına aktarılmaz (`stream` olarak kalır).
   * Mevcut sayfaya `webView.load(request)` dendiğinde form verileri kaybolabilir ve sayfa boş veya GET olarak yeniden yüklenir.

### Sonuç ve V4 Mimarisi İhtiyacı:
> **Gerçek bir tarayıcı davranışı için gelecekte kesinlikle bir `BrowserTabManager` (çoklu `WKWebView` havuzu) gereklidir.**  
> `createWebViewWith` metodu yeni bir `WKWebView` örneği döndürmeli (`return newWebView`), bu webview arka planda veya yeni bir sekme/tab olarak UI'a eklenmelidir. Obsidian içinde de her linkin ayrı bir `WorkspaceLeaf` içinde açılması bu mimariyle birebir örtüşür.

---

## 4. Dosya İndirme (Downloads) API Audit

Apple, iOS 14.5 ile birlikte WebKit'e resmi **`WKDownload`** API'sini kazandırmıştır.

### API Akışı:
1. `decidePolicyFor navigationResponse` içinde dosya MIME type'ı (`application/zip`, `application/pdf`, `application/octet-stream`) veya `Content-Disposition: attachment` başlığı kontrol edilir.
2. Karar olarak `decisionHandler(.download)` döndürülür.
3. WebKit navigasyonu durdurur ve bir `WKDownload` nesnesi oluşturur.
4. `WKDownloadDelegate` devreye girer:
   ```swift
   download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void)
   ```
5. İndirme ilerlemesi (`progress`), tamamlanması (`downloadDidFinish`) ve iptali (`download:didFailWithError:resumeData:`) delegasyon üzerinden izlenir.

### iOS Sandbox Depolama Konumları:
iOS sandbox kısıtlamaları nedeniyle indirilen dosyalar yalnızca şu dizinlere yazılabilir:
* **Uygulama İçi (Private):** `<Application_Home>/Library/Caches/Downloads/` veya `<Application_Home>/tmp/`
* **Kullanıcıya Açık (Files Uygulaması):** `<Application_Home>/Documents/Downloads/` (`UIFileSharingEnabled = YES` ve `LSSupportsOpeningDocumentsInPlace = YES` ile Dosyalar uygulamasında görünür).
* **Obsidian Vault:** İleride Obsidian entegrasyonunda dosya doğrudan Vault dizinine kaydedilebilir.

---

## 5. Dosya Yükleme (`<input type="file">`) Audit

### WebKit'in Varsayılan Davranışı:
Web sayfalarında `<input type="file">`, `<input type="file" multiple>`, `<input type="file" accept="image/*">` tıklandığında:
* **WebKit hiçbir ek Swift kodu yazılmasa dahi UIKit'in sistem modalını otomatik açar.**
* Kullanıcıya otomatik olarak 3 seçenek sunulur:
  1. *Fotoğraf Arşivi (Photo Library)*
  2. *Fotoğraf veya Video Çek (Camera)*
  3. *Dosya Seç (Choose File - UIDocumentPicker)*

### `WKUIDelegate` Özelleştirmesi (`runOpenPanelWith`):
* Apple, macOS'ta bulunan `runOpenPanelWith` metodunu **iOS 18.0+** ile birlikte iOS/visionOS platformuna da açmıştır.
* Ancak iOS 15 - 17 sürümlerinde WebKit'in yerel davranışı Google Drive, Mega, GitHub ve ODTUClass dosya yüklemelerini hiçbir ekstra koda gerek kalmadan sorunsuz çalıştırmaktadır.

---

## 6. Çerezler, Kimlik Doğrulama ve Kalıcı Depolama (Cookies / Storage)

### Depolama Türleri ve Davranışları:
* **`WKWebsiteDataStore.default()`:**
  * Çerezler (`WKHTTPCookieStore`), LocalStorage, IndexedDB ve WebSQL disk üzerinde kalıcı olarak saklanır.
  * Uygulama tamamen kapatılıp (`kill`) yeniden açıldığında oturumlar korunur.
* **Persistent Session vs Session Cookies:**
  * Kalıcı çerezler (`Max-Age` / `Expires` olanlar) diskte saklanır.
  * "Session Cookie"ler (oturum bazlı çerezler), Apple WebKit mimarisinde uygulama arka planda askıya alındığında korunur; ancak uygulama bellekten tamamen atıldığında veya `WKProcessPool` yok edildiğinde silinebilir.
* **Google / GitHub Login Durumu:**
  * İki faktörlü kimlik doğrulama (2FA), SMS kodları ve oturum anahtarları `WKWebsiteDataStore.default()` içinde saklanır.
  * Ancak Google, gömülü webview'larda bazen `disallowed_useragent` güvenlik engeli uygulayabilmektedir. Bu durum kullanıcı ajanı (User-Agent) özelleştirmesi ile aşılabilmektedir (`customUserAgent`).

---

## 7. JavaScript Ortamı ve İzolasyon (`WKContentWorld`)

### `WKContentWorld` Mimarisi (iOS 14.0+):
WebKit iki temel içerik dünyası sunar:
1. **`.page` Dünyası:** Web sitesinin kendi JS kodlarının çalıştığı dünya.
2. **`.defaultClient` veya Özel Adlandırılmış Dünya (`WKContentWorld.world(name: "ObsidianBridge")`):** Native uygulamanın enjekte ettiği script'lerin çalıştığı izole alan.

### Kritik Güvenlik İzolasyonu:
* Eğer `WKUserScript` ve `addScriptMessageHandler` varsayılan `.page` dünyasına eklenirse, ziyaret edilen kötü amaçlı bir web sayfası `window.webkit.messageHandlers.diagnosticBridge` nesnesine erişebilir, sahte mesajlar gönderebilir veya köprüyü manipüle edebilir.
* **V4 Tasarımı:**
  Native köprü ve konsol yöneticisi `WKContentWorld.world(name: "NativeEngineWorld")` içine taşınmalıdır. Bu sayede sayfa DOM'una erişilebilirken, JS değişkenleri ve köprü nesneleri sayfadaki untrusted JS tarafından **asla görülemez**.

---

## 8. Harici URL Şemaları Matrisi (Scheme Routing Matrix)

| URL Şeması | Doğal Kapsam | WKWebView Davranışı | Önerilen NativeBrowser Politikası |
| :--- | :--- | :--- | :--- |
| `http`, `https` | Web standartları | Doğrudan WebKit içinde yüklenir. | İzin ver (`.allow`). |
| `about:blank`, `about:srcdoc` | Dahili tarayıcı | Yerel boş sayfa / frame. | İzin ver (`.allow`). |
| `data:` | Gömülü veri | Resim, base64 metin yükler. | İzin ver (`.allow`). |
| `blob:` | Bellek nesnesi | WebCrypto, Mega.nz indirmeleri. | İzin ver (`.allow`). |
| `javascript:` | DOM script | Bookmarklet / link scripti. | Engelle veya dikkatli çalıştır. |
| `file:///` | Yerel dosya | Sandboxed yerel HTML. | Yalnızca güvenli bundle dizinleri için izin ver. |
| `mailto:`, `tel:`, `sms:` | Sistem servisleri | Mail/Telefon uygulamasını açmak ister. | Kullanıcı onayına bağla (`prompt` / policy). |
| `facetime:` | Sistem video arama | FaceTime'ı açmak ister. | Engelle veya onay sor. |
| `vnd.youtube:`, `youtube:` | Native YouTube | YouTube uygulamasını açar. | **Engelle (`.cancel`)**; linki webview'da tut. |
| `googlesearch:`, `googlechrome:`| Google uygulamaları | Harici uygulamaya geçiş ister. | **Engelle (`.cancel`)**. |
| `twitter:`, `x:`, `fb:`, `reddit:`| Sosyal medya uygulamaları| Native app açmak ister. | **Engelle (`.cancel`)**; webview'da aç. |
| `obsidian:` | Obsidian uygulaması | Notlar arası URI yönlendirmesi. | Gelecekte Obsidian Native Bridge'e devret. |

---

## 9. Universal Links ve Native App Handoff Derin Analizi

### Temel Soru:
> *Kullanıcı WebKit içinde `https://www.youtube.com/watch?...` linkine dokunduğunda iOS bunu YouTube uygulamasına devredebilir mi? Bunu engellemenin kesin bir API yolu var mı?*

### Apple Dokümantasyonu ve Sistem Mimarisi:
1. **Universal Link Çalışma Prensibi:**
   Universal Link'ler Apple'ın `Associated Domains` (`apple-app-site-association`) mekanizmasıyla işletim sistemi düzeyinde (SpringBoard) çözülür.
2. **`WKNavigationAction` Seviyesindeki Kısıt:**
   * Apple'ın `WKNavigationAction` API'sinde bir isteğin Universal Link olup olmadığını belirten bir **özellik (property) YOKTUR**.
   * İstek Swift tarafına sıradan bir `https` URL'si olarak gelir.
3. **WebKit'in Handoff Davranış Kuralları:**
   * **Programmatik Yükleme (`webView.load(request)`):** Universal Link işletim sistemi tarafından tetiklenmez; webview içinde yüklenir.
   * **Aynı Domain Navigasyonu:** Kullanıcı zaten `youtube.com` üzerindeyken site içindeki başka bir linke dokunduğunda iOS genellikle harici uygulamayı açmaz.
   * **Farklı Domain Navigasyonu (Cross-Domain User Click):** Örneğin `google.com` arama sonuçlarındaki bir `youtube.com` linkine kullanıcı parmağıyla dokunduğunda (`navigationType == .linkActivated`), iOS SpringBoard native YouTube uygulamasını açabilir.
4. **Engelleme / Kontrol Noktaları:**
   * Eğer hedef domain bilinen bir native app domaini ise (`youtube.com`, `instagram.com`, `twitter.com`), `decidePolicyFor navigationAction` içinde istek `.cancel` edilip, hemen ardından Swift tarafından **programmatik olarak** `webView.load(URLRequest(url: targetURL))` şeklinde yeniden yüklenebilir!
   * **Programmatik `webView.load()` çağrıları Apple tarafından Universal Link handoff'a tabi tutulmaz; webview içinde kalır!**
   * *Doğrulama Gereksinimi:* Bu davranış Apple'ın resmi kurallarıyla uyumludur ancak gerçek bir iPad üzerinde native YouTube yüklüyken doğrulanmalıdır.

---

## 10. Safari vs. WKWebView Yetenek Karşılaştırması

| Özellik | Tam Safari (iOS) | `WKWebView` (Bizim Engine) | Durum / Sınır |
| :--- | :--- | :--- | :--- |
| **HTML5 / CSS / modern JS** | Tam destek | Tam destek | **Aynı motor (WebKit)** |
| **Kalıcı Çerezler & LocalStorage** | Var | Var (`WKWebsiteDataStore.default()`) | **Aynı** |
| **IndexedDB & Cache API** | Var | Var | **Aynı** |
| **WebCrypto API** | Var | Var (Mega.nz çalışır) | **Aynı** |
| **Inline & Fullscreen Video** | Var | Var | **Aynı** |
| **Dosya İndirme (Downloads)** | Safari İndirilenler | Var (`WKDownload`, iOS 14.5+) | **Desteklenir** |
| **Dosya Yükleme (Uploads)** | Kamera / Dosyalar | Var (Sistem sheet otomatik açılır) | **Desteklenir** |
| **Çoklu Sekme (Tabs)** | Safari Tab Bar | Özel `BrowserTabManager` ile yapılabilir | Mimari geliştirme gerekir. |
| **Safari Web Extensions** | Var | **YOK (Safari'ye Özel)** | 3. parti webview'larda desteklenmez. |
| **Content Blockers** | Sistem genelinde | `WKContentRuleListStore` ile yapılabilir | Kod ile eklenebilir. |
| **iCloud Anahtarlık Otomatik Doldurma**| Otomatik Form Doldurma | Kısıtlı / Yarı-otomatik | Safari kadar pürüzsüz değildir. |
| **Apple Pay Web** | Tam destek | Sadece yetkili domainlerde | Ek yetki gerektirir. |
| **Web Push Bildirimleri** | iOS 16.4+ (PWA) | Desteklenmez | Safari / PWA'ya özeldir. |
| **WebAuthn / Passkeys** | Tam entegre | iOS 16.0+ ile sınırlı destek | ASAuthorizationController gerekir. |

---

## 11. Güvenlik, İzolasyon ve Obsidian Entegrasyonu

Gelecekteki Obsidian entegrasyonunda mimari şu şekilde olacaktır:

```text
Untrusted Web Sayfası (Örn. kötü niyetli script içeren site)
          │
          │ (İzole JS Dünyası: .page)
          ▼
     WKWebView DOM
          ▲
          │ (İzole JS Dünyası: .world("ObsidianPrivateWorld"))
          │
    NativeBridge Script
          │
          │ WKScriptMessageHandler
          ▼
     NativeBrowser (Swift)
          │
          │ Capacitor / Native Plugin Event
          ▼
   Obsidian Vault & Plugin API
```

### Güvenlik Önlemleri:
1. **`WKContentWorld` İzolasyonu:** Sayfa script'leri native bridge fonksiyonlarına (`window.webkit.messageHandlers`) erişemez.
2. **Origin & URL Doğrulaması:** Swift tarafına gelen her mesajda `message.frameInfo.securityOrigin` kontrol edilerek rastgele sitelerin Obsidian API çağırması engellenir.
3. **Yetki Kısıtlaması:** Web sayfasından gelen hiçbir komut doğrudan yerel dosya sistemine (Vault'a) yazma yetkisi alamaz. Yalnızca tarayıcı kontrolleri (sekme kapat, URL al, başlık al) açık tutulur.

---

## 12. Obsidian Entegrasyon Fizibilitesi ve Mimari Modeller

Obsidian iOS uygulamasının DOM bazlı bir Capacitor webview'ı olduğu önceki `runtime-inspector` testlerimizde doğrulanmıştı.

### Olası Native Entegrasyon Modelleri:

1. **Model A: Native Frame Overlay (En Güçlü ve Performanslı Model)**
   * Obsidian JS tarafında bir `WorkspaceLeaf` açılır ve içine bir DOM placeholder `DIV` yerleştirilir.
   * `DIV`'in ekran koordinatları (`getBoundingClientRect()`) native tarafa iletilir.
   * `NativeBrowser.setFrame(rect)` ile native `WKWebView`, Obsidian'ın ana penceresinin üzerine tam o koordinatlara pixel-perfect bir overlay olarak eklenir.
   * Sekme değiştiğinde `NativeBrowser.setVisible(false)` yapılır.

2. **Model B: Modal / Sheet View Controller**
   * Linke tıklandığında Obsidian arayüzünü kapatmayan, alt taraftan kayan yerel bir sheet açılır.
   * Tam tarayıcı deneyimi sunar ancak yan yana not alma esnekliği Model A'dan düşüktür.

3. **Önerilen V4 Browser Engine API'si:**
   Mevcut V3 `NativeBrowser` API'miz (`open`, `close`, `back`, `forward`, `reload`, `getState`, `setFrame`, `setVisible`, `onStateChanged`, `onEvent`) Model A ve Model B için **%100 yeterli ve eksiksiz bir temeldir.**

---

## 13. V4 Yol Haritası ve Milestone Ayrımı

### Özellik Sınıflandırması:
* **Kategori A (Kesinlikle Yapılabilir):** `WKDownload` indirme yöneticisi, `WKPreferences` tam ekran/popup ayarları, `WKContentWorld` script izolasyonu, `BrowserTabManager` çoklu webview altyapısı, Custom scheme engelleme.
* **Kategori B (Yapılabilir, Gerçek Cihaz Testi Gerekli):** Programmatik cross-domain Universal Link handoff engelleme (`load(request)` taktiği), Google Login User-Agent optimizasyonu.
* **Kategori C (Safari'ye Özel / Kısıtlı):** Safari Web Extensions (uBlock vb.), sistem düzeyinde tam otomatik şifre doldurma, Web Push bildirimleri.
* **Kategori D (Apple Tarafından Kontrol Edilen):** SpringBoard işletim sistemi düzeyinde bazı donanımsal Universal Link yakalama refleksleri.
* **Kategori E (Obsidian İçin Kritik):** `setFrame`/`setVisible` overlay koordinasyonu, `WKContentWorld` bridge izolasyonu, cookie kalıcılığı.

---

### V4 Milestone Planı:

#### **Milestone V4.1 — Güvenlik İzolasyonu ve Motor Ayarları (`WKContentWorld` & `Preferences`)**
* **Amaç:** Konsol köprüsünü ve teşhis scriptlerini web sayfasından izole etmek; tam ekran video ve pencere açma tercihlerini etkinleştirmek.
* **Değişecek Dosyalar:** `NativeBrowser.swift`, `BrowserUIDelegate.swift`.
* **Kullanılacak API'ler:** `WKContentWorld.world(name:)`, `WKPreferences.isElementFullscreenEnabled`, `javaScriptCanOpenWindowsAutomatically`.
* **Risk / Test:** Düşük risk. Statik analiz ve CI build ile doğrulanabilir.

#### **Milestone V4.2 — Yerel Dosya İndirme Motoru (`WKDownload` Desteği)**
* **Amaç:** Web sitelerinden PDF, ZIP ve doküman indirmeyi native dosya sistemine bağlamak ve ilerleme durumunu loglamak.
* **Değişecek Dosyalar:** `BrowserNavigationDelegate.swift`, `NativeBrowser.swift`, yeni `BrowserDownloadManager.swift`.
* **Kullanılacak API'ler:** `WKDownload`, `WKDownloadDelegate`, `decidePolicyFor navigationResponse (.download)`.
* **Risk / Test:** Sandbox dosya yazma izinleri. Gerçek iPad dosya kontrolü önerilir.

#### **Milestone V4.3 — Çoklu Sekme ve Pencere Yönetimi (`BrowserTabManager`)**
* **Amaç:** `target="_blank"` ve `window.open()` çağrılarında form verilerini ve dinamik pencereleri kaybetmemek için çoklu `WKWebView` havuzu kurmak.
* **Değişecek Dosyalar:** Yeni `BrowserTabManager.swift`, `NativeBrowser.swift`, `ViewController.swift`.
* **Kullanılacak API'ler:** `WKProcessPool`, `WKUIDelegate.createWebViewWith` (yeni webview döndürme).
* **Risk / Test:** Bellek tüketimi (aynı anda birden çok WebContent süreci).

#### **Milestone V4.4 — Universal Link & App Handoff Savunma Katmanı**
* **Amaç:** YouTube, Google, Twitter gibi sitelerin kullanıcı tıklamalarında native uygulamalara sıçramasını programmatik yeniden yükleme ile engellemek.
* **Değişecek Dosyalar:** `BrowserNavigationDelegate.swift`, `BrowserState.swift`.
* **Kullanılacak API'ler:** `WKNavigationActionPolicy.cancel` + `browser.load(request)`.
* **Risk / Test:** **Gerçek iPad testi zorunludur.** (Yüklü YouTube ve Google uygulamaları gerekir).

---

## 14. Sonuç ve Özet Değerlendirme

Native `WKWebView`, doğru konfigürasyon (`WKWebsiteDataStore.default()`, `WKContentWorld`, `WKDownload`) ve stratejik delegasyon yönetimi (`decidePolicyFor navigationAction/Response`) ile donatıldığında:
1. Google, YouTube, Mega, GitHub gibi siteleri oturumları koruyarak sorunsuz çalıştırabilir.
2. Safari'ye yakın bir gezinme, indirme ve medya deneyimi sunabilir.
3. Özel şemaları ve cross-domain yönlendirmeleri denetim altında tutabilir.
4. İleride Obsidian iOS içinde bağımsız bir tarayıcı sekmesi/overlay'i olarak çalışmaya tamamen uygundur.
