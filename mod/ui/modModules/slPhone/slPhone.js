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

  var CSS = [
    '.slp-root{position:fixed;left:0;top:0;right:0;bottom:0;pointer-events:none;z-index:50;font-family:"Roboto","Noto Sans","Segoe UI",Arial,sans-serif;color:#e6e1e5;-webkit-user-select:none;user-select:none}',
    '.slp-root *{box-sizing:border-box}',
    '.slp-root svg{display:block}',
    /* the device */
    '.slp-device{position:absolute;right:3vw;bottom:0;width:360px;height:760px;transform-origin:100% 100%;pointer-events:auto;',
    '  transition:transform .32s cubic-bezier(.2,.9,.25,1),opacity .2s;border-radius:46px;background:#0b0b0d;padding:11px;',
    '  box-shadow:0 0 0 2px #2a2a2e,0 30px 80px rgba(0,0,0,.65)}',
    '.slp-device.slp-away{opacity:0;pointer-events:none}',
    '.slp-screen{position:relative;width:100%;height:100%;border-radius:36px;overflow:hidden;background:#141218;display:flex;flex-direction:column}',
    '.slp-cam{position:absolute;left:50%;top:10px;width:11px;height:11px;margin-left:-5.5px;border-radius:50%;background:#000;box-shadow:0 0 0 2px #1d1d22;z-index:5}',
    /* status bar */
    '.slp-status{height:34px;flex:none;display:flex;align-items:center;padding:4px 22px 0 22px;font-size:13px;font-weight:500;z-index:4}',
    '.slp-status .slp-sr{margin-left:auto;display:flex;align-items:center;gap:5px}',
    '.slp-status svg{width:15px;height:15px;fill:currentColor}',
    /* home */
    '.slp-wall{position:absolute;left:0;top:0;right:0;bottom:0;background:radial-gradient(120% 70% at 20% 0%,#3b2f6b 0%,rgba(59,47,107,0) 60%),',
    '  radial-gradient(90% 60% at 100% 100%,#7a2e3d 0%,rgba(122,46,61,0) 65%),linear-gradient(#17121f,#0d0b12)}',
    '.slp-home{position:relative;flex:1;display:flex;flex-direction:column;padding:10px 18px 0 18px}',
    '.slp-clock{margin:26px 0 2px 4px;font-size:64px;font-weight:300;line-height:1;letter-spacing:-1px}',
    '.slp-date{margin-left:6px;font-size:15px;color:#cac4d0}',
    '.slp-chip{display:inline-block;margin:14px 0 0 4px;padding:6px 12px;border-radius:16px;background:rgba(255,255,255,.1);font-size:12px}',
    '.slp-grid{margin-top:auto;display:grid;grid-template-columns:repeat(4,1fr);row-gap:18px;padding-bottom:16px}',
    '.slp-app{display:flex;flex-direction:column;align-items:center;cursor:pointer;position:relative}',
    '.slp-ico{width:56px;height:56px;border-radius:50%;display:flex;align-items:center;justify-content:center}',
    '.slp-ico svg{width:28px;height:28px;fill:#fff}',
    '.slp-app span{margin-top:6px;font-size:11.5px;color:#e6e1e5}',
    '.slp-app:active .slp-ico{transform:scale(.92)}',
    '.slp-badge{position:absolute;top:-2px;left:50%;margin-left:14px;min-width:20px;height:20px;padding:0 6px;border-radius:10px;background:#f2b8b5;color:#601410;font-size:11px;font-weight:700;line-height:20px;text-align:center}',
    '.slp-dock{display:grid;grid-template-columns:repeat(4,1fr);padding:12px 6px 14px 6px;margin:0 -6px 6px -6px;border-radius:28px;background:rgba(255,255,255,.08)}',
    /* app pages */
    '.slp-page{position:relative;flex:1;display:flex;flex-direction:column;min-height:0;background:#141218}',
    '.slp-bar{height:60px;flex:none;display:flex;align-items:center;padding:0 8px 0 4px}',
    '.slp-bar b{font-size:20px;font-weight:400;margin-left:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.slp-ib{width:44px;height:44px;border-radius:50%;display:flex;align-items:center;justify-content:center;cursor:pointer;flex:none}',
    '.slp-ib:hover{background:rgba(255,255,255,.08)}',
    '.slp-ib svg{width:22px;height:22px;fill:#e6e1e5}',
    '.slp-body{flex:1;overflow-y:auto;min-height:0;padding:0 0 12px 0}',
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
    '.slp-empty{padding:40px 30px;text-align:center;color:#938f99;font-size:14px;line-height:1.5}',
    '.slp-btn{display:inline-flex;align-items:center;justify-content:center;height:40px;padding:0 20px;border-radius:20px;background:#a8c7fa;color:#062e6f;font-size:14px;font-weight:500;cursor:pointer;border:none}',
    '.slp-btn.slp-tonal{background:#3a3f4b;color:#d7e3ff}',
    '.slp-btn.slp-text{background:none;color:#a8c7fa;padding:0 12px}',
    '.slp-btn.slp-red{background:#f2b8b5;color:#601410}',
    '.slp-btn.slp-off{opacity:.38;pointer-events:none}',
    '.slp-card{margin:8px 16px;padding:14px 16px;border-radius:18px;background:#211f26}',
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
    '.slp-fade{position:absolute;left:0;top:0;right:0;bottom:0;background:#000;opacity:0;transition:opacity .5s}',
    /* the car lots: one car at a time, the SLRR way */
    '.slp-catch{position:absolute;left:0;top:0;right:0;bottom:0;pointer-events:auto;cursor:move;background:rgba(0,0,0,.01)}',
    '.slp-lot{position:absolute;left:50%;bottom:4vh;transform:translateX(-50%);width:640px;max-width:92vw;padding:18px 22px 14px 22px;border-radius:24px;',
    '  background:rgba(20,18,24,.9);pointer-events:auto;box-shadow:0 20px 60px rgba(0,0,0,.5)}',
    '.slp-lothead{display:flex;justify-content:space-between;font-size:12px;letter-spacing:1px;text-transform:uppercase;color:#cac4d0}',
    '.slp-lotname{margin-top:6px;font-size:15px;color:#cac4d0}',
    '.slp-lotname b{display:block;font-size:28px;font-weight:400;color:#e6e1e5;line-height:1.15}',
    '.slp-lottitle{display:inline-block;margin-top:6px;padding:3px 10px;border-radius:10px;background:#3a3f4b;font-size:12px;color:#d7e3ff}',
    '.slp-lotstats{display:flex;gap:22px;margin-top:12px;font-size:13px;color:#cac4d0}',
    '.slp-lotstats b{display:block;font-size:16px;font-weight:500;color:#e6e1e5}',
    '.slp-lotfaults{margin-top:10px;font-size:13px;color:#f2b8b5}',
    '.slp-lotfaults.slp-ok{color:#6dd58c}',
    '.slp-lotprice{margin-top:10px;font-size:34px;font-weight:300}',
    '.slp-lotbtns{display:flex;align-items:center;gap:10px;margin-top:12px}',
    '.slp-lotbtns .slp-btn{flex:1}',
    '.slp-arrow{width:48px;height:48px;border-radius:50%;background:#2b2930;display:flex;align-items:center;justify-content:center;cursor:pointer;font-size:18px;flex:none}',
    '.slp-arrow:hover{background:#49454f}',
    '.slp-lotleave{text-align:center;margin-top:8px}',
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
    phone: svg('M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2a1 1 0 0 1 1-.25 11.4 11.4 0 0 0 3.6.57 1 1 0 0 1 1 1V20a1 1 0 0 1-1 1A17 17 0 0 1 3 4a1 1 0 0 1 1-1h3.5a1 1 0 0 1 1 1c0 1.25.2 2.45.57 3.57a1 1 0 0 1-.25 1z'),
    msg: svg('M20 2H4a2 2 0 0 0-2 2v18l4-4h14a2 2 0 0 0 2-2V4a2 2 0 0 0-2-2zM6 9h12v2H6zm8 5H6v-2h8zm4-6H6V6h12z'),
    contacts: svg('M12 12a4 4 0 1 0-4-4 4 4 0 0 0 4 4zm0 2c-2.7 0-8 1.3-8 4v2h16v-2c0-2.7-5.3-4-8-4z'),
    flag: svg('M14.4 6 14 4H5v17h2v-7h5.6l.4 2h7V6z'),
    bank: svg('M4 10v7h3v-7zm6 0v7h3v-7zM2 22h19v-3H2zm14-12v7h3v-7zM11.5 1 2 6v2h19V6z'),
    cab: svg('M18.9 6c-.2-.6-.8-1-1.4-1h-11c-.7 0-1.2.4-1.4 1L3 12v8a1 1 0 0 0 1 1h1a1 1 0 0 0 1-1v-1h12v1a1 1 0 0 0 1 1h1a1 1 0 0 0 1-1v-8zM6.5 16A1.5 1.5 0 1 1 8 14.5 1.5 1.5 0 0 1 6.5 16zm11 0a1.5 1.5 0 1 1 1.5-1.5 1.5 1.5 0 0 1-1.5 1.5zM5 11l1.5-4.5h11L19 11z'),
    me: svg('M12 2 4 5v6c0 5 3.4 9.7 8 11 4.6-1.3 8-6 8-11V5zm-1.5 14.5-4-4 1.4-1.4 2.6 2.6 6.1-6.1 1.4 1.4z'),
    back: svg('M20 11H7.8l5.6-5.6L12 4l-8 8 8 8 1.4-1.4L7.8 13H20z'),
    gps: svg('M12 2a7 7 0 0 0-7 7c0 5.2 7 13 7 13s7-7.8 7-13a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 14.5 9 2.5 2.5 0 0 1 12 11.5z'),
    signal: svg('M2 22h20V2z'),
    wifi: svg('M12 21 1 8a16 16 0 0 1 22 0z'),
    battery: svg('M16 4h-2V2h-4v2H8a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1V5a1 1 0 0 0-1-1z'),
    down: svg('M7.4 8.6 12 13.2l4.6-4.6L18 10l-6 6-6-6z'),
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
  var APP_COLORS = { club: '#6a2e7a', jobs: '#3d7a2e', phone: '#2e7d4f', messages: '#2f5fb3', contacts: '#7b4fb0', races: '#c2541e', bank: '#1f7a70', cab: '#b58a12', me: '#5c6474', garage: '#8a3b8f' };
  var AV_COLORS = ['#a8c7fa', '#f2b8b5', '#c3e7c6', '#ffd8a8', '#d0bcff', '#9fe0e8', '#ffb4ab', '#e8def8'];
  var CLASS_NAMES = { beater: 'Beaters', compact: 'Compacts', muscle: 'Muscle', tuner: 'Tuners', sport: 'Sports cars', super: 'Supercars' };

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

  var STAKE_TEXT = { race: 'Race for money', high: 'High stakes', drag: 'Drag race', pink: 'Pink slips' };
  var QUICK = { race: 'Up for a race?', high: 'Race me. High stakes.', drag: 'Drag race at the test track?', pink: 'Pink slips. You and me.' };

  function createPhone(doc, lua, clock) {
    clock = clock || { set: function (f, ms) { return setTimeout(f, ms); }, clear: function (t) { clearTimeout(t); }, now: function () { return Date.now(); } };
    var root = doc.createElement('div');
    root.className = 'slp-root';
    var style = doc.createElement('style');
    style.textContent = CSS;
    root.appendChild(style);
    var layer = doc.createElement('div');
    root.appendChild(layer);
    doc.body.appendChild(root);

    var st = {
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
      var appsHtml = function (list) {
        return list.map(function (a) {
          var badge = a.badge ? '<div class="slp-badge">' + a.badge + '</div>' : '';
          var ico = st.slrrArt && SLRR_ICON[a.id] ? slrrIcon(SLRR_ICON[a.id], 'slp-appimg') : a.icon;
          return '<div class="slp-app" data-a="open" data-v="' + a.id + '"><div class="slp-ico" style="background:' + APP_COLORS[a.id] + '">' + ico + '</div>' + badge + '<span>' + a.title + '</span></div>';
        }).join('');
      };
      var arranged = arr(d.challenges).length;
      var tut = d.tutorial ? '<div class="slp-card slp-tut"><h4>Getting started ' + d.tutorial.step + '/' + d.tutorial.total + ': ' + esc(d.tutorial.title) + '</h4><p>' + esc(d.tutorial.text) + '</p>' +
        '<div class="slp-acts"><div class="slp-btn slp-text" data-a="tutskip" data-v="1">Skip the tutorial</div></div></div>' : '';
      return '<div class="slp-wall"></div><div class="slp-home">' +
        '<div class="slp-clock">' + two(d.hour || 0) + ':' + two(d.minute || 0) + '</div>' +
        '<div class="slp-date">Day ' + (d.day || 1) + ' &middot; Valo City' + (d.night ? ' &middot; night' : '') + '</div>' +
        '<div><span class="slp-chip">' + esc(d.title || '') + ' &middot; ' + (d.rep || 0) + ' rep &middot; ' + money(d.money) + '</span></div>' +
        tut + '<div class="slp-grid">' + appsHtml([
          { id: 'races', title: 'Races', icon: I.flag, badge: arranged || 0 },
          { id: 'garage', title: 'My cars', icon: I.cab },
          { id: 'bank', title: 'Bank', icon: I.bank },
          { id: 'me', title: 'Street cred', icon: I.me },
          { id: 'jobs', title: 'Jobs', icon: I.jobs, badge: d.jobs && d.jobs.active ? 1 : 0 },
          { id: 'club', title: 'Club', icon: I.club },
        ]) + '</div>' +
        '<div class="slp-dock">' + appsHtml([
          { id: 'phone', title: 'Phone', icon: I.phone },
          { id: 'messages', title: 'Messages', icon: I.msg, badge: unread() || 0 },
          { id: 'contacts', title: 'Contacts', icon: I.contacts },
          { id: 'cab', title: 'Cab', icon: I.cab },
        ]).replace(/<span>[^<]*<\/span>/g, '') + '</div></div>';
    }

    function contactLine(c) {
      if (c.system) return 'Your garage';
      var stars = '<span class="slp-stars">' + new Array((c.tier || 1) + 1).join('&#9733;') + '</span>';
      return stars + ' &middot; ' + esc(CLASS_NAMES[c.class] || c.class || '') + (c.nightOnly ? ' &middot; nights' : '') + (c.pinkTonight ? ' &middot; <span class="slp-pink">pinks tonight</span>' : '');
    }

    function contactsPage() {
      var list = arr(st.data.contacts), out = [], last = null;
      list.forEach(function (c) {
        var letter = c.system ? '★' : (c.short || c.name || '?')[0].toUpperCase();
        if (letter !== last) { out.push('<div class="slp-letter">' + esc(letter) + '</div>'); last = letter; }
        out.push('<div class="slp-row" data-a="contact" data-v="' + esc(c.id) + '">' + avatar(c) + '<div class="slp-rt"><b>' + esc(c.name) + '</b><span>' + contactLine(c) + '</span></div></div>');
      });
      if (list.length <= 1) out.push('<div class="slp-empty">Nobody else has given you their number yet. Win a few races and they will.</div>');
      return bar('Contacts') + '<div class="slp-body">' + out.join('') + '</div>';
    }

    function contactPage() {
      var c = contactById(st.contact);
      if (!c) return bar('Contact') + '<div class="slp-empty">Gone.</div>';
      var record = c.system ? '' : '<div class="slp-card"><div class="slp-kv"><span>You beat them</span><b>' + (c.losses || 0) + '</b></div><div class="slp-kv" style="border:none"><span>They beat you</span><b>' + (c.wins || 0) + '</b></div></div>';
      return bar('') + '<div class="slp-body"><div class="slp-hero">' + avatar(c) + '<b>' + esc(c.name) + '</b><span>' + esc(c.phone) + '</span><span>' + contactLine(c) + '</span></div>' +
        '<div class="slp-acts3"><div class="slp-act" data-a="call" data-v="' + esc(c.id) + '"><i>' + I.phone + '</i>Call</div>' +
        '<div class="slp-act" data-a="thread" data-v="' + esc(c.id) + '"><i>' + I.msg + '</i>Message</div></div>' + record + '</div>';
    }

    function messagesPage() {
      var threads = obj(st.data.threads);
      var ids = Object.keys(threads).filter(function (id) { return arr(threads[id]).length; });
      ids.sort(function (a, b) { var x = arr(threads[a]), y = arr(threads[b]); return (y[y.length - 1].at || 0) - (x[x.length - 1].at || 0); });
      var rows = ids.map(function (id) {
        var c = contactById(id) || { id: id, name: id };
        var list = arr(threads[id]), lastMsg = list[list.length - 1], n = unread(id);
        return '<div class="slp-row" data-a="thread" data-v="' + esc(id) + '">' + avatar(c) + '<div class="slp-rt"><b>' + esc(c.name) + '</b><span' + (n ? ' class="slp-unread"' : '') + '>' +
          (lastMsg.from === 'me' ? 'You: ' : '') + esc(lastMsg.text) + '</span></div>' + (n ? '<div class="slp-badge" style="position:static;margin:0">' + n + '</div>' : '') + '</div>';
      });
      return bar('Messages') + '<div class="slp-body">' + (rows.join('') || '<div class="slp-empty">No messages.</div>') + '</div>';
    }

    function threadPage() {
      var c = contactById(st.thread) || { id: st.thread, name: st.thread };
      var bubbles = thread(st.thread).map(function (m) { return '<div class="slp-bub ' + (m.from === 'me' ? 'slp-me' : 'slp-them') + '">' + esc(m.text) + '</div>'; }).join('');
      var quick = c.system ? '' : '<div class="slp-quick">' + Object.keys(QUICK).filter(function (k) { return k !== 'pink' || c.pinkTonight; }).map(function (k) { return '<div class="slp-qc" data-a="text" data-v="' + k + '">' + esc(QUICK[k]) + '</div>'; }).join('') + '</div>';
      return bar(c.name, '<div style="margin-left:auto" class="slp-ib" data-a="call" data-v="' + esc(c.id) + '">' + I.phone + '</div>') +
        '<div class="slp-msgs">' + (bubbles || '<div class="slp-empty">Say something.</div>') + '</div>' + quick;
    }

    var KEYS = [['1', ''], ['2', 'ABC'], ['3', 'DEF'], ['4', 'GHI'], ['5', 'JKL'], ['6', 'MNO'], ['7', 'PQRS'], ['8', 'TUV'], ['9', 'WXYZ'], ['*', ''], ['0', '+'], ['#', '']];
    function dialMatch() {
      var digits = st.dial.replace(/\D/g, '');
      if (!digits) return null;
      var list = arr(st.data.contacts);
      for (var i = 0; i < list.length; i++) if (String(list[i].phone).replace(/\D/g, '') === digits) return list[i];
      return null;
    }
    function phonePage() {
      var who = dialMatch();
      return bar('Phone', st.dial ? '<div style="margin-left:auto" class="slp-ib" data-a="del">' + I.back + '</div>' : '') +
        '<div class="slp-num">' + esc(st.dial || ' ') + '</div><div class="slp-who">' + (who ? esc(who.name) : '') + '</div>' +
        '<div class="slp-keys">' + KEYS.map(function (k) { return '<div class="slp-key" data-a="key" data-v="' + k[0] + '">' + k[0] + '<small>' + k[1] + '</small></div>'; }).join('') + '</div>' +
        '<div class="slp-dial" data-a="dial">' + I.phone + '</div>';
    }

    function racesPage() {
      var list = arr(st.data.challenges);
      var cards = list.map(function (c) {
        var stake = c.stake === 'pink' ? 'Pink slips' : money(c.bet);
        return '<div class="slp-card"><h4>' + esc(c.name) + '</h4><p>' + esc(c.raceName) + ' &middot; ' + stake + (c.nightOnly ? ' &middot; after dark' : '') + '</p>' +
          '<div class="slp-acts"><div class="slp-btn" data-a="gps" data-v="' + esc(c.id) + '">Show the way</div><div class="slp-btn slp-text" data-a="cancel" data-v="' + esc(c.id) + '">Call it off</div></div></div>';
      });
      return bar('Races') + '<div class="slp-body">' + (cards.join('') ||
        '<div class="slp-empty">No races arranged. Call or text one of your contacts to set one up: for money, for high stakes, or for pink slips.</div>') + '</div>';
    }

    // the job board: what is on offer now, the one you are on, your record
    function jobsPage() {
      var j = obj(st.data.jobs), a = j.active;
      var mmss = function (sec) { sec = Math.max(0, sec | 0); return Math.floor(sec / 60) + ':' + two(sec % 60); };
      var activeCard = a ? '<div class="slp-card"><h4>' + esc(a.title) + ': ' + esc(a.item || '') + (a.fragile ? ' &middot; fragile' : '') + '</h4>' +
        '<p>Next stop: ' + esc(a.next) + (a.timeLeft != null ? ' &middot; ' + (a.timeLeft > 0 ? mmss(a.timeLeft) + ' left' : 'late') : '') + ' &middot; ' + money(a.pay) + '</p>' +
        '<div class="slp-acts"><div class="slp-btn" data-a="jobway" data-v="1">Show the way</div><div class="slp-btn slp-text" data-a="jobquit" data-v="1">Give up</div></div></div>' : '';
      var cards = arr(j.offers).map(function (o) {
        return '<div class="slp-card"><h4>' + esc(o.title) + ': ' + esc(o.item || '') + (o.fragile ? ' &middot; fragile' : '') + '</h4>' +
          '<p>' + esc(o.from) + ' &rarr; ' + esc(o.to) + ' &middot; ' + (o.metres ? (o.metres / 1000).toFixed(1) + ' km &middot; ' : '') + (o.seconds ? mmss(o.seconds) + ' &middot; ' : '') + '<b>' + money(o.pay) + '</b></p>' +
          (a ? '' : '<div class="slp-acts"><div class="slp-btn" data-a="jobtake" data-v="' + esc(o.id) + '">Take it</div></div>') + '</div>';
      }).join('');
      var boostLine = j.boost && j.boost > 1.04 ? '<div class="slp-empty">New in town: jobs pay &times;' + j.boost.toFixed(1) + ' until you make a name or buy your first part.</div>' : '';
      return bar('Jobs') + '<div class="slp-body">' + boostLine + activeCard + (cards || '<div class="slp-empty">Nothing on the board. New jobs come in the morning and at dusk.</div>') +
        (j.crew ? '<div class="slp-card"><h4>Crew contract: ' + esc(j.crew.boss) + '</h4><p>Beat ' + j.crew.need + ' racers of tier ' + j.crew.tier + ' or better: ' + j.crew.won + ' so far, ' + j.crew.daysLeft + ' days left. ' + money(j.crew.pay) + '</p></div>' : '') +
        (j.sponsor ? '<div class="slp-card"><h4>Sponsor: ' + esc(j.sponsor.name) + '</h4><p>' + money(j.sponsor.weekly) + ' a week for two wins a week: ' + j.sponsor.weekWins + ' this week.</p></div>' : '') +
        (j.quarter || j.dyno ? '<div class="slp-card"><h4>Tuning challenges</h4><p>' + (j.quarter ? 'Quarter mile at the test track under ' + j.quarter + ' s. ' : '') + (j.dyno ? 'Dyno: ' + j.dyno + ' PS on the car info sheet in your garage.' : '') + '</p></div>' : '') +
        (j.flip ? '<div class="slp-card"><h4>Junkyard challenge: flip a car</h4><p>Sell one for ' + money(j.flip.target) + ' more than you paid for a bonus. Best so far: ' + money(j.flip.best || 0) + '.</p></div>' : '') +
        '<div class="slp-empty">' + (j.done || 0) + ' jobs done, ' + money(j.earned || 0) + ' earned.</div></div>';
    }

    // the club: today's league events, the standings
    function clubPage() {
      var c = st.data.club;
      if (!c) return bar('Club') + '<div class="slp-body"><div class="slp-empty">No club yet.</div></div>';
      var ev = c.today || {};
      var row = function (kind, label, e) {
        if (!e) return '';
        var act = e.done ? '<b>Done</b>' : (kind === 'day' && !e.open ? '<b>Soon</b>' : '<div class="slp-btn" data-a="league" data-v="' + kind + '">Enter</div>');
        return '<div class="slp-kv"><span>' + label + '<br><small>' + esc(e.name) + '</small></span>' + act + '</div>';
      };
      var table = arr(c.standings).map(function (r) {
        return '<div class="slp-kv"' + (r.you ? ' style="font-weight:700"' : '') + '><span>' + r.place + '. ' + esc(r.name) + '</span><b>' + r.points + '</b></div>';
      }).join('');
      return bar(c.club) + '<div class="slp-body"><div class="slp-card"><h4>Season ' + c.season + ', day ' + c.day + ' of ' + c.days + (ev.finale ? ' &middot; finale, double points' : '') + '</h4>' +
        '<p>Class ' + esc(c['class'] || '?') + (c.carClass && c.carClass !== c['class'] ? ' &middot; this car: ' + esc(c.carClass) : '') + ' &middot; skip any event, it only costs its points</p>' +
        row('night', 'Night league', ev.night) + row('day', 'Day league', ev.day) + '</div>' +
        '<div class="slp-card"><h4>Standings</h4>' + table + '</div></div>';
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
          cards += '<div class="slp-card"><h4>Loan: ' + money(bk.loan.owed) + ' owed</h4><p>Next payment ' + money(bk.loan.due) + ' in ' + bk.loan.dueIn + ' day' + (bk.loan.dueIn === 1 ? '' : 's') +
            (bk.loan.missed ? ' &middot; <span class="slp-pink">' + bk.loan.missed + ' missed</span>' : '') + '</p>' +
            '<div class="slp-acts"><div class="slp-btn" data-a="repay" data-v="' + Math.min(bk.loan.owed, st.data.money || 0) + '">Pay ' + money(Math.min(bk.loan.owed, st.data.money || 0)) + '</div></div></div>';
        } else {
          var half = Math.floor(bk.limit / 200) * 100;
          cards += '<div class="slp-card"><h4>Borrow</h4><p>Up to ' + money(bk.limit) + ' &middot; ' + Math.round(bk.rate * 100) + '% a day &middot; a quarter due each week</p>' +
            '<div class="slp-acts"><div class="slp-btn slp-tonal" data-a="borrow" data-v="' + half + '">' + money(half) + '</div><div class="slp-btn slp-tonal" data-a="borrow" data-v="' + bk.limit + '">' + money(bk.limit) + '</div></div></div>';
        }
        cards += bk.policy ? '<div class="slp-card"><h4>Insured</h4><p>' + (bk.policy.startsIn ? 'Cover starts tomorrow' : 'Covering half of repairs and impound bills over ' + money(bk.deductible)) + '</p>' +
            '<div class="slp-acts"><div class="slp-btn slp-text" data-a="insure" data-v="false">Cancel</div></div></div>'
          : '<div class="slp-card"><h4>Insurance</h4><p>' + money(bk.premium) + ' a week: half of repairs and impound bills over ' + money(bk.deductible) + ', from the next day</p>' +
            '<div class="slp-acts"><div class="slp-btn slp-tonal" data-a="insure" data-v="true">Insure</div></div></div>';
      }
      return bar('Bank') + '<div class="slp-body"><div class="slp-bal"><small>Balance</small><div>' + money(st.data.money) + '</div></div>' + cards +
        (rows.join('') || '<div class="slp-empty">No transactions yet.</div>') + '</div>';
    }

    function cabPage() {
      var rows = arr(st.data.places).map(function (p) {
        return '<div class="slp-row" data-a="taxi" data-v="' + esc(p.id) + '"><div class="slp-av" style="background:#ffd8a8">' + I.cab.replace('<svg', '<svg style="width:22px;height:22px;fill:#5b3d00"') + '</div>' +
          '<div class="slp-rt"><b>' + esc(p.name) + '</b><span>' + esc(p.kind) + '</span></div><div class="slp-ib" data-a="gps" data-v="' + esc(p.id) + '">' + I.gps + '</div></div>';
      });
      return bar('Cab') + '<div class="slp-body"><div class="slp-card"><p>On foot, a cab takes you anywhere in town. In a car, the pin shows you the way.</p></div>' +
        (rows.join('') || '<div class="slp-empty">The cab company does not know any places on this map yet.</div>') + '</div>';
    }

    // a car's health, its trunk (use what is in it) and its history
    var ITEM_NAMES = { fuelCan: 'Fuel can', oil: 'Engine oil', coolant: 'Coolant', battery: '12 V battery' };
    function careView(c) {
      var k = c.care;
      if (!k) return '';
      var pct = function (v) { return v == null ? '-' : Math.round(v * 100) + '%'; };
      var warn = function (v, low) { return v != null && v < low ? ' class="slp-warn"' : ''; };
      var rows = '<div class="slp-kv"><span>Battery</span><b' + warn(k.battery, 0.3) + '>' + pct(k.battery) + '</b></div>' +
        '<div class="slp-kv"><span>Oil</span><b' + warn(k.oilLevel, 0.5) + '>' + pct(k.oilLevel) + ' &middot; ' + (k.oilKm || 0).toLocaleString() + ' km old</b></div>' +
        '<div class="slp-kv"><span>Coolant</span><b' + warn(k.coolantLevel, 0.5) + '>' + pct(k.coolantLevel) + '</b></div>' +
        '<div class="slp-kv"><span>Fuel</span><b>' + pct(k.fuelLevel) + ' &middot; ' + esc(k.fuel) + '</b></div>' +
        (k.n2o != null ? '<div class="slp-kv"><span>Nitrous</span><b>' + pct(k.n2o) + '</b></div>' : '') +
        '<div class="slp-kv"><span>Engine</span><b>' + (k.engineKm || 0).toLocaleString() + ' km &middot; ' + Math.round((k.performance || 1) * 100) + '% power</b></div>';
      var counts = {};
      arr(k.trunk).forEach(function (i) { counts[i] = (counts[i] || 0) + 1; });
      var trunk = Object.keys(counts).map(function (i) {
        return '<div class="slp-kv slp-hudrow" data-a="useitem" data-v="' + c.id + '|' + i + '"><span>' + esc(ITEM_NAMES[i] || i) + ' &times;' + counts[i] + '</span><b class="slp-on">Use</b></div>';
      }).join('');
      var h = k.history || {};
      var hist = '<div class="slp-kv" style="border:none"><span>History</span><b>' + (h.owners || 0) + ' owners before you &middot; ' + (h.wins || 0) + '/' + (h.races || 0) + ' races won' +
        (h.wrecks ? ' &middot; wrecked ' + h.wrecks + '&times;' : '') + '</b></div>';
      return '<div class="slp-carcare">' + rows + (trunk ? '<div class="slp-trunk">Trunk</div>' + trunk : '') + hist + '</div>';
    }

    function garagePage() {
      var cars = arr(st.data.fleet);
      var cards = cars.map(function (c) {
        var faults = arr(c.faults);
        var acts = [];
        if (c.impounded) acts.push('<div class="slp-btn" data-a="release" data-v="' + c.id + '">Get it out of the impound &middot; ' + money(c.impounded) + '</div>');
        else if (!c.active) acts.push('<div class="slp-btn" data-a="usecar" data-v="' + c.id + '">Drive this one</div>');
        if (c.out && c.towFee && c.where === 'Out on the street') acts.push('<div class="slp-btn slp-tonal" data-a="tow" data-v="' + c.id + '">Tow it home &middot; ' + money(c.towFee) + '</div>');
        return '<div class="slp-card"><h4>' + esc(c.name) + (c.active ? ' &#9733;' : '') + '</h4><p>' + esc(c.where) + ' &middot; condition ' + Math.round((c.condition || 0) * 100) + '%' +
          (faults.length ? '<br>Needs: ' + esc(faults.join(', ')) : '') + '</p>' + careView(c) + (acts.length ? '<div class="slp-acts">' + acts.join('') + '</div>' : '') + '</div>';
      });
      return bar('My cars') + '<div class="slp-body">' + (cards.join('') ||
        '<div class="slp-empty">You have no car. The junkyard sells cheap ones that need work, the dealership new ones. The Cab app gets you there.</div>') + '</div>';
    }

    function mePage() {
      var d = st.data, s = obj(d.stats);
      var from = d.titleRep || 0, to = d.nextRep, pct = to ? Math.max(0, Math.min(100, ((d.rep || 0) - from) / (to - from) * 100)) : 100;
      var next = d.nextGarage ? '<div class="slp-kv"><span>Next garage</span><b>' + esc(d.nextGarage.name) + (d.nextGarage.canMove ? ' - ready' : ' - ' + esc(d.nextGarage.why)) + '</b></div>' : '';
      var acts = [];
      if (d.nextGarage && d.nextGarage.canMove) acts.push('<div class="slp-btn" data-a="move">Move to ' + esc(d.nextGarage.name) + '</div>');
      if (d.roc && !d.rocChampion) acts.push('<div class="slp-btn" data-a="roc">' + (d.rocRound ? 'ROC round ' + (d.rocRound + 1) + ' of 3' : 'Enter the ROC &middot; ' + money(d.rocEntry)) + '</div>');
      return bar('Street cred') + '<div class="slp-body"><div class="slp-card"><h4>' + esc(d.title) + '</h4><p>' + (d.rep || 0) + ' reputation' + (to ? ' &middot; next title at ' + to : '') + '</p>' +
        '<div class="slp-meter"><i style="width:' + pct.toFixed(1) + '%"></i></div></div>' +
        '<div class="slp-card"><div class="slp-kv"><span>Garage</span><b>' + esc(d.garage || '') + '</b></div>' + next +
        '<div class="slp-kv"><span>Race of Champions</span><b>' + (d.roc ? 'Open to you' : 'Not yet') + '</b></div>' +
        '<div class="slp-kv"><span>Cars</span><b>' + (d.cars || 0) + '</b></div>' +
        '<div class="slp-kv"><span>Races</span><b>' + (s.races || 0) + ' (' + (s.wins || 0) + ' won)</b></div>' +
        '<div class="slp-kv" style="border:none"><span>Pink slips</span><b>' + (s.pinksWon || 0) + ' won, ' + (s.pinksLost || 0) + ' lost</b></div>' +
        (acts.length ? '<div class="slp-acts">' + acts.join('') + '</div>' : '') + '</div>' +
        (d.rocChampion ? '<div class="slp-card"><h4>ROC champion</h4><p>The best in Valo City. There is nobody left to beat.</p></div>' : '') +
        achievementsCard(d.achievements) + hudCard(d.hud) + '</div>';
    }

    // achievements (earned ones lit, the rest dimmed) and personal best times
    function achievementsCard(a) {
      if (!a) return '';
      var rows = arr(a.list).map(function (x) {
        return '<div class="slp-kv"' + (x.day != null ? '' : ' style="opacity:.45"') + '><span>' + esc(x.title) + '<br><small>' + esc(x.desc) + '</small></span><b>' + (x.day != null ? 'Day ' + x.day : '') + '</b></div>';
      }).join('');
      var bests = arr(a.bests).map(function (b) { return '<div class="slp-kv"><span>' + esc(b.name) + '</span><b>' + Number(b.time).toFixed(2) + ' s</b></div>'; }).join('');
      return '<div class="slp-card"><h4>Achievements ' + (a.earned || 0) + ' / ' + (a.total || 0) + '</h4>' + rows + '</div>' +
        (bests ? '<div class="slp-card"><h4>Best times</h4>' + bests + '</div>' : '');
    }

    // the SLRR dashboard's switches
    function hudCard(h) {
      if (!h) return '';
      var row = function (key, label, on, text) {
        return '<div class="slp-kv slp-hudrow" data-a="hud" data-v="' + key + '"><span>' + label + '</span><b class="' + (on ? 'slp-on' : 'slp-offtxt') + '">' + (text || (on ? 'On' : 'Off')) + '</b></div>';
      };
      return '<div class="slp-card"><h4>Dashboard</h4><p>The SLRR gauges, map and damage diagram while you drive.</p>' +
        row('enabled', 'Dashboard', h.enabled) +
        (h.enabled ? row('tacho', 'Rev counter', h.tacho) + row('speedo', 'Speedometer', h.speedo) + row('map', 'Map', h.map) + row('damage', 'Damage', h.damage) +
          row('units', 'Units', true, h.units === 'mph' ? 'mph' : 'km/h') + row('freeroam', 'Also outside the career', h.freeroam) : '') + '</div>';
    }

    function callPage() {
      var c = st.call, who = contactById(c.id) || { id: c.id, name: c.id };
      var status = c.phase === 'ringing' ? 'Calling…' : (c.phase === 'ended' ? 'Call ended' : 'Connected');
      var body = '';
      if (c.phase === 'talking' || c.phase === 'ended') {
        if (c.greeting) body += '<div class="slp-said">' + esc(c.greeting) + '</div>';
        if (c.reply) body += '<div class="slp-said">' + esc(c.reply) + '</div>';
        else if (c.text) body += '<div class="slp-said">' + esc(c.text) + '</div>';
        if (c.phase === 'talking' && !c.reply && arr(c.options).length) {
          body += '<div class="slp-opts">' + c.options.map(function (k) { return '<div class="slp-btn slp-tonal" data-a="stake" data-v="' + k + '">' + STAKE_TEXT[k] + '</div>'; }).join('') + '</div>';
        }
        if (c.challenge) body += '<div class="slp-opts"><div class="slp-btn" data-a="gps" data-v="' + esc(c.challenge.id) + '">Show the way to ' + esc(c.challenge.raceName) + '</div></div>';
      }
      return '<div class="slp-call' + (c.phase === 'ringing' ? ' slp-ring' : '') + '">' + avatar(who) + '<b>' + esc(who.name) + '</b><div class="slp-cs">' + status + '</div>' + body +
        '<div class="slp-hang" data-a="hang">' + I.phone + '</div></div>';
    }

    // ---------------------------------------------------------------- the lots, a meet, a race
    function mmss(sec) { sec = Math.max(0, Math.round(sec || 0)); return Math.floor(sec / 60) + ':' + two(sec % 60); }

    function lotView() {
      var l = st.lot;
      if (!l || !l.open) return '';
      if (l.mode === 'test') {
        return '<div class="slp-hudtest">Test drive &middot; ' + mmss(l.testLeft) + ' left &middot; bring it back to ' + esc(l.name) +
          '<div class="slp-btn slp-tonal" data-a="lot" data-v="endTest()">Done</div></div>';
      }
      if (l.mode === 'sell') {
        var c = l.sellCar || {};
        return '<div class="slp-lot"><div class="slp-lothead"><span>' + esc(l.kindTitle) + ' &middot; ' + esc(l.name) + '</span></div>' +
          '<div class="slp-lotname">They will give you<b>' + money(c.price) + ' for the ' + esc(c.name) + '</b></div>' +
          '<div class="slp-lotbtns"><div class="slp-btn" data-a="lot" data-v="sell()">' + (l.kind === 'scrap' ? 'Scrap it' : 'Sell it') + '</div>' +
          '<div class="slp-btn slp-tonal" data-a="lot" data-v="browse()">Look at their cars</div></div>' +
          '<div class="slp-lotleave"><div class="slp-btn slp-text" data-a="lot" data-v="close()">Not today</div></div></div>';
      }
      var o = l.offer || {};
      var faults = arr(o.faults);
      var body = l.building ? '<div class="slp-lotname"><b>Bringing it round\u2026</b></div>' :
        '<div class="slp-lotname">' + esc(o.brand) + '<b>' + esc(o.name) + '</b></div><div class="slp-lottitle">' + esc(o.title) + '</div>' +
        '<div class="slp-lotstats"><div>Condition<b>' + Math.round((o.condition || 0) * 100) + '%</b></div><div>Mileage<b>' + String(Math.round(o.mileage || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ',') + ' km</b></div>' +
        '<div>Bodywork<b>' + (o.damage > 0.5 ? 'Bad' : o.damage > 0.15 ? 'Dented' : 'Clean') + '</b></div>' + (o.mods ? '<div>Modified<b>' + o.mods + ' parts</b></div>' : '') + '</div>' +
        '<div class="slp-lotfaults' + (faults.length ? '' : ' slp-ok') + '">' + (faults.length ? 'Needs: ' + esc(faults.join(', ')) : 'Runs and drives') + '</div>' +
        '<div class="slp-lotprice">' + money(o.price) + '</div>';
      return '<div class="slp-catch" data-catch="lot"></div><div class="slp-lot"><div class="slp-lothead"><span>' + esc(l.kindTitle) + ' &middot; ' + esc(l.name) + '</span><span>' + (l.index || 0) + ' / ' + (l.count || 0) + '</span></div>' + body +
        '<div class="slp-lotbtns"><div class="slp-arrow" data-a="lot" data-v="prev()">' + (st.slrrArt ? slrrIcon('left.png') : '&#9664;') + '</div>' +
        (l.kind !== 'scrap' ? '<div class="slp-btn slp-tonal' + (l.building ? ' slp-off' : '') + '" data-a="lot" data-v="testDrive()">Test drive</div>' : '') +
        '<div class="slp-btn' + (l.building || (o.price > l.money) ? ' slp-off' : '') + '" data-a="lot" data-v="buy()">Buy &middot; ' + money(o.price) + '</div>' +
        '<div class="slp-arrow" data-a="lot" data-v="next()">' + (st.slrrArt ? slrrIcon('right.png') : '&#9654;') + '</div></div>' +
        '<div class="slp-lotleave"><div class="slp-btn slp-text" data-a="lot" data-v="close()">Leave</div></div></div>';
    }

    // the gas station: a grade, fill the tank or a can, and the shop
    function stationView() {
      var g = st.station;
      if (!g || !g.open) return '';
      var pick = st.fuelPick || 'premium';
      var grades = arr(g.fuels).map(function (f) {
        return '<div class="slp-btn' + (f.id === pick ? '' : ' slp-tonal') + '" data-a="fuelpick" data-v="' + esc(f.id) + '">' + esc(f.name) + '<br><small>$' + Number(f.price).toFixed(2) + '/L</small></div>';
      }).join('');
      var tank = g.car ? 'Your ' + esc(g.car) + ': ' + (g.tank != null ? Math.round(g.tank * 100) + '% full' : '') + (g.inTank ? ' &middot; ' + esc(g.inTank) : '') +
        (g.litresToFull != null ? ' &middot; ' + Math.round(g.litresToFull) + ' L to fill' : '') : 'Come in your car to fill it up.';
      var shop = arr(g.items).map(function (it) {
        return '<div class="slp-kv slp-hudrow" data-a="station" data-v="buy|' + esc(it.id) + '"><span>' + esc(it.name) + '</span><b class="slp-on">' + money(it.price) + '</b></div>';
      }).join('');
      return '<div class="slp-lot"><div class="slp-lothead"><span>Gas station &middot; ' + esc(g.name) + '</span><span>' + money(g.money) + '</span></div>' +
        '<div class="slp-lotname">' + tank + '</div>' +
        '<div class="slp-lotbtns slp-grades">' + grades + '</div>' +
        '<div class="slp-lotbtns"><div class="slp-btn slp-go" data-a="station" data-v="fill|' + esc(pick) + '">Fill the tank</div></div>' +
        '<div class="slp-trunk">Shop &middot; into the trunk (' + (g.trunk || 0) + '/' + (g.trunkSlots || 6) + ')' + ' &middot; a fuel can takes the grade above</div>' + shop +
        '<div class="slp-lotleave"><div class="slp-btn slp-text" data-a="station" data-v="close">Drive on</div></div></div>';
    }

    function meetView() {
      var m = st.meet;
      if (!m || !m.open) return '';
      var rows = arr(m.racers).map(function (r) {
        return '<div class="slp-row">' + avatar(r) + '<div class="slp-rt"><b>' + esc(r.name) + '</b><span><span class="slp-stars">' + new Array((r.tier || 1) + 1).join('&#9733;') + '</span> &middot; ' +
          esc(r.car) + ' &middot; ' + money(r.betMin) + '-' + money(r.betMax) + '</span></div><div class="slp-acts">' +
          '<div class="slp-btn slp-tonal" data-a="meet" data-v="' + esc(r.id) + '|race">Race</div>' +
          '<div class="slp-btn slp-tonal" data-a="meet" data-v="' + esc(r.id) + '|high">High</div>' +
          (r.pinkTonight ? '<div class="slp-btn slp-pinkbtn" data-a="meet" data-v="' + esc(r.id) + '|pink">Pinks</div>' : '') + '</div></div>';
      });
      return '<div class="slp-meet"><h3>Car meet &middot; ' + esc(m.name) + '</h3><div class="slp-card" style="margin:6px 0 4px 0"><p>Pick somebody. The race is to the other side of town; first one there wins.</p></div>' +
        (rows.join('') || '<div class="slp-empty">Everybody has gone home.</div>') +
        (m.canShow ? '<div class="slp-lotbtns"><div class="slp-btn slp-tonal" data-a="meetshow" data-v="1">Show and shine (' + money(m.showFee || 50) + ')</div></div>' : '') +
        '<div class="slp-lotleave"><div class="slp-btn slp-text" data-a="meetclose">Just looking</div></div></div>';
    }

    function raceView() {
      var r = st.race;
      if (!r || !r.on) return '';
      var stake = r.stake === 'pink' ? 'Pink slips' : money(r.bet);
      var dist = r.laps ? 'Lap ' + r.lap + ' of ' + r.laps : (r.mine != null ? 'You ' + r.mine + ' m' : '') + (r.theirs != null ? ' &middot; them ' + r.theirs + ' m' : '');
      return (r.countdown ? '<div class="slp-count">' + r.countdown + '</div>' : '') +
        '<div class="slp-race"><b>vs ' + esc(r.name) + ' &middot; ' + stake + '</b><span>To ' + esc(r.destName) + '</span><span>' + dist + '</span>' +
        (r.ahead != null ? '<i class="' + (r.ahead ? 'slp-ahead' : 'slp-behind') + '">' + (r.ahead ? 'Ahead' : 'Behind') + '</i>' : '') + '</div>';
    }

    // the main menu's own Career button opens this: the game's career, or Wrench Works: Street Legal
    function menuView() {
      var m = st.menu;
      if (!m || !m.show || !st.chooser) return '';
      var sl = !m.installed
        ? '<div class="slp-chcard slp-chsl slp-off"><b>Wrench Works: Street Legal</b><span>Needs the Wrench Works: Valo City map (slrr_valo_city). Switch it on under Mods.</span></div>'
        : '<div class="slp-chcard slp-chsl"><b>Wrench Works: Street Legal</b>' + (st.slrrArt ? slrrIcon(m.summary ? 'load_career_a.png' : 'new_career_a.png', 'slp-chimg') : '') + '<span>' + (m.summary ? 'Your career: ' + esc(m.summary) : 'Valo City at night. No car, $5,000 and a name nobody knows. Junkyard wrecks, street racers, pink slips and the ROC.') + '</span>' +
          (m.summary ? '<div class="slp-btn slp-go" data-a="menustart" data-v="continue">Continue</div>' : '') +
          '<div class="slp-btn' + (m.summary ? ' slp-tonal' : ' slp-go') + '" data-a="menustart" data-v="new">' + (m.summary ? 'New career (replaces this one)' : 'New career') + '</div>' +
          '<div class="slp-btn slp-tonal" data-a="menustart" data-v="newskip">' + (m.summary ? 'New career, no tutorial (replaces this one)' : 'New career, no tutorial') + '</div></div>';
      return '<div class="slp-chooser"><div class="slp-chbox"><h1>Career</h1><div class="slp-chcards">' +
        '<div class="slp-chcard" data-a="chooser" data-v="beamng"><b>BeamNG Career</b><span>The game\'s own career mode: jobs, missions, your garage and vehicles.</span></div>' +
        sl + '</div><div class="slp-chback"><div class="slp-btn slp-text" data-a="chooser" data-v="close" style="display:inline-block">Back</div></div></div></div>';
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
    }, true);

    // the fade: black, or one of SLRR's loading screens (a cab ride, the garage, the dealer)
    function fadeView() {
      var pic = st.slrrArt && st.fadePic ? ' style="background:#000 url(/ui/modModules/slHud/slrr/loading/' + esc(st.fadePic) + ') center/cover no-repeat"' : '';
      return '<div class="slp-fade' + (st.fade ? ' slp-in' : '') + '"' + pic + '></div>';
    }

    // ---------------------------------------------------------------- drawing
    function render() {
      var d = st.data;
      if (!d.active) {
        layer.innerHTML = menuView() + '<div class="slp-toast' + (st.toast ? '' : ' slp-gone') + '">' + esc(st.toast || '') + '</div>' +
          fadeView();
        return;
      }
      var scroll = layer.querySelector('.slp-body, .slp-msgs');
      var keep = scroll ? scroll.scrollTop : 0, keepApp = st.app;
      var page;
      switch (st.app) {
        case 'contacts': page = contactsPage(); break;
        case 'contact': page = contactPage(); break;
        case 'messages': page = messagesPage(); break;
        case 'thread': page = threadPage(); break;
        case 'phone': page = phonePage(); break;
        case 'races': page = racesPage(); break;
        case 'jobs': page = jobsPage(); break;
        case 'club': page = clubPage(); break;
        case 'bank': page = bankPage(); break;
        case 'cab': page = cabPage(); break;
        case 'me': page = mePage(); break;
        case 'garage': page = garagePage(); break;
        default: page = homePage();
      }
      var isHome = st.app === 'home';
      var screen = '<div class="slp-screen' + (isHome ? ' slp-home-on' : '') + '"><div class="slp-cam"></div>' +
        '<div class="slp-status">' + two(d.hour || 0) + ':' + two(d.minute || 0) + '<div class="slp-sr">' + I.signal + I.wifi + I.battery + '</div></div>' +
        (isHome ? homePage() : '<div class="slp-page">' + page + '</div>') +
        (st.call ? callPage() : '') +
        '<div class="slp-nav"><div data-a="back">' + NAV.back + '</div><div data-a="home">' + NAV.home + '</div><div data-a="away">' + NAV.recent + '</div></div></div>';
      var hu = st.hu;
      var huHtml = '<div class="slp-hu' + (hu && !st.open ? '' : ' slp-gone') + '" data-a="openthread" data-v="' + esc(hu ? hu.thread : '') + '">' +
        (hu ? avatar({ id: hu.thread, name: hu.name }) + '<div><small>Messages &middot; now</small><b>' + esc(hu.name) + '</b><span>' + esc(hu.text) + '</span></div>' : '') + '</div>';
      layer.innerHTML =
        '<div class="slp-pill"' + (st.open ? ' style="display:none"' : '') + '><b>' + money(d.money) + '</b><span>' + esc(d.title) + '</span><span>' + two(d.hour || 0) + ':' + two(d.minute || 0) + '</span></div>' +
        '<div class="slp-device' + (st.open ? '' : ' slp-away') + '" style="transform:' + (st.open ? '' : 'translateY(70%) ') + 'scale(' + scale() + ')">' + screen + '</div>' +
        lotView() + stationView() + meetView() + raceView() +
        huHtml +
        '<div class="slp-toast' + (st.toast ? '' : ' slp-gone') + '">' + esc(st.toast || '') + '</div>' +
        fadeView();
      var after = layer.querySelector('.slp-body, .slp-msgs');
      if (after) {
        if (st.app === 'thread') after.scrollTop = after.scrollHeight;
        else if (keepApp === st.app) after.scrollTop = keep;
      }
    }

    function scale() {
      var h = (doc.defaultView && doc.defaultView.innerHeight) || 1080;
      return Math.max(0.5, Math.min(1.2, h * 0.78 / 760)).toFixed(3);
    }

    // ---------------------------------------------------------------- what the buttons do
    function go(app, params) {
      st.stack.push({ app: st.app, contact: st.contact, thread: st.thread });
      st.app = app;
      if (params) for (var k in params) st[k] = params[k];
      if (app === 'thread' && st.thread) { lua('markRead(' + JSON.stringify(st.thread) + ')'); var u = obj(st.data.unread); delete u[st.thread]; }
      render();
    }
    function back() {
      if (st.call) { hang(); return; }
      var prev = st.stack.pop();
      if (!prev) { setOpen(false); return; }
      st.app = prev.app; st.contact = prev.contact; st.thread = prev.thread;
      render();
    }
    function home() { st.stack = []; st.app = 'home'; render(); }
    function setOpen(open) {
      st.open = open;
      if (open) lua('request()');
      render();
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
        case 'back': back(); break;
        case 'home': home(); break;
        case 'away': setOpen(false); break;
        case 'contact': go('contact', { contact: v }); break;
        case 'thread': go('thread', { thread: v }); break;
        case 'openthread': if (v) { st.hu = null; st.open = true; st.stack = []; st.app = 'messages'; go('thread', { thread: v }); } break;
        case 'call': startCall(v); break;
        case 'hang': hang(); break;
        case 'stake': lua('challenge(' + JSON.stringify(st.call.id) + ',' + JSON.stringify(v) + ')'); st.call.options = []; render(); break;
        case 'text': lua('text(' + JSON.stringify(st.thread) + ',' + JSON.stringify(v) + ')'); break;
        case 'gps': lua('waypoint(' + JSON.stringify(v) + ')'); toast('The route is on your road.'); break;
        case 'cancel': lua('cancel(' + JSON.stringify(v) + ')'); break;
        case 'league': lua('enterLeague(' + JSON.stringify(v) + ')'); break;
        case 'borrow': lua('borrow(' + Number(v) + ')'); break;
        case 'repay': lua('repay(' + Number(v) + ')'); break;
        case 'insure': lua('insure(' + (v === 'true' ? 'true' : 'false') + ')'); break;
        case 'tutskip': lua('@sl_tutorial.skip()'); break;
        case 'jobtake': lua('takeJob(' + JSON.stringify(v) + ')'); break;
        case 'jobquit': lua('giveUpJob()'); break;
        case 'jobway': lua('jobWay()'); toast('The route is on your road.'); break;
        case 'taxi': lua('taxi(' + JSON.stringify(v) + ')'); break;
        case 'tow': lua('tow(' + Number(v) + ')'); break;
        case 'release': lua('release(' + Number(v) + ')'); break;
        case 'usecar': lua('useCar(' + Number(v) + ')'); break;
        case 'move': lua('moveGarage()'); break;
        case 'roc': lua('enterRoc()'); setOpen(false); break;
        case 'lot': if (/^[a-zA-Z]+\(\)$/.test(v)) lua('@sl_lot.' + v); break;
        case 'meet': var parts = String(v).split('|'); lua('@sl_streets.meetChallenge(' + JSON.stringify(parts[0]) + ',' + JSON.stringify(parts[1]) + ')'); break;
        case 'menustart':
          if ((v === 'new' || v === 'newskip') && st.menu && st.menu.summary && !st.confirmNew) { st.confirmNew = true; toast('Click again to start over: the career you have is lost.'); break; }
          st.confirmNew = false;
          if (v === 'newskip') lua('@sl_tutorial.skipNextCareer()');
          lua('@sl_menuTile.startFromMenu(' + (v === 'new' || v === 'newskip' ? 'true' : 'false') + ')');
          st.menu = null; st.chooser = false; render();
          break;
        case 'chooser':
          st.chooser = false; render();
          if (v === 'beamng' && careerButton) { letThrough = true; try { careerButton.click(); } finally { letThrough = false; } }
          break;
        case 'hud': lua('@sl_hud.toggle(' + JSON.stringify(v) + ')'); break;
        case 'fuelpick': st.fuelPick = v; render(); break;
        case 'station':
          var sv = String(v).split('|');
          if (sv[0] === 'close') { lua('@sl_station.close()'); st.station = null; render(); }
          else if (sv[0] === 'fill') lua('@sl_station.fill(' + JSON.stringify(sv[1]) + ')');
          else if (sv[0] === 'buy') lua('@sl_station.buy(' + JSON.stringify(sv[1]) + ',' + JSON.stringify(st.fuelPick || 'premium') + ')');
          break;
        case 'useitem': var ui = String(v).split('|'); lua('useItem(' + Number(ui[0]) + ',' + JSON.stringify(ui[1]) + ')'); break;
        case 'meetclose': lua('@sl_streets.closeMeet()'); st.meet = null; render(); break;
        case 'meetshow': lua('@sl_streets.showAndShine()'); break;
        case 'key': if (st.dial.length < 12) st.dial += v; render(); break;
        case 'del': st.dial = st.dial.slice(0, -1); render(); break;
        case 'dial': var who = dialMatch(); if (who) startCall(who.id); else if (st.dial) toast('The number you have dialled is not available.'); break;
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
      act(el.getAttribute('data-a'), el.getAttribute('data-v'));
    });

    // ---------------------------------------------------------------- what Lua says
    function handle(name, data) {
      data = data || {};
      switch (name) {
        case 'slPhoneData':
          st.data = data;
          if (!data.active) { st.open = false; st.call = null; st.hu = null; }
          render();
          break;
        case 'slPhoneToggle': setOpen(!st.open); break;
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
        case 'slFade': st.fade = !!data.on; if (data.on) st.fadePic = data.pic || null; render(); break;
        case 'slLotData': st.lot = data.open ? data : null; render(); break;
        case 'slMeet': st.meet = data.open ? data : null; render(); break;
        case 'slStation': st.station = data.open ? data : null; render(); break;
        case 'slRace': st.race = data.on ? data : null; render(); break;
        case 'slMenu': st.menu = data.show ? data : null; render(); break;
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
      var probe = new Image();
      probe.onload = function () { phone.handle('slArt'); };
      probe.src = '/ui/modModules/slHud/slrr/icons/cup.png';
      ['slPhoneData', 'slPhoneToggle', 'slPhoneCall', 'slPhoneCallReply', 'slPhoneNotify', 'slPhoneToast', 'slFade', 'slLotData', 'slMeet', 'slRace', 'slMenu', 'slStation'].forEach(function (name) {
        $rootScope.$on(name, function (ev, data) { phone.handle(name, data); });
      });
      if (window.bngApi) window.bngApi.engineLua('if sl_phone then sl_phone.request() end if sl_menuTile then sl_menuTile.request() end');
    }]);
  }
})();
