# Codemagic CI/CD Kurulum Rehberi

Bu rehber, GitHub'daki `NativeWKWebViewTest` repository'sini Codemagic'e bağlayıp, **Windows bilgisayarınızdan hiçbir Mac kullanmadan** iPad için unsigned `.ipa` build'i almanızı sağlar.

---

## 1. Codemagic Hesabı Oluşturma ve Giriş
1. [codemagic.io](https://codemagic.io/) adresine gidin.
2. **"Sign up with GitHub"** seçeneğini kullanarak `Keremdogan1` GitHub hesabınızla giriş yapın.
3. Codemagic'in GitHub depolarınıza erişmesine onay verin.

---

## 2. Uygulamayı (Repository) Ekleme
1. Codemagic ana panelinde (Dashboard) sağ üstteki **"Add application"** butonuna tıklayın.
2. Kaynak olarak **"GitHub"** seçin.
3. Depo listesinden **`Keremdogan1/NativeWKWebViewTest`** deposunu bulun ve seçin.
4. Proje türü olarak:
   * **"iOS App"** veya **"Other"** seçeneğini işaretleyin.
   * Projede `codemagic.yaml` dosyası hazır bulunduğu için Codemagic otomatik olarak yapılandırmayı bu dosyadan okuyacaktır.
5. **"Finish: Add application"** butonuna basın.

---

## 3. İlk Build'i Başlatma
1. Uygulama sayfasında projenin `codemagic.yaml` dosyasını algıladığını göreceksiniz.
2. Sağ üst köşedeki mavi **"Start new build"** butonuna tıklayın.
3. Açılan pencerede:
   * **Branch:** `main`
   * **Workflow:** `Native WKWebView Test Build` (`ios-native-poc`)
4. **"Start build"** butonuna tıklayın.

---

## 4. Build Sürecini İzleme ve Çıktıyı İndirme
1. Codemagic bir macOS M2 sanal makinesi (`mac_mini_m2`) ayağa kaldıracaktır.
2. `xcodebuild` komutu çalışacak ve Swift kodlarını ARM64 (iPad/iPhone) mimarisi için derleyecektir.
3. Ortalama build süresi: **1 - 2 dakika**.
4. Build başarıyla tamamlandığında (**Status: Success**):
   * Sağ taraftaki **"Artifacts"** panelinde:
     * **`NativeWKWebViewTest.ipa`** dosyasını göreceksiniz.
   * Bu `.ipa` dosyasını Windows bilgisayarınıza indirin.

---

## 5. Ücretsiz Plan ve Kota Bilgisi
* **Ücretsiz Aylık Süre:** Codemagic ücretsiz planda her ay **500 build dakikası** vermektedir.
* **Tüketim:** Bu hafif native PoC projesi her build'de yaklaşık 1.5 dakika tükettiği için ayda **300'den fazla build** ücretsiz olarak alınabilir.
* **Apple Developer Hesabı:** Codemagic tarafında herhangi bir Apple sertifikası veya hesabı bağlamanıza gerek yoktur; çünkü derleme `CODE_SIGNING_ALLOWED=NO` ile bağımsız olarak yapılmaktadır.

---

## 6. Windows Üzerinden iPad'e Kurulum (Sideloadly)
1. [sideloadly.io](https://sideloadly.io/) adresinden Windows sürümünü indirin ve kurun.
2. iTunes / Apple Aygıtları sürücülerinin Windows'ta kurulu olduğundan emin olun.
3. iPad'inizi kabloyla bilgisayara bağlayın ve ekranda çıkarsa "Bu Bilgisayara Güven" deyin.
4. Sideloadly'yi açın:
   * **"IPA"** kutusuna Codemagic'ten indirdiğiniz `NativeWKWebViewTest.ipa` dosyasını sürükleyin.
   * **"Apple ID"** kısmına kendi ücretsiz Apple hesabınızı yazın.
   * **"Start"** butonuna basın.
5. Kurulum bittiğinde uygulama iPad ana ekranında belirecektir.
6. iPad'de açmadan önce:
   * **Ayarlar -> Genel -> VPN ve Aygıt Yönetimi -> [Apple ID'niz] -> Güven** adımlarını izleyin.
