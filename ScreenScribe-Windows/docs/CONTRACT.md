# 实现接口约定

CommonJS Node >=22 / Electron 45，渲染器原生 HTML/CSS/ES modules。所有命名以本约定为准。

## Renderer bridge

`window.screenScribe.getState(): Promise<State>`
`window.screenScribe.action(name, payload={}): Promise<{ok:boolean,error?:string}>`
`window.screenScribe.onState(callback): unsubscribe`

State: `{version,platform,isDemo,settings,credentialStatus:{mathpix:boolean,vision:boolean},busy,error,notice,result,history,quota,pinned,shortcutError}`。
settings: `{provider:'mathpix'|'vision', mode:'equation'|'feynman', visionBaseURL,visionModel,captureShortcut,pasteShortcut,persistImages,monthlyImageLimit}`。
result/history entry: `{id,createdAt,mode,provider,model,code,structure,warnings:string[],confidence:number|null,imageDataUrl?:string}`。
quota: `{remaining:number|null,monthlyUsed:number|null,monthlyRemaining:number|null,detail:string,fetchedAt:string|null,completionRemainder:number,nextRefreshIn:number,stale:boolean}`。
Actions: capture, import-image, paste-image, recognize, cancel, update-settings(settings patch), save-credentials({provider,appId,apiKey,baseURL}), delete-credentials({provider,baseURL}), test-connection, save-billing({creditUSD,pendingUSD,imagePriceUSD,observedAt}), clear-billing, refresh-usage, select-history({id}), save-source({code}), delete-history({id}), clear-history, remove-history-images, copy-source({format:'plain'|'inline'|'display'|'equation'|'bracket'}), copy-png, set-pinned({value}), hide, quit, open-data-folder, open-help。

Keys are entered only in settings and cleared after saving. getState never returns any key or raw appId. Status indicates saved credentials. Historical images are optional, current selection may remain in memory.

## Services (agent providers)

`src/services/providers.cjs` exports:
- `normalizeVisionBase(baseURL):string` normalized root HTTPS URL, rejects credentials/query/fragment/full endpoint.
- `recognizeMathpix({png:Buffer,appId,apiKey,signal,beforeSend?,afterSend?,transport?}):Promise<Output>`
- `recognizeVision({png:Buffer,apiKey,baseURL,model,mode,signal,transport?}):Promise<Output>`
- `fetchMathpixUsage({appId,apiKey,now?:Date,signal,transport?}):Promise<{imageCount,periodStart:string,periodEnd:string,fetchedAt:string}>`
- `formatSource(code,format):string`; output `{code,structure:'',warnings:[],confidence:null}`.
Transport default uses Node HTTPS, no redirects, bounded body, timeout, cancellation, no response-body errors. Inject function `transport({url,method,headers,body?,signal,timeoutMs?}):Promise<object>` for tests.

## Core stores (agent stores)

`src/core/storage.cjs`: `JsonFileStore(baseDir)` with `read(name,fallback)`, `write(name,value)` (atomic, strict basename, permissions), errors safe fixed text.
`src/core/credentials.cjs`: `CredentialVault(store,cryptoAdapter)` with async `load(provider,baseURL?)`, `save(provider,value,baseURL?)`, `remove(provider,baseURL?)`, `status(provider,baseURL?)`; value Mathpix `{appId,apiKey}`, vision `{apiKey}`. cryptoAdapter async `{available(),encrypt(string):Buffer,decrypt(Buffer):string}`; never plaintext fallback. All stored encrypted only.
`src/core/history.cjs`: `HistoryStore(store)` with `.list()`, `.add(entry,{persistImages:false})`, `.update(id,code)`, `.remove(id)`, `.clear()`, `.removeImages()`. cap50/25MB; whitelist fields, no credentials; newest-first; corrupted-file error preserved not silently overwritten.
`src/core/credit.cjs`: `CreditStore(store)` with `.selectAccount(appId)`, `.saveBilling({creditUSD,pendingUSD,imagePriceUSD,observedAt})`, `.clearBilling()`, `.recordAttempt(appId)`, `.recordCompletion(appId):boolean` (5th true, persists without Billing), `.reconcile({imageCount,periodStart,periodEnd,fetchedAt})`, `.snapshot(monthlyImageLimit=0, now?:Date):quota`. Account hash key no raw appId. Exact microdollar BigInt/strings, pending reserve +$0.01, reserve initial known image-cost rounded up to cents, baseline lower-rounded image count then one-for-one local debits; high-water server count does not double-charge, cross month stale until Billing updated. Counter persistence no real accounts tests.

## Ownership
Root: main/preload/capture/settings/package/scripts/docs/integration.
Providers agent: services/** and tests/providers*.cjs.
Stores agent: core/{storage,credentials,history,credit}.cjs and corresponding tests.
UI agent: src/renderer/** (including all three views/settings/history) and no other files. Preview KaTeX path from index.html `../../assets/vendor/katex.min.js` and CSS. Local icon sprites or inline SVG DOM allowed; no CDN.
