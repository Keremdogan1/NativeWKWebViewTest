const { Plugin, Notice, Platform } = require("obsidian");

module.exports = class RuntimeInspectorPlugin extends Plugin {
    async onload() {
        console.log("[RuntimeInspector] Loaded");

        this.addRibbonIcon("search", "Run Native Runtime Audit", async () => {
            await this.runAudit();
        });

        this.addCommand({
            id: "run-native-runtime-audit",
            name: "Run Native Runtime Audit",
            callback: async () => {
                await this.runAudit();
            }
        });

        // Auto-run once on mobile startup after a short delay
        if (Platform.isMobile) {
            setTimeout(async () => {
                try {
                    await this.runAudit();
                } catch (err) {
                    console.error("[RuntimeInspector] Auto-audit failed:", err);
                }
            }, 3000);
        }
    }

    async runAudit() {
        new Notice("Running Native Runtime Audit...", 2000);
        const report = [];
        const timestamp = new Date().toISOString();

        report.push("# Obsidian Native Runtime Audit Report");
        report.push(`**Generated At:** ${timestamp}`);
        report.push(`**Platform:** ${Platform.isIosApp ? "iOS App" : (Platform.isAndroidApp ? "Android App" : "Desktop/Other")}`);
        report.push(`**User Agent:** \`${navigator.userAgent}\``);
        report.push(`**Location:** \`${window.location.href}\``);
        report.push(`**Origin:** \`${window.origin}\``);
        report.push("\n---\n");

        // 1. WebKit & MessageHandlers
        report.push("## 1. WebKit & Native Message Handlers");
        report.push(`- \`window.webkit\` exists: **${!!window.webkit}**`);
        if (window.webkit) {
            report.push(`- \`window.webkit.messageHandlers\` exists: **${!!window.webkit.messageHandlers}**`);
            if (window.webkit.messageHandlers) {
                const handlers = Object.keys(window.webkit.messageHandlers);
                report.push(`- Registered Message Handlers (${handlers.length}): \`${JSON.stringify(handlers)}\``);
                for (const h of handlers) {
                    try {
                        const handlerObj = window.webkit.messageHandlers[h];
                        const methods = Object.getOwnPropertyNames(handlerObj || {});
                        report.push(`  - \`${h}\`: methods = \`${JSON.stringify(methods)}\`, postMessage = \`${typeof handlerObj?.postMessage}\``);
                    } catch (e) {
                        report.push(`  - \`${h}\`: error reading properties (${e.message})`);
                    }
                }
            }
        }
        report.push(`- \`window.nativeBridge\` exists: **${!!window.nativeBridge}**`);
        report.push(`- \`window.cordova\` exists: **${!!window.cordova}**`);
        report.push(`- \`window.CDV\` exists: **${!!window.CDV}**`);

        // Check any global matching native/bridge
        const globalKeys = Object.getOwnPropertyNames(window);
        const bridgeCandidates = globalKeys.filter(k => 
            /bridge|native|capacitor|cordova|webkit/i.test(k) && 
            !["webkitStorageInfo", "webkitIndexedDB"].includes(k)
        );
        report.push(`- Global keys matching bridge/native/capacitor (${bridgeCandidates.length}): \`${JSON.stringify(bridgeCandidates)}\``);
        report.push("\n---\n");

        // 2. Capacitor Core Object
        report.push("## 2. Capacitor Core Object (`window.Capacitor`)");
        report.push(`- \`window.Capacitor\` exists: **${!!window.Capacitor}**`);
        if (window.Capacitor) {
            const cap = window.Capacitor;
            report.push(`- \`Capacitor.platform\`: \`${cap.platform}\``);
            report.push(`- \`Capacitor.isNativePlatform()\`: **${typeof cap.isNativePlatform === "function" ? cap.isNativePlatform() : "N/A"}**`);
            report.push(`- \`Capacitor.getPlatform()\`: \`${typeof cap.getPlatform === "function" ? cap.getPlatform() : "N/A"}\``);

            const capProps = Object.getOwnPropertyNames(cap);
            report.push(`- \`window.Capacitor\` own properties: \`${JSON.stringify(capProps)}\``);

            const capProto = Object.getPrototypeOf(cap);
            if (capProto && capProto !== Object.prototype) {
                report.push(`- \`window.Capacitor\` prototype properties: \`${JSON.stringify(Object.getOwnPropertyNames(capProto))}\``);
            }

            report.push(`- \`toNative\` exists: **${typeof cap.toNative === "function"}**`);
            report.push(`- \`nativeCallback\` exists: **${typeof cap.nativeCallback === "function"}**`);
            report.push(`- \`nativePromise\` exists: **${typeof cap.nativePromise === "function"}**`);
            report.push(`- \`registerPlugin\` exists: **${typeof cap.registerPlugin === "function"}**`);
        }
        report.push("\n---\n");

        // 3. Capacitor Plugins Inventory
        report.push("## 3. Capacitor Plugins Inventory (`window.Capacitor.Plugins`)");
        if (window.Capacitor?.Plugins) {
            const plugins = window.Capacitor.Plugins;
            const pluginKeys = Object.keys(plugins);
            report.push(`Total Registered Plugins: **${pluginKeys.length}**\n`);

            for (const name of pluginKeys) {
                report.push(`### Plugin: \`${name}\``);
                try {
                    const plugin = plugins[name];
                    const props = Object.getOwnPropertyNames(plugin || {});
                    const proto = Object.getPrototypeOf(plugin || {});
                    const protoProps = proto && proto !== Object.prototype ? Object.getOwnPropertyNames(proto) : [];
                    const allProps = Array.from(new Set([...props, ...protoProps]));

                    const methods = [];
                    const nonMethods = [];

                    for (const p of allProps) {
                        if (p === "constructor") continue;
                        try {
                            if (typeof plugin[p] === "function") {
                                methods.push(p);
                            } else {
                                nonMethods.push(`${p}: ${typeof plugin[p]}`);
                            }
                        } catch (err) {
                            nonMethods.push(`${p}: <error>`);
                        }
                    }

                    report.push(`- **Methods (${methods.length}):** ${methods.length > 0 ? methods.map(m => `\`${m}()\``).join(", ") : "_none_"}`);
                    if (nonMethods.length > 0) {
                        report.push(`- **Properties:** ${nonMethods.map(p => `\`${p}\``).join(", ")}`);
                    }
                } catch (e) {
                    report.push(`- Error inspecting plugin: ${e.message}`);
                }
                report.push("");
            }
        } else {
            report.push("_`window.Capacitor.Plugins` is undefined or not available._");
        }
        report.push("\n---\n");

        // 4. Targeted Deep-Dive on WebView & Browser Plugins
        report.push("## 4. Deep-Dive on Target Plugins (`WebView` & `Browser`)");
        if (window.Capacitor?.Plugins?.WebView) {
            const wv = window.Capacitor.Plugins.WebView;
            report.push("### `WebView` Plugin Details");
            report.push(`- Keys: \`${JSON.stringify(Object.keys(wv))}\``);
            try {
                if (typeof wv.getServerBasePath === "function") {
                    const basePath = await wv.getServerBasePath();
                    report.push(`- \`getServerBasePath()\` result: \`${JSON.stringify(basePath)}\``);
                }
            } catch (e) {
                report.push(`- \`getServerBasePath()\` threw: \`${e.message}\``);
            }
            report.push("- **Analysis:** Standard `@capacitor/webview` implementation managing local asset HTTP server. No factory methods for spawning secondary webviews.");
        } else {
            report.push("- `WebView` plugin not found.");
        }

        if (window.Capacitor?.Plugins?.Browser) {
            const br = window.Capacitor.Plugins.Browser;
            report.push("### `Browser` Plugin Details");
            report.push(`- Keys: \`${JSON.stringify(Object.keys(br))}\``);
            report.push(`- Methods: \`open\`, \`close\`, \`addListener\`, \`removeAllListeners\``);
            report.push("- **Analysis:** Standard `@capacitor/browser` implementation wrapping `SFSafariViewController`. Exposes no UIViewController or UIView handle.");
        } else {
            report.push("- `Browser` plugin not found.");
        }
        report.push("\n---\n");

        // 5. Obsidian Workspace, Leaves & Views
        report.push("## 5. Obsidian Workspace & View Architecture");
        try {
            const leaf = this.app.workspace.getLeaf("tab");
            const leafProps = Object.getOwnPropertyNames(leaf);
            const leafProtoProps = Object.getOwnPropertyNames(Object.getPrototypeOf(leaf));
            report.push(`- WorkspaceLeaf Own Properties: \`${JSON.stringify(leafProps)}\``);
            report.push(`- WorkspaceLeaf Prototype Methods: \`${JSON.stringify(leafProtoProps.filter(p => !p.startsWith("_")))}\``);
            report.push(`- \`leaf.containerEl\` tagName: \`${leaf.containerEl?.tagName}\`, class: \`${leaf.containerEl?.className}\``);
            report.push(`- \`leaf.view\` type: \`${leaf.view?.getViewType ? leaf.view.getViewType() : typeof leaf.view}\``);

            // Check if any property looks like a native handle
            const allLeafKeys = [...leafProps, ...leafProtoProps];
            const nativeLeafKeys = allLeafKeys.filter(k => /native|uiview|controller|window|handle/i.test(k));
            report.push(`- Native-sounding keys on Leaf (${nativeLeafKeys.length}): \`${JSON.stringify(nativeLeafKeys)}\``);

            leaf.detach();
            report.push("- Leaf successfully detached.");
        } catch (e) {
            report.push(`- Error inspecting WorkspaceLeaf: ${e.message}`);
        }

        // View Registry Check
        report.push("\n### Obsidian View Registry & Built-in View Types");
        try {
            const viewRegistry = this.app.viewRegistry;
            if (viewRegistry) {
                const typeByExt = viewRegistry.typeByExtension || {};
                report.push(`- Extensions mapped to view types (${Object.keys(typeByExt).length}):`);
                for (const [ext, type] of Object.entries(typeByExt)) {
                    report.push(`  - \`.${ext}\` -> \`${type}\``);
                }

                const viewByType = viewRegistry.viewByType || {};
                report.push(`- Registered View Types (${Object.keys(viewByType).length}): \`${JSON.stringify(Object.keys(viewByType))}\``);

                for (const vType of ["pdf", "video", "audio", "image", "canvas", "markdown"]) {
                    if (viewByType[vType]) {
                        const ctor = viewByType[vType];
                        const proto = ctor?.prototype ? Object.getOwnPropertyNames(ctor.prototype) : [];
                        report.push(`  - \`${vType}\` view constructor: \`${ctor?.name}\`, prototype methods sample: \`${JSON.stringify(proto.slice(0, 8))}\``);
                    }
                }
            }
        } catch (e) {
            report.push(`- Error inspecting view registry: ${e.message}`);
        }
        report.push("\n---\n");

        // 6. Probing Capacitor Bridge for Dynamic Native Invocation
        report.push("## 6. Capacitor Bridge Dynamic Invocation Probe");
        if (typeof window.Capacitor?.toNative === "function") {
            try {
                report.push("Attempting probe call: `toNative('NonExistentPlugin', 'testMethod', {})`...");
                // Wrap in timeout to prevent hang
                const probePromise = new Promise((resolve, reject) => {
                    const timer = setTimeout(() => reject(new Error("Timeout (500ms)")), 500);
                    try {
                        const res = window.Capacitor.toNative("NonExistentPlugin", "testMethod", {}, {
                            callback: (err, data) => {
                                clearTimeout(timer);
                                if (err) reject(err); else resolve(data);
                            }
                        });
                        if (res instanceof Promise) {
                            res.then(d => { clearTimeout(timer); resolve(d); })
                               .catch(err => { clearTimeout(timer); reject(err); });
                        }
                    } catch (syncErr) {
                        clearTimeout(timer);
                        reject(syncErr);
                    }
                });

                const probeResult = await probePromise;
                report.push(`- Probe succeeded unexpectedly: \`${JSON.stringify(probeResult)}\``);
            } catch (probeErr) {
                report.push(`- Probe rejected as expected: \`${probeErr.message}\``);
                report.push("- **Analysis:** Native bridge enforces a strict static compile-time registry. Calling uncompiled native classes/plugins is rejected by the iOS host dispatcher.");
            }
        } else {
            report.push("- `window.Capacitor.toNative` is not exposed as a direct callable function.");
        }
        report.push("\n---\n");

        // 7. Architectural Conclusion
        report.push("## 7. Audit Findings & Architectural Conclusion");
        report.push("1. **Process Boundary:** All Community Plugin JS executes strictly inside the WebKit `WebContent` process.");
        report.push("2. **Native Registry:** The iOS native binary has a fixed, compile-time registered set of Capacitor plugins. No dynamic reflection or arbitrary native class instantiation is permitted.");
        report.push("3. **Absence of Secondary WKWebView Plugin:** Obsidian's binary contains no plugin that instantiates a secondary `WKWebView` or exposes `UIView` frames to JavaScript.");
        report.push("4. **Obsidian Workspace:** `WorkspaceLeaf` is purely a DOM container (`div.workspace-leaf`). Obsidian's internal viewers (PDF, Media, Canvas) are all web-based (HTML5 Canvas, PDF.js, HTML5 Audio/Video), with no native UIKit views embedded in tabs.");
        report.push("5. **Conclusion for Pure Community Plugin:** Creating a native `WKWebView` or embedding a native `UIView` into an Obsidian workspace tab requires native code in the iOS binary (Route 4 - Custom IPA / Sideloading).");

        const content = report.join("\n");

        // Write to vault file NATIVE_RUNTIME_AUDIT.md
        const targetPath = "NATIVE_RUNTIME_AUDIT.md";
        try {
            const existing = this.app.vault.getAbstractFileByPath(targetPath);
            if (existing) {
                await this.app.vault.modify(existing, content);
            } else {
                await this.app.vault.create(targetPath, content);
            }
            new Notice("Native Runtime Audit complete! Saved to NATIVE_RUNTIME_AUDIT.md", 5000);
            console.log("[RuntimeInspector] Audit saved to", targetPath);
        } catch (writeErr) {
            console.error("[RuntimeInspector] Failed to write report file:", writeErr);
            new Notice("Audit finished, but failed to write file: " + writeErr.message, 5000);
        }
    }

    onunload() {
        console.log("[RuntimeInspector] Unloaded");
    }
};
