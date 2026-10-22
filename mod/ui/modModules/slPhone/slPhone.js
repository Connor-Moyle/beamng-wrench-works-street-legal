// Street Legal Racing - the phone.
// A global UI module (the game imports every /ui/modModules/<name>/<name>.js once, at start),
// so the phone stays on screen whatever app layout is up - driving, walking or in the garage.
// It looks and behaves like an Android phone: status bar, home screen with apps and a dock,
// three-button navigation, heads-up notifications. Everything it shows comes from the Lua side
// (lua/ge/extensions/sl/phone.lua) as events; its buttons call back into it.
//
// createPhone() holds all of it and is plain DOM, so tools/phonetest.js can run it outside the game.

(function () {
  'use strict';

  // the player-facing text: sl/core/strings (sl_phone.requestStrings, event slStrings). T('key', 'the text', a, b): the second argument shows until the table has
  // arrived and for a key the table lacks; {1}, {2} are the extra arguments. One table for the whole module.
  var TABLE = null;
  function T(key, fallback) {
    var text = TABLE && TABLE[key] !== undefined ? TABLE[key] : fallback, a = arguments;
    return String(text).replace(/\{(\d+)\}/g, function (m, i) { var v = a[Number(i) + 1]; return v === undefined ? '' : v; });
  }

  var CSS = [
    '.slp-root{position:fixed;left:0;top:0;right:0;bottom:0;pointer-events:none;z-index:50;font-family:"Roboto","Noto Sans","Segoe UI",Arial,sans-serif;color:#e6e1e5;-webkit-user-select:none;user-select:none}',
    '.slp-root *{box-sizing:border-box}',
    '.slp-root svg{display:block}',
    /* the device */
    '.slp-device{position:absolute;right:3vw;bottom:0;width:360px;height:760px;transform-origin:100% 100%;pointer-events:auto;',
    '  transition:transform .32s cubic-bezier(.2,.9,.25,1),opacity .2s,width .4s cubic-bezier(.3,.8,.25,1),height .4s cubic-bezier(.3,.8,.25,1);border-radius:46px;background:#0b0b0d;padding:11px;',
    '  box-shadow:0 0 0 2px #2a2a2e,0 30px 80px rgba(0,0,0,.65)}',
    '.slp-device.slp-away{opacity:0;pointer-events:none}',
    '.slp-device.slp-land{width:760px;height:380px;border-radius:34px}',
    '.slp-land .slp-mapbody{flex:1}.slp-land .slp-mapcv{height:100%}.slp-land .slp-mapbody .slp-card{position:absolute;left:10px;bottom:10px;margin:0;max-width:300px}',
    '.slp-page.slp-open{animation:slp-zoom .3s cubic-bezier(.2,.9,.25,1)}@keyframes slp-zoom{from{transform:scale(.2);opacity:0;border-radius:40px}to{transform:none;opacity:1}}',
    '@media (prefers-reduced-motion:reduce){.slp-device{transition:none !important}.slp-page.slp-open{animation:none}.slp-root *,.slp-root *:before,.slp-root *:after{transition:none!important;animation:none!important}}',
    '.slp-rm .slp-device,.slp-rm *,.slp-rm *:before,.slp-rm *:after{transition:none!important;animation:none!important}',      /* (the career option Reduce motion: the same) */
    '.slp-crack{position:absolute;left:0;top:0;width:100%;height:100%;pointer-events:none;z-index:9;border-radius:36px}.slp-crack path{fill:none;stroke-linecap:round;stroke-linejoin:round}.slp-crack-dark path{stroke:rgba(0,0,0,.55);stroke-width:2.2px;vector-effect:non-scaling-stroke}.slp-crack-light path{stroke:rgba(255,255,255,.85);stroke-width:1px;vector-effect:non-scaling-stroke}.slp-crack path.slp-shard{fill:rgba(0,0,0,.28);stroke:none}',
    '.slp-camon .slp-device,.slp-camon .slp-pill,.slp-camon .slp-hu{display:none!important}',
    '.slp-camui{position:fixed;left:0;top:0;right:0;bottom:0;z-index:30;pointer-events:none;color:#fff;font-family:"Segoe UI","Roboto","Noto Sans",sans-serif;animation:slp-sway 5.5s ease-in-out infinite;transform-origin:50% 50%}',
    '@keyframes slp-sway{0%,100%{transform:translate(0,0) rotate(0)}25%{transform:translate(calc(var(--slp-sway) * 3px),calc(var(--slp-sway) * -2px)) rotate(calc(var(--slp-sway) * .25deg))}50%{transform:translate(calc(var(--slp-sway) * -2px),calc(var(--slp-sway) * 2px)) rotate(calc(var(--slp-sway) * -.2deg))}75%{transform:translate(calc(var(--slp-sway) * 1.5px),calc(var(--slp-sway) * 1px)) rotate(calc(var(--slp-sway) * .15deg))}}',
    '.slp-cambz{position:absolute;background:#050506}.slp-cbl{left:0;top:0;bottom:0;width:5.5vh;border-radius:0 3vh 3vh 0}.slp-cbl i{position:absolute;left:1.6vh;top:50%;width:1.7vh;height:1.7vh;margin-top:-.85vh;border-radius:50%;background:#15151a;box-shadow:0 0 0 .3vh #222}',
    '.slp-cbr{right:0;top:0;bottom:0;width:3vh;border-radius:3vh 0 0 3vh}.slp-cbt{left:0;right:0;top:0;height:2.4vh}.slp-cbb{left:0;right:0;bottom:0;height:2.4vh}',
    '.slp-camgrid i,.slp-camgrid b{position:absolute;background:rgba(255,255,255,.35);display:block}.slp-camgrid i{top:0;bottom:0;width:1px}.slp-camgrid i:nth-child(1){left:33.33%}.slp-camgrid i:nth-child(2){left:66.66%}.slp-camgrid b{left:0;right:0;height:1px}.slp-camgrid b:nth-child(3){top:33.33%}.slp-camgrid b:nth-child(4){top:66.66%}',
    '.slp-camtop{position:absolute;left:8vh;right:6vh;top:3.4vh;display:flex;gap:2vh;align-items:center;font-size:2.2vh;text-shadow:0 1px 3px rgba(0,0,0,.8)}.slp-camtop span{pointer-events:auto;cursor:pointer;padding:.6vh 1.2vh;border-radius:2vh;background:rgba(0,0,0,.35)}.slp-camtop span:first-child{pointer-events:none;background:none;margin-right:auto}.slp-camtop .slp-on{background:rgba(255,213,79,.85);color:#3b2f00}.slp-camx{font-size:2.6vh}',
    '.slp-camright{position:absolute;right:7vh;top:0;bottom:0;display:flex;align-items:center}.slp-camshutter{pointer-events:auto;cursor:pointer;width:11vh;height:11vh;border-radius:50%;border:.7vh solid #fff;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.2)}.slp-camshutter i{display:block;width:8vh;height:8vh;border-radius:50%;background:#fff}.slp-camshutter:active i{transform:scale(.88)}',
    '.slp-cammodes{position:absolute;right:24vh;bottom:4.6vh;display:flex;gap:2.4vh;font-size:2vh;letter-spacing:.2vh;text-shadow:0 1px 3px rgba(0,0,0,.8)}.slp-cammodes span{opacity:.55}.slp-cammodes b{color:#ffd54f}',
    '.slp-camzoom{position:absolute;left:50%;bottom:4.2vh;transform:translateX(-50%);display:flex;gap:1.2vh;background:rgba(0,0,0,.4);border-radius:3vh;padding:.6vh 1.2vh}.slp-camzoom span{pointer-events:auto;cursor:pointer;font-size:2.2vh;padding:.8vh 1.6vh;border-radius:2.4vh}.slp-camzoom .slp-on{background:rgba(255,255,255,.9);color:#111}',
    '.slp-camflash{animation:none}.slp-camflash:before{content:"";position:absolute;left:0;top:0;right:0;bottom:0;background:#fff;opacity:0;animation:slp-fx .22s ease-out}@keyframes slp-fx{0%{opacity:.85}100%{opacity:0}}',
    '.slp-camui .slp-crack{position:absolute;left:0;top:0;width:100%;height:100%}',
    '.slp-screen{position:relative;width:100%;height:100%;border-radius:36px;overflow:hidden;background:#141218;display:flex;flex-direction:column}',
    '.slp-cam{position:absolute;left:50%;top:10px;width:11px;height:11px;margin-left:-5.5px;border-radius:50%;background:#000;box-shadow:0 0 0 2px #1d1d22;z-index:5}',
    /* status bar */
    '.slp-status{height:34px;flex:none;display:flex;align-items:center;padding:4px 22px 0 22px;font-size:13px;font-weight:500;z-index:4}',
    '.slp-status .slp-sr{margin-left:auto;display:flex;align-items:center;gap:5px}',
    '.slp-status svg{width:15px;height:15px;fill:currentColor}',
    /* home */
    '.slp-wall{position:absolute;left:0;top:0;right:0;bottom:0;background:radial-gradient(120% 70% at 20% 0%,#3b2f6b 0%,rgba(59,47,107,0) 60%),',
    '  radial-gradient(90% 60% at 100% 100%,#7a2e3d 0%,rgba(122,46,61,0) 65%),linear-gradient(#17121f,#0d0b12)}',
    '.slp-home{position:relative;flex:1;min-height:0;display:flex;flex-direction:column;padding:10px 18px 0 18px}',
    '.slp-clock{margin:26px 0 2px 4px;font-size:64px;font-weight:300;line-height:1;letter-spacing:-1px}',
    '.slp-date{margin-left:6px;font-size:15px;color:#cac4d0}',
    '.slp-chip{display:inline-block;margin:14px 0 0 4px;padding:6px 12px;border-radius:16px;background:rgba(255,255,255,.1);font-size:12px}',
    '.slp-grid{margin-top:auto;display:grid;grid-template-columns:repeat(4,1fr);row-gap:18px;padding-bottom:16px;flex:0 1 auto;min-height:0;overflow-y:auto;scrollbar-width:none}',
    '.slp-app{display:flex;flex-direction:column;align-items:center;cursor:pointer;position:relative}',
    '.slp-ico{width:56px;height:56px;border-radius:50%;display:flex;align-items:center;justify-content:center}',
    '.slp-ico svg{width:28px;height:28px;fill:#fff}',
    '.slp-ico img.slp-skinimg{width:100%;height:100%;object-fit:contain;border-radius:inherit}',
    '.slp-app span{margin-top:6px;font-size:11.5px;color:#e6e1e5}',
    '.slp-app:active .slp-ico{transform:scale(.92)}',
    '.slp-badge{position:absolute;top:-2px;left:50%;margin-left:14px;min-width:20px;height:20px;padding:0 6px;border-radius:10px;background:#f2b8b5;color:#601410;font-size:11px;font-weight:700;line-height:20px;text-align:center}',
    '.slp-dock{flex:none;display:grid;grid-template-columns:repeat(4,1fr);padding:12px 6px 14px 6px;margin:0 -6px 6px -6px;border-radius:28px;background:rgba(255,255,255,.08)}',
    /* app pages */
    '.slp-page{position:relative;flex:1;display:flex;flex-direction:column;min-height:0;background:#141218}',
    '.slp-bar{height:60px;flex:none;display:flex;align-items:center;padding:0 8px 0 4px;position:relative;z-index:2;background:#141218}'      /* (the header sits above the scroll area; the letterbox bars have their own class, slp-lb) */,
    '.slp-bar b{font-size:20px;font-weight:400;margin-left:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.slp-ib{width:44px;height:44px;border-radius:50%;display:flex;align-items:center;justify-content:center;cursor:pointer;flex:none}',
    '.slp-ib:hover{background:rgba(255,255,255,.08)}',
    '.slp-ib svg{width:22px;height:22px;fill:#e6e1e5}',
    '.slp-body{flex:1;overflow-y:auto;min-height:0;padding:0 0 12px 0;zoom:var(--sl-zoom,1)}',      /* (the text size scales the page's body, not its bar: a zoomed flex page overflowed the phone) */
    '.slp-body::-webkit-scrollbar{width:0}',
    '.slp-row{display:flex;align-items:center;padding:10px 18px;cursor:pointer;min-height:64px}',
    '.slp-row:hover{background:rgba(255,255,255,.05)}',
    '.slp-av{width:42px;height:42px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;font-size:17px;font-weight:500;color:#1d1b20}',
    '.slp-rt{flex:1;min-width:0;margin-left:14px}',
    '.slp-rt b{display:block;font-size:15.5px;font-weight:400;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.slp-rt span{display:block;font-size:13px;color:#cac4d0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:1px}',
    '.slp-rt span.slp-unread{color:#e6e1e5;font-weight:600}',
    '.slp-rx{margin-left:10px;font-size:12px;color:#cac4d0;text-align:right;flex:none}',
    '.slp-letter{padding:14px 18px 2px 18px;font-size:13px;color:#a8c7fa;font-weight:500}',
    '.slp-photos{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;padding:10px 12px}',
    '.slp-ph{aspect-ratio:16/9;border-radius:10px;background:#211f26 center/cover no-repeat;cursor:pointer;border:2px solid transparent}',
    '.slp-ph.slp-on{border-color:#a8c7fa}',
    '.slp-bigph{margin:10px 12px;border-radius:14px;width:calc(100% - 24px);aspect-ratio:16/9;background:#211f26 center/cover no-repeat}',
    '.slp-empty{padding:40px 30px;text-align:center;color:#938f99;font-size:14px;line-height:1.5}',
    '.slp-btn.slp-stack{flex-direction:column;height:auto;min-height:40px;padding:8px 16px;border-radius:16px;line-height:1.25;text-align:center}.slp-stack .slp-lbl{font-weight:500}.slp-stack small{display:block;font-weight:400;opacity:.85;white-space:normal}',      /* (a button with a label and a note under it: one column, as tall as it needs, never a 40 px pill with the note beside the label) */
    '.slp-btn{display:inline-flex;align-items:center;justify-content:center;height:40px;padding:0 20px;border-radius:20px;background:#a8c7fa;color:#062e6f;font-size:14px;font-weight:500;cursor:pointer;border:none}',
    '.slp-btn.slp-tonal{background:#3a3f4b;color:#d7e3ff}',
    '.slp-btn.slp-text{background:none;color:#a8c7fa;padding:0 12px}',
    '.slp-btn.slp-red{background:#f2b8b5;color:#601410}',
    '.slp-btn.slp-off{opacity:.38;pointer-events:none}',
    '.slp-card{margin:8px 16px;padding:14px 16px;border-radius:18px;background:#211f26}',
    '.slp-mapbody{position:relative;padding:0}.slp-mapcv{display:block;width:100%;height:340px;background:#f2efe9}.slp-mapzoom{position:absolute;right:10px;top:10px;background:#fff;border-radius:8px;box-shadow:0 1px 5px rgba(0,0,0,.4);color:#3c4043;font-size:20px;line-height:36px;text-align:center}.slp-mapzoom div{width:36px;cursor:pointer}',
    '.slp-tyres{margin:8px 0}.slp-tyrehead{font-size:13px;color:#a8c7fa;margin-bottom:4px}.slp-tyrebox{display:flex;gap:10px;align-items:center}.slp-tyrecar{flex:none}.slp-tyreaxles{flex:1;min-width:0}',
    '.slp-tabs{display:flex;gap:6px;margin:6px 14px 0 14px;overflow-x:auto;flex:none}',
    '.slp-tab{flex:none;padding:7px 14px;border-radius:16px;background:#2b2930;color:#cac4d0;font-size:12px;cursor:pointer;border:2px solid transparent}',
    '.slp-tab.slp-tabon{background:#a8c7fa;color:#062e6f;font-weight:500}.slp-tab:focus{outline:none;border-color:#e6e1e5}',
    /* the Settings app, Android style: sections, rows with a switch, a slider or a list, a developer section at the bottom */
    '.slp-seth{margin:18px 20px 4px 20px;font-size:12px;font-weight:500;letter-spacing:.06em;color:#a8c7fa;text-transform:uppercase}',
    '.slp-set{display:flex;align-items:center;gap:12px;margin:0 8px;padding:12px 12px;border-radius:14px;border:2px solid transparent}',
    '.slp-set:focus{outline:none;border-color:#a8c7fa}',
    '.slp-set .slp-st{flex:1;min-width:0}',
    '.slp-set .slp-st b{display:block;font-size:14px;font-weight:400}',
    '.slp-set .slp-st small{display:block;color:#938f99;font-size:11px;margin-top:2px}',
    '.slp-sw{flex:none;width:44px;height:24px;border-radius:12px;background:#49454f;position:relative}',
    '.slp-sw i{position:absolute;left:3px;top:3px;width:18px;height:18px;border-radius:50%;background:#938f99;transition:left .15s}',
    '.slp-sw.slp-swon{background:#a8c7fa}.slp-sw.slp-swon i{left:23px;background:#062e6f}',
    '.slp-val{flex:none;display:flex;align-items:center;gap:6px;font-size:13px;color:#e6e1e5}',
    '.slp-val .slp-mini{width:28px;height:28px;border-radius:50%;background:#2b3a52;color:#d3e3fd;display:flex;align-items:center;justify-content:center;cursor:pointer;border:2px solid transparent}',
    '.slp-val .slp-mini:focus{outline:none;border-color:#a8c7fa}',
    '.slp-range{width:100%;margin-top:6px}',
    /* a car ad as the stock shop lists a car: the config's picture first */
    '.slp-pic{margin:-14px -16px 10px -16px;aspect-ratio:16/9;border-radius:18px 18px 0 0;overflow:hidden;background:#0d0b12;display:flex;align-items:center;justify-content:center;color:#6f6a78;font-size:12px}',
    '.slp-pic{position:relative}',
    '.slp-pic img{position:absolute;left:0;top:0;width:100%;height:100%;object-fit:cover}',
    '.slp-pic img.slp-partpic{object-fit:contain;padding:8px;box-sizing:border-box}',
    '.slp-pico svg{width:56px;height:56px;fill:#6f6a78}',
    '.slp-pbadge{position:absolute;left:10px;bottom:10px;display:flex;align-items:center;gap:6px;padding:4px 10px 4px 6px;border-radius:14px;background:rgba(20,18,24,.82);color:#e6e1e5;font-size:12px}',
    '.slp-pbadge svg{width:18px;height:18px;fill:#a8c7fa}',
    '.slp-card.slp-mini .slp-pic{aspect-ratio:21/9}',
    '.slp-card h4{margin:0 0 4px 0;font-size:15px;font-weight:500}',
    '.slp-card p{margin:0;font-size:13px;color:#cac4d0;line-height:1.45}',
    '.slp-card .slp-acts{display:flex;gap:8px;margin-top:12px;flex-wrap:wrap}',
    /* contact card */
    '.slp-hero{display:flex;flex-direction:column;align-items:center;padding:10px 20px 6px 20px;text-align:center}',
    '.slp-hero .slp-av{width:96px;height:96px;font-size:40px}',
    '.slp-hero b{margin-top:14px;font-size:22px;font-weight:400}',
    '.slp-hero span{margin-top:4px;font-size:14px;color:#cac4d0}',
    '.slp-acts3{display:flex;justify-content:center;gap:28px;margin:18px 0 10px 0}',
    '.slp-act{display:flex;flex-direction:column;align-items:center;cursor:pointer;font-size:12px;color:#a8c7fa}',
    '.slp-act i{width:52px;height:52px;border-radius:50%;background:#2b2930;display:flex;align-items:center;justify-content:center;margin-bottom:6px}',
    '.slp-act i svg{width:24px;height:24px;fill:#a8c7fa}',
    '.slp-stars,.slp-rt span .slp-stars,.slp-hero span .slp-stars{display:inline;color:#ffd56b;letter-spacing:1px;margin:0}',
    /* messages */
    '.slp-msgs{flex:1;overflow-y:auto;padding:8px 12px 4px 12px;display:flex;flex-direction:column;min-height:0}',
    '.slp-msgs::-webkit-scrollbar{width:0}',
    '.slp-bub{max-width:78%;padding:9px 13px;margin:3px 0;border-radius:20px;font-size:14px;line-height:1.35;word-wrap:break-word}',
    '.slp-bub.slp-them{align-self:flex-start;background:#2b2930;border-bottom-left-radius:6px}',
    '.slp-bub.slp-me{align-self:flex-end;background:#a8c7fa;color:#062e6f;border-bottom-right-radius:6px}',
    '.slp-quick{flex:none;display:flex;gap:8px;padding:8px 12px 10px 12px;overflow-x:auto}',
    '.slp-quick::-webkit-scrollbar{height:0}',
    '.slp-qc{flex:none;padding:8px 14px;border-radius:18px;border:1px solid #49454f;font-size:13px;cursor:pointer;white-space:nowrap}',
    '.slp-qc:hover{background:rgba(168,199,250,.12)}',
    /* dialler */
    '.slp-num{height:72px;display:flex;align-items:center;justify-content:center;font-size:34px;font-weight:300;letter-spacing:1px}',
    '.slp-who{text-align:center;font-size:13px;color:#a8c7fa;height:18px}',
    '.slp-keys{display:grid;grid-template-columns:repeat(3,1fr);row-gap:10px;padding:8px 34px}',
    '.slp-key{width:68px;height:68px;margin:0 auto;border-radius:50%;background:#2b2930;display:flex;flex-direction:column;align-items:center;justify-content:center;cursor:pointer;font-size:28px}',
    '.slp-key small{font-size:9px;letter-spacing:1.5px;color:#cac4d0;margin-top:-2px}',
    '.slp-key:active{background:#49454f}',
    '.slp-dial{width:64px;height:64px;margin:14px auto 0 auto;border-radius:50%;background:#6dd58c;display:flex;align-items:center;justify-content:center;cursor:pointer}',
    '.slp-dial svg{width:28px;height:28px;fill:#0b3d1d}',
    /* call screen */
    '.slp-call{position:absolute;left:0;top:0;right:0;bottom:0;display:flex;flex-direction:column;align-items:center;padding:70px 22px 66px 22px;',
    '  background:linear-gradient(#1e2a3f,#0e1018);z-index:3}',
    '.slp-call .slp-av{width:110px;height:110px;font-size:46px}',
    '.slp-call b{margin-top:18px;font-size:26px;font-weight:400;text-align:center}',
    '.slp-call .slp-cs{margin-top:6px;font-size:14px;color:#cac4d0}',
    '.slp-said{margin-top:22px;max-width:100%;padding:12px 16px;border-radius:18px;background:rgba(255,255,255,.08);font-size:14.5px;line-height:1.4;text-align:center}',
    '.slp-opts{margin-top:18px;display:flex;flex-direction:column;gap:9px;width:100%}',
    '.slp-opts .slp-btn{width:100%}',
    '.slp-hang{margin-top:auto;width:68px;height:68px;border-radius:50%;background:#e64a4a;display:flex;align-items:center;justify-content:center;cursor:pointer;flex:none}',
    '.slp-hang svg{width:30px;height:30px;fill:#fff;transform:rotate(135deg)}',
    '.slp-ring .slp-av{animation:slpring 1.2s ease-in-out infinite}',
    '@keyframes slpring{0%,100%{box-shadow:0 0 0 0 rgba(168,199,250,.5)}50%{box-shadow:0 0 0 18px rgba(168,199,250,0)}}',
    /* bank, profile */
    '.slp-bal{padding:6px 22px 14px 22px}',
    '.slp-bal small{font-size:13px;color:#cac4d0}',
    '.slp-bal div{font-size:40px;font-weight:300;margin-top:2px}',
    '.slp-amt{font-variant-numeric:tabular-nums;font-size:14px}',
    '.slp-plus{color:#6dd58c}.slp-minus{color:#f2b8b5}',
    '.slp-meter{height:8px;border-radius:4px;background:#2b2930;overflow:hidden;margin-top:10px}',
    '.slp-meter i{display:block;height:100%;background:#a8c7fa;border-radius:4px}',
    /* #51 colour-blind friendly colours (Settings > Colour-blind friendly colours): blue and orange (Okabe-Ito) instead of green and red, a mark beside every good or bad figure */
    '.slp-cb .slp-plus,.slp-cb .slp-rok,.slp-cb .slp-rs,.slp-cb b.slp-on,.slp-cb .slp-lotfaults.slp-ok{color:#56b4e9}',
    '.slp-cb .slp-minus,.slp-cb .slp-rbad,.slp-cb .slp-rf,.slp-cb .slp-lotfaults,.slp-cb .slp-warn{color:#ffb454}.slp-cb .slp-lotfaults.slp-ok{color:#56b4e9}',
    '.slp-cb i.slp-ahead{background:#56b4e9;color:#062e4a}.slp-cb i.slp-behind{background:#ffb454;color:#3b2600}',
    '.slp-cb .slp-plus:before{content:"\\25B2 "}.slp-cb .slp-minus:before{content:"\\25BC "}.slp-cb .slp-rok:before,.slp-cb .slp-lotfaults.slp-ok:before{content:"\\2714 "}',
    '.slp-cb i.slp-ahead:before{content:"\\25B2 "}.slp-cb i.slp-behind:before{content:"\\25BC "}',
    /* #51 the pad's focus is always visible: a thick yellow ring on whatever is focused */
    '[bng-nav-item]:focus,[data-a]:focus,[tabindex]:focus{outline:3px solid #ffd54f!important;outline-offset:2px;box-shadow:0 0 0 2px #0d0b12}',      /* (docs/UI_STYLE.md: a dark band between the control and the ring so it shows on a yellow or accent fill) */
    '.slp-report{margin:6px 0}.slp-rsec{margin:8px 0;padding:8px 10px;border-radius:12px;background:#0d0b12}.slp-rsec h5{margin:0 0 4px;font-size:13px;color:#a8c7fa}.slp-rok{color:#7bd88f}.slp-rmid{color:#e6c35c}.slp-rbad{color:#f2b8b5}',
    '.slp-kv{display:flex;justify-content:space-between;padding:7px 0;font-size:14px;border-bottom:1px solid #2b2930}',
    '.slp-kv span{color:#cac4d0}',
    /* nav bar */
    '.slp-nav{height:48px;flex:none;display:flex;align-items:center;justify-content:space-around;padding:0 40px;background:#141218;z-index:4}',
    '.slp-home-on .slp-nav{background:transparent}',
    '.slp-nav div{width:48px;height:40px;display:flex;align-items:center;justify-content:center;cursor:pointer;border-radius:20px}',
    '.slp-nav div:hover{background:rgba(255,255,255,.08)}',
    '.slp-nav svg{width:18px;height:18px;fill:none;stroke:#e6e1e5;stroke-width:2.2}',
    /* heads-up notification, toast, little readout */
    '.slp-hu{position:absolute;right:3vw;top:3vh;width:360px;padding:12px 14px;border-radius:22px;background:#2b2930;box-shadow:0 10px 30px rgba(0,0,0,.5);',
    '  display:flex;align-items:flex-start;gap:12px;pointer-events:auto;cursor:pointer;transition:transform .3s,opacity .3s}',
    '.slp-hu.slp-gone{transform:translateY(-140%);opacity:0;pointer-events:none}',
    '.slp-hu .slp-av{width:36px;height:36px;font-size:15px}',
    '.slp-hu b{display:block;font-size:13px;font-weight:500}',
    '.slp-hu span{display:block;font-size:13.5px;color:#e6e1e5;margin-top:2px;line-height:1.35}',
    '.slp-hu small{font-size:11px;color:#cac4d0}',
    '.slp-toast{position:absolute;left:50%;bottom:9vh;transform:translateX(-50%);max-width:70%;padding:12px 20px;border-radius:24px;background:#e6e1e5;color:#1d1b20;font-size:14px;transition:opacity .3s}',
    '.slp-toast.slp-gone{opacity:0}',
    '.slp-pill{position:absolute;right:3vw;top:1.2vh;padding:6px 14px;border-radius:16px;background:rgba(20,18,24,.72);font-size:13px;display:flex;gap:12px;align-items:center}',
    '.slp-pill b{font-weight:600}',
    '.slp-bars{position:absolute;left:0;top:0;right:0;bottom:0;pointer-events:none}',
    '.slp-lb{position:absolute;left:0;right:0;height:9vh;background:#000;transition:transform .6s ease}',
    '.slp-lbtop{top:0;transform:translateY(-100%)}.slp-lbbot{bottom:0;transform:translateY(100%)}',
    '.slp-bars.slp-on .slp-lb{transform:none}',
    /* while the camera plays its shots the car card shrinks to a bar at the bottom (the car stays centred and in view); the full card returns with the camera input */
    '.slp-barson .slp-lot:not(.slp-shop){width:min(980px,94vw);bottom:1.4vh;padding:6px 18px;border-radius:16px;display:flex;align-items:center;gap:16px}',
    '.slp-barson .slp-lot:not(.slp-shop)>.slp-lothead,.slp-barson .slp-lot:not(.slp-shop)>.slp-lottitle,.slp-barson .slp-lot:not(.slp-shop)>.slp-lotstats,.slp-barson .slp-lot:not(.slp-shop)>.slp-lotfaults,',
    '.slp-barson .slp-lot:not(.slp-shop)>.slp-report,.slp-barson .slp-lot:not(.slp-shop)>.slp-acts,.slp-barson .slp-lot:not(.slp-shop)>.slp-lotleave,.slp-barson .slp-lot:not(.slp-shop)>.slp-lotfactory{display:none}',
    '.slp-barson .slp-lot:not(.slp-shop)>.slp-lotname{margin:0;flex:1}.slp-barson .slp-lot:not(.slp-shop)>.slp-lotprice{margin:0;font-size:22px}.slp-barson .slp-lot:not(.slp-shop)>.slp-lotbtns{margin:0;flex:2}',
    /* the full car report: a panel that fits the screen, its body scrolls */
    '.slp-repmodal{position:absolute;left:0;top:0;right:0;bottom:0;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;pointer-events:auto;z-index:5}',
    '.slp-reppanel{width:min(760px,92vw);max-height:80vh;display:flex;flex-direction:column;border-radius:20px;background:rgba(20,18,24,.98);box-shadow:0 20px 60px rgba(0,0,0,.6);overflow:hidden}',
    '.slp-rephead{display:flex;align-items:center;gap:14px;padding:14px 18px;border-bottom:1px solid rgba(255,255,255,.12)}.slp-rephead b{flex:1;font-size:19px;font-weight:500}',
    '.slp-repbody{flex:1 1 auto;min-height:0;overflow-y:auto;padding:10px 18px 18px;font-size:15px;line-height:1.5}',
    '.slp-repsum{display:grid;grid-template-columns:1.3fr 1fr 1.4fr auto;gap:12px;align-items:center;margin-top:8px;padding:10px 12px;border-radius:12px;background:#0d0b12;cursor:pointer}',
    '.slp-repsum:focus,.slp-repsum:hover{outline:2px solid #a8c7fa}.slp-repparts{margin:2px 0 6px 14px}',
    '.slp-fade{position:absolute;left:0;top:0;right:0;bottom:0;background:#000;opacity:0;transition:opacity .5s}',
    /* the car lots: one car at a time, the SLRR way */
    '.slp-catch{position:absolute;left:0;top:0;right:0;bottom:0;pointer-events:auto;cursor:move;background:rgba(0,0,0,.01)}',
    '.slp-lot{position:absolute;left:50%;bottom:4vh;transform:translateX(-50%);width:640px;max-width:92vw;padding:18px 22px 14px 22px;border-radius:24px;',
    '  background:rgba(20,18,24,.9);pointer-events:auto;box-shadow:0 20px 60px rgba(0,0,0,.5)}',
    '.slp-lothead{display:flex;justify-content:space-between;font-size:12px;letter-spacing:1px;text-transform:uppercase;color:#cac4d0}',
    '.slp-lotname{margin-top:6px;font-size:15px;color:#cac4d0}',
    '.slp-rmap{display:block;width:100%;height:auto;margin:-4px 0 6px 0;border-radius:12px;background:#0d0b12}',
    '.slp-rmeta{font-size:12px;color:#cac4d0}.slp-rs{color:#7bd88f}.slp-rf{color:#f2b8b5}',
    '.slp-lotload{position:fixed;left:0;top:0;right:0;bottom:0;display:flex;align-items:center;justify-content:center;background:rgba(10,9,14,.94);z-index:60;pointer-events:auto}',
    '.slp-lotload .slp-lcard{min-width:300px;max-width:80vw;padding:26px 34px;border-radius:24px;background:#211f26;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.6)}',
    '.slp-lotload b{display:block;font-size:20px;font-weight:400;margin:14px 0 4px 0}',
    '.slp-lotload span{display:block;font-size:14px;color:#cac4d0}',
    '.slp-lotload .slp-lbar{height:6px;margin-top:14px;border-radius:3px;background:rgba(255,255,255,.12);overflow:hidden}',
    '.slp-lotload .slp-lbar i{display:block;height:100%;background:#a8c7fa;transition:width .3s}',
    '.slp-lotload .slp-spin{width:34px;height:34px;margin:0 auto;border-radius:50%;border:3px solid rgba(255,255,255,.15);border-top-color:#a8c7fa;animation:slpspin 1s linear infinite}',
    '@keyframes slpspin{to{transform:rotate(360deg)}}',
    '.slp-lotname b{display:block;font-size:28px;font-weight:400;color:#e6e1e5;line-height:1.15}',
    '.slp-lottitle{display:inline-block;margin-top:6px;padding:3px 10px;border-radius:10px;background:#3a3f4b;font-size:12px;color:#d7e3ff}',
    '.slp-lotstats{display:flex;gap:22px;margin-top:12px;font-size:13px;color:#cac4d0}',
    '.slp-lotstats b{display:block;font-size:16px;font-weight:500;color:#e6e1e5}',
    '.slp-lotfaults{margin-top:10px;font-size:13px;color:#f2b8b5}',
    '.slp-lotfaults.slp-ok{color:#6dd58c}',
    '.slp-lotprice{margin-top:10px;font-size:34px;font-weight:300}',
    '.slp-shop{width:min(1100px,94vw);top:4vh;bottom:4vh;transform:translateX(-50%);overflow:auto}',
    '.slp-shopgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:12px;margin-top:12px}',
    '.slp-shopcard{cursor:pointer;display:flex;flex-direction:column;gap:3px;padding:8px;border-radius:14px;background:rgba(255,255,255,.07)}',
    '.slp-shopcard:hover,.slp-shopcard:focus{background:rgba(255,255,255,.16)}',
    '.slp-shopimg{width:100%;aspect-ratio:16/9;object-fit:cover;border-radius:10px;background:rgba(255,255,255,.08)}',
    '.slp-shopcfg{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1.2fr);gap:16px;margin-top:12px}',
    '.slp-swatches{display:flex;flex-wrap:wrap;gap:8px;margin:6px 0}',
    '.slp-swatch{width:34px;height:34px;border-radius:50%;border:2px solid rgba(255,255,255,.35);cursor:pointer}',
    '.slp-swatch.slp-on,.slp-opt.slp-on{outline:3px solid #fff}',
    '.slp-optrow{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:4px 0}',
    '.slp-opt{cursor:pointer;padding:5px 10px;border-radius:10px;background:rgba(255,255,255,.1)}',
    '.slp-lotbtns{display:flex;align-items:center;gap:10px;margin-top:12px}',
    '.slp-lotbtns .slp-btn{flex:1}',
    '.slp-arrow{width:48px;height:48px;border-radius:50%;background:#2b2930;display:flex;align-items:center;justify-content:center;cursor:pointer;font-size:18px;flex:none}',
    '.slp-arrow:hover{background:#49454f}',
    '.slp-lotleave,.slp-lotfactory{text-align:center;margin-top:8px}',
    /* race HUD */
    '.slp-race{position:absolute;left:50%;top:2vh;transform:translateX(-50%);min-width:340px;padding:10px 20px;border-radius:20px;background:rgba(20,18,24,.85);text-align:center}',
    '.slp-race b{display:block;font-size:16px;font-weight:500}',
    '.slp-race span{display:block;font-size:13px;color:#cac4d0;margin-top:2px}',
    '.slp-race i{display:inline-block;margin-top:6px;padding:2px 12px;border-radius:10px;font-style:normal;font-size:12px;font-weight:600}',
    '.slp-race i.slp-ahead{background:#6dd58c;color:#0b3d1d}.slp-race i.slp-behind{background:#f2b8b5;color:#601410}',
    '.slp-count{position:absolute;left:50%;top:30vh;transform:translateX(-50%);font-size:140px;font-weight:200;text-shadow:0 0 40px rgba(0,0,0,.6)}',
    /* a car meet */
    '.slp-meet{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:560px;max-width:92vw;max-height:80vh;overflow-y:auto;padding:18px 20px;border-radius:24px;',
    '  background:rgba(20,18,24,.94);pointer-events:auto}',
    '.slp-meet h3{margin:0 0 4px 0;font-size:22px;font-weight:400}',
    '.slp-meet .slp-row{cursor:default;padding:10px 0}',
    '.slp-meet .slp-acts{display:flex;gap:6px;margin-left:10px}',
    '.slp-meet .slp-btn{height:34px;padding:0 12px;font-size:13px}',
    /* the main menu's own button */
    '.slp-menu{position:absolute;right:3vw;bottom:9vh;width:340px;padding:18px 20px 16px 20px;border-radius:20px;background:rgba(14,12,18,.88);pointer-events:auto;',
    '  border-left:5px solid #ff6a00;box-shadow:0 18px 50px rgba(0,0,0,.5);z-index:9999}',
    '.slp-menu h2{margin:0;font-family:"Overpass","Roboto",sans-serif;font-style:italic;font-weight:800;font-size:26px;letter-spacing:.5px;color:#ff8a2a;text-transform:uppercase;line-height:1.05}',
    '.slp-menu p{margin:6px 0 12px 0;font-size:13px;color:#cac4d0;line-height:1.4}',
    '.slp-menu .slp-btn{width:100%;margin-top:8px}',
    '.slp-pink{color:#ff7eb6;font-weight:500}',
    '.slp-slrr{display:block;image-rendering:auto}',
    '.slp-appimg{width:70%;height:70%;object-fit:contain}',
    '.slp-arrow .slp-slrr{width:30px;height:30px}',
    '.slp-chcard .slp-chimg{width:100%;max-height:96px;object-fit:contain;margin:6px 0 4px 0}',
    '.slp-hudrow{cursor:pointer}',
    '.slp-carcare{margin-top:8px}',
    '.slp-grades .slp-btn{font-size:12px;line-height:1.25;padding:8px 6px}',
    '.slp-grades small{opacity:.75}',
    '.slp-warn{color:#ffb4ab}',
    '.slp-trunk{margin-top:8px;font-size:12px;letter-spacing:1px;text-transform:uppercase;color:#938f99}',
    '.slp-hudrow b.slp-on{color:#6dd58c}',
    '.slp-hudrow b.slp-offtxt{color:#938f99}',
    '.slp-pinkbtn{background:#ff5fa2;color:#2b0016}',
    '.slp-menu .slp-go{background:#ff6a00;color:#1d0d00}',
    /* the main menu's Career button asks which career */
    '.slp-chooser{position:absolute;left:0;top:0;right:0;bottom:0;background:rgba(6,6,10,.62);display:flex;align-items:center;justify-content:center;pointer-events:auto;z-index:10000}',
    '.slp-chbox{width:min(860px,92vw);font-family:"Overpass","Roboto",sans-serif}',
    '.slp-chbox h1{margin:0 0 14px 4px;font-style:italic;font-weight:800;font-size:34px;letter-spacing:.5px;text-transform:uppercase;color:#fff}',
    '.slp-chcards{display:flex;gap:16px}',
    '.slp-chcard{flex:1;min-height:230px;padding:22px 22px 18px 22px;border-radius:6px;cursor:pointer;display:flex;flex-direction:column;',
    '  background:linear-gradient(160deg,rgba(40,40,46,.96),rgba(18,18,22,.96));border-left:5px solid #ff6600;box-shadow:0 14px 40px rgba(0,0,0,.55);transition:transform .12s}',
    '.slp-chcard:hover{transform:translateY(-3px);background:linear-gradient(160deg,rgba(58,52,48,.98),rgba(24,22,22,.98))}',
    '.slp-chcard b{font-style:italic;font-weight:800;font-size:26px;text-transform:uppercase;color:#fff;line-height:1.05}',
    '.slp-chcard span{margin-top:8px;font-size:14px;color:#c9c5c0;line-height:1.45;flex:1}',
    '.slp-chcard.slp-chsl{border-left-color:#ff2a6d;background:linear-gradient(160deg,rgba(46,22,40,.96),rgba(14,10,20,.96))}',
    '.slp-chcard.slp-chsl b{color:#ff8a2a}',
    '.slp-slots{max-height:180px;overflow-y:auto;margin:6px 0}.slp-slot{padding:6px 0;border-top:1px solid rgba(255,255,255,.12)}.slp-slot span{display:block;opacity:.8}',
    '.slp-routename{width:130px;background:rgba(0,0,0,.35);color:#fff;border:1px solid rgba(255,255,255,.25);border-radius:4px;padding:2px 6px}',
    '.slp-slotname{width:110px;background:rgba(0,0,0,.35);color:#fff;border:1px solid rgba(255,255,255,.25);border-radius:4px;padding:2px 6px}',
    '.slp-chcard .slp-btn{margin-top:8px;border-radius:4px;font-family:"Overpass","Roboto",sans-serif;font-weight:700;text-transform:uppercase;letter-spacing:.4px}',
    '.slp-chcard .slp-go{background:#ff6600;color:#1d0d00}',
    '.slp-chback .slp-btn{border-radius:4px;background:rgba(40,40,46,.92);color:#fff;padding:8px 22px}',
    '.slp-chcard.slp-off{opacity:.55;cursor:default}',
    '.slp-chback{margin-top:14px;text-align:right}',
    '.slp-hudtest{position:absolute;left:50%;top:2vh;transform:translateX(-50%);padding:10px 18px;border-radius:20px;background:rgba(20,18,24,.85);pointer-events:auto;display:flex;align-items:center;gap:14px;font-size:14px}',
    '.slp-fade.slp-in{opacity:1}',
  ].join('\n');

  // icons (Material-style shapes, drawn here)
  function svg(path, viewBox) { return '<svg viewBox="' + (viewBox || '0 0 24 24') + '"><path d="' + path + '"/></svg>'; }
  var I = {
    map: svg('M20.500 3l-.2.1L15 5.100 9 3 3.360 4.900a.5.5 0 0 0-.36.480V20.500a.5.5 0 0 0 .5.5l.2-.1L9 18.900l6 2.100 5.640-1.900a.5.5 0 0 0 .36-.480V3.500a.5.5 0 0 0-.5-.5zM15 19l-6-2.110V5l6 2.110z'),
    camera: svg('M9 3 7.2 5H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V7a2 2 0 0 0-2-2h-3.200L15 3zm3 14.500a4.500 4.500 0 1 1 0-9 4.500 4.500 0 0 1 0 9zm0-2a2.500 2.500 0 1 0 0-5 2.500 2.500 0 0 0 0 5z'),
    gallery: svg('M21 19V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2zM8.500 13.500l2.500 3 3.500-4.500 4.500 6H5z'),
    settings: svg('M19.400 13a7.600 7.600 0 0 0 0-2l2-1.600-2-3.400-2.400 1a7.500 7.500 0 0 0-1.700-1L15 3.400h-4l-.4 2.600a7.500 7.500 0 0 0-1.700 1l-2.400-1-2 3.400 2 1.600a7.600 7.600 0 0 0 0 2l-2 1.600 2 3.400 2.400-1c.5.400 1.100.7 1.700 1l.4 2.600h4l.4-2.600c.6-.3 1.200-.6 1.700-1l2.400 1 2-3.400zM13 15.500a3.500 3.500 0 1 1 0-7 3.500 3.500 0 0 1 0 7z'),
    help: svg('M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 16h-2v-2h2zm2.100-7.700-.9.9c-.7.700-1.200 1.300-1.200 2.800h-2v-.5c0-1.100.5-2.100 1.200-2.800l1.200-1.300a2 2 0 1 0-3.400-1.400H8a4 4 0 1 1 8 0c0 .9-.4 1.700-.9 2.300z'),
    wait: svg('M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 5v5.4l4 2.3-.8 1.3L11 13V7z'),
    market: svg('M3 4h18l-2 6H5zm2 8h14v8H5zm4 2v4h6v-4z'),
    // what a part ad shows when there is no picture (and beside the picture): its category
    cat_engine: svg('M7 5h4v2h2V5h4v3h2v3h2v6h-2v2H5v-2H3v-5h2V8h2zm2 6v4h8v-4z'),
    cat_body: svg('M5 11l2-5h10l2 5h1v6h-2v1h-3v-1H9v1H6v-1H4v-6zm3-3l-1 3h10l-1-3zm0 6a1 1 0 1 0 0 2 1 1 0 0 0 0-2zm8 0a1 1 0 1 0 0 2 1 1 0 0 0 0-2z'),
    cat_running: svg('M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zm0 3a6 6 0 1 1 0 12 6 6 0 0 1 0-12zm0 4a2 2 0 1 0 0 4 2 2 0 0 0 0-4z'),
    cat_interior: svg('M7 3h6a3 3 0 0 1 3 3v6h3v5h-4v4h-2v-4H8v4H6v-4H4V7a4 4 0 0 1 3-4z'),
    cat_paint: svg('M12 2.5s6 6.2 6 10.5a6 6 0 0 1-12 0C6 8.700 12 2.500 12 2.500z'),
    cat_part: svg('M20.500 6.500a5 5 0 0 1-6.700 5.600L8 17.900 6 20 4 18l2.100-2L12 10.200A5 5 0 0 1 17.500 3.500l-3 3L16.500 8.500z'),
    cat_car: svg('M5 11l1.500-4.500A2 2 0 0 1 8.400 5h7.200a2 2 0 0 1 1.900 1.500L19 11h1v6h-2v1.500h-3V17H9v1.500H6V17H4v-6zm3.200-4l-1 3.500h9.600L15.800 7z'),
    paper: svg('M4 4h13v14a2 2 0 0 0 2 2H6a2 2 0 0 1-2-2zm15 4h2v10a2 2 0 0 1-2 2zM7 7v3h7V7zm0 5v1h7v-1zm0 3v1h7v-1z'),
    bid: svg('M14 3l7 7-3 3-7-7zM9 8l7 7-2 2-7-7zM3 20l6-6 2 2-6 6zM13 21h8v-2h-8z'),
    phone: svg('M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2a1 1 0 0 1 1-.25 11.4 11.4 0 0 0 3.6.57 1 1 0 0 1 1 1V20a1 1 0 0 1-1 1A17 17 0 0 1 3 4a1 1 0 0 1 1-1h3.5a1 1 0 0 1 1 1c0 1.25.2 2.45.57 3.57a1 1 0 0 1-.25 1z'),
    msg: svg('M20 2H4a2 2 0 0 0-2 2v18l4-4h14a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2zM6 9h12v2H6zm8 5H6v-2h8zm4-6H6V6h12z'),
    contacts: svg('M12 12a4 4 0 1 0-4-4 4 4 0 0 0 4 4zm0 2c-2.7 0-8 1.3-8 4v2h16v-2c0-2.7-5.3-4-8-4z'),
    flag: svg('M14.4 6 14 4H5v17h2v-7h5.6l.4 2h7V6z'),
    bank: svg('M4 10v7h3v-7zm6 0v7h3v-7zM2 22h19v-3H2zm14-12v7h3v-7zM11.5 1 2 6v2h19V6z'),
    house: svg('M12 3 2 12h3v8h5v-6h4v6h5v-8h3z'),
    health: svg('M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z'),
    food: svg('M11 9H9V2H7v7H5V2H3v7c0 2.12 1.66 3.84 3.75 3.97V22h2.5v-9.03C11.34 12.84 13 11.12 13 9V2h-2v7zm5-3v8h2.5v8H21V2c-2.76 0-5 2.24-5 4z'),
    water: svg('M12 2c-5.33 4.55-8 8.48-8 11.8 0 4.98 3.8 8.2 8 8.2s8-3.22 8-8.2c0-3.32-2.67-7.25-8-11.8z'),
    rest: svg('M12 3a9 9 0 1 0 9 9c0-.46-.04-.92-.1-1.36a5.389 5.389 0 0 1-4.4 2.26 5.403 5.403 0 0 1-3.14-9.8c-.44-.06-.9-.1-1.36-.1z'),
    sponsors: svg('M12 2l3.09 6.26L22 9.27l-5 4.87L18.18 21 12 17.77 5.82 21 7 14.14 2 9.27l6.91-1.01z'),
    event: svg('M14.4 6 14 4H5v17h2v-7h5.6l.4 2h7V6z'),
    calendar: svg('M19 3h-1V1h-2v2H8V1H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm0 16H5V9h14zM5 7V5h14v2zm2 4h5v5H7z'),
    inventory: svg('M20 7l-8-4-8 4v10l8 4 8-4zM4 7l8 4 8-4M12 11v10'),
    myroute: svg('M9 11.5A2.5 2.5 0 1 1 9 6.5a2.5 2.5 0 0 1 0 5zM9 2a6.500 6.500 0 0 0-6.500 6.500C2.500 13.400 9 21 9 21s6.500-7.600 6.500-12.500A6.500 6.500 0 0 0 9 2zm10 11h-4v2h4a1 1 0 0 1 0 2h-3v2h3a3 3 0 0 0 0-6z'),
    traps: svg('M20.38 8.57l-1.23 1.85a8 8 0 0 1-.22 7.58H5.07A8 8 0 0 1 15.58 6.85l1.85-1.23A10 10 0 0 0 3.35 19a2 2 0 0 0 1.72 1h13.85a2 2 0 0 0 1.74-1 10 10 0 0 0-.27-10.44zm-9.79 6.84a2 2 0 0 0 2.83 0l5.66-8.49-8.49 5.66a2 2 0 0 0 0 2.83z'),
    cab: svg('M18.9 6c-.2-.6-.8-1-1.4-1h-11c-.7 0-1.2.4-1.4 1L3 12v8a1 1 0 0 0 1 1h1a1 1 0 0 0 1-1v-1h12v1a1 1 0 0 0 1 1h1a1 1 0 0 0 1-1v-8zM6.5 16A1.5 1.5 0 1 1 8 14.5 1.5 1.5 0 0 1 6.5 16zm11 0a1.5 1.5 0 1 1 1.5-1.5 1.5 1.5 0 0 1-1.5 1.5zM5 11l1.5-4.5h11L19 11z'),
    me: svg('M12 2 4 5v6c0 5 3.4 9.7 8 11 4.6-1.3 8-6 8-11V5zm-1.5 14.5-4-4 1.4-1.4 2.6 2.6 6.1-6.1 1.4 1.4z'),
    back: svg('M20 11H7.8l5.6-5.6L12 4l-8 8 8 8 1.4-1.4L7.8 13H20z'),
    gps: svg('M12 2a7 7 0 0 0-7 7c0 5.2 7 13 7 13s7-7.8 7-13a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 14.5 9 2.5 2.5 0 0 1 12 11.5z'),
    signal: svg('M2 22h20V2z'),
    wifi: svg('M12 21 1 8a16 16 0 0 1 22 0z'),
    battery: svg('M16 4h-2V2h-4v2H8a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V5a1 1 0 0 0-1-1z'),
    down: svg('M7.4 8.6 12 13.2l4.6-4.6L18 10l-6 6-6-6z'),
    turf: svg('M3 3h8v8H3zm10 0h8v8h-8zM3 13h8v8H3zm10 0h8v8h-8z'),
    club: svg('M12 2 4 6v6c0 5 3.4 9 8 10 4.6-1 8-5 8-10V6zm0 4 1.8 3.6 4 .6-2.9 2.8.7 4L12 15.1 8.4 17l.7-4L6.2 10.2l4-.6z'),
    jobs: svg('M10 2h4a2 2 0 0 1 2 2v2h4a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4V4a2 2 0 0 1 2-2zm4 4V4h-4v2z'),
  };
  var NAV = {
    back: '<svg viewBox="0 0 24 24"><path d="M16 4 7 12l9 8z"/></svg>',
    home: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="7.5"/></svg>',
    recent: '<svg viewBox="0 0 24 24"><rect x="5" y="5" width="14" height="14" rx="2"/></svg>',
  };
  // SLRR's own icons (copied from the player's SLRR by tools/slrr_ui.py) where it has one; the phone's
  // own apps (calls, texts, contacts) keep their phone icons
  var SLRR_ART = '/ui/modModules/slHud/slrr/icons/';
  var SLRR_ICON = { races: 'cup.png', garage: 'garage.png', bank: 'dollar.png', cab: 'city.png', me: 'roc.png' };
  function slrrIcon(name, cls) { return '<img class="slp-slrr ' + (cls || '') + '" src="' + SLRR_ART + name + '" alt="">'; }
  var APP_COLORS = { map: '#3a7d6e', camera: '#3b6fa0', gallery: '#a05a8a', carmarket: '#2e7d4f', partmarket: '#a3322c', settings: '#5c6474', wait: '#4a5d7a', market: '#a3322c', paper: '#5b5346', bid: '#b5651d', club: '#6a2e7a', jobs: '#3d7a2e', phone: '#2e7d4f', messages: '#2f5fb3', contacts: '#7b4fb0', races: '#c2541e', bank: '#1f7a70', cab: '#b58a12', me: '#5c6474', garage: '#8a3b8f', garagekit: '#6b5b2e', traps: '#b4541a', inventory: '#7a6a2e', myroute: '#2f8f6a', health: '#b23a5e', help: '#4a6fa5', turf: '#7a4a2e', event: '#2f6f9f', calendar: '#2f6f9f', sponsors: '#9a6b12' };      // (every app has its own tile colour: the white icon needs a fill)
  var AV_COLORS = ['#a8c7fa', '#f2b8b5', '#c3e7c6', '#ffd8a8', '#d0bcff', '#9fe0e8', '#ffb4ab', '#e8def8'];
  var CLASS_NAMES = { beater: T('ui.beaters', 'Beaters'), compact: T('ui.compacts', 'Compacts'), muscle: T('ui.muscle', 'Muscle'), tuner: T('ui.tuners', 'Tuners'), sport: T('ui.sports_cars', 'Sports cars'), super: T('ui.supercars', 'Supercars') };

  function esc(t) {
    return String(t == null ? '' : t).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; });
  }
  function money(v) { v = Math.round(v || 0); return (v < 0 ? '-$' : '$') + String(Math.abs(v)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
  function two(n) { return ('0' + n).slice(-2); }
  function initials(name) {
    var words = String(name || '?').replace(/"[^"]*"|\([^)]*\)/g, ' ').trim().split(/\s+/);
    return ((words[0] || '?')[0] + (words.length > 1 ? words[words.length - 1][0] : '')).toUpperCase();
  }
  function avColor(id) {
    var h = 0, s = String(id);
    for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
    return AV_COLORS[h % AV_COLORS.length];
  }
  function avatar(c, extra) { return '<div class="slp-av"' + (extra || '') + ' style="background:' + avColor(c.id) + '">' + esc(initials(c.short || c.name)) + '</div>'; }
  function arr(x) { return Array.isArray(x) ? x : []; }
  function obj(x) { return x && typeof x === 'object' && !Array.isArray(x) ? x : {}; }

  var STAKE_TEXT = { race: T('ui.race_for_money', 'Race for money'), high: T('ui.high_stakes', 'High stakes'), drag: T('ui.drag_race', 'Drag race'), pink: T('crews.pink_slips', 'Pink slips') };
  var QUICK = { race: T('phone.up_for_a_race', 'Up for a race?'), high: T('phone.race_me_high_stakes', 'Race me. High stakes.'), drag: T('phone.drag_race_at_the_test', 'Drag race at the test track?'), pink: T('phone.pink_slips_you_and_me', 'Pink slips. You and me.') };

  // the cracked screen (sl_phonecrack, data.crack = { stage 1..3, x, y (the impact point, 0..1), seed, strength }): spider-web lines from the impact point, drawn over the whole screen and readable through
  function crackRng(seed) { var s = (Number(seed) >>> 0) || 1; return function () { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }
  function crackPaths(stage, x, y, seed, w, h) {      // (w x h: the field in units, the screen's own shape, so the web is round: 100 x 211 portrait, 200 x 100 sideways)
    w = Number(w) || 100; h = Number(h) || 211;
    stage = Math.max(1, Math.min(3, Math.floor(Number(stage) || 1)));
    var r = crackRng(seed), cx = (Number(x) || 0.5) * w, cy = (Number(y) || 0.4) * h, unit = Math.min(w, h) / 100, n = 5 + 3 * stage, step = Math.PI * 2 / n, radials = [], rings = [];
    for (var i = 0; i < n; i++) {
      var a = step * i + (r() - 0.5) * step * 0.5, len = unit * (22 + r() * (18 + stage * 22)), segs = 4 + stage, pts = [{ x: cx, y: cy }];
      for (var k = 1; k <= segs; k++) {
        var d = len * k / segs, jitter = (r() - 0.5) * 6 * unit;
        pts.push({ x: cx + Math.cos(a) * d - Math.sin(a) * jitter, y: cy + Math.sin(a) * d + Math.cos(a) * jitter });
      }
      radials.push(pts);
    }
    var ringAt = stage === 1 ? [2] : stage === 2 ? [2, 4] : [2, 3, 4, 5];
    ringAt.forEach(function (idx) {
      for (var j = 0; j < n; j++) {
        if (stage === 1 && j % 2) continue;      // (a light crack: the rings are broken)
        var p1 = radials[j][idx], p2 = radials[(j + 1) % n][idx];
        if (p1 && p2) rings.push([p1, { x: (p1.x + p2.x) / 2 + (r() - 0.5) * 3 * unit, y: (p1.y + p2.y) / 2 + (r() - 0.5) * 3 * unit }, p2]);
      }
    });
    function pathD(pts) { return 'M' + pts.map(function (p) { return p.x.toFixed(1) + ' ' + p.y.toFixed(1); }).join(' L'); }
    return radials.map(pathD).concat(rings.map(pathD));
  }
  function crackHtml(c, land) {
    if (!c || !(Number(c.stage) > 0)) return '';
    var w = land ? 200 : 100, h = land ? 100 : 211, paths = crackPaths(c.stage, c.x, c.y, c.seed, w, h), body = paths.map(function (d) { return '<path d="' + d + '"/>'; }).join('');
    var shards = '';
    if (Number(c.stage) >= 3) shards = '<path class="slp-shard" d="M' + (c.x * w - 6).toFixed(1) + ' ' + (c.y * h - 4).toFixed(1) + ' L' + (c.x * w + 9).toFixed(1) + ' ' + (c.y * h - 2).toFixed(1) + ' L' + (c.x * w + 2).toFixed(1) + ' ' + (c.y * h + 10).toFixed(1) + ' Z"/>';
    return '<svg class="slp-crack" data-stage="' + Math.floor(Number(c.stage)) + '" viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none" style="opacity:' + Math.max(0.3, Math.min(1, Number(c.strength) || 0.85)).toFixed(2) + '"><g class="slp-crack-dark">' + body + '</g><g class="slp-crack-light">' + body + '</g>' + shards + '</svg>';
  }
  if (typeof window !== 'undefined') window.__slPhoneCrack = { paths: crackPaths, html: crackHtml };

  function createPhone(doc, lua, clock) {
    clock = clock || { set: function (f, ms) { return setTimeout(f, ms); }, clear: function (t) { clearTimeout(t); }, now: function () { return Date.now(); } };
    var root = doc.createElement('div');
    root.className = 'slp-root';
    var style = doc.createElement('style');
    style.textContent = CSS;
    root.appendChild(style);
    // the phone skin (Mods menu > Phone skin; sl/core/phoneskin checked it): the colours and shapes are an extra style, the icons and app colours replace the classic ones while it is on.
    // Classic (no skin) leaves all of this empty.
    var skinStyle = doc.createElement('style');
    root.appendChild(skinStyle);
    var skinIcons = {}, savedI = {}, savedColors = {};
    function applySkin(data) {
      Object.keys(savedI).forEach(function (k) { I[k] = savedI[k]; });
      Object.keys(savedColors).forEach(function (k) { if (savedColors[k] === undefined) delete APP_COLORS[k]; else APP_COLORS[k] = savedColors[k]; });
      savedI = {}; savedColors = {}; skinIcons = {}; skinStyle.textContent = '';
      if (!data || !data.css) return;
      skinStyle.textContent = String(data.css).replace(/<\/style/gi, '');
      var icons = data.icons || {}, colors = data.appColors || {};
      Object.keys(icons).forEach(function (k) {
        if (typeof icons[k] !== 'string') return;
        skinIcons[k] = icons[k];
        if (Object.prototype.hasOwnProperty.call(I, k)) { savedI[k] = I[k]; I[k] = icons[k]; }
      });
      Object.keys(colors).forEach(function (k) { if (typeof colors[k] === 'string') { savedColors[k] = APP_COLORS[k]; APP_COLORS[k] = colors[k]; } });
    }
    var layer = doc.createElement('div');
    var bars = doc.createElement('div');           // the cinematic bars of the lot's camera: a node of their own, so their slide is not undone by a re-render
    bars.className = 'slp-bars';
    bars.innerHTML = '<i class="slp-lb slp-lbtop"></i><i class="slp-lb slp-lbbot"></i>';
    root.appendChild(bars);
    root.appendChild(layer);                       // (after the bars: the compact lot card stands on the bottom bar, not under it)
    doc.body.appendChild(root);

    var st = {
      repOpen: null, repSec: {}, tab: { cars: 'dealers', parts: 'revline', cab: 'all', cabtier: 'all', map: 'map' }, cmView: 'dealers', cmOffer: null, dealers: null, auction: null, rivals: null, offers: null,
      open: false, data: { active: false }, app: 'home', stack: [], contact: null, thread: null,
      call: null, dial: '', hu: null, toast: null, fade: false,
    };
    var huTimer = null, toastTimer = null, ringTimer = null;

    function contactById(id) {
      var list = arr(st.data.contacts);
      for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
      return null;
    }
    function unread(thread) { var u = obj(st.data.unread); return thread ? (u[thread] || 0) : Object.keys(u).reduce(function (n, k) { return n + (u[k] || 0); }, 0); }
    function thread(id) { return arr(obj(st.data.threads)[id]); }

    // ---------------------------------------------------------------- pages
    function bar(title, extra) {
      return '<div class="slp-bar"><div class="slp-ib" data-a="back">' + I.back + '</div><b>' + esc(title) + '</b>' + (extra || '') + '</div>';
    }

    function homePage() {
      var d = st.data;
      var has = obj(d.has);      // what the map can host: an app of a feature it lacks is not shown
      var appsHtml = function (list) {
        return list.filter(function (a) { return !a.hide && inFreeroam(a.id); }).map(function (a) {
          var badge = a.badge ? '<div class="slp-badge">' + a.badge + '</div>' : '';
          var ico = skinIcons[a.id] || (st.slrrArt && SLRR_ICON[a.id] ? slrrIcon(SLRR_ICON[a.id], 'slp-appimg') : a.icon);
          return '<div class="slp-app" data-a="open" data-v="' + a.id + '"><div class="slp-ico" style="background:' + APP_COLORS[a.id] + '">' + ico + '</div>' + badge + '<span>' + a.title + '</span></div>';
        }).join('');
      };
      var ON_TRIP = { event: 1, garage: 1, bank: 1, calendar: 1, help: 1, messages: 1, contacts: 1, phone: 1 };      // (away from home: the paddock, the cars brought, money, plans, talk)
      var onTrip = function (a) { if (d.visit && !ON_TRIP[a.id]) a.hide = true; return a; };
      var arranged = arr(d.challenges).length;
      var tut = d.tutorial ? ('<div class="slp-card slp-tut"><h4>' + T('ui.getting_started', 'Getting started ')) + d.tutorial.step + '/' + d.tutorial.total + ': ' + esc(d.tutorial.title) + '</h4><p>' + esc(d.tutorial.text) + '</p>' +
        ('<div class="slp-acts"><div class="slp-btn slp-text" data-a="tutskip" data-v="1">' + T('ui.skip_the_tutorial', 'Skip the tutorial') + '</div></div></div>') : '';
      return '<div class="slp-wall"' + (d.wall ? ' style="background:url(\'' + esc(d.wall) + '\') center/cover no-repeat"' : '') + '></div><div class="slp-home">' +
        '<div class="slp-clock">' + two(d.hour || 0) + ':' + two(d.minute || 0) + '</div>' +
        ('<div class="slp-date">' + T('ui.day_2', 'Day ')) + (d.day || 1) + ' &middot; ' + esc(d.mapName || T('progression.valo_city', 'Valo City')) + (d.night ? ' &middot; night' : '') + '</div>' +
        (d.weather ? '<div class="slp-date" style="opacity:.85">' + (d.weather.wet ? '&#127783; ' : '') + esc(d.weather.text) + '</div>' : '') +
        (d.freeroam ? '' :         '<div><span class="slp-chip">' + esc(d.title || '') + ' &middot; ' + (d.rep || 0) + ' rep &middot; ' + money(d.money) + '</span>' +
          '<span class="slp-chip" data-a="routegarage" data-v="1" style="cursor:pointer">' + T('ui.route_to_my_garage', 'Route to my garage') + '</span></div>') +
        (d.freeroam ? '' : tut) + '<div class="slp-grid">' + appsHtml([
          { id: 'event', title: T('app.event', 'Event'), icon: I.event, hide: !d.visit },
          { id: 'races', title: T('app.races', 'Races'), icon: I.flag, badge: arranged || 0, hide: has.races === false },
          { id: 'garage', title: T('app.garage', 'My cars'), icon: I.cab },
          { id: 'garagekit', title: T('app.garagekit', 'Garage'), icon: I.house },
          { id: 'bank', title: T('app.bank', 'Bank'), icon: I.bank, hide: has.bank === false },
          { id: 'me', title: T('app.me', 'Street cred'), icon: I.me },
          { id: 'health', title: T('app.health', 'Health'), icon: I.health, hide: !d.needs || has.needs === false },
          { id: 'sponsors', title: T('app.sponsors', 'Sponsors'), icon: I.sponsors, badge: d.sponsors && d.sponsors.offer ? 1 : 0, hide: !d.sponsors || has.sponsors === false },
          { id: 'calendar', title: T('app.calendar', 'Calendar'), icon: I.calendar, badge: calOpenInvites(), hide: !d.calendar || has.calendar === false },
          { id: 'inventory', title: T('app.inventory', 'Inventory'), icon: I.inventory, hide: !d.inventory || has.inventory === false },
          { id: 'myroute', title: T('app.myroute', 'My routes'), icon: I.myroute, hide: !d.myroute || has.myroute === false },
          { id: 'traps', title: T('app.traps', 'Speed traps'), icon: I.traps, hide: !(d.traps && has.traps !== false) && !(d.danger && has.danger !== false) },
          { id: 'jobs', title: T('app.jobs', 'Jobs'), icon: I.jobs, badge: d.jobs && d.jobs.active ? 1 : 0, hide: has.jobs === false },
          { id: 'wait', title: T('app.wait', 'Wait'), icon: I.wait },
          { id: 'help', title: T('app.help', 'Help'), icon: I.help },
          { id: 'map', title: T('app.map', 'Map'), icon: I.map, hide: has.maps === false },
          { id: 'camera', title: T('app.camera', 'Camera'), icon: I.camera },
          { id: 'gallery', title: T('app.gallery', 'Gallery'), icon: I.gallery },
          { id: 'club', title: T('app.club', 'Club'), icon: I.club, hide: has.clubs === false },
          { id: 'turf', title: T('app.turf', 'Turf'), icon: I.turf, hide: has.crews === false },
          { id: 'carmarket', title: T('app.carmarket', 'Car market'), icon: I.cab, hide: has.market === false },
          { id: 'partmarket', title: T('app.partmarket', 'Part market'), icon: I.market, badge: (d.market && d.market.deliveries || 0) + (d.market ? arr(d.market.auctions).filter(function (l) { return l.high === 'you'; }).length : 0), hide: has.classifieds === false || has.market === false },
        ].map(onTrip)) + '</div>' +
        '<div class="slp-dock">' + appsHtml([
          { id: 'phone', title: T('app.phone', 'Phone'), icon: I.phone },
          { id: 'messages', title: T('app.messages', 'Messages'), icon: I.msg, badge: unread() || 0 },
          { id: 'contacts', title: T('app.contacts', 'Contacts'), icon: I.contacts },
          { id: 'cab', title: T('app.cab', 'Cab'), icon: I.cab },
          { id: 'frjobs', title: T('app.frjobs', 'Freight runs'), icon: I.jobs, hide: !d.frjobs },
        ].map(onTrip)).replace(/<span>[^<]*<\/span>/g, '') + '</div></div>';
    }

    function contactLine(c) {
      if (c.system) return T('ui.your_garage', 'Your garage');
      var stars = '<span class="slp-stars">' + new Array((c.tier || 1) + 1).join('&#9733;') + '</span>';
      return stars + ' &middot; ' + esc(CLASS_NAMES[c.class] || c.class || '') + (c.nightOnly ? ' &middot; nights' : '') + (c.pinkTonight ? (' ' + '&middot;' + ' ' + '<span class="slp-pink">' + T('ui.pinks_tonight', 'pinks tonight') + '</span>') : '');
    }

    // the people you have met (rivals, crew leaders, dealers): a line, where you met them and a route to that place; a rival is listed here and not twice
    function peopleIds() { var ids = {}; arr(obj(st.people).people).forEach(function (p) { if (p.kind === 'rival') ids[p.id] = true; }); return ids; }
    function peopleHtml() {
      var list = arr(obj(st.people).people);
      if (!list.length) return '';
      var places = {};
      arr(st.data.places).forEach(function (p) { places[p.id] = p.name; });
      return '<div class="slp-seth">' + T('ui.people_you_have_met', 'People you have met') + '</div>' + list.map(function (p) {
        var where = p.placeId && places[p.placeId] ? ' &middot; ' + esc(T('ui.met_at_1', 'Met at {1}', places[p.placeId])) : '';
        return '<div class="slp-row"' + (p.kind === 'rival' ? ' data-a="contact" data-v="' + esc(p.id) + '"' : '') + '><div class="slp-rt"><b>' + esc(p.name) + '</b><span>' + esc(p.line || '') + where + '</span></div>' +
          (p.placeId ? '<div class="slp-btn slp-tonal" data-a="route" data-v="' + esc(p.placeId) + '">' + T('ui.route_to', 'Route to') + '</div>' : '') + '</div>';
      }).join('');
    }
    function contactsPage() {
      var hidden = peopleIds();
      var list = arr(st.data.contacts).filter(function (c) { return !hidden[c.id]; }), out = [], last = null;
      list.forEach(function (c) {
        var letter = c.system ? '★' : (c.short || c.name || '?')[0].toUpperCase();
        if (letter !== last) { out.push('<div class="slp-letter">' + esc(letter) + '</div>'); last = letter; }
        out.push('<div class="slp-row" data-a="contact" data-v="' + esc(c.id) + '">' + avatar(c) + '<div class="slp-rt"><b>' + esc(c.name) + '</b><span>' + contactLine(c) + '</span></div></div>');
      });
      if (list.length <= 1) out.push(('<div class="slp-empty">' + T('ui.nobody_else_has_given_you', 'Nobody else has given you their number yet. Win a few races and they will.') + '</div>'));
      return bar(T('app.contacts', 'Contacts')) + '<div class="slp-body">' + out.join('') + peopleHtml() + '</div>';
    }

    function contactPage() {
      var c = contactById(st.contact);
      if (!c) return bar(T('app.contact', 'Contact')) + ('<div class="slp-empty">' + T('ui.gone', 'Gone.') + '</div>');
      var record = c.system ? '' : ('<div class="slp-card"><div class="slp-kv"><span>' + T('ui.you_beat_them', 'You beat them') + '</span><b>') + (c.losses || 0) + ('</b></div><div class="slp-kv" style="border:none"><span>' + T('ui.they_beat_you', 'They beat you') + '</span><b>') + (c.wins || 0) + '</b></div></div>';
      return bar('') + '<div class="slp-body"><div class="slp-hero">' + avatar(c) + '<b>' + esc(c.name) + '</b><span>' + esc(c.phone) + '</span><span>' + contactLine(c) + '</span></div>' +
        '<div class="slp-acts3"><div class="slp-act" data-a="call" data-v="' + esc(c.id) + '"><i>' + I.phone + ('</i>' + T('ui.call', 'Call') + '</div>') +
        '<div class="slp-act" data-a="thread" data-v="' + esc(c.id) + '"><i>' + I.msg + ('</i>' + T('ui.message', 'Message') + '</div></div>') + record + '</div>';
    }

    function messagesPage() {
      var threads = obj(st.data.threads);
      var ids = Object.keys(threads).filter(function (id) { return arr(threads[id]).length; });
      ids.sort(function (a, b) { var x = arr(threads[a]), y = arr(threads[b]); return (y[y.length - 1].at || 0) - (x[x.length - 1].at || 0); });
      var rows = ids.map(function (id) {
        var c = contactById(id) || { id: id, name: id };
        var list = arr(threads[id]), lastMsg = list[list.length - 1], n = unread(id);
        return '<div class="slp-row" data-a="thread" data-v="' + esc(id) + '">' + avatar(c) + '<div class="slp-rt"><b>' + esc(c.name) + '</b><span' + (n ? ' class="slp-unread"' : '') + '>' +
          (lastMsg.from === 'me' ? T('ui.you', 'You: ') : '') + esc(lastMsg.text) + '</span></div>' + (n ? '<div class="slp-badge" style="position:static;margin:0">' + n + '</div>' : '') + '</div>';
      });
      return bar(T('app.messages', 'Messages')) + '<div class="slp-body">' + (rows.join('') || ('<div class="slp-empty">' + T('ui.no_messages', 'No messages.') + '</div>')) + '</div>';
    }

    function threadPage() {
      var c = contactById(st.thread) || { id: st.thread, name: st.thread };
      var bubbles = thread(st.thread).map(function (m) { return '<div class="slp-bub ' + (m.from === 'me' ? 'slp-me' : 'slp-them') + '">' + esc(m.text) + '</div>'; }).join('');
      var quick = c.system ? '' : '<div class="slp-quick">' + Object.keys(QUICK).filter(function (k) { return k !== 'pink' || c.pinkTonight; }).map(function (k) { return '<div class="slp-qc" data-a="text" data-v="' + k + '">' + esc(QUICK[k]) + '</div>'; }).join('') + '</div>';
      return bar(c.name, '<div style="margin-left:auto" class="slp-ib" data-a="call" data-v="' + esc(c.id) + '">' + I.phone + '</div>') +
        '<div class="slp-msgs">' + (bubbles || ('<div class="slp-empty">' + T('ui.say_something', 'Say something.') + '</div>')) + '</div>' + quick;
    }

    var KEYS = [['1', ''], ['2', T('ui.abc', 'ABC')], ['3', T('ui.def', 'DEF')], ['4', T('ui.ghi', 'GHI')], ['5', T('ui.jkl', 'JKL')], ['6', T('ui.mno', 'MNO')], ['7', T('ui.pqrs', 'PQRS')], ['8', T('ui.tuv', 'TUV')], ['9', T('ui.wxyz', 'WXYZ')], ['*', ''], ['0', '+'], ['#', '']];
    function dialMatch() {
      var digits = st.dial.replace(/\D/g, '');
      if (!digits) return null;
      var list = arr(st.data.contacts);
      for (var i = 0; i < list.length; i++) if (String(list[i].phone).replace(/\D/g, '') === digits) return list[i];
      return null;
    }
    function phonePage() {
      var who = dialMatch();
      return bar(T('ui.phone', 'Phone'), st.dial ? '<div style="margin-left:auto" class="slp-ib" data-a="del">' + I.back + '</div>' : '') +
        '<div class="slp-num">' + esc(st.dial || ' ') + '</div><div class="slp-who">' + (who ? esc(who.name) : '') + '</div>' +
        '<div class="slp-keys">' + KEYS.map(function (k) { return '<div class="slp-key" data-a="key" data-v="' + k[0] + '">' + k[0] + '<small>' + k[1] + '</small></div>'; }).join('') + '</div>' +
        '<div class="slp-dial" data-a="dial">' + I.phone + '</div>';
    }

    function racesPage() {
      var list = arr(st.data.challenges);
      var cards = list.map(function (c) {
        var stake = c.stake === 'pink' ? T('crews.pink_slips', 'Pink slips') : money(c.bet);
        var pv = obj(c.preview);
        // the route as a small map (#18): the road it takes, the start (green) and the finish (red)
        var map = pv.points ? '<svg class="slp-rmap" viewBox="0 0 ' + (pv.w || 240) + ' ' + (pv.h || 140) + '"><polyline points="' + esc(pv.points) + '" fill="none" stroke="#a8c7fa" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>' +
          '<circle cx="' + obj(pv.start).x + '" cy="' + obj(pv.start).y + '" r="5" fill="#7bd88f"/><rect x="' + (obj(pv.finish).x - 5) + '" y="' + (obj(pv.finish).y - 5) + '" width="10" height="10" fill="#f2b8b5"/></svg>' +
          '<p class="slp-rmeta"><span class="slp-rs">&#9679; ' + esc(T('status.start', 'start')) + '</span> <span class="slp-rf">&#9632; ' + esc(T('status.finish', 'finish')) + '</span> &middot; ' + ((pv.metres || 0) / 1000).toFixed(1) + ' km</p>' : '';
        return '<div class="slp-card">' + map + '<h4>' + esc(c.name) + '</h4><p>' + esc(c.raceName) + ' &middot; ' + stake + (c.nightOnly ? T('ui.middot_after_dark', ' &middot; after dark') : '') + '</p>' +
          '<div class="slp-acts"><div class="slp-btn" data-a="gps" data-v="' + esc(c.id) + ('">' + T('ui.show_the_way', 'Show the way') + '</div>') + (c.stake === 'money' ? '<div class="slp-btn slp-tonal" data-a="raise" data-v="' + esc(c.id) + ('">' + T('ui.raise_the_stake', 'Raise the stake') + '</div>') : '') + '<div class="slp-btn slp-text" data-a="cancel" data-v="' + esc(c.id) + ('">' + T('ui.call_it_off', 'Call it off') + '</div></div></div>');
      });
      var rp = st.data.replay;          // #48 the last race, recorded: watch it, keep it
      if (rp) cards.unshift(('<div class="slp-card"><h4>' + T('ui.last_race', 'Last race') + '</h4><p>') + esc(rp.name) + (rp.saved ? ' &middot; saved' : '') + ('</p><div class="slp-acts"><div class="slp-btn" data-a="watchreplay" data-v="1">' + T('ui.watch_replay', 'Watch replay') + '</div>') +
        (rp.saved ? '' : ('<div class="slp-btn slp-tonal" data-a="saveclip" data-v="1">' + T('ui.save_clip', 'Save clip') + '</div>')) + '</div></div>');
      return bar(T('app.races', 'Races')) + '<div class="slp-body">' + (cards.join('') ||
        ('<div class="slp-empty">' + T('ui.no_races_arranged_call_or', 'No races arranged. Call or text one of your contacts to set one up: for money, for high stakes, or for pink slips.') + '</div>')) + '</div>';
    }

    // the job board: what is on offer now, the one you are on, your record
    // Revline: used parts from private sellers (sl_classifieds)
    // one ad (Revline and the paper share it)
    // a car ad's picture, name line and facts (the stock shop's card: picture, year, name, brand, mileage, transmission, drivetrain, power, seller, distance)
    function adDist(m) { m = Number(m) || 0; return m >= 1000 ? (m / 1000).toFixed(1) + ' km' : Math.round(m) + ' m'; }
    // the picture of an ad (car: the config's; part: the car it fits), always on top of its category icon: a picture that does not load
    // shows the icon, never a broken image. A part ad carries its category in a badge.
    function catKey(l) { return l.car ? 'cat_car' : (l.category && I['cat_' + l.category] ? 'cat_' + l.category : (l.category === 'car' ? 'cat_car' : 'cat_part')); }
    function adPic(l) {
      return '<div class="slp-pic"><div class="slp-pico">' + I[catKey(l)] + '</div>' +
        ((l.partPic || l.preview) ? '<img' + (l.partPic ? ' class="slp-partpic"' : '') + ' src="' + esc(l.partPic || l.preview) + '" alt="" onerror="this.style.display=\'none\'">' : '') +
        (!l.car && l.category && l.category !== 'car' ? '<div class="slp-pbadge">' + I[catKey(l)] + esc(l.categoryTitle || T('ui.part', 'Part')) + '</div>' : '') + '</div>';
    }
    // a part ad's second line: the catalog chapter and the car it fits
    function partMeta(l) { return (l.chapter ? esc(l.chapter) + ' &middot; ' : '') + (l.fits ? T('ui.fits_the_1', 'fits the {1}', esc(l.fits)) : T('ui.for_the_1', 'for the {1}', esc(l.model))); }
    function adFacts(l) {
      var sp = obj(l.specs), out = [];
      if (l.mileage != null) out.push(Number(l.mileage).toLocaleString() + ' km');
      if (sp.transmission) out.push(esc(sp.transmission));
      if (sp.drivetrain) out.push(esc(sp.drivetrain));
      if (sp.power) out.push(Math.round(sp.power) + ' PS');
      return out.join(' &middot; ');
    }
    function adButtons(l) {
      var offers = l.agreed ? '' : [0.9, 0.8, 0.7].map(function (f) {
        var amt = Math.round(l.ask * f / 10) * 10;
        return '<div class="slp-btn slp-text" data-a="mkoffer" data-v="' + esc(l.id) + '|' + amt + ('">' + T('ui.offer', 'Offer ')) + money(amt) + '</div>';
      }).join('');
      return '<div class="slp-acts">' + offers + '<div class="slp-btn" data-a="mkbuy" data-v="' + esc(l.id) + ('|pickup">' + T('classifieds.pick_up', 'Pick up') + '</div>') +
        (l.delivery != null ? '<div class="slp-btn" data-a="mkbuy" data-v="' + esc(l.id) + ('|delivery">' + T('ui.deliver', 'Deliver') + '</div>') : '') + '</div>';
    }
    // the full car report (#58): every part by section with its condition, the dents, the faults and a repair estimate per section. The button
    // (here) opens a panel of its own (reportModal) that fits the screen: a header with a close button and a body that scrolls, one collapsible
    // row per section with its condition, worst fault and repair estimate.
    var reports = {};                      // key -> the report, kept while the buttons are drawn so the panel can show it
    var reportHist = {};                   // key -> the history lines of the ad (shown at the top of the panel)
    function reportBlock(key, rp, history) {
      if (!rp || !rp.sections) return '';
      reports[key] = rp;
      reportHist[key] = arr(history);
      return '<div class="slp-acts"><div class="slp-btn slp-tonal" data-a="report" data-v="' + esc(key) + '">' + T('ui.show_full_car_report', 'Show full car report') + '</div></div>';
    }
    function repWorst(rp) {                // the section in the worst condition: open when the panel opens
      var w = 0, secs = arr(rp.sections);
      for (var i = 1; i < secs.length; i++) if (secs[i].condition < secs[w].condition) w = i;
      return secs.length ? secs[w].id : null;
    }
    function repOpen(rp, id) { return st.repSec[id] !== undefined ? !!st.repSec[id] : id === repWorst(rp); }
    function reportModal() {
      var rp = st.repOpen && (reports[st.repOpen] || st.repKeep);      // (the report as it was when the button was pressed, if a data push dropped it meanwhile)
      if (!rp) return '';
      var hist = arr(reportHist[st.repOpen]);
      var nothing = !(Number(rp.total) > 0) && !arr(rp.faults).length ? '<p>' + T('ui.nothing_more_to_report', 'Nothing more to report: no faults and no repair needed.') + '</p>' : '';
      var secs = arr(rp.sections).map(function (sc) {
        var open = repOpen(rp, sc.id);
        var worst = null;
        arr(sc.parts).forEach(function (p) { if (p.fault && !worst) worst = p.fault; });
        var cls = sc.condition < 30 ? 'bad' : sc.condition < 50 ? 'mid' : 'ok';
        var head = '<div class="slp-repsum' + (open ? ' slp-open' : '') + '" data-a="repsec" data-v="' + esc(sc.id) + '"><b>' + (open ? '&#9662; ' : '&#9656; ') + esc(sc.title) + '</b><span class="slp-r' + cls + '">' + sc.condition + '% ' + esc(sc.label) + '</span>' +
          '<span>' + (worst ? '<span class="slp-rbad">&#9888; ' + esc(worst) + '</span>' : T('ui.no_faults', 'no faults')) + '</span><span>' + (sc.estimate > 0 ? money(sc.estimate) : 'none') + '</span></div>';
        if (!open) return head;
        return head + '<div class="slp-repparts">' + arr(sc.parts).map(function (p) {
          return '<div class="slp-kv"><span>' + esc(p.name) + (p.fault ? ' <b class="slp-rbad">&#9888; ' + esc(p.fault) + '</b>' : '') + '</span><b class="slp-r' + (p.condition < 30 ? 'bad' : p.condition < 50 ? 'mid' : 'ok') + '">' + p.condition + '% ' + esc(p.label) + '</b></div>';
        }).join('') + '<div class="slp-kv"><span>' + T('ui.repair_estimate', 'Repair estimate') + '</span><b>' + (sc.estimate > 0 ? money(sc.estimate) : 'none') + '</b></div></div>';
      }).join('');
      var dm = obj(rp.damage);
      return '<div class="slp-repmodal"><div class="slp-reppanel"><div class="slp-rephead"><b>' + T('ui.car_report', 'Car report') + '</b><span>' + rp.condition + '% ' + esc(rp.label) + '</span>' +
        '<div class="slp-btn slp-tonal" data-a="reportclose">' + T('ui.close', 'Close') + '</div></div><div class="slp-repbody">' +
        '<div class="slp-kv"><span>' + T('ui.overall', 'Overall') + '</span><b>' + rp.condition + '% ' + esc(rp.label) + '</b></div>' +
        hist.map(function (x) { return '<p>' + esc(x) + '</p>'; }).join('') + nothing +
        '<div class="slp-kv"><span>' + T('ui.mileage', 'Mileage') + '</span><b>' + Number(rp.mileage || 0).toLocaleString() + ' km</b></div><div class="slp-kv"><span>' + T('ui.dents_and_damage', 'Dents and damage') + '</span><b>' + esc(dm.label) + ' (' + (dm.amount || 0) + '%)</b></div>' +
        '<div class="slp-kv"><span>' + T('ui.known_faults', 'Known faults') + '</span><b>' + (arr(rp.faults).length ? esc(arr(rp.faults).join(', ')) : 'none') + '</b></div>' + secs +
        '<div class="slp-kv"><span><b>' + T('ui.repair_estimate_to_95', 'Repair estimate, to 95 %') + '</b></span><b>' + money(rp.total) + '</b></div></div></div></div>';
    }
    // used-car checks (sl_classifieds): a private car ad tells the car's history; the faults and the report show after a paid mechanic's check
    // (l.history = lines, l.hidden, l.checkFee, l.checked, l.found = { { label, cost } }); an ad without these shows nothing here
    function usedCheck(l) {
      var lines = arr(l.history);
      if (!lines.length && !l.hidden && !l.checked) return '';
      var html = '<div class="slp-card" style="margin:6px 0 4px 0"><h4>' + T('ui.history', 'History') + '</h4>' + lines.map(function (x) { return '<p>' + esc(x) + '</p>'; }).join('');
      if (l.hidden) {
        html += '<p class="slp-warn">&#9888; ' + T('ui.hidden_faults', 'The faults and the car report show after a mechanic has checked the car.') + '</p>' +
          '<div class="slp-acts"><div class="slp-btn slp-tonal" data-a="mkcheck" data-v="' + esc(l.id) + '">' + T('ui.check_car', 'Check the car') + ' &middot; ' + money(l.checkFee) + '</div></div>';
      } else if (l.checked) {
        var found = arr(l.found);
        html += found.length ? '<p>' + T('ui.faults_found', 'The mechanic found:') + '</p>' + found.map(function (f) {
          return '<div class="slp-kv"><span>' + esc(f.label || '') + '</span><b>' + money(f.cost) + '</b></div>';
        }).join('') : '<p>' + T('ui.no_faults_found', 'The mechanic found no faults.') + '</p>';
      }
      return html + '</div>';
    }
    function carAdCard(l) {
      var tells = arr(l.tells).length ? '<p class="slp-warn">&#9888; ' + arr(l.tells).map(esc).join(' &middot; ') + '</p>' : '';
      return '<div class="slp-card">' + adPic(l) + '<h4 data-a="adview" data-v="' + esc(l.id) + '">' + (l.rare ? '&#9733; ' : '') + (l.year ? l.year + ' ' : '') + esc(l.name) + '</h4>' +
        '<p>' + esc(l.brand || '') + '</p><p>' + adFacts(l) + '</p>' +
        '<p>' + esc(l.seller) + ' ' + '&#9733;'.repeat(l.rating || 0) + (l.metres != null ? T('ui.middot_1_away', ' &middot; {1} away', adDist(l.metres)) : '') + (l.hours ? T('ui.middot_delivered_in_about_1', ' &middot; delivered in about {1} h', l.hours) : '') +
        ' &middot; ' + l.condition + T('ui.condition', '% condition') + (l.faults ? T('ui.middot_1_fault_2', ' &middot; {1} fault{2}', l.faults, (l.faults > 1 ? 's' : '')) : '') + ' &middot; ' + Math.max(0, l.hoursLeft | 0) + (T('ui.h_left', ' h left') + '</p>') + tells +
        '<p><b>' + money(l.ask) + '</b>' + (l.agreed ? T('ui.agreed', ' (agreed)') : '') + ' &middot; deposit ' + money(l.deposit) + (l.delivery != null ? T('ui.middot_delivery_1', ' &middot; delivery +{1}', money(l.delivery)) : '') + '</p>' +
        usedCheck(l) + reportBlock('ad:' + l.id, l.report, l.history) +
        adButtons(l).replace('<div class="slp-acts">', '<div class="slp-acts"><div class="slp-btn slp-tonal" data-a="adview" data-v="' + esc(l.id) + ('">' + T('ui.details', 'Details') + '</div>')) + '</div>';
    }
    // the detail view: the picture, every spec, the seller and the price
    function adPage() {
      var m = obj(st.data.market), l = null;
      arr(m.listings).concat(arr(obj(m.paper).listings)).forEach(function (x) { if (x.id === st.adId) l = x; });
      if (!l) return bar(T('app.ad', 'Ad')) + ('<div class="slp-body"><div class="slp-empty">' + T('ui.this_ad_has_gone', 'This ad has gone.') + '</div></div>');
      var sp = obj(l.specs), faults = l.faultList ? arr(l.faultList) : [];
      var row = function (k, v) { return v == null || v === '' ? '' : '<div class="slp-kv"><span>' + k + '</span><b>' + v + '</b></div>'; };
      return bar((l.year ? l.year + ' ' : '') + l.name) + '<div class="slp-body"><div class="slp-card">' + adPic(l) +
        row(T('ui.brand', 'Brand'), esc(l.brand)) + row(T('ui.year', 'Year'), l.year) + row(T('ui.mileage', 'Mileage'), l.mileage != null ? Number(l.mileage).toLocaleString() + ' km' : null) + row(T('ui.condition_2', 'Condition'), l.condition + '%') +
        row(T('ui.power', 'Power'), sp.power ? Math.round(sp.power) + ' PS' : null) + row(T('ui.weight', 'Weight'), sp.weight ? Math.round(sp.weight).toLocaleString() + ' kg' : null) +
        row(T('ui.transmission', 'Transmission'), esc(sp.transmission)) + row(T('ui.drivetrain', 'Drivetrain'), esc(sp.drivetrain)) + row(T('ui.fuel', 'Fuel'), esc(sp.fuel)) + row(T('ui.body', 'Body'), esc(sp.body)) +
        row(T('ui.top_speed', 'Top speed'), sp.topSpeed ? Math.round(sp.topSpeed * 3.6) + ' km/h' : null) + (faults.length ? row(T('ui.needs', 'Needs'), esc(faults.join(', '))) : '') + usedCheck(l) + reportBlock('ad:' + l.id, l.report, l.history) + '</div>' +
        '<div class="slp-card">' + row(T('ui.seller', 'Seller'), esc(l.seller) + ' ' + '&#9733;'.repeat(l.rating || 0)) + row(T('ui.distance', 'Distance'), l.metres != null ? adDist(l.metres) : null) +
        row(T('ui.delivery', 'Delivery'), l.hours ? T('ui.to_your_garage_in_about', 'to your garage in about {1} h', l.hours) : null) + row(T('ui.asking', 'Asking'), money(l.ask)) + row(T('ui.deposit_pick_up', 'Deposit (pick up)'), money(l.deposit)) +
        (l.delivery != null ? row(T('ui.delivery_fee', 'Delivery fee'), money(l.delivery)) : '') + adButtons(l) + '</div></div>';
    }

    function adCard(l) {
        if (l.car) return carAdCard(l);
        var tells = arr(l.tells).length ? '<p class="slp-warn">&#9888; ' + arr(l.tells).map(esc).join(' &middot; ') + '</p>' : '';
        var offers = l.agreed ? '' : [0.9, 0.8, 0.7].map(function (f) {
          var amt = Math.round(l.ask * f / 10) * 10;
          return '<div class="slp-btn slp-text" data-a="mkoffer" data-v="' + esc(l.id) + '|' + amt + ('">' + T('ui.offer', 'Offer ')) + money(amt) + '</div>';
        }).join('');
        return '<div class="slp-card">' + adPic(l) + '<h4>' + (l.rare ? '&#9733; ' : '') + esc(l.name) + '</h4>' +
          '<p>' + (l.car ? T('ui.car_1_2', 'Car{1}{2}', (l.mileage ? ' &middot; ' + Math.round(l.mileage / 1000) + 'k km' : ''), (l.faults ? ' &middot; ' + l.faults + ' fault' + (l.faults > 1 ? 's' : '') : '')) : partMeta(l)) +
          ' &middot; ' + l.condition + T('ui.condition_middot', '% condition &middot; ') + esc(l.seller) + ' ' + '&#9733;'.repeat(l.rating || 0) + ' &middot; ' + Math.max(0, l.hoursLeft | 0) + (T('ui.h_left', ' h left') + '</p>') + tells +
          '<p><b>' + money(l.ask) + '</b>' + (l.agreed ? T('ui.agreed', ' (agreed)') : '') + ' &middot; deposit ' + money(l.deposit) + (l.delivery != null ? T('ui.middot_delivery_1', ' &middot; delivery +{1}', money(l.delivery)) : '') + '</p>' +
          '<div class="slp-acts">' + offers + '<div class="slp-btn" data-a="mkbuy" data-v="' + esc(l.id) + ('|pickup">' + T('classifieds.pick_up', 'Pick up') + '</div>') +
          (l.delivery != null ? '<div class="slp-btn" data-a="mkbuy" data-v="' + esc(l.id) + ('|delivery">' + T('ui.deliver', 'Deliver') + '</div>') : '') + '</div></div>';
    }

    // selling: your listings (offers to accept) and your shelf parts to list
    function sellCards(m, kind) {      // kind: 'parts' | 'cars' | undefined (both)
      var mine = arr(m.mine).filter(function (y) { return !kind || (kind === 'cars') === (y.carId != null); }).map(function (y) {
        var body = y.channel === 'auction'
          ? ('<p>' + T('ui.at_auction', 'At auction ') + '&middot;' + ' ') + (y.bid ? T('ui.top_bid_1', 'top bid {1}', money(y.bid)) : T('ui.no_bids_yet', 'no bids yet')) + ' &middot; ' + Math.max(0, y.hoursLeft | 0) + (T('ui.h_left', ' h left') + '</p>')
          : (arr(y.offers).length ? arr(y.offers).map(function (o) {
              return '<div class="slp-acts"><div class="slp-btn" data-a="mkaccept" data-v="' + esc(y.id) + '|' + o.index + ('">' + T('ui.accept', 'Accept ')) + money(o.amount) + ' from ' + esc(o.buyer || T('ui.a_buyer', 'a buyer')) + '</div></div>';
            }).join('') : ('<p>' + T('ui.no_offers_yet', 'No offers yet.') + '</p>'));
        return '<div class="slp-card slp-mini">' + adPic(y) + ('<h4>' + T('ui.your', 'Your ')) + esc(y.name) + '</h4>' + body +
          '<div class="slp-acts"><div class="slp-btn slp-text" data-a="mkwithdraw" data-v="' + esc(y.id) + ('">' + T('ui.withdraw', 'Withdraw') + '</div></div></div>');
      }).join('');
      var shelf = kind === 'cars' ? [] : arr(m.shelf).map(function (it) {
        return '<div class="slp-card slp-mini">' + adPic(it) + '<h4>' + esc(it.name) + '</h4><p>' + partMeta(it) + T('ui.middot_on_your_shelf_middot', ' &middot; on your shelf &middot; buyers pay up to about ') + money(it.estimate) + '</p>' +
          '<div class="slp-acts"><div class="slp-btn" data-a="mklist" data-v="' + esc(it.model) + '|' + it.id + ('|app">' + T('ui.list_it', 'List it') + '</div>') +
          '<div class="slp-btn" data-a="mklist" data-v="' + esc(it.model) + '|' + it.id + ('|auction">' + T('ui.auction_it', 'Auction it') + '</div></div></div>');
      }).join('');
      var cars = kind === 'parts' ? [] : arr(m.cars).map(function (c) {
        return '<div class="slp-card slp-mini">' + adPic({ car: true, preview: c.preview }) + '<h4>' + esc(c.name) + ('</h4><p>' + T('ui.your_car', 'Your car ') + '&middot;' + T('ui.buyers_pay_up_to_about', ' buyers pay up to about ')) + money(c.estimate || 0) + '</p>' +
          '<div class="slp-acts"><div class="slp-btn" data-a="mkcar" data-v="' + esc(c.id) + ('">' + T('ui.list_car', 'List car') + '</div></div></div>');
      }).join('');
      return (mine ? ('<div class="slp-empty">' + T('ui.your_listings', 'Your listings') + '</div>') + mine : '') + (shelf ? ('<div class="slp-empty">' + T('ui.sell_from_your_shelf', 'Sell from your shelf') + '</div>') + shelf : '') +
        (cars ? ('<div class="slp-empty">' + T('ui.sell_a_car', 'Sell a car') + '</div>') + cars : '');
    }

    function marketPage() {
      var m = obj(st.data.market);
      var cards = arr(m.listings).map(adCard).join('');
      return bar(T('app.revline', 'Revline')) + '<div class="slp-body">' + (m.deliveries ? '<div class="slp-empty">' + m.deliveries + (T('ui.on_the_way_to_your', ' on the way to your garage.') + '</div>') : '') +
        (cards || ('<div class="slp-empty">' + T('ui.nothing_listed_right_now_new', 'Nothing listed right now. New ads come in through the day.') + '</div>')) + sellCards(m) + '</div>';
    }

    // Valo Classifieds: the weekly paper (some ads only in the printed copy, $2 at a gas station)
    function paperPage() {
      var p = obj(obj(st.data.market).paper);
      var cards = arr(p.listings).map(function (l) { return adCard(l).replace('<h4>', '<h4>' + (l.printOnly ? ('<span class="slp-warn">' + T('ui.print_only', '[print only]') + '</span>' + ' ') : '')); }).join('');
      var head = ('<div class="slp-empty">' + T('ui.edition', 'Edition ')) + (p.edition || 1) + T('ui.small_ads_go_fast', '. Small ads go fast.') +
        (p.bought ? T('ui.you_have_the_printed_copy', ' You have the printed copy.') : (p.hidden ? T('ui.1_more_in_the_printed', ' {1} more in the printed copy.', p.hidden) : '')) + '</div>' +
        (p.bought ? '' : ('<div class="slp-acts"><div class="slp-btn" data-a="buypaper" data-v="1">' + T('ui.buy_the_paper', 'Buy the paper (')) + money(p.price || 2) + (T('ui.at_a_gas_station', ', at a gas station)') + '</div></div>'));
      return bar(st.data.mapName && st.data.mapName !== 'Valo City' ? st.data.mapName + T('ui.classifieds', ' Classifieds') : T('classifieds.valo_classifieds', 'Valo Classifieds')) + '<div class="slp-body">' + head + (cards || ('<div class="slp-empty">' + T('ui.no_ads_right_now_new', 'No ads right now. New ones come out through the week.') + '</div>')) + '</div>';
    }

    // Swap & Bid: auctions against other bidders; the lot is paid for and delivered when it ends
    function bidPage() {
      var m = obj(st.data.market);
      var cards = arr(m.auctions).map(function (l) {
        var mine = l.high === 'you';
        return '<div class="slp-card">' + adPic(l) + '<h4>' + (l.rare ? '&#9733; ' : '') + esc(l.name) + '</h4>' +
          '<p>' + partMeta(l) + ' &middot; ' + l.condition + T('ui.condition_middot', '% condition &middot; ') + Math.max(0, l.hoursLeft | 0) + (T('ui.h_left', ' h left') + '</p>') +
          '<p><b>' + money(l.bid) + '</b> ' + (mine ? T('ui.your_bid', '(your bid)') : (l.high === 'ai' ? T('ui.outbid', '(outbid)') : T('ui.opening_bid', '(opening bid)'))) + T('ui.middot_delivery', ' &middot; delivery +') + money(l.delivery || 0) + '</p>' +
          (mine ? '' : '<div class="slp-acts"><div class="slp-btn" data-a="mkbid" data-v="' + esc(l.id) + ('">' + T('ui.bid', 'Bid ')) + money(l.next) + '</div></div>') + '</div>';
      }).join('');
      var meet = obj(m.meet), stalls = '';
      if (meet.open) {
        stalls = ('<div class="slp-empty">' + T('ui.swap_meet', 'Swap meet ')) + (meet.night ? 'tonight' : 'today') + T('ui.at_the', ' at the ') + esc(meet.place || T('classifieds.tuning_shop_lot', 'Tuning shop lot')) + (meet.here ? T('ui.you_are_here', '. You are here.') : T('ui.go_and_buy_in_person', ': go and buy in person.')) + '</div>' +
          arr(meet.listings).map(function (l) {
            return '<div class="slp-card">' + adPic(l) + '<h4>' + (l.rare ? '&#9733; ' : '') + esc(l.name) + '</h4><p>' + partMeta(l) + ' &middot; ' + l.condition + T('ui.condition_middot', '% condition &middot; ') + esc(l.seller) + (T('ui.s_stall', '\'s stall') + '</p>') +
              '<p><b>' + money(l.ask) + '</b></p>' + (meet.here ? '<div class="slp-acts"><div class="slp-btn" data-a="mkmeet" data-v="' + esc(l.id) + ('">' + T('ui.buy_it', 'Buy it') + '</div></div>') : '') + '</div>';
          }).join('');
      }
      return bar(T('app.bid', 'Swap & Bid')) + '<div class="slp-body">' + stalls + (cards || ('<div class="slp-empty">' + T('ui.no_lots_right_now', 'No lots right now.') + '</div>')) + '</div>';
    }

    function jobsPage() {
      var j = obj(st.data.jobs), a = j.active;
      var mmss = function (sec) { sec = Math.max(0, sec | 0); return Math.floor(sec / 60) + ':' + two(sec % 60); };
      var activeCard = a ? '<div class="slp-card"><h4>' + esc(a.title) + ': ' + esc(a.item || '') + (a.fragile ? ' &middot; fragile' : '') + '</h4>' + (a.contract ? '<p><span class="slp-chip" style="margin:0 6px 0 0">' + T('ui.contract', 'Contract') + '</span>' + esc(a.contract.label || '') + '</p>' : '') +
        ('<p>' + T('ui.next_stop', 'Next stop: ')) + esc(a.next) + (a.timeLeft != null ? ' &middot; ' + (a.timeLeft > 0 ? mmss(a.timeLeft) + ' left' : 'late') : '') + ' &middot; ' + money(a.pay) + '</p>' +
        ('<div class="slp-acts"><div class="slp-btn" data-a="jobway" data-v="1">' + T('ui.show_the_way', 'Show the way') + '</div><div class="slp-btn slp-text" data-a="jobquit" data-v="1">' + T('ui.give_up', 'Give up') + '</div></div></div>') : '';
      // a contract (sl_jobs: an offer with terms, o.contract = { req, label, mult, basePay }): a tag, the terms, and the normal pay as small text
      var contractLines = function (c, pay) {
        if (!c) return '';
        return '<p><span class="slp-chip" style="margin:0 6px 0 0">' + T('ui.contract', 'Contract') + '</span>' + esc(c.label || '') + '</p>' +
          (c.basePay != null ? '<p style="font-size:12px;color:#cac4d0">' + T('ui.contract_pay', 'Pays {1} if you keep the terms, {2} if you miss them', money(pay), money(c.basePay)) + '</p>' : '');
      };
      var cards = arr(j.offers).map(function (o) {
        return '<div class="slp-card"><h4>' + esc(o.title) + ': ' + esc(o.item || '') + (o.fragile ? ' &middot; fragile' : '') + '</h4>' + contractLines(o.contract, o.pay) +
          '<p>' + esc(o.from) + ' &rarr; ' + esc(o.to) + ' &middot; ' + (o.metres ? (o.metres / 1000).toFixed(1) + ' km &middot; ' : '') + (o.seconds ? mmss(o.seconds) + ' &middot; ' : '') + '<b>' + money(o.pay) + '</b></p>' +
          (a ? '' : '<div class="slp-acts"><div class="slp-btn" data-a="jobtake" data-v="' + esc(o.id) + ('">' + T('ui.take_it', 'Take it') + '</div></div>')) + '</div>';
      }).join('');
      var boostLine = j.boost && j.boost > 1.04 ? ('<div class="slp-empty">' + T('ui.new_in_town_jobs_pay', 'New in town: jobs pay ') + '&times;') + j.boost.toFixed(1) + (T('ui.until_you_make_a_name', ' until you make a name or buy your first part.') + '</div>') : '';
      return bar(T('app.jobs', 'Jobs')) + '<div class="slp-body">' + boostLine + activeCard + (cards || ('<div class="slp-empty">' + T('ui.nothing_on_the_board_new', 'Nothing on the board. New jobs come in the morning and at dusk.') + '</div>')) +
        (j.crew ? ('<div class="slp-card"><h4>' + T('ui.crew_contract', 'Crew contract: ')) + esc(j.crew.boss) + ('</h4><p>' + T('ui.beat', 'Beat ')) + j.crew.need + T('ui.racers_of_tier', ' racers of tier ') + j.crew.tier + T('ui.or_better', ' or better: ') + j.crew.won + T('ui.so_far', ' so far, ') + j.crew.daysLeft + T('ui.days_left', ' days left. ') + money(j.crew.pay) + '</p></div>' : '') +
        (j.sponsor ? ('<div class="slp-card"><h4>' + T('ui.sponsor', 'Sponsor: ')) + esc(j.sponsor.name) + '</h4><p>' + money(j.sponsor.weekly) + T('ui.a_week_for_two_wins', ' a week for two wins a week: ') + j.sponsor.weekWins + (T('ui.this_week', ' this week.') + '</p></div>') : '') +
        (j.quarter || j.dyno ? ('<div class="slp-card"><h4>' + T('ui.tuning_challenges', 'Tuning challenges') + '</h4><p>') + (j.quarter ? T('ui.quarter_mile_at_the_test', 'Quarter mile at the test track under {1} s. ', j.quarter) : '') + (j.dyno ? T('ui.dyno_1_ps_on_the', 'Dyno: {1} PS on the car info sheet in your garage.', j.dyno) : '') + '</p></div>' : '') +
        (j.flip ? ('<div class="slp-card"><h4>' + T('ui.junkyard_challenge_flip_a_car', 'Junkyard challenge: flip a car') + '</h4><p>' + T('ui.sell_one_for', 'Sell one for ')) + money(j.flip.target) + T('ui.more_than_you_paid_for', ' more than you paid for a bonus. Best so far: ') + money(j.flip.best || 0) + '.</p></div>' : '') +
        '<div class="slp-empty">' + (j.done || 0) + T('ui.jobs_done', ' jobs done, ') + money(j.earned || 0) + ' earned.</div></div>';
    }

    // the club: today's league events, the standings
    // Turf: the city's districts, who holds them and how firmly (sl_crews, X21)
    // the turf map: every district a circle at its place on the map, in its owner's colour (yours in green), bigger with more control; you are the white ring
    var CREW_COLOURS = { southside: '#d55e00', riverbed: '#0072b2', northend: '#f0e442', ringroad: '#cc79a7' };      // (Okabe-Ito: told apart by every kind of colour vision)
    var YOURS_COLOUR = '#009e73';
    var CREW_INITIALS = { southside: 'S', riverbed: 'R', northend: 'N', ringroad: 'G' };      // (each crew its own letter in its circle)
    function turfMap(t) {
      var ds = arr(t.districts).filter(function (d) { return typeof d.x === 'number' && typeof d.y === 'number'; });
      if (ds.length < 2) return '';
      var xs = ds.map(function (d) { return d.x; }).concat(t.you ? [t.you.x] : []), ys = ds.map(function (d) { return d.y; }).concat(t.you ? [t.you.y] : []);
      var x0 = Math.min.apply(null, xs), x1 = Math.max.apply(null, xs), y0 = Math.min.apply(null, ys), y1 = Math.max.apply(null, ys);
      var W = 300, H = 200, pad = 30, k = Math.min((W - 2 * pad) / Math.max(1, x1 - x0), (H - 2 * pad) / Math.max(1, y1 - y0));
      var px = function (x) { return Math.round(W / 2 + (x - (x0 + x1) / 2) * k); }, py = function (y) { return Math.round(H / 2 - (y - (y0 + y1) / 2) * k); };      // (north up)
      var dots = ds.map(function (d) {
        var col = d.yours ? YOURS_COLOUR : (CREW_COLOURS[d.crew] || '#8e8e93'), r0 = 8 + Math.round((d.control || 0) / 12), initial = d.yours ? '✓' : CREW_INITIALS[d.crew] || String(d.owner || '?').charAt(0).toUpperCase();
        return '<circle cx="' + px(d.x) + '" cy="' + py(d.y) + '" r="' + r0 + '" fill="' + col + '" fill-opacity="0.75" stroke="' + (d.yours ? '#fff' : col) + '" stroke-width="' + (d.yours ? 3 : 1) + '"/>' +
          '<text x="' + px(d.x) + '" y="' + (py(d.y) + 4) + '" text-anchor="middle" font-size="12" font-weight="700" fill="#000">' + esc(initial) + '</text>' +
          '<text x="' + px(d.x) + '" y="' + (py(d.y) + 24) + '" text-anchor="middle" font-size="9" fill="#e6e1e5">' + esc(d.name) + '</text>';
      }).join('');
      var you = t.you ? '<circle cx="' + px(t.you.x) + '" cy="' + py(t.you.y) + '" r="4" fill="none" stroke="#fff" stroke-width="2"/>' : '';
      return '<div class="slp-card"><svg class="slp-turfmap" viewBox="0 0 ' + W + ' ' + H + '" width="100%">' + dots + you + '</svg></div>';
    }
    function turfPage() {
      var t = obj(st.data.turf);
      var rows = arr(t.districts).map(function (d) {
        return '<div class="slp-row"><div class="slp-rt"><b>' + esc(d.name) + (d.here ? T('ui.middot_you_are_here', ' &middot; you are here') : '') + '</b><span>' +
          (d.yours ? T('ui.yours', 'Yours') : esc(d.owner)) + ' &middot; ' + d.control + T('ui.control', '% control') + (d.home ? T('ui.middot_home_of_1', ' &middot; home of {1}', esc(d.home)) : '') +
          (d.yours && d.cut != null ? ' &middot; ' + T('ui.turf_cut_week', '{1} a week', money(d.cut)) + (d.base ? ' (' + T('ui.turf_base', 'base') + ')' : '') : '') + '</span></div></div>';
      }).join('');
      var crews = arr(t.crews).map(function (c) { return '<p>' + esc(c.name) + (c.leader ? T('ui.middot_led_by_1', ' &middot; led by {1}', esc(c.leader)) : '') + '</p>'; }).join('');
      return bar(T('app.turf', 'Turf')) + '<div class="slp-body">' + turfMap(t) +
        ('<div class="slp-empty">' + T('ui.beat_a_crew_on_its', 'Beat a crew on its own streets to take the district. You hold ')) + (t.held || 0) + '.' + (t.turfWar ? T('ui.the_leaders_want_a_word', ' The leaders want a word.') : '') + (t.income != null ? ' ' + T('ui.turf_income', 'Next payout: {1}', money(t.income)) : '') + '</div>' +
        (rows || ('<div class="slp-empty">' + T('ui.no_districts_on_this_map', 'No districts on this map.') + '</div>')) + ('<div class="slp-card"><h4>' + T('ui.the_crews', 'The crews') + '</h4>') + crews + '</div></div>';
    }

    function clubPage() {
      var c = st.data.club;
      if (!c) return bar(T('app.club', 'Club')) + ('<div class="slp-body"><div class="slp-empty">' + T('ui.no_club_yet', 'No club yet.') + '</div></div>');
      var ev = c.today || {};
      var row = function (kind, label, e) {
        if (!e) return '';
        var act = e.done ? ('<b>' + T('ui.done', 'Done') + '</b>') : (kind === 'day' && !e.open ? ('<b>' + T('ui.soon', 'Soon') + '</b>') : '<div class="slp-btn" data-a="league" data-v="' + kind + ('">' + T('ui.enter', 'Enter') + '</div>'));
        return '<div class="slp-kv"><span>' + label + '<br><small>' + esc(e.name) + '</small></span>' + act + '</div>';
      };
      var table = arr(c.standings).map(function (r) {
        return '<div class="slp-kv"' + (r.you ? ' style="font-weight:700"' : '') + '><span>' + r.place + '. ' + esc(r.name) + '</span><b>' + r.points + '</b></div>';
      }).join('');
      return bar(c.club) + ('<div class="slp-body"><div class="slp-card"><h4>' + T('ui.season', 'Season ')) + c.season + T('ui.day', ', day ') + c.day + ' of ' + c.days + (ev.finale ? T('ui.middot_finale_double_points', ' &middot; finale, double points') : '') + '</h4>' +
        ('<p>' + T('ui.class', 'Class ')) + esc(c['class'] || '?') + (c.carClass && c.carClass !== c['class'] ? T('ui.middot_this_car_1', ' &middot; this car: {1}', esc(c.carClass)) : '') + (' ' + '&middot;' + T('ui.skip_any_event_it_only', ' skip any event, it only costs its points') + '</p>') +
        row('night', T('clubs.night_league', 'Night league'), ev.night) + row('day', T('clubs.day_league', 'Day league'), ev.day) + '</div>' +
        ('<div class="slp-card"><h4>' + T('ui.standings', 'Standings') + '</h4>') + table + '</div></div>';
    }

    // the weekly costs (sl_weekly.summary(): { enabled, week, dayOfWeek, nextBillDay, debt, bills = { { id, label, amount, due } }, history = { { week, income, costs, net } } }, any part may be
    // missing or empty). Bills are paid by themselves on the billing day; what is short becomes debt, which the only button here pays.
    function weeklyCard() {
      var wk = st.data.weekly;
      if (!wk || wk.enabled === false || obj(st.data.has).weekly === false) return '';
      var left = Number(wk.nextBillDay) || 0, bills = arr(wk.bills), hist = arr(wk.history).slice(0, 4), debt = Math.round(Number(wk.debt) || 0);
      var html = '<div class="slp-card"><h4>' + T('ui.weekly_costs', 'Weekly costs') + '</h4><p>' + T('ui.week_day', 'Week {1}, day {2} of 7', Number(wk.week) || 1, Number(wk.dayOfWeek) || 1) + ' &middot; ' +
        (left <= 0 ? T('ui.bills_tonight', 'bills are paid tonight') : left === 1 ? T('ui.bills_in_one_day', 'bills are paid in 1 day') : T('ui.bills_in_days', 'bills are paid in {1} days', left)) + '</p>';
      html += bills.length ? bills.map(function (b) {
        return '<div class="slp-row" style="min-height:40px;cursor:default;padding:6px 0"><div class="slp-rt" style="margin-left:0"><b>' + esc(b.label || '') + '</b><small>' + (Number(b.due) <= 0 ? T('ui.due_tonight', 'tonight') : T('ui.due_in_days', 'in {1} d', Number(b.due) || 0)) +
          '</small></div><div class="slp-amt slp-minus">' + money(-(Number(b.amount) || 0)) + '</div></div>';
      }).join('') : '<p>' + T('ui.no_bills_yet', 'No bills yet: rent starts with a second garage or more than two cars.') + '</p>';
      if (debt > 0) {
        var pay = Math.min(debt, Math.max(0, Math.floor(st.data.money || 0)));
        html += '<p class="slp-pink">' + T('ui.weekly_debt', 'Debt: {1}. The bank will not lend until it is paid.', money(debt)) + '</p>' +
          (pay > 0 ? '<div class="slp-acts"><div class="slp-btn" data-a="paydebt" data-v="' + pay + '">' + T('ui.pay', 'Pay ') + money(pay) + '</div></div>' : '');
      }
      html += hist.map(function (h) {
        var net = Number(h.net) || 0;
        return '<div class="slp-row" style="min-height:40px;cursor:default;padding:6px 0"><div class="slp-rt" style="margin-left:0"><b>' + T('ui.week_n', 'Week {1}', Number(h.week) || 0) + '</b><small>' + T('ui.week_in_out', 'in {1} &middot; out {2}', money(h.income), money(h.costs)) +
          '</small></div><div class="slp-amt ' + (net >= 0 ? 'slp-plus' : 'slp-minus') + '">' + (net >= 0 ? '+' : '') + money(net) + '</div></div>';
      }).join('');
      return html + '</div>';
    }

    function bankPage() {
      var rows = arr(st.data.ledger).map(function (e) {
        return '<div class="slp-row" style="min-height:52px;cursor:default"><div class="slp-rt"><b>' + esc(e.label || '') + '</b></div><div class="slp-amt ' + (e.amount >= 0 ? 'slp-plus' : 'slp-minus') + '">' +
          (e.amount >= 0 ? '+' : '') + money(e.amount) + '</div></div>';
      });
      // the loan and the insurance
      var bk = st.data.bank, cards = '';
      if (bk) {
        if (bk.loan) {
          cards += ('<div class="slp-card"><h4>' + T('ui.loan', 'Loan: ')) + money(bk.loan.owed) + (' owed' + '</h4><p>' + T('ui.next_payment', 'Next payment ')) + money(bk.loan.due) + ' in ' + bk.loan.dueIn + ' day' + (bk.loan.dueIn === 1 ? '' : 's') +
            (bk.loan.missed ? ' &middot; <span class="slp-pink">' + bk.loan.missed + ' missed</span>' : '') + '</p>' +
            '<div class="slp-acts"><div class="slp-btn" data-a="repay" data-v="' + Math.min(bk.loan.owed, st.data.money || 0) + ('">' + T('ui.pay', 'Pay ')) + money(Math.min(bk.loan.owed, st.data.money || 0)) + '</div></div></div>';
        } else {
          var half = Math.floor(bk.limit / 200) * 100, quarter = Math.floor(bk.limit / 400) * 100;
          cards += ('<div class="slp-card"><h4>' + T('ui.borrow', 'Borrow') + '</h4><p>' + 'Up to ') + money(bk.limit) + ' &middot; ' + Math.round(bk.rate * 100) + (T('ui.a_day', '% a day ') + '&middot;' + T('ui.a_quarter_due_each_week', ' a quarter due each week') + '</p>') +
            '<div class="slp-acts">' + (quarter >= 100 && quarter < half ? '<div class="slp-btn slp-tonal" data-a="borrow" data-v="' + quarter + '">' + money(quarter) + '</div>' : '') + '<div class="slp-btn slp-tonal" data-a="borrow" data-v="' + half + '">' + money(half) + '</div><div class="slp-btn slp-tonal" data-a="borrow" data-v="' + bk.limit + '">' + money(bk.limit) + '</div></div></div>';
        }
        cards += bk.policy ? ('<div class="slp-card"><h4>' + T('ui.insured', 'Insured') + '</h4><p>') + (bk.policy.startsIn ? T('ui.cover_starts_tomorrow', 'Cover starts tomorrow') : T('ui.covering_half_of_repairs_and', 'Covering half of repairs and impound bills over {1}', money(bk.deductible))) + '</p>' +
            ('<div class="slp-acts"><div class="slp-btn slp-text" data-a="insure" data-v="false">' + T('ui.cancel', 'Cancel') + '</div></div></div>')
          : ('<div class="slp-card"><h4>' + T('ui.insurance', 'Insurance') + '</h4><p>') + money(bk.premium) + T('ui.a_week_half_of_repairs', ' a week: half of repairs and impound bills over ') + money(bk.deductible) + (T('ui.from_the_next_day', ', from the next day') + '</p>') + (bk.premiumWhy ? '<p class="slp-sub">' + esc(bk.premiumWhy) + '</p>' : '') +
            ('<div class="slp-acts"><div class="slp-btn slp-tonal" data-a="insure" data-v="true">' + T('ui.insure', 'Insure') + '</div></div></div>');
      }
      return bar(T('app.bank', 'Bank')) + ('<div class="slp-body"><div class="slp-bal"><small>' + T('ui.balance', 'Balance') + '</small><div>') + money(st.data.money) + '</div></div>' + weeklyCard() + cards +
        (rows.join('') || ('<div class="slp-empty">' + T('ui.no_transactions_yet', 'No transactions yet.') + '</div>')) + '</div>';
    }

    // the two marketplaces: cars (the dealers and the private ads) and parts (Revline, Swap & Bid, the paper, the Wrench Works catalog).
    // The laptop shows the same data in the same tabs; a bought car or part goes the one delivery path.
    function bodyOf(html) { var i = html.indexOf('<div class="slp-body">'); return i < 0 ? html : html.slice(i); }
    function tabsHtml(kind, list) {
      var cur = st.tab[kind];
      return '<div class="slp-tabs">' + list.map(function (t) {
        return '<div class="slp-tab' + (t[0] === cur ? ' slp-tabon' : '') + '" data-a="mtab" data-v="' + kind + '|' + t[0] + '">' + t[1] + '</div>';
      }).join('') + '</div>';
    }
    function dealerCards() {
      var d = obj(st.dealers);
      var coming = arr(d.coming).map(function (c) {
        return '<div class="slp-kv"><span>' + esc(c.name) + '</span><b>' + (c.hours > 0 ? T('ui.in_about_1_h', 'in about {1} h', c.hours) : 'arriving') + '</b></div>';
      }).join('');
      var rows = arr(d.dealers).map(function (x) {
        return '<div class="slp-card" data-a="mdealer" data-v="' + esc(x.id) + '"><h4>' + esc(x.name) + '</h4><p>' + adDist(x.metres) + ' away &middot; ' + x.count + ' car' + (x.count === 1 ? '' : 's') + ' today</p></div>';
      }).join('');
      return '<div class="slp-body">' + (coming ? ('<div class="slp-card"><h4>' + T('ui.on_the_way_to_your_2', 'On the way to your garage') + '</h4>') + coming + '</div>' : '') + (rows || ('<div class="slp-empty">' + T('ui.no_dealers_on_this_map', 'No dealers on this map.') + '</div>')) + '</div>';
    }
    function dealerOffers() {
      var o = obj(st.offers);
      var cards = arr(o.offers).map(function (c) {
        var faults = arr(c.faults);
        return '<div class="slp-card">' + adPic(c) + '<h4 data-a="moffer" data-v="' + esc(c.id) + '">' + (c.year ? c.year + ' ' : '') + esc(c.name) + '</h4><p>' + esc(c.brand || '') + (c.title ? ' &middot; ' + esc(c.title) : '') + '</p><p>' + adFacts(c) + '</p>' +
          '<p>' + esc(c.seller || o.name) + ' &middot; ' + adDist(c.metres) + T('ui.away_middot_arrives_in_about', ' away &middot; arrives in about ') + (c.hours || 0) + T('ui.h_middot_condition', ' h &middot; condition ') + Math.round((c.condition || 0) * 100) + '%' + (faults.length ? ('<br>' + T('ui.needs_2', 'Needs: ')) + esc(faults.join(', ')) : '') + '</p>' +
          '<p><b>' + money(c.price) + '</b></p><div class="slp-acts"><div class="slp-btn slp-tonal" data-a="moffer" data-v="' + esc(c.id) + ('">' + T('ui.details', 'Details') + '</div>') +
          '<div class="slp-btn' + ((o.money || 0) < c.price ? ' slp-off' : '') + '" data-a="mbuy" data-v="' + esc(o.dealer) + '|' + esc(c.id) + ('">' + T('ui.buy', 'Buy') + '</div></div></div>');
      }).join('');
      return '<div class="slp-body"><div class="slp-empty">' + esc(o.name || T('ui.dealer', 'Dealer')) + '</div>' + (cards || ('<div class="slp-empty">' + T('ui.nothing_left_on_the_lot', 'Nothing left on the lot today.') + '</div>')) + '</div>';
    }
    function dealerOffer() {
      var o = obj(st.offers), c = null;
      arr(o.offers).forEach(function (x) { if (x.id === st.cmOffer) c = x; });
      if (!c) return ('<div class="slp-body"><div class="slp-empty">' + T('ui.this_car_has_gone', 'This car has gone.') + '</div></div>');
      var sp = obj(c.specs), faults = arr(c.faults);
      var row = function (k, v) { return v == null || v === '' ? '' : '<div class="slp-kv"><span>' + k + '</span><b>' + v + '</b></div>'; };
      return '<div class="slp-body"><div class="slp-card">' + adPic(c) + '<h4>' + (c.year ? c.year + ' ' : '') + esc(c.name) + '</h4>' +
        row(T('ui.brand', 'Brand'), esc(c.brand)) + row(T('ui.year', 'Year'), c.year) + row(T('ui.mileage', 'Mileage'), c.mileage != null ? Number(c.mileage).toLocaleString() + ' km' : null) + row(T('ui.condition_2', 'Condition'), Math.round((c.condition || 0) * 100) + '%') +
        row(T('ui.power', 'Power'), sp.power ? Math.round(sp.power) + ' PS' : null) + row(T('ui.weight', 'Weight'), sp.weight ? Math.round(sp.weight).toLocaleString() + ' kg' : null) + row(T('ui.transmission', 'Transmission'), esc(sp.transmission)) +
        row(T('ui.drivetrain', 'Drivetrain'), esc(sp.drivetrain)) + row(T('ui.fuel', 'Fuel'), esc(sp.fuel)) + row(T('ui.body', 'Body'), esc(sp.body)) + row(T('ui.top_speed', 'Top speed'), sp.topSpeed ? Math.round(sp.topSpeed * 3.6) + ' km/h' : null) +
        (faults.length ? row(T('ui.needs', 'Needs'), esc(faults.join(', '))) : '') + reportBlock('offer:' + c.id, c.report) + '</div><div class="slp-card">' + row(T('ui.seller', 'Seller'), esc(c.seller || o.name)) + row(T('ui.distance', 'Distance'), adDist(c.metres)) +
        row(T('ui.delivery', 'Delivery'), T('ui.to_your_garage_in_about', 'to your garage in about {1} h', (c.hours || 0))) + row(T('ui.price', 'Price'), money(c.price)) +
        '<div class="slp-acts"><div class="slp-btn' + ((o.money || 0) < c.price ? ' slp-off' : '') + '" data-a="mbuy" data-v="' + esc(o.dealer) + '|' + esc(c.id) + ('">' + T('ui.buy_2', 'Buy ') + '&middot;' + ' ') + money(c.price) + '</div></div></div></div>';
    }
    // the car auctions (sl_carauctions), as on the laptop
    function leftText(min) {
      min = Math.max(0, Math.round(min || 0));
      return min >= 1440 ? Math.floor(min / 1440) + ' d ' + Math.floor(min % 1440 / 60) + ' h' : min >= 60 ? Math.floor(min / 60) + ' h ' + (min % 60) + ' min' : min + ' min';
    }
    function auctionCard(l) {
      var mine = l.high === 'you', faults = arr(l.faults);
      var state = l.mine ? T('ui.auction_your_reserve', 'Your reserve {1}', money(l.reserve)) : (l.bid > 0 ? (mine ? T('ui.auction_high_you', 'You are the highest bidder') : T('ui.auction_outbid', 'Outbid')) : T('ui.auction_no_bids', 'No bids yet'));
      var plus = Math.round((l.bid || l.next) * 1.1 / 10) * 10;
      var acts = l.mine ? '' : '<div class="slp-acts">' + (mine ? '' : '<div class="slp-btn' + ((st.auction && st.auction.money != null && st.auction.money < l.next) ? ' slp-off' : '') + '" data-a="abid" data-v="' + esc(l.id) + '|' + l.next + '">' + T('ui.auction_bid_next', 'Bid {1}', money(l.next)) + '</div>' +
        '<div class="slp-btn slp-tonal' + ((st.auction && st.auction.money != null && st.auction.money < plus) ? ' slp-off' : '') + '" data-a="abid" data-v="' + esc(l.id) + '|' + plus + '">' + T('ui.auction_bid_plus', 'Bid +10% ({1})', money(plus)) + '</div>') +
        '<div class="slp-btn slp-text" data-a="awatch" data-v="' + esc(l.id) + '|' + (l.watched ? 0 : 1) + '">' + (l.watched ? T('ui.auction_watching', 'Watching (tap to stop)') : T('ui.auction_watch', 'Watch')) + '</div></div>';
      return '<div class="slp-card">' + adPic(l) + '<h4>' + (l.year ? l.year + ' ' : '') + esc(l.name) + ' &middot; ' + T('ui.auction_grade', 'Grade {1}', esc(l.grade)) + '</h4>' +
        '<p>' + T('ui.auction_condition', 'Condition {1}%', l.condition) + (l.mileage != null ? ' &middot; ' + Math.round(l.mileage / 1000) + 'k km' : '') + (faults.length ? ' &middot; ' + T('ui.needs_2', 'Needs: ') + esc(faults.join(', ')) : '') + '</p>' +
        '<p><b>' + money(l.bid) + '</b> &middot; ' + state + ' &middot; ' + (l.reserveMet ? T('ui.auction_reserve_met', 'Reserve met') : T('ui.auction_reserve_not_met', 'Reserve not met')) +
        ' &middot; ' + (l.live ? T('ui.auction_going_in', 'Going in {1} s', l.secondsLeft) : T('ui.auction_closes_in', 'Closes in {1}', leftText(l.minutesLeft))) + (l.mine ? '' : ' &middot; ' + T('ui.auction_delivery', 'Delivery {1}', money(l.delivery))) + '</p>' +
        reportBlock('auction:' + l.id, l.report) + acts + '</div>';
    }
    function auctionPage() {
      var a = obj(st.auction), cars = arr(a.sellable);
      var lots = arr(a.lots).map(auctionCard).join(''), mine = arr(a.mine).map(auctionCard).join('');
      var sell = cars.map(function (c) {
        return '<div class="slp-card"><h4>' + esc(c.name) + ' &middot; ' + T('ui.auction_grade', 'Grade {1}', esc(c.grade)) + '</h4><p>' + T('ui.auction_fair', 'Worth about {1}', money(c.fair)) + '</p><div class="slp-acts">' +
          [70, 80, 90].map(function (pc) { return '<div class="slp-btn slp-tonal" data-a="asell" data-v="' + esc(c.id) + '|' + Math.round(c.fair * pc / 100 / 10) * 10 + '">' + T('ui.auction_reserve_pct', 'Reserve {1}%', pc) + '</div>'; }).join('') + '</div></div>';
      }).join('');
      var lv = a.live ? ('<h4>' + T('ui.auction_live', 'Live at the yard: lot {1} of {2}', a.live.index, a.live.total) + '</h4>' + (a.live.waiting ? '<div class="slp-empty">' + T('ui.auction_next_lot', 'The next lot is coming up.') + '</div>' : '') + auctionCard(a.live.lot)) : '';
      return '<div class="slp-body">' + lv + (lots || ('<div class="slp-empty">' + T('ui.auction_none', 'No lots right now.') + '</div>')) +
        '<div class="slp-empty">' + T('ui.auction_hint', 'A car can hide a fault the report does not show. The reserve stays secret until it is met.') + '</div>' +
        (mine ? '<h4>' + T('ui.auction_your_lots', 'Your cars at auction') + '</h4>' + mine : '') +
        '<h4>' + T('ui.auction_sell_title', 'Sell one of your cars at auction') + '</h4>' + (sell || ('<div class="slp-empty">' + T('ui.auction_no_cars', 'No other car to put up.') + '</div>')) + '</div>';
    }
    function carMarketPage() {
      var m = obj(st.data.market), tab = st.tab.cars;
      var body;
      if (tab === 'auction') {
        body = auctionPage();
      } else if (tab === 'ads') {
        var cards = arr(m.listings).filter(function (l) { return l.car; }).map(adCard).join('');
        body = '<div class="slp-body">' + (cards || ('<div class="slp-empty">' + T('ui.no_private_cars_for_sale', 'No private cars for sale right now. New ads come in through the day.') + '</div>')) + sellCards(m, 'cars') + '</div>';
      } else {
        body = st.cmView === 'offer' ? dealerOffer() : (st.cmView === 'offers' ? dealerOffers() : dealerCards());
      }
      return bar(T('app.carmarket', 'Car market')) + tabsHtml('cars', [['dealers', T('ui.dealers', 'Dealers')], ['ads', T('ui.private_ads', 'Private ads')], ['auction', T('ui.car_auctions', 'Car auctions')]]) + body;
    }
    function partMarketPage() {
      var m = obj(st.data.market), tab = st.tab.parts, body;
      if (tab === 'auctions') body = bodyOf(bidPage());
      else if (tab === 'paper') body = bodyOf(paperPage());
      else if (tab === 'catalog') {
        body = ('<div class="slp-body"><div class="slp-card"><h4>' + T('ui.the_wrench_works_catalog', 'The Wrench Works catalog') + '</h4><p>' + T('ui.every_part_that_fits_your', 'Every part that fits your car, new, with its price. Open it from the garage: the car goes in, the catalog opens, what you order is delivered to your shelf.') + '</p>') +
          ('<div class="slp-acts"><div class="slp-btn" data-a="pcatalog" data-v="1">' + T('ui.open_the_catalog', 'Open the catalog') + '</div></div></div></div>');
      } else {
        var cards = arr(m.listings).filter(function (l) { return !l.car; }).map(adCard).join('');
        body = '<div class="slp-body">' + (m.deliveries ? '<div class="slp-empty">' + m.deliveries + (T('ui.on_the_way_to_your', ' on the way to your garage.') + '</div>') : '') +
          (cards || ('<div class="slp-empty">' + T('ui.nothing_listed_right_now_new', 'Nothing listed right now. New ads come in through the day.') + '</div>')) + sellCards(m, 'parts') + '</div>';
      }
      return bar(T('app.partmarket', 'Part market')) + tabsHtml('parts', [['revline', T('ui.revline', 'Revline')], ['auctions', T('ui.swap_bid', 'Swap & Bid')], ['paper', T('ui.classifieds_2', 'Classifieds')], ['catalog', T('ui.catalog', 'Catalog')]]) + body;
    }

                // Help: the topics (sl/core/help, the same words as docs/PLAYER_GUIDE.md), then one page
    function helpPage() {
      var rows = arr(st.help).map(function (p) {
        return '<div class="slp-row" data-a="helppage" data-v="' + esc(p.id) + '"><div class="slp-rt"><b>' + esc(p.title) + '</b></div></div>';
      }).join('');
      return bar(T('app.help', 'Help')) + '<div class="slp-body">' + (rows || ('<div class="slp-empty">' + T('ui.loading_the_help', 'Loading the help...') + '</div>')) + '</div>';
    }
    function helpTopicPage() {
      var p = arr(st.help).filter(function (x) { return x.id === st.helpId; })[0];
      if (!p) return bar(T('app.help', 'Help')) + ('<div class="slp-body"><div class="slp-empty">' + T('ui.no_such_page', 'No such page.') + '</div></div>');
      var inList = false, html = '';
      arr(p.body).forEach(function (t) {
        var bullet = String(t).indexOf('- ') === 0;
        if (bullet && !inList) { html += '<ul style="margin:6px 0 6px 18px;padding:0">'; inList = true; }
        if (!bullet && inList) { html += '</ul>'; inList = false; }
        html += bullet ? '<li style="margin:4px 0">' + esc(String(t).slice(2)) + '</li>' : '<p>' + esc(t) + '</p>';
      });
      if (inList) html += '</ul>';
      return bar(p.title) + '<div class="slp-body"><div class="slp-card">' + html + '</div></div>';
    }

    // the camera, the gallery and a photo with the wallpaper buttons (sl_photos)
    // the map: the places by kind, nearest first; a tap sets the route on the road
    var MAP_KINDS = { garage: T('ui.kind_garage', 'Garages'), dealer: T('ui.kind_dealer', 'Dealers'), junkyard: T('ui.kind_junkyard', 'Junkyards'),
      scrapyard: T('ui.kind_scrapyard', 'Scrapyards and auctions'), shop: T('ui.kind_shop', 'Shops'), parts: T('ui.kind_parts', 'Parts shops'),
      carwash: T('ui.kind_carwash', 'Car washes'), meet: T('ui.kind_meet', 'Car meets'), hospital: T('ui.kind_hospital', 'Hospital'), valet: T('ui.kind_valet', 'Valet'), gas: T('ui.kind_gas', 'Gas stations'), auction: T('ui.kind_auction', 'Live auction'), job: T('ui.kind_job', 'Job stops') };
    function distText(m) { return m == null ? '' : (m < 1000 ? m + ' m' : (m / 1000).toFixed(1) + ' km'); }
    // the live map (a canvas drawn by the global module slMapsDraw from the tiles of sl_mapsfeed): the Map tab; the places by kind stay as the List tab
    var lastLand = false;
    var MV = { tiles: {}, asked: {}, pose: null, route: [], places: [], on: false, last: 0, roads: [], key: '', mpp: 2, opts: { style: 'street', headingUp: false, speed: true }, zoomed: false };
    function mapWanted() { return !!(st.open && st.app === 'map' && st.tab.map === 'map'); }
    function syncMapFeed() {
      var w = mapWanted();
      if (w === MV.on) return;
      MV.on = w;
      lua('@sl_mapsfeed.use("phone", ' + w + ')');
      if (!w) MV.asked = {};
    }
    function paintMap() {
      var now = Date.now();
      if (!mapWanted() || now - MV.last < 100) return;           // at most 10 frames a second
      var cv = layer.querySelector('.slp-mapcv'), D = win.slMapsDraw;
      if (!cv || !D || !MV.pose || !cv.clientWidth || !cv.getContext) return;
      MV.last = now;
      var w = cv.clientWidth, h = cv.clientHeight, ctx;
      try { ctx = cv.getContext('2d'); } catch (e) { return; }
      if (!ctx) return;
      if (cv.width !== w || cv.height !== h) { cv.width = w; cv.height = h; MV.key = ''; }
      var half = Math.max(w, h) * MV.mpp * 0.75, keys = [], p = MV.pose;
      for (var tx = Math.floor((p.x - half) / 256); tx <= Math.floor((p.x + half) / 256); tx++) for (var ty = Math.floor((p.y - half) / 256); ty <= Math.floor((p.y + half) / 256); ty++) keys.push(tx + ',' + ty);
      var want = keys.filter(function (k) { return !MV.tiles[k] && !MV.asked[k]; });
      if (want.length) { want.forEach(function (k) { MV.asked[k] = true; }); lua('@sl_mapsfeed.tiles({' + want.map(function (k) { return '"' + k + '"'; }).join(',') + '})'); }      // (a Lua table: tile keys are digits, commas and minus signs)
      var key = keys.join(';');
      if (key !== MV.key) { MV.key = key; MV.roads = []; keys.forEach(function (k) { if (MV.tiles[k]) MV.roads = MV.roads.concat(Array.isArray(MV.tiles[k]) ? MV.tiles[k] : []); }); }
      D.draw(ctx, w, h, { roads: MV.roads, route: MV.route, pins: MV.places, player: p, speed: MV.opts.speed === false ? null : { now: p.speed || 0, limit: p.limit || null, mph: !!p.mph, sign: p.mph ? 'us' : 'round' } }, { cx: p.x, cy: p.y, mpp: MV.mpp, rot: MV.opts.headingUp ? -(p.heading || 0) : 0, skin: MV.opts.style || 'street', night: obj(st.data).phase === 'night' });
    }
    function mapPage() {
      var m = obj(st.map), groups = arr(m.groups), r = m.route;
      if (st.tab.map === 'map') {
        return bar(T('app.map', 'Map')) + tabsHtml('map', [['map', T('ui.map_tab', 'Map')], ['list', T('ui.list_tab', 'List')]]) +
          '<div class="slp-body slp-mapbody"><canvas class="slp-mapcv"></canvas>' +
          '<div class="slp-mapzoom"><div data-a="mapzoom" data-v="in">+</div><div data-a="mapzoom" data-v="out">&minus;</div></div>' +
          (r ? '<div class="slp-card"><h4>' + esc(T('ui.route_to_1', 'Route: {1}', r.name)) + '</h4><div class="slp-acts"><div class="slp-btn slp-tonal" data-a="clearroute" data-v="1">' + T('ui.clear_route', 'Clear route') + '</div></div></div>' : '') + '</div>';
      }
      var head = '<div class="slp-card"><p>' + esc(T('ui.map_text', 'Tap a place and the route shows on the road. It clears when you get there.')) + '</p>' +
        (r ? '<h4>' + esc(T('ui.route_to_1', 'Route: {1}', r.name)) + '</h4><div class="slp-acts"><div class="slp-btn slp-tonal" data-a="clearroute" data-v="1">' + T('ui.clear_route', 'Clear route') + '</div></div>' : '') + '</div>';
      var body = groups.map(function (g) {
        return '<div class="slp-seth">' + esc(MAP_KINDS[g.kind] || T('ui.kind_other', 'Other places')) + '</div>' + arr(g.places).map(function (p) {
          return '<div class="slp-row" data-a="route" data-v="' + esc(p.id) + '"><div class="slp-rt"><b>' + esc(p.name) + (r && r.id === p.id ? ' &#10003;' : '') + '</b><span>' + distText(p.dist) + '</span></div><div class="slp-ib">' + I.gps + '</div></div>';
        }).join('');
      }).join('');
      return bar(T('app.map', 'Map')) + tabsHtml('map', [['map', T('ui.map_tab', 'Map')], ['list', T('ui.list_tab', 'List')]]) + '<div class="slp-body">' + head + (body || '<div class="slp-empty">' + T('ui.no_places_yet', 'The map has no places yet.') + '</div>') + '</div>';
    }
    function cameraPage() {
      return bar(T('app.camera', 'Camera')) + '<div class="slp-body"><div class="slp-card"><p>' + esc(T('ui.camera_text', 'Takes a picture of what you see, without the phone or any other screen. It is kept in the Gallery and in the folder screenshots/street_legal.')) + '</p>' +
        '<div class="slp-acts"><div class="slp-btn" data-a="photo">' + T('ui.take_a_photo', 'Take a photo') + '</div></div></div></div>';
    }
    // the Camera app as a camera (sl_phonecam puts the view in first person): a full-screen sideways phone over it. data.camera = { firstPerson, sway 0..1, grid, bezel, zoomMax }
    function camHtml() {
      var c = obj(st.data.camera), cam = st.cam = st.cam || { zoom: 1, flash: false, grid: c.grid !== false };
      var zooms = [1, 2, 4, 8].filter(function (z) { return z <= (Number(c.zoomMax) || 4); });
      var sway = Math.max(0, Math.min(1, c.sway == null ? 0.5 : Number(c.sway)));
      return '<div class="slp-camui' + (st.camFlashFx ? ' slp-camflash' : '') + '" style="--slp-sway:' + sway.toFixed(2) + '">' +
        (c.bezel === false ? '' : '<div class="slp-cambz slp-cbl"><i></i></div><div class="slp-cambz slp-cbr"></div><div class="slp-cambz slp-cbt"></div><div class="slp-cambz slp-cbb"></div>') +
        (cam.grid ? '<div class="slp-camgrid"><i></i><i></i><b></b><b></b></div>' : '') +
        '<div class="slp-camtop"><span>' + two(st.data.hour || 0) + ':' + two(st.data.minute || 0) + '</span><span class="slp-camflashb' + (cam.flash ? ' slp-on' : '') + '" data-a="camflash" data-v="1" role="button" aria-label="' + T('ui.cam_flash', 'Flash') + '">&#9889; ' + T('ui.cam_flash', 'Flash') + (cam.flash ? '' : ' &#215;') + '</span><span class="slp-camgridb' + (cam.grid ? ' slp-on' : '') + '" data-a="camgrid" data-v="1" role="button">&#9638; ' + T('ui.cam_grid', 'Grid') + '</span><span class="slp-camx" data-a="home" role="button" aria-label="' + T('ui.cam_close', 'Close the camera') + '">&#10005;</span></div>' +
        '<div class="slp-camright"><div class="slp-camshutter" data-a="photo" data-v="1" role="button" aria-label="' + T('ui.cam_shutter', 'Take a photo') + '"><i></i></div></div>' +
        '<div class="slp-cammodes"><b>' + T('ui.cam_mode_photo', 'PHOTO') + '</b><span>' + T('ui.cam_mode_portrait', 'PORTRAIT') + '</span><span>' + T('ui.cam_mode_pano', 'PANO') + '</span><span>' + T('ui.cam_mode_video', 'VIDEO') + '</span></div>' +
        '<div class="slp-camzoom">' + zooms.map(function (z) { return '<span class="' + (cam.zoom === z ? 'slp-on' : '') + '" data-a="camzoom" data-v="' + z + '" role="button">' + z + '&times;</span>'; }).join('') + '</div>' +
        crackHtml(st.data.crack, true) + '</div>';
    }
    function galleryPage() {
      var list = arr(obj(st.photos).photos);
      var body = list.length ? '<div class="slp-photos">' + list.map(function (p) {
        return '<div class="slp-ph' + (p.file === st.photos.phone || p.file === st.photos.laptop ? ' slp-on' : '') + '" data-a="photoopen" data-v="' + esc(p.file) + '" style="background-image:url(\'' + esc(p.file) + '\')"></div>';
      }).join('') + '</div>' : '<div class="slp-empty">' + T('ui.no_photos_yet', 'No photos yet. Take one with the Camera.') + '</div>';
      return bar(T('app.gallery', 'Gallery')) + '<div class="slp-body">' + body + '</div>';
    }
    function photoPage() {
      var f = st.photoFile || '';
      return bar(T('app.gallery', 'Gallery')) + '<div class="slp-body"><div class="slp-bigph" style="background-image:url(\'' + esc(f) + '\')"></div>' +
        '<div class="slp-acts" style="padding:0 12px 12px;display:flex;gap:8px;flex-wrap:wrap">' +
        '<div class="slp-btn" data-a="setwall" data-v="laptop|' + esc(f) + '">' + T('ui.set_as_laptop_wallpaper', 'Set as laptop wallpaper') + '</div>' +
        '<div class="slp-btn" data-a="setwall" data-v="phone|' + esc(f) + '">' + T('ui.set_as_phone_wallpaper', 'Set as phone wallpaper') + '</div>' +
        '<div class="slp-btn slp-tonal" data-a="setwall" data-v="both|">' + T('ui.usual_wallpapers', 'Back to the usual wallpapers') + '</div></div></div>';
    }

    
    // waiting: to the next morning or a few hours on (the clock, deliveries and shop hours follow); refused in a race, on a job or with the police after you
    function waitPage() {
      var h = [['switch', st.data.phaseSwitch || T('phase.startNight', 'Start the night')], ['1', T('wait.hour1', 'One hour')], ['3', T('wait.hour3', 'Three hours')], ['6', T('wait.hour6', 'Six hours')]].map(function (x) {
        return '<div class="slp-btn' + (x[0] === 'switch' ? '' : ' slp-tonal') + '" data-a="wait" data-v="' + x[0] + '">' + x[1] + '</div>';
      }).join('');
      return bar(T('app.wait', 'Wait')) + '<div class="slp-body"><div class="slp-card"><h4>' + (st.data.phase === 'night' ? T('phase.night', 'Night') : T('phase.day', 'Day')) + ' ' + (st.data.day || 1) + ', ' + two(st.data.hour || 0) + ':' + two(st.data.minute || 0) + '</h4>' +
        '<p>' + esc(T('wait.stops', 'The clock stops at the end of the {1}. Waiting never goes past it; {2} to go on. Not in a race, on a job or with the police after you.',
          st.data.phase === 'night' ? T('wait.endNight', 'night (04:00)') : T('wait.endDay', 'day (19:00)'), String(st.data.phaseSwitch || T('phase.startNight', 'Start the night')).toLowerCase())) + '</p>' +
        '<div class="slp-acts">' + h + '</div></div></div>';
    }

    // the cab's places by category (#21): garages, shops, dealers (by the price tier of their cars), junkyards
    var CAB_KINDS = { all: null, garage: ['garage'], shop: ['shop', 'parts', 'gas', 'carwash'], dealer: ['dealer'], junk: ['junkyard', 'scrapyard'], other: ['meet', 'hospital', 'valet', 'auction', 'job'] };
    var CAB_TIERS = [['all', T('ui.any', 'Any')], ['high', T('ui.high', 'High')], ['mid', T('ui.mid', 'Mid')], ['low', T('ui.low', 'Low')], ['junk', T('ui.junk', 'Junk')]];
    function cabShown(p) {
      var kinds = CAB_KINDS[st.tab.cab];
      if (kinds && kinds.indexOf(p.kind) < 0) return false;
      if (st.tab.cab === 'dealer' && st.tab.cabtier !== 'all' && p.tier !== st.tab.cabtier) return false;
      return true;
    }
    // free-roam freight runs (sl_frjobs.summary(); tools/frjobs_fixture.js): the board's offers with a Take button, the run under way with Cancel
    function frJobsPage() {
      var f = obj(st.data.frjobs), a = f.active;
      function mins(s) { return Math.max(1, Math.round((Number(s) || 0) / 60)) + ' min'; }
      function far(m) { return m < 1000 ? Math.round(m) + ' m' : (m / 1000).toFixed(1) + ' km'; }
      var act = a ? '<div class="slp-card"><h4>' + T('ui.fr_active', 'On a run') + ': ' + esc(a.title || '') + '</h4><p>' + esc(a.item || '') + '</p>' +
        '<div class="slp-kv"><span>' + (Number(a.leg) === 2 ? T('ui.fr_go_drop', 'Drop at {1}', esc(a.to || '')) : T('ui.fr_go_pickup', 'Pick up at {1}', esc(a.next || ''))) + '</span><b>' + money(a.pay) + '</b></div>' +
        '<div class="slp-acts"><div class="slp-btn slp-tonal" data-a="frcancel">' + T('ui.fr_cancel', 'Cancel the run') + '</div></div></div>' : '';
      var offers = arr(f.offers).map(function (o) {
        return '<div class="slp-card"><h4>' + esc(o.title || '') + '</h4><p>' + esc(o.item || '') + '</p>' +
          '<div class="slp-kv"><span>' + T('ui.fr_from', 'From') + '</span><b>' + esc(o.from || '') + '</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.fr_to', 'To') + '</span><b>' + esc(o.to || '') + '</b></div>' +
          '<div class="slp-kv"><span>' + far(Number(o.metres) || 0) + ' &middot; ' + mins(o.seconds) + '</span><b>' + money(o.pay) + '</b></div>' +
          (a ? '' : '<div class="slp-acts"><div class="slp-btn" data-a="frtake" data-v="' + esc(String(o.id)) + '">' + T('ui.fr_take', 'Take') + '</div></div>') + '</div>';
      }).join('');
      return bar(T('app.frjobs', 'Freight runs')) + '<div class="slp-body"><p style="padding:0 16px">' + T('ui.fr_intro', 'Take a run, pick the load up and drop it where it goes. Wrench Works pays on delivery.') + '</p>' + act +
        (offers || (a ? '' : '<div class="slp-empty">' + T('ui.fr_none', 'No runs on the board right now. Check back later.') + '</div>')) + '</div>';
    }

    function cabPage() {
      var rows = arr(st.data.places).filter(cabShown).map(function (p) {
        return '<div class="slp-row" data-a="taxi" data-v="' + esc(p.id) + '"><div class="slp-av" style="background:#ffd8a8">' + I.cab.replace('<svg', '<svg style="width:22px;height:22px;fill:#5b3d00"') + '</div>' +
          '<div class="slp-rt"><b>' + esc(p.name) + '</b><span>' + esc(MAP_KINDS[p.kind] || p.kind) + (p.tierLabel ? ' &middot; ' + esc(p.tierLabel) : '') + '</span></div><div class="slp-ib" data-a="gps" data-v="' + esc(p.id) + '">' + I.gps + '</div></div>';
      });
      return bar(T('app.cab', 'Cab')) + tabsHtml('cab', [['all', T('ui.all', 'All')], ['garage', T('ui.garages', 'Garages')], ['shop', T('ui.shops', 'Shops')], ['dealer', T('ui.dealers', 'Dealers')], ['junk', T('ui.junkyards', 'Junkyards')], ['other', T('ui.other_places', 'More')]]) +
        (st.tab.cab === 'dealer' ? tabsHtml('cabtier', CAB_TIERS) : '') +
        ('<div class="slp-body"><div class="slp-card"><p>' + T('ui.on_foot_a_cab_takes', 'On foot, a cab takes you anywhere in town. In a car, the pin shows you the way.') + '</p></div>') +
        (rows.join('') || '<div class="slp-empty">' + (st.tab.cab === 'all' ? T('ui.the_cab_company_does_not', 'The cab company does not know any places on this map yet.') : T('ui.no_such_place_here', 'No such place here.')) + '</div>') + '</div>';
    }

    // the tyres of a car (sl_tyrecare.card): a top-down car with its four tyres coloured by tread, and a line per axle
    var TYRE_COLOURS = { new: '#4caf7d', good: '#8bc34a', worn: '#f2b84b', low: '#ef7b45', bald: '#e5534b', blown: '#b04bd6' };
    function tyreWord(stage) { return T('tyres.word_' + stage, stage); }
    function tyreName(id) { return T('tyres.name_' + id, id); }
    function tyresView(t) {
      if (t && t.tracked === false) return '<div class="slp-tyres"><div class="slp-kv" style="border:none"><span style="opacity:.75">' + T('tyres.no_tyres', 'No tyres fitted') + '</span><b class="slp-on" data-a="pcatalog" data-v="1">' + T('ui.fit_tyres', 'Fit tyres') + '</b></div></div>';
      if (!t || !arr(t.rows).length) return '';
      var rows = arr(t.rows);
      var tyres = rows.map(function (w) {
        var left = w.side ? String(w.side).toLowerCase().charAt(0) === 'l' : (w.idx || 0) % 2 === 0, front = w.axle ? w.axle === 'front' : (w.idx || 0) < 2;      // (a wheel the tyre module has not described: by its number)
        var x = left ? 14 : 78, y = front ? 20 : 92, col = TYRE_COLOURS[w.stage] || '#888';
        var pct = Math.round((w.frac || 0) * 100);
        return '<rect x="' + x + '" y="' + y + '" width="18" height="40" rx="5" fill="' + col + '"' + (w.blown ? ' stroke="#fff" stroke-dasharray="3 2"' : '') + '/>' +
          '<text x="' + (x + 9) + '" y="' + (y + 24) + '" font-size="9" text-anchor="middle" fill="#111" font-weight="600">' + (w.blown ? '&times;' : pct + '%') + '</text>' +
          (w.flat ? '<circle cx="' + (x + 9) + '" cy="' + (y + 6) + '" r="3" fill="#fff"/>' : '');
      }).join('');
      var svg = '<svg class="slp-tyrecar" viewBox="0 0 110 152" width="96" height="132"><rect x="32" y="10" width="46" height="132" rx="16" fill="#2a2830" stroke="#555"/>' +
        '<rect x="38" y="26" width="34" height="28" rx="6" fill="#3a3844"/><rect x="38" y="90" width="34" height="34" rx="6" fill="#3a3844"/>' + tyres + '</svg>';
      var axles = arr(t.axles).map(function (a) {
        return '<div class="slp-kv"><span>' + T('tyres.axle_' + a.axle, String(a.axle).charAt(0).toUpperCase() + String(a.axle).slice(1)) + '</span><b' + (a.replace ? ' class="slp-warn"' : '') + '>' + (a.replace ? '&#9888; ' : '') + esc(tyreName(a.compound)) +
          ' &middot; ' + T('ui.tyre_tread_pct', '{1}% tread', Math.round((a.frac || 0) * 100)) + ' &middot; ' + esc(tyreWord(a.stage)) + (a.flat ? ' &middot; ' + T('ui.tyre_flat_spot', 'flat spot') : '') + '</b></div>';
      }).join('');
      return '<div class="slp-tyres"><div class="slp-tyrehead">' + T('ui.tyres_title', 'Tyres') + '</div><div class="slp-tyrebox">' + svg + '<div class="slp-tyreaxles">' + axles + '</div></div></div>';
    }
    function tyreSwapCard(c) {
      if (!(c.seated && c.tyres && arr(c.tyres.offers).length)) return '';
      return c.tyres.swapAt ? tyreSwapView(c) : '<div class="slp-kv" style="border:none"><span>' + T('ui.tyre_changes_where', 'Tyre changes: at a garage or a track') + '</span></div>';
    }
    // the Swap tyres panel at a meet: what each set costs here, refused by the game side while the car moves
    function tyreSwapView(car) {
      car = car || arr(st.data.fleet).filter(function (c) { return c.seated && c.tyres && arr(c.tyres.offers).length; })[0];
      if (!car) return '';
      var offers = arr(car.tyres.offers).filter(function (o) { return !o.current; }).map(function (o) {
        return '<div class="slp-btn slp-stack slp-tonal" data-a="tyreswap" data-v="' + esc(o.id) + '"><span class="slp-lbl">' + esc(tyreName(o.id)) + '</span><small>' + money(o.price) + '</small></div>';
      }).join('');
      return '<div class="slp-card" style="margin:6px 0 4px 0"><h4>' + T('ui.swap_tyres', 'Swap tyres') + '</h4><p>' + T('ui.swap_tyres_text', 'The crew changes the set where you stand. The car must be stopped.') + '</p>' +
        '<div class="slp-acts" style="flex-wrap:wrap">' + offers + '</div></div>';
    }

    // a car's service card (sl_service.serviceOf: { due, km_since, km_interval, wearFactor, count, sections = { { id, label, condition } }, options = { { id, label, cost, available, why } } });
    // nothing when the part is off or the game sent none
    function serviceCard(c) {
      var sv = c.service;
      if (!sv || obj(st.data.has).service === false) return '';
      var secs = arr(sv.sections).map(function (x) {
        var v = Math.max(0, Math.min(1, Number(x.condition) || 0));
        return '<div class="slp-kv"><span>' + esc(x.label || x.id || '') + '</span><b' + (v < 0.4 ? ' class="slp-warn"' : '') + '>' + (v < 0.4 ? '&#9888; ' : '') + Math.round(v * 100) + '%</b></div>';
      }).join('');
      var opts = arr(sv.options).map(function (o) {
        var ok = o.available !== false;
        return '<div class="slp-btn slp-stack slp-tonal' + (ok ? '' : ' slp-off') + '"' + (ok ? ' data-a="service" data-v="' + c.id + '|' + esc(o.id) + '"' : '') + '><span class="slp-lbl">' + esc(o.label || o.id) + '</span><small>' + money(o.cost) + (o.why ? ' &middot; ' + esc(o.why) : '') + '</small></div>';
      }).join('');
      var factor = Number(sv.wearFactor) || 1;
      return '<div class="slp-card" style="margin:6px 0 4px 0"><h4>' + (sv.due ? '&#9888; ' + T('ui.service_due', 'Service due') : T('ui.service', 'Service')) + '</h4><p>' +
        T('ui.service_km', '{1} km since the last service (every {2} km)', Math.round(Number(sv.km_since) || 0), Math.round(Number(sv.km_interval) || 0)) +
        (factor > 1.001 ? ' &middot; ' + T('ui.service_wear_faster', 'parts wear {1} times as fast until it is serviced', factor.toFixed(1)) : '') + '</p>' + secs +
        (opts ? '<div class="slp-acts" style="flex-wrap:wrap">' + opts + '</div>' : '') + '</div>';
    }

    // a car's health, its trunk (use what is in it) and its history
    var ITEM_NAMES = { fuelCan: T('ui.fuel_can', 'Fuel can'), oil: T('ui.engine_oil', 'Engine oil'), coolant: T('ui.coolant', 'Coolant'), battery: T('ui.12_v_battery', '12 V battery') };
    function careView(c) {
      var k = c.care;
      if (!k) return '';
      var pct = function (v) { return v == null ? '-' : Math.round(v * 100) + '%'; };
      var warn = function (v, low) { return v != null && v < low ? ' class="slp-warn"' : ''; };
      var mark = function (v, low) { return v != null && v < low ? '&#9888; ' : ''; };      // (#51: a mark as well as a colour)
      var rows = ('<div class="slp-kv"><span>' + T('ui.battery', 'Battery') + '</span><b') + warn(k.battery, 0.3) + '>' + mark(k.battery, 0.3) + pct(k.battery) + '</b></div>' +
        ('<div class="slp-kv"><span>' + T('ui.oil', 'Oil') + '</span><b') + warn(k.oilLevel, 0.5) + '>' + mark(k.oilLevel, 0.5) + pct(k.oilLevel) + ' &middot; ' + (k.oilKm || 0).toLocaleString() + (T('ui.km_old', ' km old') + '</b></div>') +
        ('<div class="slp-kv"><span>' + T('ui.coolant', 'Coolant') + '</span><b') + warn(k.coolantLevel, 0.5) + '>' + mark(k.coolantLevel, 0.5) + pct(k.coolantLevel) + '</b></div>' +
        ('<div class="slp-kv"><span>' + T('ui.fuel', 'Fuel') + '</span><b>') + pct(k.fuelLevel) + ' &middot; ' + esc(k.fuel) + '</b></div>' +
        (k.n2o != null ? ('<div class="slp-kv"><span>' + T('ui.nitrous', 'Nitrous') + '</span><b>') + pct(k.n2o) + '</b></div>' : '') +
        ('<div class="slp-kv"><span>' + T('ui.engine', 'Engine') + '</span><b>') + (k.engineKm || 0).toLocaleString() + ' km &middot; ' + Math.round((k.performance || 1) * 100) + (T('ui.power_2', '% power') + '</b></div>');
      var counts = {};
      arr(k.trunk).forEach(function (i) { counts[i] = (counts[i] || 0) + 1; });
      var trunk = Object.keys(counts).map(function (i) {
        return '<div class="slp-kv slp-hudrow" data-a="useitem" data-v="' + c.id + '|' + i + '"><span>' + esc(ITEM_NAMES[i] || i) + ' &times;' + counts[i] + ('</span><b class="slp-on">' + T('ui.use', 'Use') + '</b></div>');
      }).join('');
      var h = k.history || {};
      var hist = ('<div class="slp-kv" style="border:none"><span>' + T('ui.history', 'History') + '</span><b>') + (h.owners || 0) + T('ui.owners_before_you_middot', ' owners before you &middot; ') + (h.wins || 0) + '/' + (h.races || 0) + T('ui.races_won', ' races won') +
        (h.wrecks ? T('ui.middot_wrecked_1_times', ' &middot; wrecked {1}&times;', h.wrecks) : '') + '</b></div>';
      return '<div class="slp-carcare">' + rows + tyresView(c.tyres) + tyreSwapCard(c) + (trunk ? ('<div class="slp-trunk">' + T('ui.trunk', 'Trunk') + '</div>') + trunk : '') + hist + serviceCard(c) + reportBlock('car:' + c.id, c.report) + '</div>';
    }

    function garagePage() {
      var ordered = arr(st.data.onOrder).map(function (o) {
        return '<div class="slp-card"><h4>' + esc(o.name) + '</h4><p>' + (o.hours != null
          ? T('ui.arriving_at_in_about', 'Arriving at {1} in about {2} h', esc(st.data.garage || ''), o.hours)
          : T('ui.on_order_1_arrives_day', 'On order: {1}, {2} &middot; arrives day {3} {4}:00', esc(o.name), esc(o.dealer || ''), o.day, two(o.hour))) + '</p></div>';
      });
      var cars = arr(st.data.fleet);
      var cards = cars.map(function (c) {
        var faults = arr(c.faults);
        var acts = [];
        if (c.impounded) acts.push('<div class="slp-btn" data-a="release" data-v="' + c.id + ('">' + T('ui.get_it_out_of_the', 'Get it out of the impound ') + '&middot;' + ' ') + money(c.impounded) + '</div>');
        else if (!c.seated) acts.push('<div class="slp-btn" data-a="usecar" data-v="' + c.id + ('">' + T('ui.drive_this_one', 'Drive this one') + '</div>'));
        if (c.out && c.towFee && c.where === 'Out on the street') acts.push('<div class="slp-btn slp-tonal" data-a="tow" data-v="' + c.id + ('">' + T('ui.tow_it_home', 'Tow it home ') + '&middot;' + ' ') + money(c.towFee) + '</div>');
        if (c.out && !c.impounded) acts.push('<div class="slp-btn slp-text" data-a="despawn" data-v="' + c.id + ('">' + T('ui.put_it_away', 'Put it away') + '</div>'));
        return '<div class="slp-card"><h4>' + esc(c.name) + (c.active ? ' &#9733;' : '') + '</h4><p>' + esc(c.where) + ' &middot; condition ' + Math.round((c.condition || 0) * 100) + '%' + (c.look ? ' &middot; ' + esc(c.look) : '') + (c.mastery && c.mastery.level > 0 ? ' &middot; <b>' + esc(c.mastery.label) + ' ' + c.mastery.level + '/' + c.mastery.max + '</b>' + (c.mastery.perks.length ? ' (' + esc(c.mastery.perks.join(' ')) + ')' : '') : '') +
          (faults.length ? ('<br>' + T('ui.needs_2', 'Needs: ')) + esc(faults.join(', ')) : '') + '</p>' + careView(c) + (acts.length ? '<div class="slp-acts">' + acts.join('') + '</div>' : '') + '</div>';
      });
      return bar(T('app.garage', 'My cars')) + '<div class="slp-body">' + (cards.join('') + ordered.join('') ||
        ('<div class="slp-empty">' + T('ui.you_have_no_car_the', 'You have no car. The junkyard sells cheap ones that need work, the dealership new ones. The Cab app gets you there.') + '</div>')) + '</div>';
    }

    // the Garage app: the garage itself (its kit, where it is), not the cars (that is My cars)
    function garageKitPage() {
      var d = st.data;
      // the garage's own kit (X58): what it has, and what can be put in
      var ups = arr(d.upgrades).map(function (u) {
        return '<div class="slp-kv"><span>' + esc(u.name) + '<br><small>' + esc(u.desc) + '</small></span><b>' +
          (u.has ? T('fleet.in_the_garage', 'In the garage') : '<div class="slp-btn slp-tonal" data-a="upgrade" data-v="' + esc(u.id) + '">' + money(u.price) + '</div>') + '</b></div>';
      }).join('');
      return bar(T('app.garagekit', 'Garage')) + '<div class="slp-body">' +
        '<div class="slp-card"><h4>' + esc(d.garage || T('ui.the_garage', 'The garage')) + '</h4><div class="slp-acts"><div class="slp-btn" data-a="routegarage" data-v="1">' + T('ui.route_to_my_garage', 'Route to my garage') + '</div></div></div>' +
        (ups ? ('<div class="slp-card"><h4>' + T('ui.the_garage', 'The garage') + '</h4>') + ups + '</div>' : '<div class="slp-empty">' + T('ui.no_garage_upgrades', 'No garage upgrades to buy here.') + '</div>') + '</div>';
    }


    // the named rivals (sl_rivals): six cards with the crew, the car, the rivalry meter and your record against them
    function rivalCards() {
      var rv = obj(st.rivals), list = arr(rv.rivals);
      if (!list.length) return '';
      var words = { blood: T('rivals.meter_blood', 'Bad blood'), rivals: T('rivals.meter_rivals', 'Rivalry'), neutral: T('rivals.meter_neutral', 'Neutral'), respect: T('rivals.meter_respect', 'Respect'), friends: T('rivals.meter_friends', 'Friends') };
      return '<h4>' + T('rivals.title', 'Rivals') + '</h4>' + list.map(function (r) {
        var tag = r.boss ? ' &middot; ' + T('rivals.boss_star', 'Boss') + ' ' + r.tier : (r.nemesis ? ' &middot; ' + T('rivals.nemesis', 'Nemesis') : '');
        return '<div class="slp-card"' + (r.locked ? ' style="opacity:.75"' : '') + '><h4>' + (r.boss ? '&#9733; ' : '') + esc(r.name) + tag + '</h4>' +
          '<p>' + esc(r.crew || '') + (r.car ? ' &middot; ' + esc(r.car) : '') + '</p>' +
          '<div class="slp-meter"><i style="width:' + Math.round(((r.meter || 0) + 100) / 2) + '%"></i></div>' +
          '<p>' + words[r.word] + ' &middot; ' + T('ui.rival_record', 'Won {1}, lost {2}', r.beaten || 0, r.youLost || 0) + (r.locked ? ' &middot; ' + T('ui.rival_locked', 'Beat {1} to move up', esc(r.locked)) : '') + '</p>' +
        (r.offer ? '<p class="slp-warn">' + T('ui.rival_offer', 'Pink slip offer: your {1} against their {2}', esc(r.offer.myCar || '?'), esc(r.offer.theirCar || '?')) + '</p><div class="slp-acts">' +
          '<div class="slp-btn slp-pinkbtn" data-a="rvyes" data-v="' + esc(r.id) + '">' + T('ui.rival_accept', 'Accept the pink slips') + '</div>' +
          '<div class="slp-btn slp-tonal" data-a="rvmoney" data-v="' + esc(r.id) + '">' + T('ui.rival_money', 'Race for money instead') + '</div>' +
          '<div class="slp-btn slp-text" data-a="rvno" data-v="' + esc(r.id) + '">' + T('ui.rival_walk', 'Walk away') + '</div></div>' : '') +
          '</div>';
      }).join('');
    }

    // tier perks (sl_perks.perks(): { tier, list = { { id, label, text, unlocked, tier } } }): what each rank has opened, the next ones dimmed; nothing when the part is off
    function perksCard() {
      var pk = st.data.perks;
      if (!pk || obj(st.data.has).perks === false || !arr(pk.list).length) return '';
      return '<div class="slp-card"><h4>' + T('ui.tier_perks', 'Tier perks') + '</h4>' + arr(pk.list).map(function (x) {
        return '<div class="slp-kv"' + (x.unlocked ? '' : ' style="opacity:.6"') + '><span>' + esc(x.label || '') + '<br><small>' + esc(x.text || '') + '</small></span><b' + (x.unlocked ? ' class="slp-on"' : '') + '>' +
          (x.unlocked ? '&#10004; ' + T('ui.perk_open', 'Open') : T('ui.perk_rank', 'Rank {1}', Number(x.tier) || 0)) + '</b></div>';
      }).join('') + '</div>';
    }

    // the needs part (sl_needs.summary(): { meters = { { id: food|water|rest, value 0..100, stage: ok|nudge|handicap|problem, word } }, wellFed, effects = { blur, lag, tremor, sleepy },
    // items = { { id, name, price } }, canEat, canNap, showMeters }): the stage is a mark as well as a colour (never colour alone)
    var NEED_LABEL = { food: T('ui.need_food', 'Food'), water: T('ui.need_water', 'Water'), rest: T('ui.need_rest', 'Rest') };
    var NEED_WORDS = { fed: T('ui.need_fed', 'fed'), peckish: T('ui.need_peckish', 'peckish'), hungry: T('ui.need_hungry', 'hungry'), starving: T('ui.need_starving', 'starving'),
      fine: T('ui.need_fine', 'fine'), thirsty: T('ui.need_thirsty', 'thirsty'), parched: T('ui.need_parched', 'parched'), dehydrated: T('ui.need_dehydrated', 'dehydrated'),
      rested: T('ui.need_rested', 'rested'), yawning: T('ui.need_yawning', 'yawning'), tired: T('ui.need_tired', 'tired'), exhausted: T('ui.need_exhausted', 'exhausted') };
    var STAGE_MARK = { ok: '', nudge: '&middot; ', handicap: '&#9888; ', problem: '&#9660; ' };
    var STAGE_COLOUR = { ok: '#6dd58c', nudge: '#a8c7fa', handicap: '#ffd54f', problem: '#f2b8b5' };
    function needMeters() { var n = st.data.needs; return n && obj(st.data.has).needs !== false ? arr(n.meters) : []; }
    function healthPage() {
      var n = obj(st.data.needs), ef = obj(n.effects);
      var bars = arr(n.meters).map(function (m) {
        var stage = STAGE_MARK[m.stage] !== undefined ? m.stage : 'ok', v = Math.max(0, Math.min(100, Math.round(Number(m.value) || 0)));
        return '<div class="slp-kv" style="display:block;padding:8px 0"><div style="display:flex;align-items:center;gap:10px"><span style="width:22px;height:22px;display:block">' + (I[m.id] || '') + '</span><b style="flex:1">' + esc(NEED_LABEL[m.id] || m.id) + '</b>' +
          '<span style="color:' + STAGE_COLOUR[stage] + '">' + STAGE_MARK[stage] + esc(NEED_WORDS[m.word] || m.word || '') + ' &middot; ' + v + '</span></div>' +
          '<div class="slp-meter"><i style="width:' + v + '%;background:' + STAGE_COLOUR[stage] + '"></i></div></div>';
      }).join('');
      var fx = [];
      if (Number(ef.blur) > 0.02) fx.push(T('ui.need_fx_blur', 'blurred sight'));
      if (Number(ef.lag) > 0.005) fx.push(T('ui.need_fx_lag', 'slow reactions'));
      if (Number(ef.tremor) > 0.02) fx.push(T('ui.need_fx_tremor', 'shaky hands'));
      if (ef.sleepy) fx.push(T('ui.need_fx_sleepy', 'heavy eyelids'));
      var eat = n.canEat ? '<div class="slp-acts" style="flex-wrap:wrap">' + arr(n.items).map(function (it) {
        return '<div class="slp-btn slp-stack slp-tonal" data-a="eat" data-v="' + esc(it.id) + '"><span class="slp-lbl">' + esc(it.name) + '</span><small>' + money(it.price) + '</small></div>';
      }).join('') + '</div>' : '<p>' + T('ui.need_eat_where', 'Food and drink are sold at fuel stations.') + '</p>';
      var nap = n.canNap ? '<div class="slp-acts">' + [1, 3, 6].map(function (h) {
        return '<div class="slp-btn slp-tonal" data-a="nap" data-v="' + h + '">' + T('ui.need_nap_hours', 'Nap {1} h', h) + '</div>';
      }).join('') + '</div>' : '<p>' + T('ui.need_nap_where', 'You can nap at a garage.') + '</p>';
      return bar(T('app.health', 'Health')) + '<div class="slp-body"><div class="slp-card"><h4>' + T('ui.need_you', 'You') + (n.wellFed ? ' &middot; <span style="color:#6dd58c">&#10004; ' + T('ui.need_well_fed', 'well fed') + '</span>' : '') + '</h4>' + bars +
        (fx.length ? '<p class="slp-warn">&#9888; ' + T('ui.need_affecting', 'Affecting you now: {1}', fx.join(', ')) + '</p>' : '') + '</div>' +
        '<div class="slp-card"><h4>' + T('ui.need_eat', 'Eat and drink') + '</h4>' + eat + '</div><div class="slp-card"><h4>' + T('ui.need_nap', 'Sleep') + '</h4>' + nap + '</div></div>';
    }
    // the small icons of the pill: a meter under 40, or all three when the player asked for them (showMeters)
    function needsPill() {
      var n = st.data.needs;
      if (!n) return '';
      return needMeters().filter(function (m) { return n.showMeters || Number(m.value) < 40; }).map(function (m) {
        var stage = STAGE_MARK[m.stage] !== undefined ? m.stage : 'ok';
        return '<span style="display:inline-flex;align-items:center;gap:3px;color:' + STAGE_COLOUR[stage] + '"><span style="width:14px;height:14px;display:block">' + (I[m.id] || '') + '</span>' + (stage === 'problem' ? '&#9660;' : stage === 'handicap' ? '&#9888;' : '') + '</span>';
      }).join('');
    }

    // the inventory (sl_inventory.summary(): { used, cap, groups = { { kind: item|can|tool|part, name, count, points, extra = { id|index, litres, size, uses, brand, wear } } } })
    function inventoryPage() {
      var iv = obj(st.data.inventory), groups = arr(iv.groups), used = Number(iv.used) || 0, cap = Number(iv.cap) || 0;
      var pct = cap ? Math.min(100, Math.round(100 * used / cap)) : 0;
      var head = '<div class="slp-card"><h4>' + T('ui.inv_boot', 'Boot') + '</h4><div class="slp-kv"><span>' + T('ui.inv_points', 'carry points') + '</span><b>' + used + ' / ' + cap + '</b></div>' +
        '<div class="slp-meter"><i style="width:' + pct + '%"></i></div><p>' + T('ui.inv_intro', 'Car parts you buy wait here until you drive into your garage; oil, coolant, a battery, cans and tools stay until you use them.') + '</p></div>';
      var rows = groups.map(function (g) {
        var x = obj(g.extra), detail = '';
        if (g.kind === 'can') detail = T('ui.inv_litres', '{1} of {2} L', Math.round(Number(x.litres) || 0), Number(x.size) || 0);
        else if (g.kind === 'tool') detail = x.uses != null ? T('ui.inv_uses', '{1} uses left', Number(x.uses)) : '';
        else if (g.kind === 'part') detail = (x.brand ? esc(x.brand) : '') + (Number(x.wear) > 0 ? (x.brand ? ' &middot; ' : '') + T('ui.inv_wear', '{1} % worn', Math.round(100 * Number(x.wear))) : '');
        var key = g.kind === 'can' ? Number(x.index) : (x.id != null ? x.id : '');
        var canUse = g.kind === 'item' && (x.id === 'oil' || x.id === 'coolant' || x.id === 'battery');
        var canDrop = g.kind !== 'part';
        var did = g.kind + ':' + key;
        return '<div class="slp-row" style="min-height:48px;cursor:default"><div class="slp-rt"><b>' + esc(g.name || '') + (Number(g.count) > 1 ? ' &times;' + Number(g.count) : '') + '</b><small>' +
          T('ui.inv_points_n', '{1} pts', Number(g.points) || 0) + (detail ? ' &middot; ' + detail : '') + '</small></div><div class="slp-acts">' +
          (canUse ? '<div class="slp-btn slp-text" data-a="invuse" data-v="' + esc(String(x.id)) + '">' + T('ui.inv_use', 'Use') + '</div>' : '') +
          (canDrop ? '<div class="slp-btn slp-text" data-a="invdrop" data-v="' + esc(did) + '">' + (st.invDrop === did ? T('ui.inv_drop_sure', 'Sure? Drop') : T('ui.inv_drop', 'Drop')) + '</div>' : '') + '</div></div>';
      }).join('');
      return bar(T('app.inventory', 'Inventory')) + '<div class="slp-body">' + head + (rows || '<div class="slp-empty">' + T('ui.inv_empty', 'Nothing in the boot.') + '</div>') + '</div>';
    }

    // my routes (sl_myroute.summary(): { routes = { { id, name, points, length (m), best (s, 0 = never), bestText, runs, last, lastText } }, draft (points dropped), draftMin, draftMax, maxRoutes,
    // run = { id, name, next, points, started, t, clock } or nil })
    function myroutePage() {
      var m = obj(st.data.myroute), run = m.run, routes = arr(m.routes);
      var km = function (len) { return Number(len) >= 1000 ? (len / 1000).toFixed(1) + ' km' : Math.round(len) + ' m'; };
      var runCard = run ? '<div class="slp-card"><h4>' + T('ui.myroute_racing', 'Racing {1}: waypoint {2} of {3}', esc(run.name || ''), Math.min(Number(run.next) || 1, Number(run.points) || 1), Number(run.points) || 0) + '</h4>' +
        '<div class="slp-kv"><span>' + (run.started ? T('ui.myroute_best', 'Best') : '') + '</span><b>' + (run.started ? esc(run.clock || '') : T('ui.myroute_to_start', 'Drive to the start of {1}', esc(run.name || ''))) + '</b></div>' +
        '<div class="slp-btn slp-text" data-a="routestop" data-v="1">' + T('ui.myroute_stop', 'Stop') + '</div></div>' : '';
      var draft = Number(m.draft) || 0;
      var editor = run ? '' : '<div class="slp-card"><p>' + T('ui.myroute_intro', 'Drive to a place and drop a waypoint. Four to eight, then save: you race the route against the clock, and the best time is kept.') + '</p>' +
        '<div class="slp-kv"><span>' + T('ui.myroute_dropped', 'Waypoints dropped: {1} of {2}', draft, Number(m.draftMax) || 8) + '</span></div>' +
        '<div class="slp-acts"><div class="slp-btn slp-text" data-a="routedrop" data-v="1">' + T('ui.myroute_drop', 'Drop waypoint here') + '</div>' +
        (draft ? '<div class="slp-btn slp-text" data-a="routeundo" data-v="1">' + T('ui.myroute_undo', 'Undo') + '</div><div class="slp-btn slp-text" data-a="routediscard" data-v="1">' + T('ui.myroute_discard', 'Discard') + '</div>' : '') + '</div>' +
        (draft >= (Number(m.draftMin) || 4) ? '<div class="slp-acts"><input class="slp-routename" placeholder="' + T('ui.myroute_name', 'Name') + '" maxlength="24"><div class="slp-btn slp-text" data-a="routesave" data-v="1">' + T('ui.myroute_save', 'Save route') + '</div></div>' : '') + '</div>';
      var cards = routes.map(function (r) {
        return '<div class="slp-card"><h4>' + esc(r.name || '') + '</h4>' +
          '<div class="slp-kv"><span>' + T('ui.myroute_length', 'Length') + '</span><b>' + km(r.length) + ' &middot; ' + (Number(r.points) || 0) + '</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.myroute_best', 'Best') + '</span><b>' + esc(r.bestText || '--') + '</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.myroute_last', 'Last') + '</span><b>' + esc(r.lastText || '--') + '</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.myroute_runs', 'Runs') + '</span><b>' + (Number(r.runs) || 0) + '</b></div>' +
          '<div class="slp-acts">' + (run ? '' : '<div class="slp-btn slp-text" data-a="routerace" data-v="' + Number(r.id) + '">' + T('ui.myroute_race', 'Race it') + '</div>') +
          '<div class="slp-btn slp-text" data-a="routedel" data-v="' + Number(r.id) + '">' + (st.routeDel === Number(r.id) ? T('ui.myroute_sure', 'Sure? Delete') : T('ui.myroute_delete', 'Delete')) + '</div></div></div>';
      }).join('');
      return bar(T('app.myroute', 'My routes')) + '<div class="slp-body">' + runCard + editor + (cards || '<div class="slp-empty">' + T('ui.myroute_none', 'No routes on this map yet.') + '</div>') + '</div>';
    }

    // the speed traps and zones (sl_traps.summary(): { list = { { id, name, kind: trap|zone, target km/h, best km/h (0 = never), count, paid, metres, pay } } }): nearest first
    function trapsPage() {
      var tr = obj(st.data.traps), dg = obj(st.data.danger), hasTraps = st.data.traps && obj(st.data.has).traps !== false, hasDanger = st.data.danger && obj(st.data.has).danger !== false;
      var byDistance = function (a, b) { return (a.metres == null ? 1e9 : a.metres) - (b.metres == null ? 1e9 : b.metres); };
      var away = function (t) { return t.metres != null ? '<p>' + T('ui.trap_away', '{1} away', Number(t.metres) >= 1000 ? (t.metres / 1000).toFixed(1) + ' km' : Math.round(t.metres) + ' m') + '</p>' : ''; };
      var cards = (hasTraps ? arr(tr.list) : []).slice().sort(byDistance).map(function (t) {
        var met = Number(t.best) >= Number(t.target);
        return '<div class="slp-card"><h4>' + esc(t.name || '') + ' <span class="slp-chip" style="margin:0 0 0 6px">' + (t.kind === 'zone' ? T('ui.trap_zone', 'Zone') : T('ui.trap_trap', 'Trap')) + '</span></h4>' +
          '<div class="slp-kv"><span>' + T('ui.trap_target', 'Target') + '</span><b>' + Math.round(Number(t.target) || 0) + ' km/h</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.trap_best', 'Your best') + '</span><b' + (met ? ' class="slp-on"' : '') + '>' + (Number(t.best) > 0 ? (met ? '&#10004; ' : '') + Math.round(t.best) + ' km/h' : '&ndash;') + '</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.trap_times', 'Times passed') + '</span><b>' + (Number(t.count) || 0) + '</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.trap_reward', 'Reward') + '</span><b>' + (t.paid ? '&#10004; ' + T('ui.trap_paid', 'Paid') : money(t.pay)) + '</b></div>' + away(t) + '</div>';
      }).join('');
      // the danger zones (sl_danger.summary(): { drift = { { id, name, target (points), best, count, paid, metres, pay } }, jump = { best (m), count, next (m or nil), prize } })
      var jump = hasDanger ? obj(dg.jump) : null;
      var jumpCard = jump ? '<div class="slp-card"><h4>' + T('ui.danger_jumps', 'Jumps') + '</h4>' +
        '<div class="slp-kv"><span>' + T('ui.danger_jump_best', 'Longest jump') + '</span><b>' + (Number(jump.best) > 0 ? Math.round(jump.best) + ' m' : '&ndash;') + '</b></div>' +
        '<div class="slp-kv"><span>' + T('ui.danger_jumps_count', 'Jumps') + '</span><b>' + (Number(jump.count) || 0) + '</b></div>' +
        '<p>' + (jump.next != null ? T('ui.danger_jump_next', 'Next prize {1} at {2} m', money(jump.prize), Math.round(jump.next)) : '&#10004; ' + T('ui.danger_jump_done', 'Every prize is paid')) + '</p></div>' : '';
      var drift = (hasDanger ? arr(dg.drift) : []).slice().sort(byDistance).map(function (z) {
        var met = Number(z.best) >= Number(z.target);
        return '<div class="slp-card"><h4>' + esc(z.name || '') + ' <span class="slp-chip" style="margin:0 0 0 6px">' + T('ui.danger_drift', 'Drift') + '</span></h4>' +
          '<div class="slp-kv"><span>' + T('ui.danger_target', 'Target') + '</span><b>' + Math.round(Number(z.target) || 0) + ' ' + T('ui.danger_points', 'points') + '</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.trap_best', 'Your best') + '</span><b' + (met ? ' class="slp-on"' : '') + '>' + (Number(z.best) > 0 ? (met ? '&#10004; ' : '') + Math.round(z.best) : '&ndash;') + '</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.trap_reward', 'Reward') + '</span><b>' + (z.paid ? '&#10004; ' + T('ui.trap_paid', 'Paid') : money(z.pay)) + '</b></div>' + away(z) + '</div>';
      }).join('');
      var title = hasDanger && !hasTraps ? T('ui.danger_title', 'Danger zones') : T('app.traps', 'Speed traps');
      return bar(title) + '<div class="slp-body">' + (hasTraps ? '<div class="slp-card"><p>' + T('ui.trap_intro', 'Drive through a trap faster than its target to be paid, once. A zone pays for holding the speed through it.') + '</p></div>' + (cards || '<div class="slp-empty">' + T('ui.trap_none', 'No traps on this map yet.') + '</div>') : '') +
        (hasDanger ? '<div class="slp-card"><h4>' + T('ui.danger_title', 'Danger zones') + '</h4><p>' + T('ui.danger_intro', 'A jump ladder and drift zones: each prize is paid once.') + '</p></div>' + jumpCard + drift : '') + '</div>';
    }

    // brand sponsorships (sl_sponsor.summary(): { current = { brand, name, kind: maker|aftermarket, since, retainer, discount, terms = { wins, car }, weekWins, carRaces, strikes 0..2, daysToReview },
    // offer = { brand, name, retainer, discount, terms = { wins, car }, expiresIn }, standing = { { brand, name, kind, standing, nextAt } } }): the offer on top, the deal, the standing bars
    function sponsorTerms(t, wins, carRaces) {
      t = obj(t);
      var out = [T('ui.spn_term_wins', 'Win {1} races a week', Number(t.wins) || 0) + (wins != null ? ' (' + T('ui.spn_progress', '{1} of {2}', Number(wins) || 0, Number(t.wins) || 0) + ')' : '')];
      if (t.car) out.push(T('ui.spn_term_car', 'Race in a car with their parts') + (carRaces != null ? ' (' + (Number(carRaces) || 0) + ')' : ''));
      return out;
    }
    function sponsorsPage() {
      var sp = obj(st.data.sponsors), cur = sp.current, off = sp.offer;
      var offerCard = off ? '<div class="slp-card"><h4>&#9993; ' + T('ui.spn_offer', 'Offer: {1}', esc(off.name || off.brand || '')) + '</h4>' +
        '<div class="slp-kv"><span>' + T('ui.spn_retainer', 'Retainer') + '</span><b>' + money(off.retainer) + ' ' + T('ui.spn_a_week', 'a week') + '</b></div>' +
        '<div class="slp-kv"><span>' + T('ui.spn_discount', 'Discount') + '</span><b>' + Math.round((Number(off.discount) || 0) * 100) + ' %</b></div>' +
        sponsorTerms(off.terms).map(function (x) { return '<p>' + esc(x) + '</p>'; }).join('') +
        (off.expiresIn != null ? '<p class="slp-warn">' + T('ui.spn_expires', 'Expires in {1} d', Number(off.expiresIn) || 0) + '</p>' : '') +
        '<div class="slp-acts"><div class="slp-btn" data-a="spnaccept" data-v="1">' + T('ui.spn_accept', 'Accept') + '</div><div class="slp-btn slp-text" data-a="spndecline" data-v="1">' + T('ui.spn_decline', 'Decline') + '</div></div></div>' : '';
      var strikes = cur ? Math.max(0, Math.min(2, Number(cur.strikes) || 0)) : 0;
      var curCard = cur ? '<div class="slp-card"><h4>' + esc(cur.name || cur.brand || '') + ' <span class="slp-chip" style="margin:0 0 0 6px">' + (cur.kind === 'aftermarket' ? T('ui.spn_aftermarket', 'Aftermarket') : T('ui.spn_maker', 'Maker')) + '</span></h4>' +
        '<div class="slp-kv"><span>' + T('ui.spn_retainer', 'Retainer') + '</span><b>' + money(cur.retainer) + ' ' + T('ui.spn_a_week', 'a week') + '</b></div>' +
        '<div class="slp-kv"><span>' + T('ui.spn_discount', 'Discount') + '</span><b>' + Math.round((Number(cur.discount) || 0) * 100) + ' %</b></div>' +
        sponsorTerms(cur.terms, cur.weekWins, cur.carRaces).map(function (x) { return '<p>' + esc(x) + '</p>'; }).join('') +
        '<div class="slp-kv"><span>' + T('ui.spn_strikes', 'Strikes') + '</span><b' + (strikes ? ' class="slp-warn"' : '') + '>' + (strikes ? '&#9888; ' : '&#10004; ') + strikes + ' / 2</b></div>' +
        (cur.daysToReview != null ? '<p>' + T('ui.spn_review', 'Review in {1} d', Number(cur.daysToReview) || 0) + '</p>' : '') +
        (st.spnQuit ? '<p class="slp-warn">' + T('ui.spn_quit_sure', 'Leave {1}? You will not get the old sponsor back; new offers come when brands know you.', esc(cur.name || cur.brand || '')) + '</p>' : '') +
        '<div class="slp-acts"><div class="slp-btn slp-text" data-a="spnquit" data-v="1">' + (st.spnQuit ? T('ui.spn_quit_yes', 'Yes, leave') : T('ui.spn_quit', 'Leave this deal')) + '</div>' +
        (st.spnQuit ? '<div class="slp-btn slp-text" data-a="spnquit" data-v="0">' + T('ui.cancel', 'Cancel') + '</div>' : '') + '</div></div>'
        : (off ? '' : '<div class="slp-empty">' + T('ui.spn_none', 'No sponsor yet. Win races and brands notice you.') + '</div>');
      var standing = arr(sp.standing).map(function (b) {
        var v = Math.max(0, Math.min(100, Math.round(Number(b.standing) || 0))), at = Number(b.nextAt) || 100;
        return '<div class="slp-kv" style="display:block;padding:8px 0"><div style="display:flex;justify-content:space-between"><b>' + esc(b.name || b.brand || '') + '</b><span>' + v + ' / ' + at + '</span></div>' +
          '<div class="slp-meter"><i style="width:' + Math.round(v / at * 100) + '%"></i></div></div>';
      }).join('');
      return bar(T('app.sponsors', 'Sponsors')) + '<div class="slp-body">' + offerCard + curCard +
        (standing ? '<div class="slp-card"><h4>' + T('ui.spn_standing', 'Brands that know you') + '</h4>' + standing + '</div>' : '') + '</div>';
    }

    // the Calendar (sl_calendar.summary(): { today = { day, hour, week, dayOfWeek }, events = { { id, title, kind: race|series|weekend|invite|travel, day, hour, place, map, travel = { needed, fee, hours },
    // series = { id, name, round, rounds }, status: open|entered|missed|done|declined, reward (number or text), requires = { label, met }, reminder, expiresIn } }, series = { { id, name, map, round, rounds,
    // points, rank, nextDay } }, invites = { { id, from, text, eventId, expiresIn } } }). Three views (Agenda, Week, Series) and an event page with the actions.
    function calOpenInvites() { var c = st.data.calendar; return c && obj(st.data.has).calendar !== false ? arr(c.invites).length : 0; }
    var CAL_KIND = { race: T('ui.cal_kind_race', 'Race'), series: T('ui.cal_kind_series', 'Series'), weekend: T('ui.cal_kind_weekend', 'Weekend'), invite: T('ui.cal_kind_invite', 'Invitational'), travel: T('ui.cal_kind_travel', 'Trip') };
    var CAL_STATUS = { entered: '&#10004; ' + T('ui.cal_entered', 'Entered'), missed: '&#9660; ' + T('ui.cal_missed', 'Missed'), done: '&#10004; ' + T('ui.cal_done', 'Done'), declined: T('ui.cal_declined', 'Declined') };
    var DAY_NAMES = [T('ui.cal_mon', 'Mon'), T('ui.cal_tue', 'Tue'), T('ui.cal_wed', 'Wed'), T('ui.cal_thu', 'Thu'), T('ui.cal_fri', 'Fri'), T('ui.cal_sat', 'Sat'), T('ui.cal_sun', 'Sun')];
    function calWhen(c, e) {      // "Today 18:00", "Tomorrow", "Sat, day 13 19:00"
      var d = Number(e.day) || 0, today = Number(obj(c.today).day) || 0, dow = ((Number(obj(c.today).dayOfWeek) || 1) - 1 + (d - today)) % 7;
      if (dow < 0) dow += 7;
      var label = d === today ? T('ui.cal_today', 'Today') : d === today + 1 ? T('ui.cal_tomorrow', 'Tomorrow') : d < today ? T('ui.cal_day_ago', 'Day {1}', d) : DAY_NAMES[dow] + ', ' + T('ui.cal_day', 'day {1}', d);
      return label + (e.hour != null ? ' ' + two(Math.floor(e.hour)) + ':' + two(Math.round((e.hour % 1) * 60)) : '');
    }
    function calReward(e) { return e.reward == null || e.reward === '' ? '' : (typeof e.reward === 'number' ? money(e.reward) : esc(e.reward)); }
    function calEventCard(c, e) {
      var tr = obj(e.travel), st1 = CAL_STATUS[e.status] || '';
      var rq = e.requires && e.requires.label ? '<p' + (e.requires.met === false ? ' class="slp-warn"' : '') + '>' + (e.requires.met === false ? '&#9888; ' : '&#10004; ') + esc(e.requires.label) + '</p>' : '';
      return '<div class="slp-card" data-a="calopen" data-v="' + esc(e.id) + '"><h4>' + esc(e.title || '') + ' <span class="slp-chip" style="margin:0 0 0 6px">' + (e.kind === 'invite' ? '&#9733; ' : '') + (CAL_KIND[e.kind] || esc(e.kind || '')) + '</span>' + (e.reminder ? ' <span aria-label="' + T('ui.cal_reminder_on', 'Reminder on') + '">&#128276;</span>' : '') + '</h4>' +
        '<p>' + calWhen(c, e) + (e.place ? ' &middot; ' + esc(e.place) : '') + (e.series ? ' &middot; ' + T('ui.cal_round', 'round {1} of {2}', e.series.round, e.series.rounds) : '') + '</p>' +
        (tr.needed ? '<p>' + T('ui.cal_travel', 'Travel to {1}: {2} and {3} h', esc(e.map || ''), money(tr.fee), Number(tr.hours) || 0) + '</p>' : '') + rq +
        (calReward(e) ? '<p>' + T('ui.cal_reward', 'Reward') + ': <b>' + calReward(e) + '</b></p>' : '') + (st1 ? '<p><b>' + st1 + '</b></p>' : '') +
        (e.expiresIn != null ? '<p class="slp-warn">' + T('ui.cal_expires', 'Expires in {1} d', Number(e.expiresIn) || 0) + '</p>' : '') + '</div>';
    }
    function calEventPage(c, e) {
      var tr = obj(e.travel), open = e.status === 'open', canEnter = open && !(e.requires && e.requires.met === false);
      var acts = '';
      if (open) {
        acts += '<div class="slp-btn' + (canEnter ? '' : ' slp-off') + '" data-a="' + (tr.needed ? 'caltravel' : 'calenter') + '" data-v="' + esc(e.id) + '">' + (tr.needed ? T('ui.cal_go', 'Go there &middot; {1}', money(tr.fee)) : T('ui.cal_enter', 'Enter')) + '</div>';
        acts += '<div class="slp-btn slp-tonal" data-a="calremind" data-v="' + esc(e.id) + '|' + (e.reminder ? 'false' : 'true') + '">' + (e.reminder ? T('ui.cal_remind_off', 'Reminder: on') : T('ui.cal_remind_on', 'Remind me')) + '</div>';
        if (e.kind === 'invite' || e.expiresIn != null) acts += '<div class="slp-btn slp-text" data-a="caldecline" data-v="' + esc(e.id) + '">' + T('ui.cal_decline', 'Decline') + '</div>';
      }
      return bar(esc(e.title || T('app.calendar', 'Calendar'))) + '<div class="slp-body">' + calEventCard(c, e).replace(' data-a="calopen" data-v="' + esc(e.id) + '"', '') +
        (acts ? '<div class="slp-card"><div class="slp-acts" style="flex-wrap:wrap">' + acts + '</div>' + (!canEnter && open ? '<p class="slp-warn">&#9888; ' + T('ui.cal_cannot', 'You cannot enter yet: see the requirement above.') + '</p>' : '') + '</div>' : '') + '</div>';
    }
    // the home championship (sl_season.summary(); tools/season_fixture.js): a card on the Series tab: the six rounds, the table, Enter while it can be entered, the titles won
    function seasonCard() {
      var sm = obj(st.data.season);
      if (!st.data.season) return '';
      var se = sm.season;
      var titles = Number(sm.titles) || 0, trophies = arr(sm.trophies);
      var trophyLine = titles > 0 ? '<p>&#127942; ' + T('ui.sn_titles', 'Titles won: {1}', titles) + (trophies.length ? ' &middot; ' + esc(trophies.slice(-1)[0].title || '') : '') + '</p>' : '';
      if (!se) return '<div class="slp-card"><h4>' + T('ui.sn_title', 'Home championship') + '</h4><p>' + T('ui.sn_none', 'No season running. The next one opens soon: {1} for the champion.', money(sm.purse)) + '</p>' + trophyLine + '</div>';
      var rows = arr(se.rounds).map(function (r, i) {
        var status = r.done ? '&#10004; ' + T('ui.sn_place', 'Place {1}, {2} pts', Number(r.place) || 0, Number(r.points) || 0) : r.missed ? '&#9660; ' + T('ui.cal_missed', 'Missed') : (se.round === i + 1 ? '&#9654; ' + T('ui.sn_next', 'Next') : '');
        return '<div class="slp-kv" style="display:block;padding:6px 0"><div style="display:flex;justify-content:space-between;gap:8px"><span>' + (r.kind === 'duel' ? '&#9876; ' : '') + esc(r.title || '') + '</span><b>' + T('ui.sn_day', 'Day {1}', Number(r.day) || 0) + '</b></div>' + (status ? '<div style="opacity:.85">' + status + '</div>' : '') + '</div>';
      }).join('');
      var tbl = arr(se.table).map(function (x) {
        return '<div class="slp-kv"><span>' + (Number(x.pos) || 0) + '. ' + (x.you ? '<b>' + esc(x.name) + '</b>' : esc(x.name)) + '</span><b>' + (Number(x.points) || 0) + ' ' + T('ui.trip_pts', 'pts') + '</b></div>';
      }).join('');
      return '<div class="slp-card"><h4>' + T('ui.sn_title_n', 'Home championship, season {1}', Number(se.n) || 1) + '</h4><p>' + T('ui.sn_span', 'Days {1} to {2} &middot; {3} for the champion', Number(se.from) || 0, Number(se.to) || 0, money(sm.purse)) +
        (se.entered && se.position != null ? ' &middot; ' + T('ui.sn_position', 'you are {1}', placeWord(se.position)) : '') + '</p>' + trophyLine + rows +
        (!se.entered ? '<div class="slp-acts"><div class="slp-btn' + (se.canEnter ? '' : ' slp-off') + '" data-a="seasonenter" data-v="1">' + T('ui.sn_enter', 'Enter the season') + '</div></div>' : '') + '</div>' +
        (tbl ? '<div class="slp-card"><h4>' + T('ui.trip_standings', 'Standings') + '</h4>' + tbl + '</div>' : '');
    }
    function calendarPage() {
      var c = obj(st.data.calendar), events = arr(c.events).slice().sort(function (a, b) { return (a.day - b.day) || ((a.hour == null ? -1 : a.hour) - (b.hour == null ? -1 : b.hour)); });
      if (st.calEvent) {
        var ev = events.filter(function (x) { return x.id === st.calEvent; })[0];
        if (ev) return calEventPage(c, ev);
        st.calEvent = null;
      }
      var tab = st.calTab || 'agenda', today = Number(obj(c.today).day) || 0, dow = Number(obj(c.today).dayOfWeek) || 1;
      var tabs = ['agenda', 'week', 'series'].map(function (t) {
        return '<div class="slp-tab' + (tab === t ? ' slp-tabon' : '') + '" data-a="caltab" data-v="' + t + '">' + ({ agenda: T('ui.cal_agenda', 'Agenda'), week: T('ui.cal_week', 'Week'), series: T('ui.cal_series', 'Series') }[t]) + '</div>';
      }).join('');
      var body = '';
      var inv = arr(c.invites).map(function (i) {
        return '<div class="slp-card" data-a="calopen" data-v="' + esc(i.eventId) + '"><h4>&#9993; ' + esc(i.from || '') + '</h4><p>' + esc(i.text || '') + '</p>' + (i.expiresIn != null ? '<p class="slp-warn">' + T('ui.cal_expires', 'Expires in {1} d', Number(i.expiresIn) || 0) + '</p>' : '') + '</div>';
      }).join('');
      if (tab === 'agenda') {
        var shown = events.filter(function (e) { return st.calDay == null || Number(e.day) === Number(st.calDay); });
        body = inv + (shown.map(function (e) { return calEventCard(c, e); }).join('') || '<div class="slp-empty">' + T('ui.cal_none', 'Nothing planned.') + '</div>');
      } else if (tab === 'week') {
        var start = today - (dow - 1), cells = [];
        for (var i = 0; i < 7; i++) {
          var day = start + i, n = events.filter(function (e) { return Number(e.day) === day; }).length;
          cells.push('<div class="slp-card" data-a="calday" data-v="' + day + '" style="margin:3px;padding:8px 2px;text-align:center;flex:1;min-width:0;overflow:hidden' + (day === today ? ';outline:2px solid #a8c7fa' : '') + '"><b>' + DAY_NAMES[i] + '</b><br><small>' + day + '</small><br>' + (n ? '<span class="slp-chip" style="margin:4px 0 0 0">' + n + '</span>' : '&nbsp;') + '</div>');
        }
        body = '<div style="display:flex;padding:0 12px">' + cells.join('') + '</div>' + (st.calDay != null ? '<div class="slp-acts" style="padding:0 16px"><div class="slp-btn slp-text" data-a="calday" data-v="">' + T('ui.cal_all_days', 'Show all days') + '</div></div>' : '') +
          events.filter(function (e) { return st.calDay == null || Number(e.day) === Number(st.calDay); }).map(function (e) { return calEventCard(c, e); }).join('');
      } else {
        body = seasonCard() + arr(c.series).map(function (x) {
          return '<div class="slp-card"><h4>' + esc(x.name || '') + '</h4>' +
            '<div class="slp-kv"><span>' + T('ui.cal_where', 'Where') + '</span><b>' + esc(x.map || '') + '</b></div>' +
            '<div class="slp-kv"><span>' + T('ui.cal_round_label', 'Round') + '</span><b>' + (Number(x.round) || 0) + ' / ' + (Number(x.rounds) || 0) + '</b></div>' +
            '<div class="slp-kv"><span>' + T('ui.cal_points', 'Points') + '</span><b>' + (Number(x.points) || 0) + '</b></div>' +
            '<div class="slp-kv"><span>' + T('ui.cal_rank', 'Position') + '</span><b>' + (x.rank != null ? Number(x.rank) : '&ndash;') + '</b></div>' +
            (x.nextDay != null ? '<p>' + T('ui.cal_next_round', 'Next round: day {1}', Number(x.nextDay)) + '</p>' : '') + '</div>';
        }).join('') || (st.data.season ? '' : '<div class="slp-empty">' + T('ui.cal_no_series', 'No series running. One opens each month.') + '</div>');
      }
      return bar(T('app.calendar', 'Calendar')) + '<div class="slp-tabs" style="padding:0 16px 8px">' + tabs + '</div><div class="slp-body">' + body + '</div>';
    }

    // the trip (docs/DESIGN_CAREER_TRAVEL.md): the pick-cars screen over everything while the series module’s options for the event is open, the paddock hub (sl_series.hub()) while on a visit
    function pickPage() {
      var o = obj(st.data.travelPick), sel = arr(st.pickSel), max = Number(o.max) || 3, lo = o.loaner;
      if (st.pickFor !== o.eventId) { st.pickFor = o.eventId; st.pickSel = sel = []; st.pickLoaner = false; }
      var n = sel.length + (st.pickLoaner ? 1 : 0), total = (Number(o.fee) || 0) + (Number(o.perCar) || 0) * sel.length + (st.pickLoaner && lo ? Number(lo.deposit) || 0 : 0);
      var cars = arr(o.cars).map(function (c) {
        var cid = String(c.id), on = sel.indexOf(cid) >= 0, ok = c.fits !== false && (on || sel.length < max);
        return '<div class="slp-card' + (c.fits === false ? ' slp-off' : '') + '"' + (ok ? ' data-a="pickcar" data-v="' + esc(cid) + '" style="cursor:pointer"' : '') + '><h4>' + (on ? '&#10004; ' : '') + esc(c.name) + '</h4>' +
          (c.fits === false ? '<p class="slp-warn">&#9888; ' + esc(c.why || T('ui.trip_no_fit', 'Does not fit this event')) + '</p>' : (c.report ? '<p>' + esc(c.report) + '</p>' : '')) + '</div>';
      }).join('');
      var loan = lo ? '<div class="slp-card" data-a="pickloaner" data-v="1" style="cursor:pointer"><h4>' + (st.pickLoaner ? '&#10004; ' : '') + T('ui.trip_loaner', 'Borrow {1}', esc(lo.name || '')) + '</h4><p>' + T('ui.trip_deposit', 'Deposit {1}', money(lo.deposit)) + '</p></div>' : '';
      var body = o.refuse ? '<div class="slp-empty">' + esc(o.refuse) + '</div>'
        : '<p style="padding:0 16px">' + T('ui.trip_pick', 'Pick up to {1} cars to bring.', max) + '</p>' + cars + loan +
          '<div class="slp-card"><div class="slp-kv"><span>' + T('ui.trip_fee', 'Entry fee') + '</span><b>' + money(o.fee) + '</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.trip_per_car', 'Each car brought') + '</span><b>' + money(o.perCar) + '</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.trip_time', 'Travel') + '</span><b>' + T('ui.trip_hours', '{1} h', Number(o.hours) || 0) + '</b></div>' +
          '<div class="slp-kv"><span>' + T('ui.trip_total', 'Total') + '</span><b>' + money(total) + '</b></div>' +
          '<div class="slp-acts"><div class="slp-btn' + (n ? '' : ' slp-off') + '" data-a="pickconfirm" data-v="1">' + T('ui.trip_confirm', 'Confirm and go') + '</div></div></div>';
      return bar(o.name || T('app.event', 'Event')).replace('data-a="back"', 'data-a="pickback"') + '<div class="slp-body">' + body + '</div>';
    }
    // the paddock = sl_series.hub(): { event = { title, mapName, round, rounds, rules = { text }, status 'ready'|'running'|'done' }, standings = { { pos, name, points, you, time } }, schedule = { { day, hour, title, status 'done'|'missed'|'next'|'later' } },
    // cars = { { id, name } }, canStart, startWhy, leaveNote }; the trip's end day comes from the phone's `visit`
    function hubPage() {
      var h = obj(st.data.hub), ev = obj(h.event), vis = obj(st.data.visit), over = ev.status === 'done';
      var rows = arr(h.standings).map(function (r) {
        return '<div class="slp-kv"><span>' + (Number(r.pos) || 0) + '. ' + (r.you ? '<b>' + esc(r.name) + '</b>' : esc(r.name)) + '</span><b>' + (Number(r.points) || 0) + ' ' + T('ui.trip_pts', 'pts') + (r.time ? ' &middot; ' + esc(r.time) : '') + '</b></div>';
      }).join('');
      var MARK = { done: '&#10004; ', missed: '&#9660; ', next: '&#9654; ', later: '' };
      var sched = arr(h.schedule).map(function (x) {
        return '<div class="slp-kv"><span>' + (MARK[x.status] || '') + esc(x.title || '') + '</span><b>' + T('ui.trip_day_hour', 'Day {1} {2}:00', Number(x.day) || 0, two(Number(x.hour) || 0)) + '</b></div>';
      }).join('');
      var home = '<div class="slp-card">' + (st.hubHome ? '<p class="slp-warn">' + esc(h.leaveNote || T('ui.trip_home_sure', 'Go home now? The rest of this series counts as missed and the entry fee is gone.')) + '</p>' : '') +
        '<div class="slp-acts"><div class="slp-btn slp-text" data-a="hubhome" data-v="1">' + (st.hubHome ? T('ui.trip_home_yes', 'Yes, go home') : T('ui.trip_home', 'Go home')) + '</div>' +
        (st.hubHome ? '<div class="slp-btn slp-text" data-a="hubhome" data-v="0">' + T('ui.cancel', 'Cancel') + '</div>' : '') + '</div></div>';
      var go = over ? '<div class="slp-card"><h4>' + T('ui.trip_over', 'The series is over') + '</h4></div>'
        : '<div class="slp-card"><h4>' + T('ui.trip_next', 'Next: {1}', esc(((arr(h.schedule).filter(function (x) { return x.status === 'next'; })[0]) || {}).title || '')) + '</h4>' +
          (h.canStart === false && h.startWhy ? '<p class="slp-warn">' + esc(h.startWhy) + '</p>' : '') +
          '<div class="slp-acts"><div class="slp-btn' + (h.canStart === false ? ' slp-off' : '') + '" data-a="hubstart" data-v="1">' + T('ui.trip_start', 'Start') + '</div></div></div>';
      return bar(ev.title || T('app.event', 'Event')) + '<div class="slp-body">' +
        '<div class="slp-card"><h4>' + esc(ev.title || '') + '</h4><div class="slp-kv"><span>' + esc(ev.mapName || '') + '</span><b>' + T('ui.trip_round', 'Round {1} of {2}', Number(ev.round) || 1, Number(ev.rounds) || 1) + '</b></div>' +
        arr(ev.rules).map(function (x) { return '<p>' + esc(x) + '</p>'; }).join('') +
        (vis.untilDay != null ? '<p>' + T('ui.trip_until', 'You can stay until day {1}', Number(vis.untilDay) || 0) + '</p>' : '') + '</div>' + go +
        (sched ? '<div class="slp-card"><h4>' + T('ui.trip_schedule', 'Schedule') + '</h4>' + sched + '</div>' : '') +
        (rows ? '<div class="slp-card"><h4>' + T('ui.trip_standings', 'Standings') + '</h4>' + rows + '</div>' : '') +
        (arr(h.cars).length ? '<div class="slp-card"><h4>' + T('ui.trip_cars', 'Your cars here') + '</h4>' + arr(h.cars).map(function (c) { return '<p>' + esc(c.name) + '</p>'; }).join('') + '</div>' : '') + home + '</div>';
    }

    // the trophy shelf's list (s.trophies = { { name, kind sprint|invite|series, day, place } }, newest last; tools/trophies_fixture.js): newest first, a card only when the list exists
    var TROPHY_KIND = { sprint: T('ui.trophy_sprint', 'Sprint'), invite: T('ui.trophy_invite', 'Invitational'), series: T('ui.trophy_series', 'Series') };
    function placeWord(n) { n = Number(n) || 0; var m = n % 100; var sfx = (m >= 11 && m <= 13) ? 'th' : ['th', 'st', 'nd', 'rd'][n % 10] || 'th'; return n + sfx; }
    function trophiesCard() {
      var list = st.data.trophies;
      if (!Array.isArray(list)) return '';
      var rows = list.slice().reverse().map(function (t) {
        return '<div class="slp-kv"><span>&#127942; ' + esc(t.name || '') + '<br><small>' + (TROPHY_KIND[t.kind] || esc(t.kind || '')) + ' &middot; ' + T('ui.trophy_day', 'day {1}', Number(t.day) || 0) + '</small></span><b>' + placeWord(t.place) + '</b></div>';
      }).join('');
      return '<div class="slp-card"><h4>' + T('ui.trophies', 'Trophies: {1}', list.length) + '</h4>' + (rows || '<p>' + T('ui.trophy_none', 'No trophies yet. Win an invitational or a series.') + '</p>') + '</div>';
    }
    // a save from before the 0.8.0 economy is offered it (data.economyOffer = the text, only for such a save): one card, one button
    function economyCard() {
      var t = st.data.economyOffer;
      if (!t) return '';
      return '<div class="slp-card"><h4>' + T('ui.economy_title', 'New in 0.8.0') + '</h4><p>' + esc(t) + '</p><div class="slp-acts"><div class="slp-btn" data-a="economy" data-v="1">' + T('ui.economy_on', 'Turn them on') + '</div></div></div>';
    }
    function mePage() {
      var d = st.data, s = obj(d.stats);
      var from = d.titleRep || 0, to = d.nextRep, pct = to ? Math.max(0, Math.min(100, ((d.rep || 0) - from) / (to - from) * 100)) : 100;
      var next = d.nextGarage ? ('<div class="slp-kv"><span>' + T('ui.next_garage', 'Next garage') + '</span><b>') + esc(d.nextGarage.name) + (d.nextGarage.canMove ? T('ui.ready', ' - ready') : ' - ' + esc(d.nextGarage.why)) + '</b></div>' : '';
      var acts = [];
      if (d.nextGarage && d.nextGarage.canMove) acts.push(('<div class="slp-btn" data-a="move">' + T('ui.move_to', 'Move to ')) + esc(d.nextGarage.name) + '</div>');
      if (d.roc && !d.rocChampion) acts.push('<div class="slp-btn" data-a="roc">' + (d.rocRound ? T('ui.roc_round_1_of_3', 'ROC round {1} of 3', (d.rocRound + 1)) : T('ui.enter_the_roc_middot_1', 'Enter the ROC &middot; {1}', money(d.rocEntry))) + '</div>');
      return bar(T('app.me', 'Street cred')) + '<div class="slp-body">' + economyCard() + '<div class="slp-card"><h4>' + esc(d.title) + '</h4><p>' + (d.rep || 0) + ' reputation' + (to ? T('ui.middot_next_title_at_1', ' &middot; next title at {1}', to) : '') + '</p>' +
        '<div class="slp-meter"><i style="width:' + pct.toFixed(1) + '%"></i></div></div>' + perksCard() + trophiesCard() +
        ('<div class="slp-card"><div class="slp-kv"><span>' + T('ui.garage', 'Garage') + '</span><b>') + esc(d.garage || '') + '</b></div>' + next +
        (d.hasRoc === false ? '' : ('<div class="slp-kv"><span>' + T('activityrules.race_of_champions', 'Race of Champions') + '</span><b>') + (d.roc ? T('ui.open_to_you', 'Open to you') : T('ui.not_yet', 'Not yet')) + '</b></div>') +
        ('<div class="slp-kv"><span>' + T('ui.cars', 'Cars') + '</span><b>') + (d.cars || 0) + '</b></div>' +
        ('<div class="slp-kv"><span>' + T('ui.races', 'Races') + '</span><b>') + (s.races || 0) + ' (' + (s.wins || 0) + (T('ui.won_2', ' won)') + '</b></div>') +
        ('<div class="slp-kv" style="border:none"><span>' + T('crews.pink_slips', 'Pink slips') + '</span><b>') + (s.pinksWon || 0) + T('ui.won_3', ' won, ') + (s.pinksLost || 0) + ' lost</b></div>' +
        (acts.length ? '<div class="slp-acts">' + acts.join('') + '</div>' : '') + '</div>' +
        (d.rocChampion ? ('<div class="slp-card"><h4>' + T('streets.roc_champion', 'ROC champion') + '</h4><p>' + T('ui.the_best_in', 'The best in ')) + esc(d.mapName || T('progression.valo_city', 'Valo City')) + (T('ui.there_is_nobody_left_to', '. There is nobody left to beat.') + '</p></div>') : '') +
        rivalCards() + achievementsCard(d.achievements) + '</div>';
    }

    // achievements (earned ones lit, the rest dimmed) and personal best times
    function achievementsCard(a) {
      if (!a) return '';
      var rows = arr(a.list).map(function (x) {
        return '<div class="slp-kv"' + (x.day != null ? '' : ' style="opacity:.45"') + '><span>' + esc(x.title) + '<br><small>' + esc(x.desc) + '</small></span><b>' + (x.day != null ? T('ui.day_1', 'Day {1}', x.day) : '') + '</b></div>';
      }).join('');
      var bests = arr(a.bests).map(function (b) { return '<div class="slp-kv"><span>' + esc(b.name) + '</span><b>' + Number(b.time).toFixed(2) + ' s</b></div>'; }).join('');
      return ('<div class="slp-card"><h4>' + T('ui.achievements', 'Achievements ')) + (a.earned || 0) + ' / ' + (a.total || 0) + '</h4>' + rows + '</div>' +
        (bests ? ('<div class="slp-card"><h4>' + T('ui.best_times', 'Best times') + '</h4>') + bests + '</div>' : '');
    }

    function callPage() {
      var c = st.call, who = contactById(c.id) || { id: c.id, name: c.id };
      var status = c.phase === 'ringing' ? 'Calling…' : (c.phase === 'ended' ? T('ui.call_ended', 'Call ended') : T('ui.connected', 'Connected'));
      var body = '';
      if (c.phase === 'talking' || c.phase === 'ended') {
        if (c.greeting) body += '<div class="slp-said">' + esc(c.greeting) + '</div>';
        if (c.reply) body += '<div class="slp-said">' + esc(c.reply) + '</div>';
        else if (c.text) body += '<div class="slp-said">' + esc(c.text) + '</div>';
        if (c.phase === 'talking' && !c.reply && arr(c.options).length) {
          body += '<div class="slp-opts">' + c.options.map(function (k) { return '<div class="slp-btn slp-tonal" data-a="stake" data-v="' + k + '">' + STAKE_TEXT[k] + '</div>'; }).join('') + '</div>';
        }
        if (c.challenge) body += '<div class="slp-opts"><div class="slp-btn" data-a="gps" data-v="' + esc(c.challenge.id) + ('">' + T('ui.show_the_way_to', 'Show the way to ')) + esc(c.challenge.raceName) + '</div></div>';
      }
      return '<div class="slp-call' + (c.phase === 'ringing' ? ' slp-ring' : '') + '">' + avatar(who) + '<b>' + esc(who.name) + '</b><div class="slp-cs">' + status + '</div>' + body +
        '<div class="slp-hang" data-a="hang">' + I.phone + '</div></div>';
    }

    // ---------------------------------------------------------------- the lots, a meet, a race
    function mmss(sec) { sec = Math.max(0, Math.round(sec || 0)); return Math.floor(sec / 60) + ':' + two(sec % 60); }

    // a lot with its menu on screen (not the test drive: then you are driving) takes the pill and the heads-up out of the way
    function lotHides() { return !!(st.lot && st.lot.open && st.lot.mode !== 'test'); }

    function lotView() {
      var l = st.lot;
      if (!l || !l.open) return '';
      if (l.mode === 'reveal') return '<div class="slp-lot"><div class="slp-lotleave"><div class="slp-btn slp-text" data-a="lot" data-v="skip()">' + T('ui.skip', 'Skip') + '</div></div></div>';
      if (l.mode === 'test') {
        return ('<div class="slp-hudtest">' + T('ui.test_drive', 'Test drive ') + '&middot;' + ' ') + mmss(l.testLeft) + T('ui.left_middot_bring_it_back', ' left &middot; bring it back to ') + esc(l.name) +
          ('<div class="slp-btn slp-tonal" data-a="lot" data-v="endTest()">' + T('ui.done', 'Done') + '</div></div>');
      }
      if (l.mode === 'sell') {
        var c = l.sellCar || {};
        return '<div class="slp-lot"><div class="slp-lothead"><span>' + esc(l.kindTitle) + ' &middot; ' + esc(l.name) + '</span></div>' +
          ('<div class="slp-lotname">' + T('ui.they_will_give_you', 'They will give you') + '<b>') + money(c.price) + T('ui.for_the', ' for the ') + esc(c.name) + '</b></div>' +
          '<div class="slp-lotbtns"><div class="slp-btn" data-a="lot" data-v="sell()">' + (l.kind === 'scrap' ? T('ui.scrap_it', 'Scrap it') : T('ui.sell_it', 'Sell it')) + '</div>' +
          ('<div class="slp-btn slp-tonal" data-a="lot" data-v="browse()">' + T('ui.look_at_their_cars', 'Look at their cars') + '</div></div>') +
          ('<div class="slp-lotleave"><div class="slp-btn slp-text" data-a="lot" data-v="close()">' + T('ui.not_today', 'Not today') + '</div></div></div>');
      }
      if (l.building) {         // the row is being made: a loading screen, the lot shows when all is done
        var pr = obj(l.progress), tot = pr.total || 0, dn = Math.min(pr.done || 0, tot);
        return ('<div class="slp-lotload"><div class="slp-lcard"><div class="slp-spin"></div><b>' + T('ui.getting_the_cars_out', 'Getting the cars out') + '&hellip;</b>') +
          '<span>' + esc(l.name) + '</span><span>' + (tot ? (pr.phase === 'bodywork' ? T('ui.bodywork', 'Bodywork ') : T('ui.car', 'Car ')) + dn + ' of ' + tot : T('ui.one_moment', 'One moment')) + '</span>' +
          '<div class="slp-lbar"><i style="width:' + (tot ? Math.round(100 * dn / tot) : 5) + '%"></i></div>' +
          ('<div class="slp-btn slp-text" data-a="lot" data-v="close()" style="margin-top:10px">' + T('ui.cancel', 'Cancel') + '</div></div></div>');
      }
      if (l.mode === 'auction' && l.auction) {      // the yard's live auction: the lot's card and the bid buttons
        var au = l.auction, al = obj(au.lot), aplus = Math.round((al.bid || al.next) * 1.1 / 10) * 10, aleader = al.high === 'you';
        return '<div class="slp-catch" data-catch="lot"></div><div class="slp-lot"><div class="slp-lothead"><span>' + T('ui.auction_yard', 'Car auction') + ' &middot; ' + esc(l.name) + '</span><span>' + T('ui.auction_lot_of', 'Lot {1} of {2}', au.index, au.total) + '</span></div>' +
          '<div class="slp-lotname"><b>' + esc(al.name) + '</b></div><div class="slp-lottitle">' + T('ui.auction_grade', 'Grade {1}', esc(al.grade)) + ' &middot; ' + T('ui.auction_condition', 'Condition {1}%', al.condition) + '</div>' +
          reportBlock('lot', al.report) +
          '<div class="slp-lotprice">' + money(al.bid) + '</div><div class="slp-lottitle">' + (aleader ? T('ui.auction_high_you', 'You are the highest bidder') : (al.bid > 0 ? T('ui.auction_outbid', 'Outbid') : T('ui.auction_no_bids', 'No bids yet'))) +
          ' &middot; ' + (al.reserveMet ? T('ui.auction_reserve_met', 'Reserve met') : T('ui.auction_reserve_not_met', 'Reserve not met')) + ' &middot; ' + (au.waiting ? T('ui.auction_next_lot', 'The next lot is coming up.') : T('ui.auction_going_in', 'Going in {1} s', al.secondsLeft)) + '</div>' +
          '<div class="slp-lotbtns">' + (aleader || au.waiting ? '' : '<div class="slp-btn' + (au.money != null && au.money < al.next ? ' slp-off' : '') + '" data-a="abid" data-v="' + esc(al.id) + '|' + al.next + '">' + T('ui.auction_bid_next', 'Bid {1}', money(al.next)) + '</div>' +
          '<div class="slp-btn slp-tonal' + (au.money != null && au.money < aplus ? ' slp-off' : '') + '" data-a="abid" data-v="' + esc(al.id) + '|' + aplus + '">' + T('ui.auction_bid_plus', 'Bid +10% ({1})', money(aplus)) + '</div>') + '</div>' +
          '<div class="slp-lotleave"><div class="slp-btn slp-text" data-a="lot" data-v="close()">' + T('ui.leave', 'Leave') + '</div></div></div>';
      }
      if (l.factory) {
        var f = l.factory, rows = '';
        function pic(u) { return u ? '<img class="slp-shopimg" src="' + esc(u) + '">' : '<div class="slp-shopimg"></div>'; }
        if (f.step === 'models') rows = '<div class="slp-shopgrid">' + arr(f.models).map(function (m) {
          return '<div class="slp-shopcard" data-a="lot" data-v="factoryModel(' + m.i + ')">' + pic(m.picture) + '<b>' + esc(m.name) + '</b><span>' + esc(m.body) +
            (m.special ? ' &middot; ' + T('ui.special_order', 'Special order') : '') + '</span><span>' + T('ui.factory_from', 'from') + ' ' + money(m.from) + ' &middot; ' + T('ui.factory_trims_n', '{1} trims', m.trims) + '</span></div>';
        }).join('') + '</div>';
        else if (f.step === 'trims') rows = '<div class="slp-shopgrid">' + arr(f.trims).map(function (t) {
          return '<div class="slp-shopcard" data-a="lot" data-v="factoryTrim(' + t.i + ')">' + pic(t.picture) + '<b>' + esc(t.name) + '</b><span>' + money(t.price) + '</span><span>' +
            [t.power ? Math.round(t.power) + ' hp' : '', t.weight ? Math.round(t.weight) + ' kg' : '', t.drive || '', t.transmission || ''].filter(Boolean).map(esc).join(' &middot; ') + '</span></div>';
        }).join('') + '</div>';
        else {
          rows = '<div class="slp-shopcfg">' + pic(f.picture) + '<div><div class="slp-lottitle">' + T('ui.factory_colour', 'Colour') + ': ' + esc(f.paint || '') + '</div><div class="slp-swatches">' +
            arr(f.swatches).map(function (c, i) { return '<div class="slp-swatch' + (c.on ? ' slp-on' : '') + '" title="' + esc(c.name) + '" style="background:' + esc(c.css) + '" data-a="lot" data-v="factoryPaint(' + (i + 1) + ')"></div>'; }).join('') + '</div>' +
            arr(f.groups).map(function (g) {
              return '<div class="slp-lottitle">' + T('ui.factory_group_' + g.id, g.id) + '</div>' + arr(g.slots).map(function (sl) {
                return '<div class="slp-optrow"><small>' + esc(sl.label) + '</small>' + arr(sl.options).map(function (op) {
                  return '<div class="slp-opt' + (op.on ? ' slp-on' : '') + '" data-a="lot" data-v="factoryPick(' + (sl.n * 1000 + op.j) + ')">' + esc(op.name) + (op.delta ? ' ' + (op.delta > 0 ? '+' : '-') + money(Math.abs(op.delta)) : '') + '</div>';
                }).join('') + '</div>';
              }).join('');
            }).join('') + '<div class="slp-lottitle">' + T('ui.factory_delivery_in', 'Delivered to your garage in about {1} hours', f.hours) + '</div>' +
            '<div class="slp-lotbtns"><div class="slp-btn' + (f.total > l.money ? ' slp-off' : '') + '" data-a="lot" data-v="factoryBuy()">' + T('ui.factory_order_it', 'Order') + ' &middot; ' + money(f.total) + '</div></div></div></div>';
        }
        return '<div class="slp-lot slp-shop"><div class="slp-lothead"><span>' + esc(l.kindTitle) + ' &middot; ' + esc(l.name) + '</span><b>' + esc(f.model || T('ui.factory_models', 'Factory models')) + (f.trim ? ' &middot; ' + esc(f.trim) : '') + '</b></div>' + rows +
          '<div class="slp-lotleave"><div class="slp-btn slp-text" data-a="lot" data-v="factoryBack()">' + T('ui.factory_back', 'Back') + '</div></div></div>';
      }
      var o = l.offer || {};
      var faults = arr(o.faults);
      var body = l.building ? ('<div class="slp-lotname"><b>' + T('ui.bringing_it_round', 'Bringing it round…') + '</b></div>') :
        '<div class="slp-lotname">' + esc(o.brand) + '<b>' + esc(o.name) + '</b></div><div class="slp-lottitle">' + esc(o.title) + '</div>' +
        ('<div class="slp-lotstats"><div>' + T('ui.condition_2', 'Condition') + '<b>') + Math.round((o.condition || 0) * 100) + ('%' + '</b></div><div>' + T('ui.mileage', 'Mileage') + '<b>') + String(Math.round(o.mileage || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ',') + ' km</b></div>' +
        ('<div>' + T('ui.bodywork_2', 'Bodywork') + '<b>') + (o.damage > 0.5 ? T('ui.bad', 'Bad') : o.damage > 0.15 ? T('ui.dented', 'Dented') : T('ui.clean', 'Clean')) + '</b></div>' + (o.mods ? ('<div>' + T('ui.modified', 'Modified') + '<b>') + o.mods + ' parts</b></div>' : '') + '</div>' +
        '<div class="slp-lotfaults' + (faults.length ? '' : ' slp-ok') + '">' + (faults.length ? T('ui.needs_1', 'Needs: {1}', esc(faults.join(', '))) : T('ui.runs_and_drives', 'Runs and drives')) + '</div>' +
        reportBlock('lot', o.report) + '<div class="slp-lotprice">' + money(o.price) + '</div>';
      return '<div class="slp-catch" data-catch="lot"></div><div class="slp-lot"><div class="slp-lothead"><span>' + esc(l.kindTitle) + ' &middot; ' + esc(l.name) + '</span><span>' + (l.index || 0) + ' / ' + (l.count || 0) + '</span></div>' + body +
        '<div class="slp-lotbtns"><div class="slp-arrow" data-a="lot" data-v="prev()">' + (st.slrrArt ? slrrIcon('left.png') : '&#9664;') + '</div>' +
        (l.kind !== 'scrap' ? '<div class="slp-btn slp-tonal' + (l.building ? ' slp-off' : '') + ('" data-a="lot" data-v="testDrive()">' + T('ui.test_drive_2', 'Test drive') + '</div>') : '') +
        '<div class="slp-btn' + (l.building || (o.price > l.money) ? ' slp-off' : '') + ('" data-a="lot" data-v="buy()">' + T('ui.buy_2', 'Buy ') + '&middot;' + ' ') + money(o.price) + '</div>' +
        '<div class="slp-arrow" data-a="lot" data-v="next()">' + (st.slrrArt ? slrrIcon('right.png') : '&#9654;') + '</div></div>' +
        (l.canFactory ? '<div class="slp-lotfactory"><div class="slp-btn slp-tonal" data-a="lot" data-v="factoryOpen()">' + T('ui.order_from_the_factory', 'Order from the factory') + '</div></div>' : '') +
        ('<div class="slp-lotleave"><div class="slp-btn slp-text" data-a="lot" data-v="close()">' + T('ui.leave', 'Leave') + '</div></div></div>');
    }

    // the gas station: a grade, fill the tank or a can, and the shop
    // on foot in a garage's doorway: your cars, to take out, work on (the garage opens on it) or put away
    function garageView() {
      var g = st.garage;
      if (!g || !g.open) return '';
      var rows = arr(st.data.fleet).map(function (c) {
        var acts = [];
        if (c.impounded) acts.push(('<div class="slp-btn slp-tonal slp-off">' + T('ui.impounded', 'Impounded') + '</div>'));
        else {
          acts.push('<div class="slp-btn" data-a="workon" data-v="' + c.id + '">' + (c.out ? T('ui.work_on_it', 'Work on it') : T('ui.take_out_and_work_on', 'Take out and work on it')) + '</div>');
          if (!c.out) acts.push('<div class="slp-btn slp-tonal" data-a="usecar" data-v="' + c.id + ('">' + T('ui.take_out', 'Take out') + '</div>'));
          else acts.push('<div class="slp-btn slp-tonal" data-a="despawn" data-v="' + c.id + ('">' + T('ui.put_away', 'Put away') + '</div>'));
        }
        return '<div class="slp-kv"><span>' + esc(c.name) + (c.active ? ' &#9733;' : '') + '<br><small>' + esc(c.where) + ' &middot; condition ' + Math.round((c.condition || 0) * 100) + '%</small></span></div>' +
          '<div class="slp-lotbtns">' + acts.join('') + '</div>';
      }).join('');
      return ('<div class="slp-lot"><div class="slp-lothead"><span>' + T('ui.garage_2', 'Garage ') + '&middot;' + ' ') + esc(g.name) + '</span></div>' +
        ('<div class="slp-lotname">' + T('ui.your_cars', 'Your cars') + '</div>') + (rows || ('<div class="slp-empty">' + T('ui.you_have_no_car', 'You have no car.') + '</div>')) +
        ('<div class="slp-lotleave"><div class="slp-btn slp-text" data-a="garageclose">' + T('ui.leave', 'Leave') + '</div></div></div>');
    }

    function stationView() {
      var g = st.station;
      if (!g || !g.open) return '';
      var pick = st.fuelPick || 'premium';
      var grades = arr(g.fuels).map(function (f) {
        return '<div class="slp-btn slp-stack' + (f.id === pick ? '' : ' slp-tonal') + '" data-a="fuelpick" data-v="' + esc(f.id) + '"><span class="slp-lbl">' + esc(f.name) + '</span><small>$' + Number(f.price).toFixed(2) + '/L</small></div>';
      }).join('');
      var tank = g.car ? T('ui.your_1_2_3_4', 'Your {1}: {2}{3}{4}', esc(g.car), (g.tank != null ? Math.round(g.tank * 100) + '% full' : ''), (g.inTank ? ' &middot; ' + esc(g.inTank) : ''), (g.litresToFull != null ? ' &middot; ' + Math.round(g.litresToFull) + ' L to fill' : '')) : T('ui.come_in_your_car_to', 'Come in your car to fill it up.');
      var shop = arr(g.items).map(function (it) {
        return '<div class="slp-kv slp-hudrow" data-a="station" data-v="buy|' + esc(it.id) + '"><span>' + esc(it.name) + '</span><b class="slp-on">' + money(it.price) + '</b></div>';
      }).join('');
      return ('<div class="slp-lot"><div class="slp-lothead"><span>' + T('ui.gas_station', 'Gas station ') + '&middot;' + ' ') + esc(g.name) + '</span><span>' + money(g.money) + '</span></div>' +
        '<div class="slp-lotname">' + tank + '</div>' +
        '<div class="slp-lotbtns slp-grades">' + grades + '</div>' +
        '<div class="slp-lotbtns"><div class="slp-btn slp-go" data-a="station" data-v="fill|' + esc(pick) + ('">' + T('ui.fill_the_tank', 'Fill the tank') + '</div>') +
        (g.washPrice != null ? ('<div class="slp-btn slp-tonal" data-a="station" data-v="wash">' + T('ui.car_wash', 'Car wash ') + '&middot;' + ' ') + money(g.washPrice) + '</div>' : '') + '</div>' +
        ('<div class="slp-trunk">' + T('ui.shop', 'Shop ') + '&middot;' + T('ui.into_the_trunk', ' into the trunk (')) + (g.trunk || 0) + '/' + (g.trunkSlots || 6) + ')' + (' ' + '&middot;' + T('ui.a_fuel_can_takes_the', ' a fuel can takes the grade above') + '</div>') + shop +
        ('<div class="slp-lotleave"><div class="slp-btn slp-text" data-a="station" data-v="close">' + T('ui.drive_on', 'Drive on') + '</div></div></div>');
    }

    function meetView() {
      var m = st.meet;
      if (!m || !m.open) return '';
      var rows = arr(m.racers).map(function (r) {
        return '<div class="slp-row">' + avatar(r) + '<div class="slp-rt"><b>' + esc(r.name) + '</b><span><span class="slp-stars">' + new Array((r.tier || 1) + 1).join('&#9733;') + '</span> &middot; ' +
          esc(r.car) + ' &middot; ' + money(r.betMin) + '-' + money(r.betMax) + '</span></div><div class="slp-acts">' +
          '<div class="slp-btn slp-tonal" data-a="meet" data-v="' + esc(r.id) + ('|race">' + T('ui.race', 'Race') + '</div>') +
          '<div class="slp-btn slp-tonal" data-a="meet" data-v="' + esc(r.id) + ('|high">' + T('ui.high', 'High') + '</div>') +
          (r.pinkTonight ? '<div class="slp-btn slp-pinkbtn" data-a="meet" data-v="' + esc(r.id) + ('|pink">' + T('ui.pinks', 'Pinks') + '</div>') : '') + '</div></div>';
      });
      var owners = arr(m.owners).map(function (o) {
        return '<div class="slp-row"><div class="slp-rt"><b>' + esc(o.name) + '</b><span>' + esc(o.car) + (o.talked ? T('ui.middot_spoken_to', ' &middot; spoken to') : '') + '</span></div><div class="slp-acts">' +
          '<div class="slp-btn slp-tonal" data-a="meettalk" data-v="' + esc(o.id) + ('">' + T('ui.talk', 'Talk') + '</div></div></div>');
      }).join('');
      return '<div class="slp-meet"><h3>' + (m.theme ? esc(m.theme) + ' &middot; ' : T('ui.car_meet_middot', 'Car meet &middot; ')) + esc(m.name) + '</h3><div class="slp-card" style="margin:6px 0 4px 0"><p>Pick somebody. The race is to the other side of town; first one there wins.</p></div>' +
        (rows.join('') || ('<div class="slp-empty">' + T('ui.everybody_has_gone_home', 'Everybody has gone home.') + '</div>')) +
        (owners ? ('<div class="slp-trunk">' + T('ui.owners_by_their_cars', 'Owners by their cars') + '</div>') + owners : '') +
        tyreSwapView() +
        (m.canShow ? ('<div class="slp-lotbtns"><div class="slp-btn slp-tonal" data-a="meetshow" data-v="1">' + T('ui.show_and_shine', 'Show and shine (')) + money(m.showFee || 50) + ')</div></div>' : '') +
        ('<div class="slp-lotleave"><div class="slp-btn slp-text" data-a="meetclose">' + T('ui.just_looking', 'Just looking') + '</div></div></div>');
    }

    function raceView() {
      var r = st.race;
      if (!r || !r.on) return '';
      var stake = r.stake === 'pink' ? T('crews.pink_slips', 'Pink slips') : money(r.bet);
      var dist = r.laps ? T('ui.lap_1_of_2', 'Lap {1} of {2}', r.lap, r.laps) : (r.mine != null ? T('ui.you_1_m', 'You {1} m', r.mine) : '') + (r.theirs != null ? T('ui.middot_them_1_m', ' &middot; them {1} m', r.theirs) : '');
      return (r.countdown ? '<div class="slp-count">' + r.countdown + '</div>' : '') +
        '<div class="slp-race"><b>vs ' + esc(r.name) + ' &middot; ' + stake + '</b><span>To ' + esc(r.destName) + '</span><span>' + dist + '</span>' +
        (r.ahead != null ? '<i class="' + (r.ahead ? 'slp-ahead' : 'slp-behind') + '">' + (r.ahead ? T('ui.ahead', 'Ahead') : T('ui.behind', 'Behind')) + '</i>' : '') + '</div>';
    }

    // the careers saved (X52): play, rename, delete (twice to be sure); each keeps its own backup
    function slotsHtml(m) {
      var list = arr(m.slots);
      if (list.length < 2 && !st.slotEdit) return list.length ? ('<div class="slp-btn slp-text" data-a="slotedit" data-v="1">' + T('ui.manage_careers', 'Manage careers') + '</div>') : '';
      return '<div class="slp-slots">' + list.map(function (c) {
        return '<div class="slp-slot"><b>' + esc(c.name) + (c.last ? T('ui.middot_last_played', ' &middot; last played') : '') + '</b><span>' + esc(c.summary || '') + '</span>' +
          '<div class="slp-acts"><div class="slp-btn slp-text" data-a="slotplay" data-v="' + c.slot + ('">' + T('ui.play', 'Play') + '</div>') +
          '<input class="slp-slotname" data-slot="' + c.slot + '" value="' + esc(c.name) + '" maxlength="32">' +
          '<div class="slp-btn slp-text" data-a="slotname" data-v="' + c.slot + ('">' + T('ui.rename', 'Rename') + '</div>') +
          '<div class="slp-btn slp-text" data-a="slotdel" data-v="' + c.slot + '">' + (st.slotDel === c.slot ? T('ui.sure_delete', 'Sure? Delete') : T('ui.delete', 'Delete')) + '</div></div></div>';
      }).join('') + '</div>';
    }

    function askOf(n) { return arr(st.menu && st.menu.slots).filter(function (c) { return c.slot === n && c.visit; })[0]; }
    function lastSlot() { var l = arr(st.menu && st.menu.slots); return l.filter(function (c) { return c.last; })[0] || l[0]; }

    // a career left on a trip (slotVisit: { name, round, rounds, verdict 'ask' }): go back to it, or go home and count the rest as missed
    function visitAskHtml(c) {
      var v = obj(c.visit);
      return '<div class="slp-slot"><b>' + esc(c.name) + '</b><span>' + T('ui.visit_left', 'You left this career at {1}, round {2} of {3}.', esc(v.name || ''), Number(v.round) || 1, Number(v.rounds) || 1) + '</span>' +
        '<div class="slp-btn slp-go" data-a="visitgo" data-v="' + c.slot + '|resume">' + T('ui.visit_back', 'Go back to {1} (round {2} of {3})', esc(v.name || ''), Number(v.round) || 1, Number(v.rounds) || 1) + '</div>' +
        '<div class="slp-btn slp-tonal" data-a="visitgo" data-v="' + c.slot + '|home">' + T('ui.visit_home', 'Go home: the rest counts as missed') + '</div>' +
        '<div class="slp-btn slp-text" data-a="visitgo" data-v="0|cancel">' + T('ui.back', 'Back') + '</div></div>';
    }

    // the map a new career is on (W1): the installed ones as chips, the first picked unless the player picked another
    function installedMaps(m) { return arr(m && m.maps).filter(function (x) { return x.installed; }); }
    function newMapId() {
      var maps = installedMaps(st.menu);
      var picked = maps.filter(function (x) { return x.id === st.newMap; })[0] || maps[0];
      return picked ? picked.id : null;
    }
    function newMapArg() { var id = newMapId(); return id ? ', nil, ' + JSON.stringify(id) : ''; }   // (none known: the career's default)
    function mapsHtml(m) {
      var maps = installedMaps(m), pick = newMapId();
      if (maps.length < 2) return '';
      return '<div class="slp-acts">' + maps.map(function (x) {
        return '<div class="slp-btn slp-text' + (x.id === pick ? ' slp-tonal' : '') + '" data-a="newmap" data-v="' + esc(x.id) + '">' + esc(x.name) + '</div>';
      }).join('') + '</div>';
    }

    // the main menu's own Career button opens this: the game's career, or Wrench Works: Street Legal
    function menuView() {
      var m = st.menu;
      if (!m || !m.show || !st.chooser) return '';
      var askSlot = arr(m.slots).filter(function (c) { return c.slot === st.visitAsk && c.visit; })[0];
      var sl = !m.installed
        ? ('<div class="slp-chcard slp-chsl slp-off"><b>' + T('menuTile.wrench_works_street_legal', 'Wrench Works: Street Legal') + '</b><span>' + T('ui.needs_the_wrench_works_valo', 'Needs the West Coast USA map (west_coast_usa).') + '</span></div>')
        : ('<div class="slp-chcard slp-chsl"><b>' + T('menuTile.wrench_works_street_legal', 'Wrench Works: Street Legal') + '</b>') + (st.slrrArt ? slrrIcon(m.summary ? 'load_career_a.png' : 'new_career_a.png', 'slp-chimg') : '') + '<span>' + (m.summary ? T('ui.your_career_1', 'Your career: {1}', esc(m.summary)) : T('ui.no_car_5_000_and', 'No car, $5,000 and a name nobody knows. Junkyard wrecks, street racers, pink slips and the top garage.')) + '</span>' +
          (askSlot ? visitAskHtml(askSlot) : '') +
          (m.summary && !askSlot ? ('<div class="slp-btn slp-go" data-a="menustart" data-v="continue">' + T('ui.continue', 'Continue') + '</div>') : '') +
          (askSlot ? '' : slotsHtml(m)) +
          (askSlot ? '' : arr(m.slots).length < (m.maxSlots || 6)
            ? mapsHtml(m) + '<div class="slp-btn' + (m.summary ? ' slp-tonal' : ' slp-go') + ('" data-a="menustart" data-v="new">' + T('ui.new_career', 'New career') + '</div>') +
              ('<div class="slp-btn slp-tonal" data-a="menustart" data-v="newskip">' + T('ui.new_career_no_tutorial', 'New career, no tutorial') + '</div>')
            : ('<span>' + T('ui.every_career_slot_is_taken', 'Every career slot is taken: delete one to start another.') + '</span>')) + '</div>';
      return ('<div class="slp-chooser"><div class="slp-chbox"><h1>' + T('ui.career', 'Career') + '</h1><div class="slp-chcards">') +
        ('<div class="slp-chcard" data-a="chooser" data-v="beamng"><b>' + T('ui.beamng_career', 'BeamNG Career') + '</b><span>' + T('ui.the_game_s_own_career', 'The game\'s own career mode: jobs, missions, your garage and vehicles.') + '</span></div>') +
        sl + ('</div><div class="slp-chback"><div class="slp-btn slp-text" data-a="chooser" data-v="close" style="display:inline-block">' + T('ui.back', 'Back') + '</div></div></div></div>');
    }

    // catch the main menu's Career button before the game sees it (and let it through for its own career)
    var careerButton = null, letThrough = false;
    function careerButtonOf(el) {
      for (var e = el; e && e.classList; e = e.parentElement) {
        if (e.classList.contains('mainmenu-button')) {
          var label = e.querySelector('.label-container .text') || e.querySelector('.text');
          return label && label.textContent.trim() === 'Career' ? e : null;
        }
      }
      return null;
    }
    doc.addEventListener('click', function (ev) {
      if (letThrough || !st.menu || !st.menu.show) return;
      var btn = careerButtonOf(ev.target);
      if (!btn) return;
      ev.preventDefault();
      ev.stopPropagation();
      if (ev.stopImmediatePropagation) ev.stopImmediatePropagation();
      careerButton = btn;
      st.chooser = true;
      render();
    }, true);
    doc.addEventListener('keydown', function (ev) {
      if (st.chooser && (ev.key === 'Escape' || ev.keyCode === 27)) { st.chooser = false; render(); ev.stopPropagation(); }
      if (st.camOn && (ev.key === 'Escape' || ev.keyCode === 27)) { home(); ev.stopPropagation(); }      // (Esc leaves the camera: the previous camera comes back)
    }, true);

    // the fade: black, or one of SLRR's loading screens (a cab ride, the garage, the dealer)
    function fadeView() {
      return '<div class="slp-fade' + (st.fade ? ' slp-in' : '') + '"></div>';
    }

    // Hardcore: the driver died and the career is over (sl_hospital); what it came to, and what next
    function gameOverView() {
      var g = st.gameOver;
      if (!g) return '';
      var line = function (k, v) { return '<p><b>' + k + '</b> ' + v + '</p>'; };
      return ('<div class="slp-chooser"><div class="slp-chbox"><h1>' + T('ui.game_over', 'Game over') + '</h1><div class="slp-chcard slp-chsl"><b>' + T('ui.your_career_ended_on_day', 'Your career ended on day ')) + (g.day || 1) + '</b>' +
        '<span>' + esc(g.title || '') + ' &middot; ' + money(g.money || 0) + ' &middot; ' + (g.rep || 0) + ' rep</span>' +
        line(T('ui.races', 'Races'), (g.races || 0) + T('ui.won', ', won ') + (g.wins || 0)) + line(T('ui.pink_slips_won', 'Pink slips won'), g.pinksWon || 0) + line(T('ui.cars', 'Cars'), g.cars || 0) +
        line(T('ui.achievements_2', 'Achievements'), (g.achievements || 0) + ' of ' + (g.achievementsTotal || 0)) +
        ('<div class="slp-btn slp-go" data-a="gameover" data-v="new">' + T('ui.new_career', 'New career') + '</div>') +
        ('<div class="slp-btn slp-tonal" data-a="gameover" data-v="menu">' + T('ui.main_menu', 'Main menu') + '</div></div></div></div>');
    }

    // ---------------------------------------------------------------- drawing
    function render() {
      var d = st.data;
      if (d.freeroam === true && st.app !== 'home' && arr(d.apps).indexOf(st.app) < 0) { st.stack = []; st.app = 'home'; }
      if (!d.active) {
        layer.innerHTML = menuView() + gameOverView() + '<div class="slp-toast' + (st.toast ? '' : ' slp-gone') + '">' + esc(st.toast || '') + '</div>' +
          fadeView();
        navify(focusKey);
        return;
      }
      var scroll = layer.querySelector('.slp-body, .slp-msgs');
      var keep = scroll ? scroll.scrollTop : 0, keepApp = st.app;
      var repScroll0 = layer.querySelector('.slp-repbody');
      var repKeep = repScroll0 ? repScroll0.scrollTop : 0;
      var page;
      if (!d.travelPick) st.pickDismissed = null;
      if (d.travelPick && d.travelPick.eventId !== st.pickDismissed) st.app = 'pick';      // (Back dismisses it here too: the screen never traps the player if Lua does not answer)
      else if (st.app === 'pick') st.app = 'home';
      switch (st.app) {
        case 'pick': page = pickPage(); break;
        case 'event': page = hubPage(); break;
        case 'contacts': page = contactsPage(); break;
        case 'contact': page = contactPage(); break;
        case 'messages': page = messagesPage(); break;
        case 'thread': page = threadPage(); break;
        case 'phone': page = phonePage(); break;
        case 'races': page = racesPage(); break;
        case 'wait': page = waitPage(); break;
        case 'map': page = mapPage(); break;
        case 'camera': page = cameraPage(); break;
        case 'gallery': page = galleryPage(); break;
        case 'photo': page = photoPage(); break;
        case 'help': page = helpPage(); break;
        case 'helppage': page = helpTopicPage(); break;
        case 'carmarket': page = carMarketPage(); break;
        case 'partmarket': page = partMarketPage(); break;
        case 'jobs': page = jobsPage(); break;
        case 'club': page = clubPage(); break;
        case 'turf': page = turfPage(); break;
        case 'market': page = marketPage(); break;
        case 'paper': page = paperPage(); break;
        case 'bid': page = bidPage(); break;
        case 'ad': page = adPage(); break;
        case 'bank': page = bankPage(); break;
        case 'health': page = healthPage(); break;
        case 'sponsors': page = sponsorsPage(); break;
        case 'calendar': page = calendarPage(); break;
        case 'traps': page = trapsPage(); break;
        case 'inventory': page = inventoryPage(); break;
        case 'myroute': page = myroutePage(); break;
        case 'cab': page = cabPage(); break;
        case 'frjobs': page = frJobsPage(); break;
        case 'me': page = mePage(); break;
        case 'garage': page = garagePage(); break;
        case 'garagekit': page = garageKitPage(); break;
        default: page = homePage();
      }
      // #51 text size: the Text size setting, and at least Large while a pad is in use (read from a distance)
      var zoom = Math.max(Number(d.textScale) || 1, Date.now() - padAt < 60000 ? 1.25 : 1);
      layer.style.setProperty('--sl-zoom', zoom); layer.setAttribute('data-zoom', zoom);
      layer.classList.toggle('slp-cb', !!d.colorBlind);      // #51 colour-blind friendly colours
      layer.classList.toggle('slp-rm', !!d.reduceMotion);      // the Reduce motion option (docs/UI_STYLE.md)
      var camNow = !!(d.active && st.open && st.app === 'camera');      // (the Camera app is a camera: first person, the phone drawn sideways over it)
      if (camNow !== !!st.camOn) { st.camOn = camNow; if (camNow) st.cam = { zoom: 1, flash: false, grid: obj(d.camera).grid !== false }; lua(camNow ? 'cameraEnter()' : 'cameraLeave()'); }
      layer.classList.toggle('slp-camon', camNow);
      var isHome = st.app === 'home';
      var screen = '<div class="slp-screen' + (isHome ? ' slp-home-on' : '') + '"><div class="slp-cam"></div>' +
        '<div class="slp-status">' + two(d.hour || 0) + ':' + two(d.minute || 0) + '<div class="slp-sr">' + I.signal + I.wifi + I.battery + '</div></div>' +
        (isHome ? homePage() : '<div class="slp-page">' + page + '</div>') +
        (st.call ? callPage() : '') +
        '<div class="slp-nav"><div data-a="back">' + NAV.back + '</div><div data-a="home">' + NAV.home + '</div><div data-a="away">' + NAV.recent + '</div></div>' + crackHtml(d.crack, mapWanted()) + '</div>';
      var hu = st.hu;
      var huHtml = '<div class="slp-hu' + (hu && !st.open && !lotHides() && obj(d.has).hudpill !== false ? '' : ' slp-gone') + '" data-a="openthread" data-v="' + esc(hu ? hu.thread : '') + '">' +
        (hu ? avatar({ id: hu.thread, name: hu.name }) + ('<div><small>' + T('ui.messages', 'Messages ') + '&middot;' + ' now' + '</small><b>') + esc(hu.name) + '</b><span>' + esc(hu.text) + '</span></div>' : '') + '</div>';
      var html =
        '<div class="slp-pill"' + (st.open || lotHides() || obj(d.has).hudpill === false ? ' style="display:none"' : '') + '><b>' + money(d.money) + '</b><span>' + esc(d.title) + '</span>' +
          (d.phase ? '<span>' + (d.phase === 'night' ? '&#9790;' : '&#9728;') + '</span>' : '') + needsPill() + (d.heat > 0 ? '<span style="color:#ff6a4a">' + '&#9650;'.repeat(d.heat) + '</span>' : '') + (d.phase === 'night' && d.atRisk > 0 ? '<span style="color:#ffb74a">+' + d.atRisk + (T('ui.at_risk', ' at risk') + '</span>') : '') + '<span>' + two(d.hour || 0) + ':' + two(d.minute || 0) + '</span></div>' +
        '<div class="slp-device@@LAND@@' + (st.open ? '' : ' slp-away') + '" style="transform:' + (st.open ? '' : 'translateY(70%) ') + 'scale(' + scale() + ')">' + screen + '</div>' +
        lotView() + garageView() + stationView() + meetView() + raceView() +
        huHtml + reportModal() + (camNow ? camHtml() : '') +
        '<div class="slp-toast' + (st.toast ? '' : ' slp-gone') + '">' + esc(st.toast || '') + '</div>' +
        fadeView();
      // the game sends the data every few seconds: a screen that did not change is left alone (a rebuild between the press and the release of a click loses the
      // click, and drops what is typed, the hover and the scroll)
      var wantLand = mapWanted(), landChanged = wantLand !== lastLand;
      var final = html.replace('@@LAND@@', wantLand ? ' slp-land' : '');
      if (final === lastHtml && layer.firstChild) { renderSkips++; reportRenders(); return; }
      // the Map tab turns the phone to landscape: the device keeps its element, so the class changes after the first paint and the size animates (right edge fixed: it grows to the left)
      lastHtml = final; renders++; reportRenders();
      layer.innerHTML = landChanged ? final.replace('slp-device' + (wantLand ? ' slp-land' : ''), 'slp-device' + (lastLand ? ' slp-land' : '')) : final;
      if (landChanged) {
        var dv = layer.querySelector('.slp-device');
        if (dv) { void dv.offsetWidth; dv.classList.toggle('slp-land', wantLand); }
        lastLand = wantLand;
      }
      // a new app, or Home: back at the top (focus moves had scrolled the clipped screen, so the home grid came back shifted and the next tap hit another app)
      if (shownApp !== st.app) {
        // an app opened from the home screen grows out of its icon (the animation is a class on the new page; not with reduced motion: the style rule)
        var pg = layer.querySelector('.slp-page');
        if (pg && shownApp === 'home' && st.iconAt) { pg.style.transformOrigin = st.iconAt; pg.classList.add('slp-open'); }
        toTop(); shownApp = st.app;
      }
      var after = layer.querySelector('.slp-body, .slp-msgs');
      if (after) {
        if (st.app === 'thread') after.scrollTop = after.scrollHeight;
        else if (keepApp === st.app) after.scrollTop = keep;
      }
      var repScroll1 = layer.querySelector('.slp-repbody');
      if (repScroll1) repScroll1.scrollTop = repKeep;
      navify(focusKey);
      syncMapFeed();
      MV.last = 0;
      paintMap();
    }

    // ---------------------------------------------------------------- gamepad (BeamNG's UI navigation, X51)
    // The game moves focus between [bng-nav-item] elements with the d-pad/stick and clicks the focused one on A;
    // our buttons are data-a divs, so they get bng-nav-item and a tabindex while they can be seen (a phone put
    // away or a hidden panel never takes the focus), the pages scroll on the right stick, and the focus survives
    // a re-render (the same button again, else the first one).
    var focusKey = null, lastHtml = null;
    var renders = 0, renderSkips = 0, reportAt = 0;      // how often the screen was rebuilt and how often that was skipped as unchanged: told to the overlay (sl_uipush) every 5 s
    function reportRenders() {
      var now = Date.now();
      if (now - reportAt < 5000) return;
      reportAt = now;
      lua('@sl_uipush.js("phone",' + renders + ',' + renderSkips + ')');
      renders = 0; renderSkips = 0;
    }
    var padAt = 0;          // the last pad input: only then does the phone take the focus (mouse and keyboard keep theirs)
    function keyOf(el) { return el && el.getAttribute ? (el.getAttribute('data-a') || '') + '|' + (el.getAttribute('data-v') || '') : null; }
    function navify(key) {
      var device = layer.querySelector('.slp-device');
      var items = layer.querySelectorAll('[data-a]');
      var first = null, again = null, panel = null;
      var modal = layer.querySelector('.slp-repmodal');
      var PANELS = '.slp-lot, .slp-meet, .slp-race, .slp-chooser, .slp-chcard';      // what opens without the phone
      for (var i = 0; i < items.length; i++) {
        var el = items[i];
        var hidden = (modal && !modal.contains(el)) || (device && device.contains(el) && !st.open) || (el.closest && el.closest('.slp-gone')) || el.classList.contains('slp-gone');
        if (hidden) { el.setAttribute('bng-no-nav', 'true'); el.removeAttribute('bng-nav-item'); el.removeAttribute('tabindex'); continue; }
        el.setAttribute('bng-nav-item', '');
        el.setAttribute('tabindex', '0');
        el.removeAttribute('bng-no-nav');
        if (!first && el.getAttribute('data-a') !== 'back' && el.getAttribute('data-a') !== 'home' && el.getAttribute('data-a') !== 'away') first = el;
        if (key && !again && keyOf(el) === key) again = el;
        if (!panel && el.closest && el.closest(PANELS)) panel = el;
      }
      var pages = layer.querySelectorAll('.slp-body, .slp-msgs, .slp-repbody');
      for (var j = 0; j < pages.length; j++) pages[j].setAttribute('bng-nav-scroll', '');
      var active = doc.activeElement;
      var inside = active && layer.contains(active) && active.hasAttribute && active.hasAttribute('bng-nav-item');
      var padding = Date.now() - padAt < 15000;
      var target = again || (padding && !inside ? (modal ? modal.querySelector('[data-a="repsec"], [data-a="reportclose"]') : st.open ? first : panel) : null);
      if (target && target !== active && target.focus) target.focus({ preventScroll: true });      // (BUGS_1018 #9: a plain focus() scrolled the home screen 171 px, the focus ring brings the control into view)
    }
    // drag the report's body to scroll it (the wheel and the pad work by themselves)
    var drag = null;
    layer.addEventListener('mousedown', function (ev) {
      var rb = ev.target && ev.target.closest && ev.target.closest('.slp-repbody');
      if (rb && !(ev.target.closest('[data-a]'))) drag = { rb: rb, y: ev.clientY, top: rb.scrollTop };
    });
    layer.addEventListener('mousemove', function (ev) { if (drag) drag.rb.scrollTop = drag.top - (ev.clientY - drag.y); });
    layer.addEventListener('mouseup', function () { drag = null; });
    layer.addEventListener('mouseleave', function () { drag = null; });
    doc.addEventListener('focusin', function (ev) { focusKey = layer.contains(ev.target) ? keyOf(ev.target) : null; }, true);   // (elsewhere: leave it there)
    // B on the pad: back a page (and put the phone away from its home screen) instead of opening the game's menu
    (doc.defaultView || doc).addEventListener('ui_nav', function (ev) {      // (window capture: before the game's document handler)
      var d = ev.detail || {};
      padAt = Date.now();
      // a lot being looked at: the right stick turns the camera round the car, the zoom buttons zoom (what the mouse does on the catch layer)
      if (st.repOpen) {                      // the report panel: the right stick scrolls it
        var rb = layer.querySelector('.slp-repbody');
        var sv = Number(d.value) || 0;
        if (rb && d.name === 'rotate_v_cam' && Math.abs(sv) > 0.15) rb.scrollTop += sv * 40;
      } else if (!st.open && st.lot && st.lot.open && st.lot.mode === 'browse') {
        var v = Number(d.value) || 0;
        if (d.name === 'rotate_h_cam' && Math.abs(v) > 0.15) lua('@sl_lot.cameraDrag(' + Math.round(v * 10) + ',0)');
        else if (d.name === 'rotate_v_cam' && Math.abs(v) > 0.15) lua('@sl_lot.cameraDrag(0,' + Math.round(v * 8) + ')');
        else if ((d.name === 'zoom_in' || d.name === 'zoom_out') && v === 1) lua('@sl_lot.cameraZoom(' + (d.name === 'zoom_in' ? 1 : -1) + ')');
      }
      if (d.name !== 'back' || d.value !== 1) return;
      if (st.repOpen) { st.repOpen = null; render(); }       // B closes the report panel first
      else if (st.open) back();
      else {
        // B leaves what opens without the phone (a lot, a car meet, a gas station, the career chooser) through its own leave button
        var panel = layer.querySelector('.slp-lot, .slp-meet, .slp-chooser');
        var leave = panel && panel.querySelector('.slp-lotleave [data-a], .slp-chback [data-a]');
        if (!leave) return;
        leave.click();
      }
      if (ev.stopImmediatePropagation) ev.stopImmediatePropagation();
      if (ev.preventDefault) ev.preventDefault();
    }, true);

    function scale() {
      var h = (doc.defaultView && doc.defaultView.innerHeight) || 1080;
      return Math.max(0.4, Math.min(1.2, (h - 40) / 760, h * 0.78 / 760)).toFixed(3);
    }

    // Free roam (a phone outside a career: data.freeroam, data.apps = the app ids it has, e.g. map and cab): only those apps are shown. One rule at the one place every route ends up in
    // (render): a screen that is not one of those apps (a sub-screen of another app, a thread, a help page, a screen a Back pops to) becomes the home screen and the stack is cleared.
    function inFreeroam(id) {
      var d = st.data;
      return !(d && d.freeroam === true) || arr(d.apps).indexOf(id) >= 0;
    }
    // ---------------------------------------------------------------- what the buttons do
    function go(app, params) {
      st.stack.push({ app: st.app, contact: st.contact, thread: st.thread });
      st.app = app;
      if (app === 'gallery') lua('photos()');
      if (app === 'contacts') lua('people()');
      if (app === 'map') { st.tab.map = 'map'; st.mapAt = Date.now(); lua('mapPlaces()'); }      // (the Map app opens on the map)
      if (app === 'help' && !arr(st.help).length) lua('requestHelp()');
      if (app === 'carmarket') { st.cmView = 'dealers'; lua('@sl_dealers.list()'); }
      if (app === 'me') lua('@sl_rivals.list()');
      if (params) for (var k in params) st[k] = params[k];
      if (app === 'thread' && st.thread) { lua('markRead(' + JSON.stringify(st.thread) + ')'); var u = obj(st.data.unread); delete u[st.thread]; }
      render();
    }
    function back() {
      if (st.call) { hang(); return; }
      if (st.app === 'carmarket' && st.tab.cars === 'dealers' && st.cmView !== 'dealers') {      // an offer to its dealer's list, the list to the dealers
        if (st.cmView === 'offer') st.cmView = 'offers'; else { st.cmView = 'dealers'; lua('@sl_dealers.list()'); }
        render();
        return;
      }
      var prev = st.stack.pop();
      if (!prev) { setOpen(false); return; }
      st.app = prev.app; st.contact = prev.contact; st.thread = prev.thread;
      if (st.app !== 'carmarket') lua('@sl_carauctions.view(false)');
      render();
    }
    var shownApp = null;
    function toTop() {
      layer.scrollTop = 0;
      Array.prototype.forEach.call(layer.querySelectorAll('.slp-screen, .slp-home, .slp-grid, .slp-page'), function (e) { e.scrollTop = 0; });
    }
    function home() { st.stack = []; st.app = 'home'; lua('@sl_carauctions.view(false)'); toTop(); render(); }
    // K with the Maps HUD app on screen: the phone turns out of the landscape app and slides to its place at the right edge (and back when it closes).
    // The app tells us where it is (window.slMapsHud = { rect(), setHidden(b) }); a missing app, no layout, reduced motion, the Mods switch off or any error in here
    // leaves the plain open and close. The animation is a Web Animations transform on the phone's own element (centre origin), so when it ends or is cut short the
    // phone is at rest where the style puts it.
    // slide: 'in' | 'out' while the animation runs; intent: the last K press during it (true open, false close, applied when the slide ends: three presses are three toggles);
    // slideSeq makes the callbacks of an older slide harmless
    var slide = null, intent = null, slideSeq = 0;
    function hudApp() {
      var h = win.slMapsHud;
      if (!h || typeof h.rect !== 'function' || MV.opts.slide === false || (st.data && st.data.reduceMotion)) return null;      // (no slide with Reduce motion: the plain open and close)
      try { if (win.matchMedia && win.matchMedia('(prefers-reduced-motion: reduce)').matches) return null; } catch (e) { return null; }
      return h;
    }
    function slideFrames(dv, A) {
      var R = dv.getBoundingClientRect(), w = dv.offsetWidth, h = dv.offsetHeight;
      if (!(R.width > 0 && w > 0 && h > 0 && A && A.width > 40 && A.height > 40 && typeof dv.animate === 'function')) return null;
      var s = R.width / w, cx = R.right - w / 2, cy = R.bottom - h / 2;                 // (the phone is scaled about its bottom right corner)
      var k = Math.min(A.width / h, A.height / w);                                      // (turned a quarter, it fits the app's rectangle)
      var from = 'translate(' + (A.left + A.width / 2 - cx) + 'px,' + (A.top + A.height / 2 - cy) + 'px) rotate(-90deg) scale(' + k + ')';
      var to = 'translate(' + (1 - s) * w / 2 + 'px,' + (1 - s) * h / 2 + 'px) scale(' + s + ')';
      return [{ transform: from, transformOrigin: '50% 50%', opacity: 0.85 }, { transform: to, transformOrigin: '50% 50%', opacity: 1 }];
    }
    function hudShow() { try { var h = win.slMapsHud; if (h && h.setHidden) h.setHidden(false); } catch (e) { /* the app is gone */ } }
    function slideIn() {
      var h = hudApp();
      if (!h) return;
      try {
        var dv = layer.querySelector('.slp-device'), fr = dv && slideFrames(dv, h.rect());
        if (!fr) return;
        h.setHidden(true);
        var seq = ++slideSeq, a = dv.animate(fr, { duration: 420, easing: 'cubic-bezier(.2,.9,.25,1)' }), done = false;
        slide = 'in';
        var end = function () { if (done || seq !== slideSeq) return; done = true; endSlide(); };
        if ('onfinish' in a) a.onfinish = end;
        clock.set(end, 520);                                                            // (an animation that never reports back must not hold the phone)
      } catch (e) { slide = null; hudShow(); }
    }
    // a slide is over: a press made during it is applied now
    function endSlide() {
      var want = intent;
      intent = null; slide = null;
      if (want !== null && want !== st.open) setOpen(want);
    }
    // closing: the phone turns back into the app first, then the normal close; false when it cannot (the caller closes at once)
    function slideOut(then) {
      var h = hudApp();
      if (!h || slide) return false;
      try {
        var dv = layer.querySelector('.slp-device'), fr = dv && slideFrames(dv, h.rect());
        if (!fr) return false;
        var seq = ++slideSeq;
        slide = 'out';
        var a = dv.animate(fr.slice().reverse(), { duration: 360, easing: 'cubic-bezier(.4,0,.6,1)', fill: 'forwards' }), done = false;
        var finish = function () {
          if (done || seq !== slideSeq) return;
          done = true;
          var want = intent;
          intent = null; slide = null;
          if (want === true) { try { a.cancel(); } catch (e) { /* no animation left */ } slideIn(); return; }      // (pressed again while it closed: the phone stays up)
          then();
        };
        if ('onfinish' in a) a.onfinish = finish; else { slide = null; return false; }
        clock.set(finish, 500);                                                         // (an animation that never reports back must not keep the phone open)
        return true;
      } catch (e) { slide = null; hudShow(); return false; }
    }
    function setOpen(open, plain) {
      if (slide && !plain) { intent = (open === (slide === 'in')) ? null : open; return; }      // (during a slide only the last press counts: it is applied when the slide ends)
      if (!open && st.open && !plain && slideOut(function () { setOpen(false, true); })) return;
      st.open = open;
      lua('uiOpen("phone", ' + (open ? 'true' : 'false') + ')');      // (the game side sends the phone's data faster while it is open)
      if (open && !TABLE) lua('requestStrings()');
      if (!open && !slide) hudShow();
      if (open) lua('request()'); else { st.stack = []; st.app = 'home'; lua('@sl_carauctions.view(false)'); }      // (B68: closed, it opens on the home screen next time)
      render();
      if (open) slideIn();
    }
    function startCall(id) {
      st.call = { id: id, phase: 'ringing', started: clock.now(), result: null };
      lua('call(' + JSON.stringify(id) + ')');
      render();
    }
    function settleCall() {
      var c = st.call;
      if (!c || !c.result || c.phase !== 'ringing') return;
      var wait = 1800 - (clock.now() - c.started);       // let it ring a moment
      if (wait > 0) { clock.clear(ringTimer); ringTimer = clock.set(settleCall, wait); return; }
      c.phase = c.result.answered ? 'talking' : 'ended';
      c.greeting = c.result.greeting; c.text = c.result.text; c.options = arr(c.result.options);
      render();
    }
    function hang() { clock.clear(ringTimer); st.call = null; render(); }

    function act(a, v) {
      switch (a) {
        case 'open': go(v); break;
        case 'helppage': go('helppage', { helpId: v }); break;
        case 'back': if (st.app === 'calendar' && st.calEvent) { st.calEvent = null; render(); } else back(); break;      // (on a Calendar event page Back returns to the list)
        case 'home': home(); break;
        case 'away': setOpen(false); break;
        case 'contact': go('contact', { contact: v }); break;
        case 'thread': go('thread', { thread: v }); break;
        case 'openthread': if (v) { st.hu = null; st.open = true; st.stack = []; st.app = 'messages'; go('thread', { thread: v }); } break;
        case 'call': startCall(v); break;
        case 'hang': hang(); break;
        case 'stake': lua('challenge(' + JSON.stringify(st.call.id) + ',' + JSON.stringify(v) + ')'); st.call.options = []; render(); break;
        case 'text': lua('text(' + JSON.stringify(st.thread) + ',' + JSON.stringify(v) + ')'); break;
        case 'gps': lua('waypoint(' + JSON.stringify(v) + ')'); toast(T('ui.the_route_is_on_your', 'The route is on your road.')); break;
        case 'cancel': lua('cancel(' + JSON.stringify(v) + ')'); break;
        case 'raise': lua('raise(' + JSON.stringify(v) + ')'); break;
        case 'league': lua('enterLeague(' + JSON.stringify(v) + ')'); break;
        case 'watchreplay': lua('watchReplay()'); break;
        case 'saveclip': lua('saveClip()'); break;
        case 'adview': go('ad', { adId: v }); break;
        case 'report': st.repOpen = v; st.repKeep = reports[v] || null; st.repSec = {}; render(); break;
        case 'reportclose': st.repOpen = null; render(); break;
        case 'repsec': var rpOpen = st.repOpen && reports[st.repOpen]; if (rpOpen) { st.repSec[v] = !repOpen(rpOpen, v); render(); } break;
        case 'workon': lua('workOn(' + Number(v) + ')'); st.garage = null; break;
        case 'despawn': lua('despawn(' + Number(v) + ')'); break;
        case 'garageclose': lua('closeGarage()'); st.garage = null; render(); break;
        case 'mapzoom': MV.zoomed = true; MV.mpp = Math.max(0.5, Math.min(12, MV.mpp * (v === 'in' ? 0.7 : 1.43))); MV.last = 0; paintMap(); break;
        case 'tyreswap': lua('@sl_tyrecare.swap(' + JSON.stringify(String(v)) + ')'); break;
        case 'route': lua('routeTo(' + JSON.stringify(String(v)) + ')'); break;
        case 'routegarage': lua('routeGarage()'); break;
        case 'clearroute': lua('clearRoute()'); break;
        case 'photo': lua('takePhoto()'); break;
        case 'photoopen': go('photo', { photoFile: v }); break;
        case 'setwall': (function () { var q = String(v).split('|'); lua('setWallpaper(' + JSON.stringify(q[0]) + ',' + JSON.stringify(q[1] || '') + ')'); })(); break;
        case 'mtab': var tp = String(v).split('|'); st.tab[tp[0]] = tp[1]; if (tp[0] === 'cars' && tp[1] === 'dealers') { st.cmView = 'dealers'; lua('@sl_dealers.list()'); }
        if (tp[0] === 'cars') lua('@sl_carauctions.view(' + (tp[1] === 'auction' ? 'true' : 'false') + ')');
        render(); break;
        case 'mdealer': st.cmView = 'offers'; st.offers = { name: T('ui.dealer', 'Dealer'), offers: [], dealer: v }; lua('@sl_dealers.offers(' + JSON.stringify(v) + ')'); render(); break;
        case 'moffer': st.cmView = 'offer'; st.cmOffer = v; render(); break;
        case 'mbuy': var bp = String(v).split('|'); lua('@sl_dealers.buy(' + JSON.stringify(bp[0]) + ',' + JSON.stringify(bp[1]) + ')'); break;
        case 'pcatalog': lua('catalog()'); break;
        case 'wait': lua('wait(' + JSON.stringify(String(v)) + ')'); break;
        case 'borrow': lua('borrow(' + Number(v) + ')'); break;
        case 'repay': lua('repay(' + Number(v) + ')'); break;
        case 'economy': lua('economyOptIn()'); break;
        case 'frtake': lua('frjobAccept(' + JSON.stringify(String(v)) + ')'); break;
        case 'frcancel': lua('frjobCancel()'); break;
        case 'paydebt': lua('payDebt(' + Number(v) + ')'); break;
        case 'eat': lua('eat(' + JSON.stringify(String(v)) + ')'); break;
        case 'nap': lua('nap(' + Number(v) + ')'); break;
        case 'spnaccept': lua('sponsorAccept()'); break;
        case 'spndecline': lua('sponsorDecline()'); break;
        case 'spnquit':
          if (v === '0') st.spnQuit = false;
          else if (!st.spnQuit) st.spnQuit = true;      // (the deal does not come back: ask once more)
          else { st.spnQuit = false; lua('sponsorQuit()'); }
          render(); break;
        case 'caltab': st.calTab = String(v); st.calDay = null; render(); break;
        case 'calday': st.calDay = v === '' ? null : Number(v); render(); break;
        case 'calopen': st.calEvent = String(v); render(); break;
        case 'calenter': lua('calendarEnter(' + JSON.stringify(String(v)) + ')'); break;
        case 'caldecline': lua('calendarDecline(' + JSON.stringify(String(v)) + ')'); st.calEvent = null; break;
        case 'calremind': var cr = String(v).split('|'); lua('calendarRemind(' + JSON.stringify(cr[0]) + ',' + (cr[1] === 'true' ? 'true' : 'false') + ')'); break;
        case 'seasonenter': lua('seasonEnter()'); break;
        case 'camzoom': st.cam = st.cam || {}; st.cam.zoom = Number(v) || 1; lua('cameraZoom(' + (Number(v) || 1) + ')'); render(); break;
        case 'camflash': st.cam = st.cam || {}; st.cam.flash = !st.cam.flash; render(); break;
        case 'camgrid': st.cam = st.cam || {}; st.cam.grid = !st.cam.grid; render(); break;
        case 'caltravel': st.pickDismissed = null; lua('travelPick(' + JSON.stringify(String(v)) + ')'); break;
        case 'pickcar':
          var ps = arr(st.pickSel).slice(), pi = ps.indexOf(String(v));
          if (pi >= 0) ps.splice(pi, 1); else ps.push(String(v));
          st.pickSel = ps; render(); break;
        case 'pickloaner': st.pickLoaner = !st.pickLoaner; render(); break;
        case 'pickconfirm':
          if (arr(st.pickSel).length || st.pickLoaner) lua('travelConfirm(' + JSON.stringify(String(obj(st.data.travelPick).eventId)) + ',' + JSON.stringify(arr(st.pickSel)) + ',' + (st.pickLoaner ? 'true' : 'false') + ')');
          break;
        case 'pickback': st.pickFor = null; st.pickDismissed = obj(st.data.travelPick).eventId; lua('travelClose()'); render(); break;      // (the next time starts with no cars picked)
        case 'hubstart': lua('hubStart()'); break;
        case 'hubhome':
          if (v === '0') st.hubHome = false;
          else if (!st.hubHome) st.hubHome = true;      // (the rest counts as missed: ask once more)
          else { st.hubHome = false; lua('hubHome()'); }
          render(); break;
        case 'service': var sp = String(v).split('|'); lua('service(' + Number(sp[0]) + ',' + JSON.stringify(sp[1] || '') + ')'); break;
        case 'insure': lua('insure(' + (v === 'true' ? 'true' : 'false') + ')'); break;
        case 'tutskip': lua('@sl_tutorial.skip()'); break;
        case 'jobtake': lua('takeJob(' + JSON.stringify(v) + ')'); break;
        case 'mkoffer': lua('marketOffer(' + JSON.stringify(String(v).split('|')[0]) + ',' + Number(String(v).split('|')[1]) + ')'); break;
        case 'mklist': (function () { var q = String(v).split('|'); lua('listPart(' + JSON.stringify(q[0]) + ',' + Number(q[1]) + ',' + JSON.stringify(q[2]) + ')'); })(); break;
        case 'mkaccept': lua('acceptOffer(' + JSON.stringify(String(v).split('|')[0]) + ',' + Number(String(v).split('|')[1]) + ')'); break;
        case 'mkcar': lua('listCar(' + JSON.stringify(v) + ')'); break;
        case 'mkwithdraw': lua('withdrawListing(' + JSON.stringify(v) + ')'); break;
        case 'mkmeet': lua('buyAtMeet(' + JSON.stringify(v) + ')'); break;
        case 'mkbid': lua('marketBid(' + JSON.stringify(v) + ')'); break;
        case 'rvyes': lua('@sl_rivals.accept(' + JSON.stringify(String(v)) + ')'); break;
        case 'rvmoney': lua('@sl_rivals.decline(' + JSON.stringify(String(v)) + ',true)'); break;
        case 'rvno': lua('@sl_rivals.decline(' + JSON.stringify(String(v)) + ',false)'); break;
        case 'abid': var ab = String(v).split('|'); lua('@sl_carauctions.bid(' + JSON.stringify(ab[0]) + ',' + Number(ab[1]) + ')'); break;
        case 'awatch': var aw = String(v).split('|'); lua('@sl_carauctions.watch(' + JSON.stringify(aw[0]) + ',' + (aw[1] === '1' ? 'true' : 'false') + ')'); break;
        case 'asell': var as = String(v).split('|'); lua('@sl_carauctions.sell(' + Number(as[0]) + ',' + Number(as[1]) + ')'); break;
        case 'buypaper': lua('buyPaper()'); break;
        case 'mkcheck': lua('marketCheck(' + JSON.stringify(String(v)) + ')'); break;
        case 'mkbuy': lua('marketBuy(' + JSON.stringify(String(v).split('|')[0]) + ',' + JSON.stringify(String(v).split('|')[1]) + ')'); break;
        case 'jobquit': lua('giveUpJob()'); break;
        case 'jobway': lua('jobWay()'); toast(T('ui.the_route_is_on_your', 'The route is on your road.')); break;
        case 'taxi': lua('taxi(' + JSON.stringify(v) + ')'); break;
        case 'tow': lua('tow(' + Number(v) + ')'); break;
        case 'upgrade': lua('upgrade(' + JSON.stringify(v) + ')'); break;
        case 'release': lua('release(' + Number(v) + ')'); break;
        case 'usecar': lua('useCar(' + Number(v) + ')'); break;
        case 'move': lua('moveGarage()'); break;
        case 'roc': lua('enterRoc()'); setOpen(false); break;
        case 'lot': if (/^[a-zA-Z]+\(\d*\)$/.test(v)) lua('@sl_lot.' + v); break;
        case 'meet': var parts = String(v).split('|'); lua('@sl_streets.meetChallenge(' + JSON.stringify(parts[0]) + ',' + JSON.stringify(parts[1]) + ')'); break;
        case 'slotedit': st.slotEdit = true; render(); break;
        case 'gameover':
          st.gameOver = null; render();
          if (v === 'new') lua('@sl_menuTile.startFromMenu(true' + newMapArg() + ')'); else lua('@sl_menuTile.toMainMenu()');
          break;
        case 'visitgo':
          var vg = String(v).split('|');
          if (vg[1] === 'cancel') { st.visitAsk = null; render(); break; }
          lua('@sl_menuTile.startFromMenu(false,' + Number(vg[0]) + ',nil,' + JSON.stringify(vg[1]) + ')'); st.visitAsk = null; st.menu = null; st.chooser = false; render();
          break;
        case 'slotplay':
          if (askOf(Number(v))) { st.visitAsk = Number(v); render(); break; }
          lua('@sl_menuTile.startFromMenu(false,' + Number(v) + ')'); st.menu = null; st.chooser = false; render(); break;
        case 'invuse': lua('@sl_inventory.use(' + JSON.stringify(String(v)) + ')'); break;
        case 'invdrop':
          if (st.invDrop !== v) { st.invDrop = v; render(); break; }
          st.invDrop = null;
          var ip = String(v).split(':');
          lua('@sl_inventory.discard(' + JSON.stringify(ip[0]) + ',' + (ip[0] === 'can' ? Number(ip[1]) : JSON.stringify(ip[1])) + ')');
          break;
        case 'routedrop': lua('@sl_myroute.drop()'); break;
        case 'routeundo': lua('@sl_myroute.undo()'); break;
        case 'routediscard': lua('@sl_myroute.discard()'); break;
        case 'routestop': lua('@sl_myroute.cancel()'); break;
        case 'routerace': lua('@sl_myroute.race(' + Number(v) + ')'); break;
        case 'routesave':
          var rn = root.querySelector('.slp-routename');
          lua('@sl_myroute.save(' + JSON.stringify(String(rn && rn.value || '')) + ')');
          break;
        case 'routedel':
          if (st.routeDel !== Number(v)) { st.routeDel = Number(v); toast(T('ui.click_again_to_delete_that', 'Click again to delete that career for good.')); render(); break; }
          st.routeDel = null; lua('@sl_myroute.delete(' + Number(v) + ')');
          break;
        case 'slotname':
          var inp = root.querySelector('.slp-slotname[data-slot="' + Number(v) + '"]');
          if (inp) lua('@sl_menuTile.renameSlot(' + Number(v) + ',' + JSON.stringify(String(inp.value || '')) + ')');
          break;
        case 'slotdel':
          if (st.slotDel !== Number(v)) { st.slotDel = Number(v); toast(T('ui.click_again_to_delete_that', 'Click again to delete that career for good.')); render(); break; }
          st.slotDel = null; lua('@sl_menuTile.deleteSlot(' + Number(v) + ')');
          break;
        case 'newmap': st.newMap = v; render(); break;
        case 'menustart':
          if (v === 'continue') { var lastC = lastSlot(); if (lastC && lastC.visit) { st.visitAsk = lastC.slot; render(); break; } }
          if (v === 'newskip') lua('@sl_tutorial.skipNextCareer()');
          lua('@sl_menuTile.startFromMenu(' + (v === 'new' || v === 'newskip' ? 'true' + newMapArg() : 'false') + ')');
          st.menu = null; st.chooser = false; render();
          break;
        case 'chooser':
          st.chooser = false; render();
          if (v === 'beamng' && careerButton) { letThrough = true; try { careerButton.click(); } finally { letThrough = false; } }
          break;
        case 'fuelpick': st.fuelPick = v; render(); break;
        case 'station':
          var sv = String(v).split('|');
          if (sv[0] === 'close') { lua('@sl_station.close()'); st.station = null; render(); }
          else if (sv[0] === 'fill') lua('@sl_station.fill(' + JSON.stringify(sv[1]) + ')');
          else if (sv[0] === 'wash') lua('@sl_station.wash()');
          else if (sv[0] === 'buy') lua('@sl_station.buy(' + JSON.stringify(sv[1]) + ',' + JSON.stringify(st.fuelPick || 'premium') + ')');
          break;
        case 'useitem': var ui = String(v).split('|'); lua('useItem(' + Number(ui[0]) + ',' + JSON.stringify(ui[1]) + ')'); break;
        case 'meetclose': lua('@sl_streets.closeMeet()'); st.meet = null; render(); break;
        case 'meetshow': lua('@sl_streets.showAndShine()'); break;
        case 'meettalk': lua('@sl_streets.meetTalk(' + JSON.stringify(String(v)) + ')'); break;
        case 'key': if (st.dial.length < 12) st.dial += v; render(); break;
        case 'del': st.dial = st.dial.slice(0, -1); render(); break;
        case 'dial': var who = dialMatch(); if (who) startCall(who.id); else if (st.dial) toast(T('phone.the_number_you_have_dialled', 'The number you have dialled is not available.')); break;
      }
    }

    function toast(text) {
      st.toast = text;
      clock.clear(toastTimer);
      toastTimer = clock.set(function () { st.toast = null; render(); }, 3500);
      render();
    }

    // right-drag over the lot turns the camera round the car, the wheel zooms
    var drag = null;
    root.addEventListener('mousedown', function (ev) {
      if (ev.target && ev.target.getAttribute && ev.target.getAttribute('data-catch') === 'lot') {
        ev.preventDefault();
        drag = { x: ev.clientX, y: ev.clientY };
      }
    });
    var win = doc.defaultView || {};
    if (win.addEventListener) {
      win.addEventListener('mousemove', function (ev) {
        if (!drag) return;
        var dx = ev.clientX - drag.x, dy = ev.clientY - drag.y;
        drag = { x: ev.clientX, y: ev.clientY };
        if (dx || dy) lua('@sl_lot.cameraDrag(' + dx + ',' + dy + ')');
      });
      win.addEventListener('mouseup', function () { drag = null; });
    }
    root.addEventListener('wheel', function (ev) {
      if (ev.target && ev.target.getAttribute && ev.target.getAttribute('data-catch') === 'lot') lua('@sl_lot.cameraZoom(' + (ev.deltaY < 0 ? 1 : -1) + ')');
    });
    root.addEventListener('contextmenu', function (ev) { if (st.lot && st.lot.open) ev.preventDefault(); });

    root.addEventListener('click', function (ev) {
      var el = ev.target;
      while (el && el !== root && !(el.getAttribute && el.getAttribute('data-a'))) el = el.parentNode;
      if (!el || el === root) return;
      ev.stopPropagation();
      if (el.getAttribute('data-a') === 'open') {                  // where the icon is, for the app to grow out of
        var sc = layer.querySelector('.slp-screen'), r = el.getBoundingClientRect(), sr = sc ? sc.getBoundingClientRect() : null;
        st.iconAt = sr && r.width ? Math.round(r.left + r.width / 2 - sr.left) + 'px ' + Math.round(r.top + r.height / 2 - sr.top) + 'px' : null;
      }
      act(el.getAttribute('data-a'), el.getAttribute('data-v'));
    });

    // ---------------------------------------------------------------- what Lua says
    function handle(name, data) {
      data = data || {};
      if (!st.open && slide !== 'out') hudShow();                                  // (never leave the Maps app hidden behind a closed phone)
      switch (name) {
        case 'slMapsTiles': Object.keys(data.tiles || {}).forEach(function (k) { MV.tiles[k] = data.tiles[k]; }); MV.key = ''; paintMap(); break;
        case 'slMapsPose': MV.pose = data; paintMap(); break;
        case 'slMapsRoute': MV.route = data.route || []; paintMap(); break;
        case 'slMapsOptions': MV.opts = data || MV.opts; if (data && data.mpp && !MV.zoomed) MV.mpp = data.mpp; MV.key = ''; paintMap(); break;
        case 'slMapsPlaces': MV.places = data.places || []; break;
        case 'slPhoneData':
          st.data = data;
          if (!data.active) { st.open = false; st.call = null; st.hu = null; slide = null; intent = null; slideSeq++; hudShow(); }
          if (st.open && st.app === 'map' && Date.now() - (st.mapAt || 0) > 4000) { st.mapAt = Date.now(); lua('mapPlaces()'); }      // (the distances follow the car)
          render();
          break;
        case 'slPhoneToggle': setOpen(!(intent !== null ? intent : (slide === 'out' ? false : st.open))); break;
        case 'slPhoneGo': if (!st.open) setOpen(true); st.stack = []; st.app = 'home'; if (data.app && data.app !== 'home') go(data.app); else render();
          if (data.tabs) { Object.keys(data.tabs).forEach(function (k) { st.tab[k] = data.tabs[k]; }); render(); }
          break;      // (a game test: open this app; the yard auction opens the Car auctions tab)
        case 'slPhoneCall':
          if (st.call && st.call.id === data.id) { st.call.result = data; settleCall(); }
          break;
        case 'slPhoneCallReply':
          if (st.call && st.call.id === data.id) { st.call.reply = data.text; st.call.challenge = data.accept ? data.challenge : null; render(); }
          break;
        case 'slPhoneNotify':
          if (st.open && st.app === 'thread' && st.thread === data.thread) { lua('markRead(' + JSON.stringify(data.thread) + ')'); break; }
          st.hu = { thread: data.thread, name: data.name, text: data.text };
          clock.clear(huTimer);
          huTimer = clock.set(function () { st.hu = null; render(); }, 6000);
          render();
          break;
        case 'slPhoneToast': toast(data.text); break;
        case 'slGameOver': st.gameOver = data && data.day ? data : null; render(); break;
        case 'slFade': st.fade = !!data.on; render(); break;
        case 'slLotBars': bars.classList.toggle('slp-on', !!data.on); layer.classList.toggle('slp-barson', !!data.on); break;
        case 'slLotData':
          st.lot = data.open ? data : null;
          if (!data.open) { bars.classList.remove('slp-on'); layer.classList.remove('slp-barson'); }      // (no lot: no bars, whatever the Lua side last said)
          render();
          break;
        case 'slMeet': st.meet = data.open ? data : null; render(); break;
        case 'slStation': st.station = data.open ? data : null; render(); break;
        case 'slGarage': st.garage = data.open ? data : null; render(); break;
        case 'slPhotos': st.photos = data; render(); break;
        case 'slMap': st.map = data; render(); break;
        case 'slPeople': st.people = data; render(); break;
        case 'slHelp': st.help = arr(data && data.pages); render(); break;
        case 'slStrings': TABLE = (data && data.text) || {}; render(); break;
        case 'slPhoneSkin': applySkin(data); render(); break;
        case 'slLaptopDealers': st.dealers = data; render(); break;
        case 'slAuctions': st.auction = data; render(); break;
        case 'slRivals': st.rivals = data; render(); break;
        case 'slLaptopOffers': st.offers = data; render(); break;
        case 'slRace': st.race = data.on ? data : null; render(); break;
        case 'slMenu': st.menu = data.show ? data : null; render(); break;
        case 'slrrGarageState': if (data && data.phase && data.phase !== 'idle' && st.open) setOpen(false, true); break;      // (Wrench Works' garage: its screens take the right of the view, the phone is put away while a visit is on)
        case 'slArt': st.slrrArt = true; render(); break;
      }
    }

    render();
    return { handle: handle, state: st, act: act, root: root };
  }

  if (typeof window !== 'undefined') window.__slPhoneCreate = createPhone;

  // in the game: one phone for the whole UI, fed by the Lua side's events
  if (typeof angular !== 'undefined' && typeof window !== 'undefined' && !window.__slPhoneTest) {
    angular.module('slPhone', []).run(['$rootScope', function ($rootScope) {
      if (window.__slPhone) return;
      var phone = createPhone(document, function (call) {
        if (!window.bngApi) return;
        // '@sl_lot.next()' goes to another extension than the phone's
        if (call.charAt(0) === '@') {
          var ext = call.slice(1).split('.')[0];
          window.bngApi.engineLua('if ' + ext + ' then ' + call.slice(1) + ' end');
        } else {
          window.bngApi.engineLua('if sl_phone then sl_phone.' + call + ' end');
        }
      });
      window.__slPhone = phone;
      // SLRR's art, when the player has copied it from their SLRR (tools/slrr_ui.py)
      // (asked for only when the game side says the art is there: the released pack has none, and a missing picture is a 404 in the log)
      var probed = false;
      $rootScope.$on('slPhoneData', function (ev, data) {
        if (probed || !data || data.art !== true) return;
        probed = true;
        var probe = new Image();
        probe.onload = function () { phone.handle('slArt'); };
        probe.src = '/ui/modModules/slHud/slrr/icons/cup.png';
      });
      ['slPhoneData', 'slPhoneSkin', 'slPhoneToggle', 'slPhoneGo', 'slPhoneCall', 'slPhoneCallReply', 'slPhoneNotify', 'slPhoneToast', 'slFade', 'slLotBars', 'slLotData', 'slMeet', 'slRace', 'slMenu', 'slrrGarageState', 'slStation', 'slGarage', 'slPhotos', 'slMap', 'slPeople', 'slLaptopDealers', 'slAuctions', 'slRivals', 'slLaptopOffers', 'slHelp', 'slStrings', 'slMapsTiles', 'slMapsPose', 'slMapsRoute', 'slMapsPlaces', 'slMapsOptions'].forEach(function (name) {
        $rootScope.$on(name, function (ev, data) { phone.handle(name, data); });
      });
      if (window.bngApi) window.bngApi.engineLua('if sl_phone then sl_phone.request() end if sl_menuTile then sl_menuTile.request() end');
    }]);
  }
})();
