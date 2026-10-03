import Foundation

/// Provider supplying offline local WebFixtures for deterministic WebKit engine testing
public final class WebFixturesProvider {

    public static let shared = WebFixturesProvider()
    public static let baseSuiteURL = URL(string: "https://local-suite.poc/")!

    private init() {}

    /// Returns HTML content for a given fixture path or name
    public func html(for path: String) -> String {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "?").first ?? path

        switch clean {
        case "", "index.html":
            return indexHTML
        case "test_nav.html":
            return testNavHTML
        case "test_popups.html":
            return testPopupsHTML
        case "test_storage.html":
            return testStorageHTML
        case "test_dialogs.html":
            return testDialogsHTML
        case "test_download.html":
            return testDownloadHTML
        default:
            return notFoundHTML(for: clean)
        }
    }

    // MARK: - Embedded Deterministic Fixture Templates
    public let indexHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>V4.3 WebKit Test Suite Portal</title>
        <style>
            :root { --primary: #007aff; --bg: #f8f9fa; --card-bg: #ffffff; --border: #e2e8f0; --text: #1e293b; }
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: var(--bg); color: var(--text); padding: 16px; margin: 0; line-height: 1.5; }
            h2 { margin: 0 0 4px 0; font-size: 20px; color: #0f172a; }
            p.subtitle { margin: 0 0 16px 0; font-size: 13px; color: #64748b; }
            .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 12px; }
            .card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; padding: 12px 14px; box-shadow: 0 1px 2px rgba(0,0,0,0.05); }
            .card h3 { margin: 0 0 6px 0; font-size: 14px; display: flex; align-items: center; justify-content: space-between; }
            .badge { font-size: 10px; font-weight: bold; padding: 2px 6px; border-radius: 4px; text-transform: uppercase; }
            .badge-auto { background: #dcfce7; color: #166534; }
            .badge-manual { background: #fef3c7; color: #92400e; }
            p.desc { font-size: 12px; color: #475569; margin: 0 0 10px 0; }
            .actions { display: flex; gap: 8px; flex-wrap: wrap; }
            button, a.btn { display: inline-flex; align-items: center; justify-content: center; padding: 6px 12px; background: var(--primary); color: #fff; text-decoration: none; border-radius: 6px; border: none; font-size: 12px; font-weight: 500; cursor: pointer; }
            button.secondary, a.btn.secondary { background: #e2e8f0; color: #334155; }
            .result-box { margin-top: 8px; font-family: monospace; font-size: 11px; background: #f1f5f9; padding: 6px 8px; border-radius: 4px; display: none; }
        </style>
    </head>
    <body>
        <h2>🧪 V4.3 WebKit Test Suite</h2>
        <p class="subtitle">Offline / Local Deterministic Test Harness for Multi-Tab & Native WKWebView Engine</p>

        <div class="grid">
            <div class="card">
                <h3>A. Basic Navigation <span class="badge badge-auto">Auto/Interactive</span></h3>
                <p class="desc">Tests local page-to-page navigation, back, forward, and reload operations.</p>
                <div class="actions">
                    <a class="btn" href="test_nav.html">Open Navigation Fixture</a>
                </div>
            </div>

            <div class="card">
                <h3>B. target="_blank" GET <span class="badge badge-auto">Auto</span></h3>
                <p class="desc">Hyperlink with target="_blank". Verifies createWebViewWith intercepts and spawns new tab.</p>
                <div class="actions">
                    <a class="btn" href="test_nav.html?test=blank_get" target="_blank" id="btnBlankGet">Launch GET New Tab</a>
                </div>
            </div>

            <div class="card">
                <h3>C. target="_blank" POST <span class="badge badge-auto">Observed</span></h3>
                <p class="desc">HTML form POST with target="_blank". Verifies form submission routing to new tab.</p>
                <form action="test_popups.html?mode=post_target" method="POST" target="_blank" style="margin: 0;">
                    <input type="hidden" name="fixturePayload" value="V4.3_SECRET_POST_DATA_9988">
                    <input type="hidden" name="timestamp" id="postTimestamp" value="">
                    <button type="submit" onclick="document.getElementById('postTimestamp').value = Date.now()">Submit POST Form New Tab</button>
                </form>
            </div>

            <div class="card">
                <h3>D & E. window.open Popups <span class="badge badge-auto">Auto</span></h3>
                <p class="desc">Tests immediate synchronous popup vs 1000ms delayed asynchronous popup.</p>
                <div class="actions">
                    <button onclick="testImmediateOpen()">Immediate open()</button>
                    <button class="secondary" onclick="testDelayedOpen()">Delayed open (1s)</button>
                </div>
                <div id="delayStatus" class="result-box"></div>
            </div>

            <div class="card">
                <h3>F & G. Multi-Popup & Close <span class="badge badge-auto">Auto</span></h3>
                <p class="desc">Spawns 3 simultaneous popups and tests window.close() self-termination.</p>
                <div class="actions">
                    <button onclick="testTriplePopups()">Spawn 3 Popups</button>
                    <button class="secondary" onclick="testSelfClose()">window.close()</button>
                </div>
            </div>

            <div class="card">
                <h3>H. Tab State Preservation <span class="badge badge-auto">Interactive</span></h3>
                <p class="desc">Input values, scroll depth, and JS execution counter preserved across tab switches.</p>
                <div class="actions">
                    <a class="btn" href="test_nav.html?test=state">Open Tab State Tester</a>
                </div>
            </div>

            <div class="card">
                <h3>I - L. Storage & Cookies <span class="badge badge-auto">Shared</span></h3>
                <p class="desc">Deterministic cookie, localStorage, IndexedDB, and sessionStorage tests.</p>
                <div class="actions">
                    <a class="btn" href="test_storage.html">Open Storage Suite</a>
                </div>
            </div>

            <div class="card">
                <h3>M. WKDownload Engine <span class="badge badge-auto">Sandboxed</span></h3>
                <p class="desc">Content-Disposition: attachment, MIME detection, progress and Documents/Downloads saving.</p>
                <div class="actions">
                    <a class="btn" href="test_download.html">Open Download Fixtures</a>
                </div>
            </div>

            <div class="card">
                <h3>N. JavaScript Dialogs <span class="badge badge-auto">Modal</span></h3>
                <p class="desc">Verifies alert(), confirm(), and prompt() native UI presentation via BrowserUIDelegate.</p>
                <div class="actions">
                    <a class="btn" href="test_dialogs.html">Open Dialog Fixtures</a>
                </div>
            </div>

            <div class="card">
                <h3>O. Custom Schemes <span class="badge badge-auto">Policy</span></h3>
                <p class="desc">Tests custom URL scheme interception (vnd.test://) under Allow vs Block policies.</p>
                <div class="actions">
                    <button onclick="window.location.href='vnd.test://action?param=123'">Trigger vnd.test://</button>
                </div>
            </div>

            <div class="card">
                <h3>P. Invalid Navigation <span class="badge badge-auto">Failure</span></h3>
                <p class="desc">Triggers non-resolvable domain to verify fail navigation handling and BrowserState.lastError.</p>
                <div class="actions">
                    <button onclick="window.location.href='https://nonexistent-domain-test-404-xyz.invalid/'">Invalid Host</button>
                </div>
            </div>

            <div class="card">
                <h3>Q. Process Crash & Recovery <span class="badge badge-manual">Manual / Real Device</span></h3>
                <p class="desc">Simulating WebContent termination reliably requires low-memory jetsam or SIGKILL on device.</p>
                <div class="actions">
                    <button class="secondary" onclick="alert('WebContent crash cannot be reliably triggered from inside standard unprivileged JS sandbox. Requires real device memory pressure or native SIGKILL.')">Crash Notice</button>
                </div>
            </div>
        </div>

        <script>
            function testImmediateOpen() {
                window.open('test_popups.html?mode=immediate', '_blank');
            }

            function testDelayedOpen() {
                const box = document.getElementById('delayStatus');
                box.style.display = 'block';
                box.innerText = 'Timer running: opening popup in 1000ms...';
                setTimeout(() => {
                    box.innerText = 'Triggering window.open() now...';
                    window.open('test_popups.html?mode=delayed', '_blank');
                }, 1000);
            }

            function testTriplePopups() {
                for (let i = 1; i <= 3; i++) {
                    window.open('test_popups.html?mode=multi&idx=' + i, '_blank');
                }
            }

            function testSelfClose() {
                window.close();
            }
        </script>
    </body>
    </html>
    """

    public let testNavHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Navigation & State Fixture</title>
        <style>
            body { font-family: -apple-system, sans-serif; padding: 16px; line-height: 1.5; color: #1e293b; background: #fff; }
            .box { background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px; padding: 12px; margin-bottom: 14px; }
            h3 { margin-top: 0; font-size: 16px; }
            button, a.btn { display: inline-block; padding: 6px 12px; background: #007aff; color: #fff; text-decoration: none; border-radius: 6px; border: none; font-size: 12px; font-weight: 500; cursor: pointer; }
            input[type="text"] { padding: 6px 10px; border: 1px solid #cbd5e1; border-radius: 6px; font-size: 13px; width: 220px; }
            .counter-badge { font-size: 18px; font-weight: bold; color: #007aff; font-family: monospace; }
            .scroll-spacer { height: 1200px; background: linear-gradient(180deg, #f1f5f9 0%, #cbd5e1 100%); margin: 20px 0; border-radius: 8px; padding: 20px; box-sizing: border-box; }
        </style>
    </head>
    <body>
        <a href="index.html" class="btn" style="background:#64748b; margin-bottom: 12px;">← Back to Suite Portal</a>

        <h2>A & H. Navigation & Tab State Fixture</h2>

        <div class="box">
            <h3>1. Local Navigation Steps</h3>
            <p>Test sequential local navigation, history stack push, back/forward functionality:</p>
            <button onclick="window.location.href='test_nav.html?step=2'">Navigate to Step 2</button>
            <button onclick="history.back()">history.back()</button>
            <button onclick="history.forward()">history.forward()</button>
            <button onclick="location.reload()">location.reload()</button>
            <p id="navStepInfo" style="font-size: 12px; color: #64748b; margin-top: 8px;"></p>
        </div>

        <div class="box">
            <h3>2. Tab State Preservation Test</h3>
            <p>Type into the input, verify counter continues running, scroll down, switch tabs and return to verify retention.</p>
            <div style="margin-bottom: 10px;">
                <label>Input Field: </label>
                <input type="text" id="stateInput" placeholder="Type 'TEST123' here..." value="TEST123">
            </div>
            <div style="margin-bottom: 10px;">
                <label>JavaScript Runtime Counter: </label>
                <span id="counterVal" class="counter-badge">0</span>
                <span style="font-size: 11px; color: #64748b;"> (Increments every second)</span>
            </div>
            <div>
                <label>Current Scroll Y: </label>
                <span id="scrollYVal" style="font-family: monospace; font-weight: bold;">0px</span>
            </div>
        </div>

        <div class="scroll-spacer">
            <p><strong>Scroll Depth Marker</strong></p>
            <p>Scroll down here, switch to another tab, and switch back. The scroll offset must remain exactly here.</p>
            <button onclick="window.scrollTo(0, 0)">Scroll Back to Top</button>
        </div>

        <script>
            const urlParams = new URLSearchParams(window.location.search);
            const step = urlParams.get('step') || '1';
            document.getElementById('navStepInfo').innerText = 'Current Location: Step ' + step + ' (' + window.location.href + ')';

            let count = 0;
            setInterval(() => {
                count++;
                document.getElementById('counterVal').innerText = count;
            }, 1000);

            window.addEventListener('scroll', () => {
                document.getElementById('scrollYVal').innerText = Math.round(window.scrollY) + 'px';
            });
        </script>
    </body>
    </html>
    """

    public let testPopupsHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Popup & Window.open Target Fixture</title>
        <style>
            body { font-family: -apple-system, sans-serif; padding: 16px; line-height: 1.5; color: #1e293b; background: #fff; }
            .box { background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px; padding: 14px; margin-bottom: 12px; }
            h3 { margin-top: 0; font-size: 16px; }
            button, a.btn { display: inline-block; padding: 6px 12px; background: #007aff; color: #fff; text-decoration: none; border-radius: 6px; border: none; font-size: 12px; font-weight: 500; cursor: pointer; }
            button.danger { background: #ef4444; }
            .info-table { width: 100%; border-collapse: collapse; font-size: 12px; margin-top: 10px; }
            .info-table td { padding: 6px; border: 1px solid #e2e8f0; }
            .info-table td:first-child { font-weight: bold; background: #f1f5f9; width: 35%; }
        </style>
    </head>
    <body>
        <a href="index.html" class="btn" style="background:#64748b; margin-bottom: 12px;">← Back to Suite Portal</a>

        <h2>Popups & Windows Fixture</h2>

        <div class="box">
            <h3>Popup Reception Details</h3>
            <p>This tab was spawned via popup interception (target="_blank" or window.open).</p>
            <table class="info-table">
                <tr><td>Spawn Mode</td><td id="spawnMode">-</td></tr>
                <tr><td>Current URL</td><td id="currentUrl">-</td></tr>
                <tr><td>window.opener Available?</td><td id="openerStatus">-</td></tr>
                <tr><td>HTTP Method Received</td><td id="httpMethodStatus">GET / Unknown (Static Page Context)</td></tr>
            </table>
        </div>

        <div class="box">
            <h3>G. window.close() Test</h3>
            <p>Click below to execute <code>window.close()</code>. The Native UIDelegate must intercept webViewDidClose and destroy this tab.</p>
            <button class="danger" onclick="triggerClose()">Close This Tab (window.close)</button>
        </div>

        <script>
            const params = new URLSearchParams(window.location.search);
            const mode = params.get('mode') || 'direct';
            const idx = params.get('idx') || '';
            document.getElementById('spawnMode').innerText = mode + (idx ? ' (Popup #' + idx + ')' : '');
            document.getElementById('currentUrl').innerText = window.location.href;

            try {
                const hasOpener = (window.opener !== null && window.opener !== undefined);
                document.getElementById('openerStatus').innerText = hasOpener ? 'YES (Connected to Opener)' : 'NO / null (noopener)';
            } catch(e) {
                document.getElementById('openerStatus').innerText = 'Restricted / Exception: ' + e.message;
            }

            function triggerClose() {
                console.log('[TEST] Executing window.close()');
                window.close();
            }
        </script>
    </body>
    </html>
    """

    public let testStorageHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Storage & Cookie Persistence Fixture</title>
        <style>
            body { font-family: -apple-system, sans-serif; padding: 16px; line-height: 1.5; color: #1e293b; background: #fff; }
            .box { background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px; padding: 12px; margin-bottom: 12px; }
            h3 { margin-top: 0; font-size: 15px; }
            button, a.btn { display: inline-block; padding: 6px 12px; background: #007aff; color: #fff; text-decoration: none; border-radius: 6px; border: none; font-size: 12px; font-weight: 500; cursor: pointer; }
            .res { font-family: monospace; font-size: 11px; background: #f1f5f9; padding: 6px 8px; border-radius: 4px; margin-top: 6px; word-break: break-all; }
            .pass { color: #166534; font-weight: bold; }
            .fail { color: #991b1b; font-weight: bold; }
        </style>
    </head>
    <body>
        <a href="index.html" class="btn" style="background:#64748b; margin-bottom: 12px;">← Back to Suite Portal</a>

        <h2>I, J, K, L. Storage & Persistence Suite</h2>

        <div class="box">
            <h3>I. Cookies (WKHTTPCookieStore)</h3>
            <button onclick="writeCookie()">1. Write Cookie (Tab A)</button>
            <button onclick="readCookie()">2. Read Cookie (Tab B)</button>
            <div id="cookieRes" class="res">Cookie not checked yet</div>
        </div>

        <div class="box">
            <h3>J. localStorage (Persistent SQLite)</h3>
            <button onclick="writeLS()">1. Write localStorage (Tab A)</button>
            <button onclick="readLS()">2. Read localStorage (Tab B)</button>
            <div id="lsRes" class="res">localStorage not checked yet</div>
        </div>

        <div class="box">
            <h3>K. IndexedDB (Structured Storage)</h3>
            <button onclick="writeIDB()">1. Write IDB Record (Tab A)</button>
            <button onclick="readIDB()">2. Read IDB Record (Tab B)</button>
            <div id="idbRes" class="res">IndexedDB not checked yet</div>
        </div>

        <div class="box">
            <h3>L. sessionStorage (Browsing Context Isolation)</h3>
            <p style="font-size: 12px; color: #64748b;">sessionStorage must be isolated between independent tabs, but inherited initially by window.open() popups.</p>
            <button onclick="writeSS()">1. Write sessionStorage</button>
            <button onclick="readSS()">2. Read sessionStorage</button>
            <button onclick="window.open('test_storage.html?mode=ss_popup', '_blank')">3. Open Popup & Read SS</button>
            <div id="ssRes" class="res">sessionStorage not checked yet</div>
        </div>

        <script>
            const TEST_KEY = 'v43_fixture_token';

            function writeCookie() {
                const val = 'cookie_' + Date.now();
                document.cookie = TEST_KEY + '=' + encodeURIComponent(val) + '; path=/; max-age=86400';
                document.getElementById('cookieRes').innerHTML = '<span class="pass">WROTE:</span> ' + val;
                console.log('[TEST] Wrote cookie:', val);
            }
            function readCookie() {
                const c = document.cookie;
                const match = c.match(new RegExp('(^|; )' + TEST_KEY + '=([^;]*)'));
                const val = match ? decodeURIComponent(match[2]) : null;
                if (val) {
                    document.getElementById('cookieRes').innerHTML = '<span class="pass">PASS (Read Shared):</span> ' + val;
                } else {
                    document.getElementById('cookieRes').innerHTML = '<span class="fail">FAIL:</span> Token not found in document.cookie';
                }
            }

            function writeLS() {
                const val = 'ls_' + Date.now();
                localStorage.setItem(TEST_KEY, val);
                document.getElementById('lsRes').innerHTML = '<span class="pass">WROTE:</span> ' + val;
                console.log('[TEST] Wrote localStorage:', val);
            }
            function readLS() {
                const val = localStorage.getItem(TEST_KEY);
                if (val) {
                    document.getElementById('lsRes').innerHTML = '<span class="pass">PASS (Read Shared):</span> ' + val;
                } else {
                    document.getElementById('lsRes').innerHTML = '<span class="fail">FAIL:</span> Key not found in localStorage';
                }
            }

            function getDB(cb) {
                const req = indexedDB.open('v43_test_db', 1);
                req.onupgradeneeded = (e) => {
                    const db = e.target.result;
                    if (!db.objectStoreNames.contains('tokens')) {
                        db.createObjectStore('tokens', { keyPath: 'id' });
                    }
                };
                req.onsuccess = (e) => cb(e.target.result);
                req.onerror = (e) => console.error('IDB Open error', e);
            }
            function writeIDB() {
                getDB((db) => {
                    const tx = db.transaction('tokens', 'readwrite');
                    const store = tx.objectStore('tokens');
                    const val = 'idb_' + Date.now();
                    store.put({ id: TEST_KEY, value: val });
                    tx.oncomplete = () => {
                        document.getElementById('idbRes').innerHTML = '<span class="pass">WROTE:</span> ' + val;
                        console.log('[TEST] Wrote IndexedDB record:', val);
                    };
                });
            }
            function readIDB() {
                getDB((db) => {
                    const tx = db.transaction('tokens', 'readonly');
                    const store = tx.objectStore('tokens');
                    const req = store.get(TEST_KEY);
                    req.onsuccess = () => {
                        if (req.result) {
                            document.getElementById('idbRes').innerHTML = '<span class="pass">PASS (Read Shared):</span> ' + req.result.value;
                        } else {
                            document.getElementById('idbRes').innerHTML = '<span class="fail">FAIL:</span> Record not found in IndexedDB';
                        }
                    };
                });
            }

            function writeSS() {
                const val = 'ss_' + Date.now();
                sessionStorage.setItem(TEST_KEY, val);
                document.getElementById('ssRes').innerHTML = '<span class="pass">WROTE:</span> ' + val;
            }
            function readSS() {
                const val = sessionStorage.getItem(TEST_KEY);
                document.getElementById('ssRes').innerHTML = val ? 'Value: ' + val : 'Value: (empty / isolated)';
            }

            const params = new URLSearchParams(window.location.search);
            if (params.get('mode') === 'ss_popup') {
                const ssVal = sessionStorage.getItem(TEST_KEY);
                document.getElementById('ssRes').innerHTML = ssVal ? '<span class="pass">PASS: Inherited from opener</span>: ' + ssVal : '<span class="fail">Empty (Not inherited)</span>';
            }
        </script>
    </body>
    </html>
    """

    public let testDialogsHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>JavaScript Dialogs Fixture</title>
        <style>
            body { font-family: -apple-system, sans-serif; padding: 16px; line-height: 1.5; color: #1e293b; background: #fff; }
            .box { background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px; padding: 12px; margin-bottom: 12px; }
            h3 { margin-top: 0; font-size: 15px; }
            button, a.btn { display: inline-block; padding: 6px 12px; background: #007aff; color: #fff; text-decoration: none; border-radius: 6px; border: none; font-size: 12px; font-weight: 500; cursor: pointer; margin-right: 6px; }
            .res { font-family: monospace; font-size: 12px; background: #f1f5f9; padding: 6px 8px; border-radius: 4px; margin-top: 6px; }
        </style>
    </head>
    <body>
        <a href="index.html" class="btn" style="background:#64748b; margin-bottom: 12px;">← Back to Suite Portal</a>

        <h2>N. JavaScript Dialog Panels Fixture</h2>

        <div class="box">
            <h3>1. window.alert()</h3>
            <button onclick="triggerAlert()">Trigger alert()</button>
            <div id="alertRes" class="res">Not triggered</div>
        </div>

        <div class="box">
            <h3>2. window.confirm()</h3>
            <button onclick="triggerConfirm()">Trigger confirm()</button>
            <div id="confirmRes" class="res">Not triggered</div>
        </div>

        <div class="box">
            <h3>3. window.prompt()</h3>
            <button onclick="triggerPrompt()">Trigger prompt()</button>
            <div id="promptRes" class="res">Not triggered</div>
        </div>

        <script>
            function triggerAlert() {
                alert("V4.3 Test Harness Alert Message");
                document.getElementById('alertRes').innerText = "Alert dismissed by user";
                console.log('[TEST] alert() completed');
            }

            function triggerConfirm() {
                const res = confirm("Do you confirm this V4.3 WebKit action?");
                document.getElementById('confirmRes').innerText = "Result: " + (res ? "CONFIRMED (true)" : "CANCELLED (false)");
                console.log('[TEST] confirm() result:', res);
            }

            function triggerPrompt() {
                const res = prompt("Please enter text:", "Sample Input 123");
                document.getElementById('promptRes').innerText = "Result: " + (res !== null ? "ENTERED: '" + res + "'" : "CANCELLED (null)");
                console.log('[TEST] prompt() result:', res);
            }
        </script>
    </body>
    </html>
    """

    public let testDownloadHTML = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>WKDownload Engine Fixture</title>
        <style>
            body { font-family: -apple-system, sans-serif; padding: 16px; line-height: 1.5; color: #1e293b; background: #fff; }
            .box { background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px; padding: 12px; margin-bottom: 12px; }
            h3 { margin-top: 0; font-size: 15px; }
            a.btn, button { display: inline-block; padding: 6px 12px; background: #007aff; color: #fff; text-decoration: none; border-radius: 6px; border: none; font-size: 12px; font-weight: 500; cursor: pointer; }
        </style>
    </head>
    <body>
        <a href="index.html" class="btn" style="background:#64748b; margin-bottom: 12px;">← Back to Suite Portal</a>

        <h2>M. WKDownload Engine Fixture</h2>

        <div class="box">
            <h3>1. Text File Download (Data URI)</h3>
            <p>Suggested filename: <code>fixture_notes.txt</code></p>
            <a class="btn" href="data:text/plain;charset=utf-8,V4.3%20Local%20Fixture%20Download%20Content" download="fixture_notes.txt">Download fixture_notes.txt</a>
        </div>

        <div class="box">
            <h3>2. Unicode Filename (.txt)</h3>
            <p>Suggested filename: <code>türkçe_belge_2026.txt</code></p>
            <a class="btn" href="data:text/plain;charset=utf-8,Unicode%20Filename%20Test" download="türkçe_belge_2026.txt">Download türkçe_belge_2026.txt</a>
        </div>

        <div class="box">
            <h3>3. Binary Blob Stream (.bin)</h3>
            <p>Dynamically generated octet-stream blob: <code>binary_archive.bin</code></p>
            <button onclick="triggerBlobDownload()">Generate & Download binary_archive.bin</button>
        </div>

        <script>
            function triggerBlobDownload() {
                const data = new Uint8Array([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00]);
                const blob = new Blob([data], { type: 'application/octet-stream' });
                const url = URL.createObjectURL(blob);
                const a = document.createElement('a');
                a.href = url;
                a.download = 'binary_archive.bin';
                document.body.appendChild(a);
                a.click();
                document.body.removeChild(a);
                URL.revokeObjectURL(url);
                console.log('[TEST] Triggered binary blob download');
            }
        </script>
    </body>
    </html>
    """

    private func notFoundHTML(for path: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head><title>404 Fixture Not Found</title></head>
        <body style="font-family: sans-serif; padding: 20px;">
            <h2>404 Fixture Not Found</h2>
            <p>Requested path: <code>\(path)</code></p>
            <a href="index.html">← Back to Index</a>
        </body>
        </html>
        """
    }
}
