// Ataste Motion board, part 3 (ranks 16–22 + the onboarding ring fix). Load after ataste-motion.js and ataste-motion-2.js.
(function(){
if (customElements.get('atm-signin')) return;
const A=window.AtMotion;if(!A){console.warn('Load ataste-motion.js first');return;}
const {Mo,K,rp,ic,GL,BASE}=A;
const cl=(x,a=0,b=1)=>Math.max(a,Math.min(b,x));
const RING=[1.2,1.0]; // Motion.ringTurn (response / dampingFraction)
const ringSvg=(s,c)=>`<svg width="${s}" height="${s}" viewBox="0 0 100 100" style="display:block"><circle cx="50" cy="50" r="49" fill="none" stroke="${c}" stroke-width="${120/s}" stroke-dasharray="3 3"></circle></svg>`;
const progRing=(s)=>{const r=s/2-2,C=2*Math.PI*r;return {C,html:`<svg width="${s}" height="${s}" viewBox="0 0 ${s} ${s}" style="position:absolute;inset:0;transform:rotate(-90deg)"><circle cx="${s/2}" cy="${s/2}" r="${r}" fill="none" stroke="rgba(251,243,234,.3)" stroke-width="3"></circle><circle class="pr" cx="${s/2}" cy="${s/2}" r="${r}" fill="none" stroke="${K.cream}" stroke-width="3" stroke-linecap="round" stroke-dasharray="${C}" stroke-dashoffset="${C}"></circle></svg>`};};
// ringTurn spring is slower than the shared set: it only drives the dashed ring
Mo.prototype.spRing=function(o,t,delay=0){Object.assign(o,{mode:'s',t,r:RING[0],d:RING[1],delay,then:null});this.run(o);};
const pose=n=>`url(uploads/art/pose-${n}.png) center/cover no-repeat`;

/* Fix: onboarding ring (1-1 splash, 1-4a waiting). Turns a quarter on each real step, then rests. */
class Ring extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:560px;padding:0;background:${K.car}}
 .sp{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:40px}
 .rw{position:relative;width:260px;height:260px}.rg{position:absolute;inset:0}.ms{position:absolute;inset:22px;border-radius:50%;background:${pose('neutral')},${K.peach}}
 .lg{background:${K.cream};border:4px solid ${K.cream};border-radius:999px;padding:6px 26px 10px;box-shadow:0 5px 0 ${K.cocoa}}.lg span{font:700 46px/1 Roundo,sans-serif;color:${K.car};letter-spacing:-.03em}
 .tx{position:absolute;left:0;right:0;bottom:48px;text-align:center;font:700 20px/1 Roundo,sans-serif;color:${K.cream}}
 .wl{position:absolute;inset:0;background:${K.cream};opacity:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;padding:24px;text-align:center;pointer-events:none}
 .wl b{font:700 32px/1.05 Roundo,sans-serif;letter-spacing:-.02em}.wl span{font:500 15px/1.5 Manrope,sans-serif;color:${K.ink2}}</style>
 <div class="sp"><div class="rw"><div class="rg">${ringSvg(260,K.cream)}</div><div class="ms" role="img" aria-label="Mascot"></div></div><span class="lg"><span>ataste</span></span></div>
 <span class="tx">Proofing the dough…</span>
 <div class="wl"><b>One order for the whole group.</b><span>Welcome screen (1-2) takes over here.</span></div>`;
 const $=s=>this.q(s);this.rg=$('.rg');this.ms=$('.ms');this.lg=$('.lg');this.wl=$('.wl');this.tx=$('.tx');
 const p=()=>{this.rg.style.transform=`rotate(${this.r.v}deg)`;this.ms.style.transform=this.rm?'none':`scale(${this.m.v})`;this.lg.style.transform=`translateY(${this.ly.v}px) scale(${this.lb.v})`;this.lg.style.opacity=cl(this.lo.v);this.wl.style.opacity=cl(this.wo.v);this.tx.style.opacity=cl(this.to.v);};
 const V=(x,e)=>this.v(x,p,e);this.r=V(0,.05);this.m=V(1);this.ly=V(0,.05);this.lb=V(1);this.lo=V(1);this.wo=V(0);this.to=V(1);
 this.reset();}
launch(){this.ready=0;this.set(this.wo,0);const rm=this.rm;
 if(rm){this.set(this.r,0);this.set(this.m,1);this.set(this.ly,0);this.set(this.lo,0);this.tw(this.lo,1,.2,'easeInOut');this.set(this.to,0);this.tw(this.to,1,.2,'easeInOut',.1);}
 else{this.set(this.r,-90);this.spRing(this.r,0);this.set(this.m,.9);this.sp(this.m,1,'bounce',.08);this.set(this.ly,-24);this.set(this.lo,0);this.sp(this.ly,0,'arrive',.12);this.tw(this.lo,1,.2,'easeOut',.12);this.set(this.to,0);this.tw(this.to,1,.2,'easeOut',.3);}
 this.hap('None','Launch · the ring turns a quarter and rests');}
done(){if(this.ready)return;this.ready=1;const rm=this.rm;
 if(rm){this.tw(this.wo,1,.2,'easeInOut');}else{this.spRing(this.r,this.r.t+90);this.set(this.lb,1.06);this.sp(this.lb,1,'bump');this.tw(this.wo,1,.2,'easeOut',.25);}
 this.hap('None','Ready · one more quarter turn, then Welcome');}
reset(){this.ready=0;this.set(this.r,0);this.set(this.m,1);this.set(this.ly,0);this.set(this.lb,1);this.set(this.lo,1);this.set(this.wo,0);this.set(this.to,1);}
}

/* 16 Sign-in: WhatsApp code, waiting, verified */
class SignIn extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:680px;padding:0}
 .ly{position:absolute;left:24px;right:24px;display:grid}.ly>div{grid-area:1/1;display:flex;flex-direction:column;gap:10px}
 .h{margin:0;font:700 30px/1.1 Roundo,sans-serif;letter-spacing:-.01em}.p{margin:0;font:500 15px/1.5 Manrope,sans-serif;color:${K.ink2}}
 .ring{position:absolute;left:76px;top:150px;width:250px;height:250px;opacity:0}
 .ms{position:absolute;left:50%;border-radius:50%;overflow:hidden}.ms i{position:absolute;inset:0}
 .code{position:absolute;box-sizing:border-box;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;overflow:hidden;white-space:nowrap}
 .code .lab{font:600 12px/1 Manrope,sans-serif;letter-spacing:.03em;text-transform:uppercase;color:${K.ink3}}
 .code .val{display:flex;align-items:baseline;gap:8px;font:700 40px/1 Roundo,sans-serif;letter-spacing:.05em}.code .val .roll{gap:0}.code .left{font:500 12px Manrope,sans-serif;letter-spacing:0;color:${K.ink2}}
 .note{position:absolute;left:24px;right:24px;top:470px;text-align:center;font:500 14px/1.45 Manrope,sans-serif;color:${K.ink2}}
 .bot{position:absolute;left:16px;right:16px;bottom:40px}.bot .cta{width:100%}
 .cta .face{display:flex;align-items:center;justify-content:center;gap:10px;padding:14px 32px;border-radius:999px;border:4px solid;font:600 17px/1.25 Manrope,sans-serif;white-space:nowrap}
 .vf{position:absolute;inset:0;background:${K.cocoa};opacity:0;visibility:hidden;overflow:hidden}
 .sun{position:absolute;width:500px;height:500px;left:-49px;top:70px;border-radius:50%;background:repeating-conic-gradient(${K.lime} 0 9deg,transparent 9deg 18deg)}
 .disc{position:absolute;width:300px;height:300px;left:51px;top:170px;border-radius:50%;background:${K.lime}}
 .cel{position:absolute;left:76px;top:195px;width:250px;height:250px;border-radius:50%;background:${pose('celebrating')}}
 .yi{position:absolute;left:24px;right:24px;top:480px;display:flex;flex-direction:column;align-items:center;gap:12px;text-align:center}
 .yi b{font:400 52px/1 Shrikhand,cursive;color:${K.lime};font-weight:400}.yi span{display:inline-flex;align-items:center;gap:8px;font:600 16px Manrope,sans-serif;color:${K.cream}}
 .cont{position:absolute;left:16px;right:16px;bottom:40px;display:flex;align-items:center;justify-content:center;padding:14px 32px;border-radius:999px;background:${K.lime};border:4px solid ${K.limeR};color:${K.cocoa};font:600 17px/1.25 Manrope,sans-serif}</style>
 <div class="ly" style="top:28px"><div class="t0"><h2 class="h">Send us one message</h2><p class="p">Tap the button. WhatsApp opens with a code already typed — just press send.</p></div>
  <div class="t1" style="opacity:0;align-items:center;text-align:center;padding-top:400px"><h2 class="h" style="font-size:28px">Checking your WhatsApp…</h2><p class="p" style="max-width:310px">This finishes by itself as soon as your message reaches us. You can leave and come back.</p></div>
  <div class="t2" style="opacity:0;align-items:center;text-align:center;padding-top:400px"><h2 class="h" style="font-size:28px">We didn’t get your message</h2><p class="p" style="max-width:310px">Codes last 10 minutes and this one ran out. Here’s a fresh one — send it the same way.</p></div></div>
 <div class="ring">${ringSvg(250,K.car)}</div>
 <div class="ms"><i class="m0" style="background:${pose('phone')},${K.lime}"></i><i class="m1" style="background:${pose('waiting')},${K.peach};opacity:0"></i><i class="m2" style="background:${pose('confused')},${K.pink||'#F9B7D2'};opacity:0"></i></div>
 <div class="code"><span class="lab">Your code</span><span class="val"><span class="roll cv"></span><span class="left"></span></span></div>
 <span class="note">Send it from the WhatsApp you want to log in with. We read your number from the message.</span>
 <div class="bot"><button class="cta" aria-label="Open WhatsApp"><span class="face">${ic('wa',20)}<span class="roll cl"></span></span></button></div>
 <div class="vf"><div class="sun"></div><div class="disc"></div><div class="cel" role="img" aria-label="Mascot celebrating"></div><div class="yi"><b>You’re in!</b><span>${ic('verified',20,K.lime)}Verified as +62 812-xxxx-5521</span></div><span class="cont">Continue</span></div>`;
 const $=s=>this.q(s);Object.assign(this,{t0:$('.t0'),t1:$('.t1'),t2:$('.t2'),ringEl:$('.ring'),msEl:$('.ms'),m0:$('.m0'),m1:$('.m1'),m2:$('.m2'),code:$('.code'),lab:$('.lab'),cv:$('.cv'),left:$('.left'),note:$('.note'),face:$('.cta .face'),clab:$('.cl'),vf:$('.vf'),sun:$('.sun'),disc:$('.disc'),cel:$('.cel'),yi:$('.yi'),cont:$('.cont'),val:$('.val')});
 const p=()=>this.paint(),V=(x,e)=>this.v(x,p,e);
 this.V={cx:V(24,.05),cy:V(300,.05),cw:V(354,.05),ch:V(102,.05),fs:V(40,.05),lo:V(1),ms:V(140,.05),my:V(140,.05),ro:V(0),rr:V(0,.05),t0:V(1),t1:V(0),t2:V(0),no:V(1),
  vo:V(0),sr:V(0,.05),ss:V(1),ds:V(1),cy2:V(0,.05),co:V(1),yo:V(0),ys:V(1),vy:V(0),bo:V(1),by:V(0,.05),sh:V(0,.05)};
 this.P=this.wire($('.cta'),this.face,[1.02,.92],{tone:()=>this.st==='verify'||this.st==='expired'?[K.cocoa,'#4A3329',K.cocoa,'#4A3329']:[K.cream,'#FDF8F2',K.peach,K.peachP],commit:()=>this.open()});
 this.reset();}
paint(){const V=this.V,c=this.code.style,rm=this.rm;c.left=V.cx.v+'px';c.top=V.cy.v+'px';c.width=V.cw.v+'px';c.height=V.ch.v+'px';c.transform=`translateX(${V.sh.v}px)`;
 this.val.style.fontSize=V.fs.v+'px';this.lab.style.opacity=cl(V.lo.v);this.lab.style.display=V.lo.v<.02?'none':'';this.left.style.opacity=1-cl(V.lo.v);this.left.style.display=V.lo.v>.98?'none':'';
 const ms=this.msEl.style;ms.width=ms.height=V.ms.v+'px';ms.marginLeft=-V.ms.v/2+'px';ms.top=V.my.v+'px';
 this.ringEl.style.opacity=cl(V.ro.v);this.ringEl.style.transform=`rotate(${V.rr.v}deg)`;
 this.t0.style.opacity=cl(V.t0.v);this.t1.style.opacity=cl(V.t1.v);this.t2.style.opacity=cl(V.t2.v);this.note.style.opacity=cl(V.no.v);
 this.vf.style.opacity=cl(V.vo.v);this.vf.style.visibility=V.vo.v>.001?'visible':'hidden';
 this.sun.style.transform=rm?'none':`rotate(${V.sr.v}deg) scale(${V.ss.v})`;this.disc.style.transform=rm?'none':`scale(${Math.max(0,V.ds.v)})`;
 this.cel.style.transform=rm?'none':`translateY(${V.cy2.v}px)`;this.cel.style.opacity=cl(V.co.v);
 this.yi.firstElementChild.style.transform=rm?'none':`scale(${.6+.4*V.ys.v}) rotate(${-6*(1-V.ys.v)}deg)`;this.yi.firstElementChild.style.opacity=cl(V.yo.v);this.yi.lastElementChild.style.opacity=cl(V.vy.v);
 this.cont.style.opacity=cl(V.bo.v);this.cont.style.transform=`translateY(${V.by.v}px)`;}
look(dark,ins){this.face.style.transition=ins?'none':`background-color ${.2*this.slow}s,border-color ${.2*this.slow}s,color ${.2*this.slow}s`;this.face.style.backgroundColor=dark?K.cocoa:K.cream;this.face.style.borderColor=dark?K.cocoa:K.peach;this.face.style.color=dark?K.cream:K.cocoa;
 this.code.style.transition=ins?'none':`background-color ${.2*this.slow}s,border-color ${.2*this.slow}s,border-radius ${.2*this.slow}s`;}
codeBox(card){const s=this.code.style;s.background=card?'#fff':K.mist;s.border=card?`2px dashed ${K.car}`:'2px solid transparent';s.borderRadius=card?'32px':'999px';}
tick(){clearInterval(this._iv);this.secs=598;const f=()=>{const m=Math.floor(this.secs/60),s=String(this.secs%60).padStart(2,'0');this.left.textContent='· '+m+':'+s+' left';};f();this._iv=setInterval(()=>{this.secs=Math.max(0,this.secs-1);f();},1000*this.slow);}
spOr(o,t,n,d=0){if(this.rm)this.set(o,t);else this.sp(o,t,n,d);}
open(){const V=this.V,rm=this.rm;
 if(this.st==='verify'||this.st==='expired'){const fresh=this.st==='expired';this.st='wait';this.hap('.impact(weight: .light)',fresh?'Send new code · WhatsApp opens':'Open WhatsApp · the code is already typed');
  this.after(.35,()=>this.toWait(fresh));return;}
 this.hap('.impact(weight: .light)','Open WhatsApp again');}
toWait(fresh){const V=this.V,rm=this.rm;this.look(false);this.codeBox(false);this.roll(this.clab,'Open WhatsApp again',1);this.tick();
 const f=(o,t)=>rm?this.tw(o,t,.2,'easeInOut'):(t?this.tw(o,t,.2,'easeOut',.08):this.tw(o,0,.15,'easeIn'));
 f(V.t0,0);f(V.t2,0);f(V.t1,1);f(V.no,0);f(V.lo,0);
 this.spOr(V.cx,83,'lead');this.spOr(V.cw,236,'lead');this.spOr(V.cy,462,'trail');this.spOr(V.ch,38,'lead');this.spOr(V.fs,15,'settle');
 this.spOr(V.ms,206,'settle');this.spOr(V.my,172,'settle');
 this.fadeTo(this.m1);f(V.ro,1);if(!rm)this.spRing(V.rr,V.rr.t+90);
 this.hap('None','Back from WhatsApp · waiting; the ring turns a quarter and rests');}
fadeTo(el){[this.m0,this.m1,this.m2].forEach(e=>{e.style.transition=`opacity ${.2*this.slow}s`;e.style.opacity=e===el?1:0;});}
arrive(){if(this.st!=='wait')return;this.st='done';clearInterval(this._iv);const V=this.V,rm=this.rm;
 if(rm){this.tw(V.vo,1,.2,'easeInOut');['co','yo','vy','bo'].forEach(k=>this.set(V[k],1));this.set(V.ys,1);this.set(V.by,0);this.hap('.success','Verified');return;}
 this.spRing(V.rr,V.rr.t+90);this.tw(V.vo,1,.2,'easeOut',.06);
 this.set(V.sr,-40);this.set(V.ss,.8);this.sp(V.sr,0,'glide',.06);this.sp(V.ss,1,'settle',.06);
 this.set(V.ds,0);this.sp(V.ds,1,'pop',.10);this.set(V.cy2,60);this.set(V.co,0);this.sp(V.cy2,0,'bounce',.16);this.tw(V.co,1,.15,'easeOut',.16);
 this.set(V.ys,0);this.sp(V.ys,1,'pop',.24);this.tw(V.yo,1,.12,'easeOut',.24);this.tw(V.vy,1,.2,'easeOut',.32);
 this.set(V.by,40);this.set(V.bo,0);this.sp(V.by,0,'arrive',.38);this.tw(V.bo,1,.2,'easeOut',.38);
 this.hap('.success','Verified · the message reached Ataste');}
expire(){if(this.st!=='wait')return;this.st='expired';clearInterval(this._iv);const V=this.V,rm=this.rm;
 this.keys(V.sh,rm?[[0,0],[.01,0]]:[[0,0],[.05,4],[.12,-3],[.19,2],[.26,-1],[.32,0]]);
 this.after(rm?0:.32,()=>{this.roll(this.cv,'ATASTE 7HQ2',1);this.left.textContent='· 10:00 left';});
 const f=(o,t)=>rm?this.tw(o,t,.2,'easeInOut'):(t?this.tw(o,t,.2,'easeOut',.08):this.tw(o,0,.15,'easeIn'));f(V.t1,0);f(V.t2,1);f(V.ro,0);
 this.fadeTo(this.m2);this.look(true);this.roll(this.clab,'Send new code',1);this.hap('.warning','Code timed out · a fresh code is ready');}
reset(){clearInterval(this._iv);this.st='verify';const V=this.V;Object.entries({cx:24,cy:300,cw:354,ch:102,fs:40,lo:1,ms:140,my:140,ro:0,rr:0,t0:1,t1:0,t2:0,no:1,vo:0,sr:0,ss:1,ds:1,cy2:0,co:1,yo:0,ys:1,vy:0,bo:1,by:0,sh:0}).forEach(([k,x])=>this.set(V[k],x));
 this.look(true,true);this.codeBox(true);this.cv.innerHTML='<span class="rl">ATASTE 4K9X</span>';this.left.textContent='· 9:58 left';this.clab.innerHTML='<span class="rl">Open WhatsApp</span>';
 [this.m0,this.m1,this.m2].forEach((e,i)=>{e.style.transition='none';e.style.opacity=i?0:1;});this.P.rest();}
disconnectedCallback(){clearInterval(this._iv);}
}

/* 17 Send to WhatsApp and coming back */
const MSG={id:'Halo Kak, saya mau pesan untuk grup *Academy Bali Friday Treats* (via Ataste).\n\nPengiriman: Jumat, 3 Okt 2026, 10.00 WITA\nAlamat: Apple Developer Academy Bali\nKontak: Rani · +62 812 7788 2210\n\nTotal: Rp 481.000 (belum termasuk ongkir).',
 en:'Hi! I’d like to place an order for the group *Academy Bali Friday Treats* (via Ataste).\n\nDelivery: Friday, 3 Oct 2026, 10:00 WITA\nAddress: Apple Developer Academy Bali\nContact: Rani · +62 812 7788 2210\n\nTotal: Rp 481.000 (excluding delivery).'};
class SendWA extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:660px;padding:0}
 .s1,.s2{position:absolute;inset:0;padding:24px 16px}
 .tt{display:block;text-align:center;font:600 17px/1.2 Manrope,sans-serif;margin-bottom:16px}
 .intro{display:flex;gap:12px;align-items:center;margin-bottom:14px}.intro i{width:44px;height:44px;border-radius:50%;background:${pose('phone')},${K.lime};flex:none}.intro span{font:500 14px/1.45 Manrope,sans-serif;color:${K.ink2}}
 .seg{position:relative;display:flex;padding:4px;border-radius:999px;background:${K.mist};margin-bottom:12px}.seg button{flex:1;position:relative;z-index:1;text-align:center;padding:8px 0;font:600 13px Manrope,sans-serif}
 .pill{position:absolute;top:4px;bottom:4px;border-radius:999px;background:#fff;box-shadow:0 1px 3px rgba(43,26,18,.15)}
 .msg{background:#fff;border-radius:24px;padding:16px;overflow:hidden}.msg .roll{display:grid}.msg .rl{white-space:pre-wrap;align-items:flex-start;font:500 14px/1.5 Manrope,sans-serif}
 .bar{position:absolute;left:12px;right:12px;bottom:26px;padding:12px;border-radius:36px;${GL}}.bar .cta{width:100%}
 .cta .face{display:flex;align-items:center;justify-content:center;gap:10px;padding:14px 0;border-radius:999px;background:${K.cocoa};border:4px solid ${K.cocoa};color:${K.cream};font:600 17px/1.25 Manrope,sans-serif}
 .away{position:absolute;inset:0;background:rgba(43,26,18,.88);color:${K.cream};display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;opacity:0;visibility:hidden;font:600 15px Manrope,sans-serif;text-align:center;padding:24px}
 .away small{font:500 12px Manrope,sans-serif;color:${K.mauve}}
 .s2{opacity:0;visibility:hidden}.hd{display:flex;flex-direction:column;gap:8px;margin-bottom:16px}.hd b{font:700 26px/1.1 Roundo,sans-serif}
 .wc{display:flex;gap:14px;align-items:center;background:#fff;border-radius:32px;padding:16px;margin-bottom:12px}.wc i{width:72px;height:72px;border-radius:50%;background:${pose('delivery')},${K.peach};flex:none}
 .wc b{display:block;font:700 17px/1.2 Roundo,sans-serif;margin-bottom:4px}.wc span{font:500 13px/1.45 Manrope,sans-serif;color:${K.ink2}}
 .tot{background:#fff;border-radius:24px;padding:14px 16px;display:flex;flex-direction:column;gap:8px}.tot div{display:flex;justify-content:space-between;font:600 14px Manrope,sans-serif}
 .rep{display:flex;align-items:center;justify-content:center;padding:14px 0;border-radius:999px;background:${K.car};border:4px solid ${K.car};color:${K.cream};font:600 17px/1.25 Manrope,sans-serif}</style>
 <div class="s1"><span class="tt">Send to Atas</span><div class="intro"><i></i><span>This is the message Atas will get. Tap to edit anything before you open WhatsApp.</span></div>
  <div class="seg"><span class="pill"></span><button data-l="id">Bahasa Indonesia</button><button data-l="en">English</button></div>
  <div class="msg"><span class="roll mr"></span></div></div>
 <div class="s2"><div class="hd"><span class="chipw"><at-tag kind="sent"></at-tag></span><b>Academy Bali Friday Treats</b></div>
  <div class="wc"><i role="img" aria-label="Mascot with delivery bag"></i><div><b>Waiting for Atas to reply</b><span>Sent 13:42 WITA on WhatsApp. When they confirm the ongkir, enter it here so everyone’s bill is final.</span></div></div>
  <div class="tot"><div><span>Items</span><span>Rp 481.000</span></div><div style="color:${K.ink3}"><span>Ongkir</span><span>Waiting for Atas</span></div></div></div>
 <div class="bar"><button class="cta"><span class="face">${ic('wa',20)}Open WhatsApp</span></button><span class="rep" style="display:none">Atas replied · enter final bill</span></div>
 <div class="away"><span>In WhatsApp</span><small>Board only: the system handles the switch. Use “Come back” to return.</small></div>`;
 const $=s=>this.q(s);Object.assign(this,{s1:$('.s1'),s2:$('.s2'),pill:$('.pill'),seg:$('.seg'),mr:$('.mr'),msg:$('.msg'),away:$('.away'),cta:$('.cta'),rep:$('.rep'),chip:$('.chipw'),wc:$('.wc'),tot:$('.tot'),hd:$('.hd b')});
 const p=()=>this.paint(),V=(x,e)=>this.v(x,p,e);this.V={pl:V(4,.05),pr:V(4,.05),mh:V(0,.05),s1:V(1),s2:V(0),aw:V(0),cs:V(1),cr:V(0),wy:V(0,.05),wo:V(1),ty:V(0,.05),to:V(1),my:V(0,.05),ro:V(0),ry:V(0,.05)};
 this.btns=[...this.seg.querySelectorAll('button')];
 this.btns.forEach(b=>this.wire(b,b,[1.04,.92],{commit:()=>this.lang(b.dataset.l)}));
 this.wire(this.cta,$('.cta .face'),[1.02,.92],{tone:()=>[K.cocoa,'#4A3329',K.cocoa,'#4A3329'],commit:()=>this.leave()});
 this.reset();if(document.fonts)document.fonts.ready.then(()=>{if(this.st==='edit')this.place(true);});}
paint(){const V=this.V;this.pill.style.left=V.pl.v+'px';this.pill.style.width=Math.max(0,V.pr.v-V.pl.v)+'px';if(V.mh.v>0)this.msg.style.height=V.mh.v+'px';
 this.s1.style.opacity=cl(V.s1.v);this.s1.style.visibility=V.s1.v>.001?'visible':'hidden';this.s2.style.opacity=cl(V.s2.v);this.s2.style.visibility=V.s2.v>.001?'visible':'hidden';
 this.away.style.opacity=cl(V.aw.v);this.away.style.visibility=V.aw.v>.001?'visible':'hidden';
 this.chip.style.display='inline-flex';this.chip.style.transformOrigin='0 50%';this.chip.style.transform=this.rm?'none':`scale(${Math.max(0,V.cs.v)}) rotate(${-12*(1-V.cs.v)}deg)`;
 this.wc.style.transform=`translateY(${V.wy.v}px)`;this.wc.style.opacity=cl(V.wo.v);this.wc.firstElementChild.style.transform=`translateY(${V.my.v}px)`;
 this.tot.style.transform=`translateY(${V.ty.v}px)`;this.tot.style.opacity=cl(V.to.v);this.rep.style.opacity=cl(V.ro.v);this.rep.style.transform=`translateY(${V.ry.v}px)`;}
place(ins){const b=this.btns[this.l==='id'?0:1],x=b.offsetLeft,w=b.offsetWidth;if(ins){this.set(this.V.pl,x);this.set(this.V.pr,x+w);}return[x,w];}
text(l,ins){if(ins){this.mr.innerHTML=`<span class="rl">${MSG[l]}</span>`;this.msg.style.height='auto';this.set(this.V.mh,0);return;}
 const h0=this.msg.offsetHeight;this.roll(this.mr,MSG[l],1);const last=this.mr.lastElementChild;this.msg.style.height='auto';const h1=this.mr.offsetHeight+32;this.set(this.V.mh,h0);if(this.rm)this.set(this.V.mh,h1);else this.sp(this.V.mh,h1,'settle');}
lang(l){if(l===this.l||this.st!=='edit')return;const o=this.l;this.l=l;const[x,w]=this.place();const V=this.V,right=l==='en';
 if(this.rm){this.set(V.pl,x);this.set(V.pr,x+w);this.fadeIn(this.pill);}else{this.sp(right?V.pr:V.pl,right?x+w:x,'lead');this.sp(right?V.pl:V.pr,right?x:x+w,'trail');}
 this.btns.forEach(b=>b.style.color=b.dataset.l===l?K.cocoa:K.ink2);this.text(l);this.hap('.selection','Message language · '+(l==='id'?'Bahasa Indonesia':'English'));}
leave(){if(this.st!=='edit')return;this.st='away';this.hap('.impact(weight: .light)','Open WhatsApp · the message is prefilled');this.after(.15,()=>this.tw(this.V.aw,1,.2,this.rm?'easeInOut':'easeOut'));}
back(){if(this.st!=='away')return;this.st='sent';const V=this.V,rm=this.rm;this.tw(V.aw,0,.15,'easeIn');this.set(V.s1,0);
 this.cta.style.display='none';this.rep.style.display='flex';
 if(rm){this.set(V.s2,0);this.tw(V.s2,1,.2,'easeInOut');this.set(V.ro,0);this.tw(V.ro,1,.2,'easeInOut');['cs','wo','to'].forEach(k=>this.set(V[k],1));['wy','ty','my','ry'].forEach(k=>this.set(V[k],0));}
 else{this.set(V.s2,1);this.set(V.cs,0);this.sp(V.cs,1,'pop',.06);
  this.set(V.wy,16);this.set(V.wo,0);this.sp(V.wy,0,'settle',.10);this.tw(V.wo,1,.2,'easeOut',.10);this.set(V.my,-30);this.sp(V.my,0,'bounce',.16);
  this.set(V.ty,16);this.set(V.to,0);this.sp(V.ty,0,'settle',.16);this.tw(V.to,1,.2,'easeOut',.16);
  this.set(V.ry,40);this.set(V.ro,0);this.sp(V.ry,0,'arrive',.24);this.tw(V.ro,1,.2,'easeOut',.24);}
 this.hap('None','Back from WhatsApp · Sent to Atas; the button already gave its haptic');}
reset(){this.st='edit';this.l='id';const V=this.V;this.cta.style.display='';this.rep.style.display='none';
 Object.entries({s1:1,s2:0,aw:0,cs:1,wy:0,wo:1,ty:0,to:1,my:0,ro:0,ry:0}).forEach(([k,x])=>this.set(V[k],x));this.btns.forEach(b=>b.style.color=b.dataset.l==='id'?K.cocoa:K.ink2);this.text('id',true);this.place(true);}
}

/* 18 Upload a payment photo */
class Upload extends Mo{
build(){const R=progRing(56);this.C=R.C;
 this.sr.innerHTML=`<style>${BASE}:host{height:560px;padding:0}
 .top{padding:24px 16px}.card{background:#fff;border-radius:32px;padding:20px;display:flex;flex-direction:column;gap:12px}
 .amt{font:700 44px/1 Roundo,sans-serif;letter-spacing:-.02em}.sub{font:500 13px Manrope,sans-serif;color:${K.ink2}}
 .slot{position:relative;align-self:flex-start;width:140px;height:180px;margin-top:4px}
 .empty{position:absolute;inset:0;border-radius:16px;border:2px dashed ${K.mauve};display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;text-align:center;padding:12px;font:600 13px/1.35 Manrope,sans-serif;color:${K.ink2};cursor:pointer;background:${K.cream}}
 .th{position:absolute;inset:0;border-radius:16px;overflow:hidden;background:${K.mist};box-shadow:inset 0 0 0 1.5px ${K.mauve};visibility:hidden}
 .th>i{position:absolute;inset:0;background:repeating-linear-gradient(135deg,rgba(43,26,18,.1) 0 3px,transparent 3px 6px)}
 .th>span{position:absolute;left:0;right:0;bottom:10px;text-align:center;font:500 10px ui-monospace,Menlo,monospace;color:${K.ink3}}
 .ov{position:absolute;inset:0;background:rgba(43,26,18,.45);display:flex;align-items:center;justify-content:center}
 .pg{position:relative;width:56px;height:56px}.rt{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;color:${K.cream};font:600 12px Manrope,sans-serif;opacity:0}
 .ok{position:absolute;right:-8px;top:-8px;width:28px;height:28px;border-radius:50%;background:${K.lime};box-shadow:0 0 0 3px #fff;display:flex;align-items:center;justify-content:center;opacity:0}
 .bar{position:absolute;left:12px;right:12px;bottom:26px;padding:12px;border-radius:36px;${GL}}
 .pay{display:flex;align-items:center;justify-content:center;padding:14px 0;border-radius:999px;border:4px solid;color:${K.cream};font:600 17px/1.25 Manrope,sans-serif}</style>
 <div class="top"><div class="card"><span class="amt">Rp 99.500</span><span class="sub">to Rani · BCA · Friday Treats</span>
 <div class="slot"><button class="empty" aria-label="Add your transfer receipt"><span class="face" style="display:flex;flex-direction:column;align-items:center;gap:8px">${ic('image',22,K.car)}Add your transfer receipt</span></button>
 <div class="th"><i></i><span>receipt photo</span><div class="ov"><div class="pg">${R.html}</div><div class="rt">${ic('refresh',20,K.cream)}Tap to retry</div></div><span class="ok">${ic('check',14,K.cocoa,3)}</span></div></div></div></div>
 <div class="bar"><span class="pay">I’ve paid</span></div>`;
 const $=s=>this.q(s);Object.assign(this,{emp:$('.empty'),th:$('.th'),ov:$('.ov'),pg:$('.pg'),pr:$('.pr'),rt:$('.rt'),ok:$('.ok'),pay:$('.pay')});
 const p=()=>{const V=this.V;this.th.style.visibility=this.has?'visible':'hidden';this.th.style.transform=`translateX(${V.sh.v}px) scale(${V.ts.v})`;this.th.style.opacity=cl(V.to.v);this.emp.style.opacity=1-cl(V.to.v);
  this.pr.setAttribute('stroke-dashoffset',String(this.C*(1-cl(V.rg.v))));this.ov.style.opacity=cl(V.oo.v);this.pg.style.opacity=cl(V.po.v);this.rt.style.opacity=cl(V.rto.v);
  this.ok.style.opacity=cl(V.ko.v);this.ok.style.transform=this.rm?'none':`scale(${Math.max(0,V.ks.v)}) rotate(${-12*(1-V.ks.v)}deg)`;this.pay.style.transform=`scale(${V.pb.v})`;};
 const V=(x,e)=>this.v(x,p,e);this.V={ts:V(1),to:V(0),sh:V(0,.05),rg:V(0),oo:V(1),po:V(1),rto:V(0),ko:V(0),ks:V(1),pb:V(1)};
 this.P=this.wire(this.emp,this.emp.firstElementChild,[1.04,.92],{inert:()=>this.has,commit:()=>this.pick()});
 this.th.addEventListener('click',()=>{if(this.st==='fail')this.upload(true);});
 this.reset();}
paycol(on,ins){this.pay.style.transition=ins?'none':`background-color ${.2*this.slow}s,border-color ${.2*this.slow}s`;this.pay.style.backgroundColor=this.pay.style.borderColor=on?K.car:K.mauve;}
pick(){this.hap('.impact(weight: .light)','Add receipt · the photo picker opens (system)');this.after(.4,()=>{this.has=true;const V=this.V;
 if(this.rm){this.set(V.ts,1);this.set(V.to,0);this.tw(V.to,1,.2,'easeInOut');}else{this.set(V.ts,.9);this.set(V.to,0);this.sp(V.ts,1,'settle');this.tw(V.to,1,.2);}this.upload();});}
upload(retry){const V=this.V,rm=this.rm;this.st='up';this.set(V.rg,0);this.tw(V.rto,0,.12,'easeIn');this.tw(V.po,1,.12);this.set(V.oo,1);this.tw(V.rg,.85,2.4,'easeOut');
 if(retry)this.hap('.impact(weight: .light)','Retry upload');this.after(1.4,()=>this.getAttribute('result')==='fail'?this.fail():this.ok_());}
ok_(){const V=this.V,rm=this.rm;this.st='done';if(rm)this.tw(V.rg,1,.2,'easeInOut');else this.sp(V.rg,1,'lead');
 this.after(rm?.1:.2,()=>{this.tw(V.oo,0,.2,rm?'easeInOut':'easeOut');if(rm)this.tw(V.ko,1,.2,'easeInOut');else{this.set(V.ko,1);this.set(V.ks,0);this.sp(V.ks,1,'pop');}
  this.paycol(true);if(!rm){this.set(V.pb,1.05);this.sp(V.pb,1,'bump');}});this.hap('.success','Receipt uploaded');}
fail(){const V=this.V,rm=this.rm;this.st='fail';if(rm)this.tw(V.rg,0,.2,'easeInOut');else{this.sp(V.rg,0,'leave');this.keys(V.sh,[[0,0],[.05,4],[.12,-3],[.19,2],[.26,-1],[.32,0]]);}
 this.tw(V.po,0,.15,'easeIn');this.tw(V.rto,1,.2,'easeOut',.1);this.hap('.error','Upload failed · tap the photo to retry');}
reset(){this.has=false;this.st='idle';const V=this.V;Object.entries({ts:1,to:0,sh:0,rg:0,oo:1,po:1,rto:0,ko:0,ks:1,pb:1}).forEach(([k,x])=>this.set(V[k],x));this.paycol(false,true);this.P.rest();}
}

/* 19 Mark paid on the payment board */
const BRD=[['P','Putri',99500,'says',1],['K','Kevin',89500,'unpaid',0],['D','Dimas',38500,'paid',0],['A','Arief',26500,'says',1]];
const TG={unpaid:['Unpaid','#fff',K.cocoa,`inset 0 0 0 1.5px ${K.mauve}`],says:['Says paid',K.peach,K.cocoa,'none'],paid:['Paid',K.lime,K.cocoa,`inset 0 0 0 1.5px ${K.limeR}`]};
class Board extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:640px}
 .sum{background:#fff;border-radius:32px;padding:20px;display:flex;flex-direction:column;gap:12px}
 .bar{position:relative;height:16px;border-radius:999px;overflow:hidden}.sg{position:absolute;top:0;bottom:0}
 .tri{display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px}.tri div{display:flex;flex-direction:column;gap:2px}.tri em{display:flex;align-items:center;gap:5px;font:600 11px Manrope,sans-serif;font-style:normal;color:${K.ink2}}.tri em i{width:8px;height:8px;border-radius:50%}
 .tri .roll{font:700 17px Roundo,sans-serif}
 .list{margin-top:14px;background:#fff;border-radius:32px;padding:4px 16px}.row{display:flex;gap:12px;align-items:center;padding:14px 0;border-bottom:1px solid ${K.mist}}.row:last-child{border-bottom:0}
 .nm{font:700 16px Manrope,sans-serif}.rp{font:700 16px Roundo,sans-serif}
 .tag{display:inline-flex;align-items:center;gap:4px;height:19px;padding:0 10px;border-radius:999px;font:600 10px/1.4 Manrope,sans-serif;letter-spacing:.03em;text-transform:uppercase;white-space:nowrap;overflow:hidden;transform-origin:0 50%}.tag .roll{gap:4px}
 .rc{width:28px;height:36px;border-radius:6px;position:relative;overflow:hidden;background:${K.mist};box-shadow:inset 0 0 0 1.5px ${K.mauve}}.rc i{position:absolute;inset:0;background:repeating-linear-gradient(135deg,rgba(43,26,18,.1) 0 3px,transparent 3px 6px)}
 .act{overflow:hidden;display:flex;justify-content:flex-end}
 .mk .face,.ng .face{display:inline-flex;align-items:center;gap:5px;padding:5px 12px;border-radius:999px;font:600 12px Manrope,sans-serif;white-space:nowrap}
 .mk .face{background:${K.lime};box-shadow:inset 0 0 0 1.5px ${K.limeR}}.ng .face{background:${K.peach}}
 .meas{position:absolute;visibility:hidden;left:0;top:0}</style>
 <div class="sum"><div style="display:flex;justify-content:space-between;align-items:baseline"><span class="cap" style="color:${K.cocoa}">Owed to you</span><span style="font:700 18px Roundo,sans-serif">Rp 254.000</span></div>
  <div class="bar"><span class="sg s0" style="background:${K.limeR}"></span><span class="sg s1" style="background:#F39E60"></span><span class="sg s2" style="background:${K.mist}"></span></div>
  <div class="tri"><div><em><i style="background:${K.limeR}"></i>Collected</em><span class="roll t0"></span></div><div><em><i style="background:#F39E60"></i>To check</em><span class="roll t1"></span></div><div><em><i style="background:${K.mauve}"></i>Outstanding</em><span class="roll t2"></span></div></div></div>
 <div class="list">${BRD.map(([i,n,a,s,r])=>`<div class="row" data-k="${i}"><at-avatar i="${i}" size="40"></at-avatar><div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:6px"><div style="display:flex;justify-content:space-between;align-items:center"><span class="nm">${n}</span><span class="rp">${rp(a)}</span></div><div style="display:flex;align-items:center;gap:8px"><span class="tag"><span class="roll"></span></span><span style="flex:1"></span>${r?'<span class="rc"><i></i></span>':''}<span class="act">${s==='says'?`<button class="mk"><span class="face">${ic('check',12,null,3)}Mark paid</span></button>`:s==='unpaid'?`<button class="ng"><span class="face"><span class="roll ngl"></span></span></button>`:''}</span></div></div></div>`).join('')}</div>
 <span class="tag meas"><span class="roll"></span></span>`;
 this.meas=this.q('.meas');this.segs=[0,1,2].map(i=>this.q('.s'+i));this.tots=[0,1,2].map(i=>this.q('.t'+i));this.R={};
 const pb=()=>this.paintBar();this.F=[this.v(0,pb,.0005),this.v(0,pb,.0005),this.v(0,pb,.0005)];this.N=[0,1,2].map(i=>this.v(0,()=>{this.tots[i].firstElementChild&&(this.tots[i].firstElementChild.textContent=rp(this.N[i].v));},1));
 BRD.forEach(([i])=>{const row=this.qa('.row').find(e=>e.dataset.k===i),r={row,tag:row.querySelector('.tag'),act:row.querySelector('.act'),mk:row.querySelector('.mk'),ng:row.querySelector('.ng')};
  const p=()=>{r.tag.style.width=r.w.v+'px';r.tag.style.transform=`scale(${r.bs.v})`;r.act.style.width=r.aw.v>=0?Math.max(0,r.aw.v)+'px':'';r.act.style.opacity=cl(r.ao.v);};r.w=this.v(60,p,.05);r.bs=this.v(1,p);r.aw=this.v(-1,p,.05);r.ao=this.v(1,p);
  if(r.mk)r.P=this.wire(r.mk,r.mk.firstElementChild,[1.04,.92],{tone:()=>[K.lime,K.limeP],inert:()=>this.st[i]!=='says',commit:()=>this.mark(i)});
  if(r.ng)r.P=this.wire(r.ng,r.ng.firstElementChild,[1.04,.92],{tone:()=>[K.peach,K.peachP],blocked:()=>this.nudged,onBlocked:()=>{r.P.shake();this.hap('.impact(weight: .light, intensity: 0.5)','Nudge · already sent today');},commit:()=>this.nudge(i)});
  this.R[i]=r;});
 this.reset();if(document.fonts)document.fonts.ready.then(()=>{if(!this._t)this.reset();});}
sums(){const s=[0,0,0];BRD.forEach(([i,,a])=>{const st=this.st[i];s[st==='paid'?0:st==='says'?1:2]+=a;});return s;}
paintBar(){const W=this.segs[0].parentNode.clientWidth||322;let x=0;this.F.forEach((f,j)=>{const w=Math.max(0,f.v)*W;this.segs[j].style.left=x+'px';this.segs[j].style.width=Math.max(0,w-(j<2&&w>2.5?2:0))+'px';x+=w;});}
totals(ins){const s=this.sums(),T=s[0]+s[1]+s[2];s.forEach((v,j)=>{if(ins){this.tots[j].innerHTML=`<span class="rl">${rp(v)}</span>`;this.set(this.N[j],v);this.set(this.F[j],v/T);return;}
  if(this.rm){this.set(this.N[j],v);this.tw(this.F[j],v/T,.25,'easeInOut');this.fadeIn(this.tots[j]);}else{this.sp(this.N[j],v,'glide');this.sp(this.F[j],v/T,'trail');}});}
cw(k){const s=TG[k];this.meas.firstElementChild.innerHTML=`<span class="rl">${k==='paid'?ic('check',10,null,3):''}${s[0]}</span>`;return this.meas.offsetWidth;}
tagTo(r,k,ins){const s=TG[k];r.tag.style.transition=ins?'none':`background-color ${(this.rm?.2:.12)*this.slow}s,box-shadow ${(this.rm?.2:.12)*this.slow}s`;r.tag.style.backgroundColor=s[1];r.tag.style.color=s[2];r.tag.style.boxShadow=s[3];
 const html=(k==='paid'?ic('check',10,null,3):'')+s[0],w=this.cw(k);if(ins){r.tag.firstElementChild.innerHTML=`<span class="rl">${html}</span>`;this.set(r.w,w);return;}
 this.roll(r.tag.firstElementChild,html,1);if(this.rm)this.set(r.w,w);else{this.sp(r.w,w,'lead');this.after(.06,()=>{this.set(r.bs,1.08);this.sp(r.bs,1,'bump');});}}
mark(i){const r=this.R[i];this._t=1;this.st[i]='paid';this.tagTo(r,'paid');const w=r.act.offsetWidth;this.set(r.aw,w);
 if(this.rm)this.tw(r.ao,0,.2,'easeInOut',0,()=>this.set(r.aw,0));else{this.tw(r.ao,0,.12,'easeIn');this.sp(r.aw,0,'leave',.04);}
 this.after(this.rm?0:.10,()=>this.totals());this.hap('.success','Mark paid · '+BRD.find(b=>b[0]===i)[1]+'’s transfer confirmed');}
nudge(i){const r=this.R[i];this._t=1;this.nudged=1;this.roll(r.ng.querySelector('.ngl'),ic('check',12,null,3)+'Nudged',1);r.P.bump(1.15);
 this.tr(r.ng.firstElementChild,['background-color'],.12);r.ng.firstElementChild.style.backgroundColor=K.mist;this.hap('.impact(weight: .light)','Nudge · Kevin gets a reminder');}
reset(){this._t=0;this.nudged=0;this.st={};BRD.forEach(([i,,,s])=>{this.st[i]=s;const r=this.R[i];this.tagTo(r,s,true);this.set(r.aw,-1);this.set(r.ao,1);this.set(r.bs,1);if(r.P)r.P.rest();
  if(r.ng){r.ng.querySelector('.ngl').innerHTML=`<span class="rl">${ic('bell',13)}Nudge</span>`;r.ng.firstElementChild.style.transition='none';r.ng.firstElementChild.style.backgroundColor=K.peach;}});this.totals(true);}
}

/* 20 Share an invite */
class Share extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:700px}
 .bgt{font:700 26px/1.1 Roundo,sans-serif;display:block;margin:10px 0 16px}.blk{height:150px;border-radius:32px;background:#fff}
 .inv{margin-top:16px}.inv .face{display:flex;align-items:center;justify-content:center;gap:8px;padding:12px 24px;border-radius:999px;background:${K.cream};border:4px solid ${K.peach};font:600 16px/1.25 Manrope,sans-serif}
 .scrim{position:absolute;inset:0;background:rgba(43,26,18,.3);opacity:0;pointer-events:none}
 .sh{position:absolute;left:8px;right:8px;bottom:8px;border-radius:40px;${GL}padding:10px 18px 24px;visibility:hidden}
 .grab{display:block;margin:0 auto 12px;width:36px;height:5px;border-radius:3px;background:${K.mauve}}
 .hd{display:flex;align-items:center;justify-content:space-between;margin-bottom:14px}.hd b{font:700 17px Manrope,sans-serif}
 .x .face{width:30px;height:30px;border-radius:50%;background:${K.mist};display:flex;align-items:center;justify-content:center}
 .body{background:#fff;border-radius:32px;padding:20px;display:flex;flex-direction:column;align-items:center;gap:10px;text-align:center}
 .gn{font:700 20px/1.15 Roundo,sans-serif}.lk{display:flex;align-items:center;gap:6px;font:500 13px Manrope,sans-serif;color:${K.ink2}}
 .qr{padding:12px;border-radius:24px;background:${K.cream}}
 .lr{align-self:stretch;display:flex;justify-content:space-between;align-items:center;gap:8px;padding:10px 10px 10px 16px;border-radius:999px;background:${K.cream};font:600 14px Manrope,sans-serif}
 .cp .face{display:inline-flex;align-items:center;gap:6px;padding:6px 14px;border-radius:999px;background:${K.peach};font:600 13px Manrope,sans-serif}.cp .ico{position:relative;width:15px;height:15px}
 .two{display:flex;gap:10px;margin-top:12px}.wa{flex:1}.wa .face{display:flex;align-items:center;justify-content:center;gap:8px;padding:14px 0;border-radius:999px;background:${K.cocoa};border:4px solid ${K.cocoa};color:${K.cream};font:600 16px/1.25 Manrope,sans-serif}
 .sb .face{width:58px;height:58px;border-radius:50%;background:#fff;display:flex;align-items:center;justify-content:center}
 .toast{position:absolute;left:50%;bottom:42px;display:flex;align-items:center;gap:8px;padding:12px 20px;border-radius:999px;background:${K.cocoa};color:${K.cream};font:600 14px Manrope,sans-serif;white-space:nowrap;opacity:0;pointer-events:none}</style>
 <at-tag kind="open"></at-tag><span class="bgt">Academy Bali Friday Treats</span><div class="blk"></div>
 <button class="inv"><span class="face">${ic('share',18)}Invite people</span></button>
 <div class="scrim"></div>
 <div class="sh" role="dialog"><span class="grab"></span><div class="hd"><span style="width:30px"></span><b>Invite people</b><button class="x" aria-label="Close"><span class="face">${ic('x',16,K.cocoa,2.5)}</span></button></div>
  <div class="body"><span class="gn">Academy Bali Friday Treats</span><span class="lk">${ic('clock',14)}Locks Thu 2 Oct, 13:00 WITA</span><div class="qr"><at-qr size="176" seed="11"></at-qr></div>
  <div class="lr"><span>ataste.app/j/FRI-7Q2K</span><button class="cp"><span class="face"><span class="ico"><span class="lay c0">${ic('copy',15)}</span><span class="lay c1">${ic('check',15,null,3)}</span></span>Copy link</span></button></div></div>
  <div class="two"><button class="wa"><span class="face">${ic('wa',17)}Send on WhatsApp</span></button><button class="sb" aria-label="Share"><span class="face">${ic('share',18)}</span></button></div></div>
 <div class="toast">${ic('check',16,K.lime,3)}Link copied</div>`;
 const $=s=>this.q(s);Object.assign(this,{sh:$('.sh'),scrim:$('.scrim'),qr:$('.qr'),c0:$('.c0'),c1:$('.c1'),toast:$('.toast')});
 const p=()=>{const V=this.V;this.sh.style.visibility=this.vis?'visible':'hidden';this.sh.style.transform=`translateY(${Math.max(0,V.y.v)}px)`;this.sh.style.paddingBottom=(24+Math.max(0,-V.y.v))+'px';this.sh.style.opacity=cl(V.so.v);
  this.scrim.style.opacity=this.vis?cl(1-Math.max(0,V.y.v)/600)*cl(V.so.v):0;this.scrim.style.pointerEvents=this.open?'auto':'none';
  const q=cl(V.q.v);this.qr.style.clipPath=this.rm?'none':`circle(${q*75}% at 50% 50%)`;this.qr.firstElementChild.style.opacity=this.rm?q:1;
  const c=V.c.v;this.c1.style.opacity=c>.005?1:0;this.c1.style.transform=`scale(${Math.max(0,c)}) rotate(${-12*(1-c)}deg)`;this.c0.style.transform=`scale(${Math.max(0,1-c)})`;
  this.toast.style.opacity=cl(V.to.v);this.toast.style.transform=`translateX(-50%) translateY(${V.ty.v}px) scale(${V.ts.v})`;};
 const V=(x,e)=>this.v(x,p,e);this.V={y:V(900,.05),so:V(1),q:V(0),c:V(0),to:V(0),ty:V(24,.05),ts:V(.96)};
 this.wire($('.inv'),$('.inv .face'),[1.02,.92],{tone:()=>[K.cream,'#FDF8F2',K.peach,K.peachP],commit:()=>this.present()});
 this.wire($('.x'),$('.x .face'),[1.08,.88],{commit:()=>{this.dismiss();this.hap('.impact(weight: .light)','Close');}});
 this.scrim.addEventListener('click',()=>{if(this.open){this.dismiss();this.hap('None','Scrim tap');}});
 this.wire($('.cp'),$('.cp .face'),[1.04,.92],{tone:()=>[K.peach,K.peachP],commit:()=>this.copy()});
 this.wire($('.wa'),$('.wa .face'),[1.02,.92],{tone:()=>[K.cocoa,'#4A3329',K.cocoa,'#4A3329'],commit:()=>this.hap('.impact(weight: .light)','Send on WhatsApp · hands off as in 17')});
 this.wire($('.sb'),$('.sb .face'),[1.08,.88],{commit:()=>this.hap('.impact(weight: .light)','Share · the system share sheet takes over')});
 this.reset();}
present(){const V=this.V,rm=this.rm,h=this.sh.offsetHeight;this.vis=true;this.open=true;this.hap('.impact(weight: .light)','Invite people · sheet opens');
 if(rm){this.set(V.y,0);this.set(V.so,0);this.tw(V.so,1,.2,'easeInOut');this.set(V.q,0);this.tw(V.q,1,.2,'easeInOut',.1);return;}
 this.set(V.so,1);this.set(V.y,h+16);this.sp(V.y,0,'arrive');this.set(V.q,0);this.sp(V.q,1,'settle',.18);}
dismiss(){const V=this.V,h=this.sh.offsetHeight;this.open=false;const done=()=>{this.vis=false;V.y.paint();};if(this.rm)this.tw(V.so,0,.2,'easeInOut',0,done);else this.sp(V.y,h+16,'leave',0,done);V.y.paint();}
copy(){const V=this.V,rm=this.rm;if(rm)this.tw(V.c,1,.2,'easeInOut');else{this.set(V.c,0);this.sp(V.c,1,'pop');}clearTimeout(this._ci);this._ci=setTimeout(()=>this.tw(V.c,0,.2),1600*this.slow);
 if(V.to.t>0){if(!rm){this.set(V.ts,1.06);this.sp(V.ts,1,'bump');}}else if(rm){this.set(V.ty,0);this.set(V.ts,1);this.tw(V.to,1,.2,'easeInOut');}else{this.set(V.ty,24);this.set(V.ts,.96);this.sp(V.ty,0,'arrive');this.sp(V.ts,1,'arrive');this.tw(V.to,1,.2);}
 clearTimeout(this._tt);this._tt=setTimeout(()=>{if(this.rm)this.tw(V.to,0,.2,'easeInOut');else{this.tw(V.ty,8,.15,'easeIn');this.tw(V.to,0,.15,'easeIn');}},1800*this.slow);this.hap('.impact(weight: .light)','Link copied · toast (05)');}
reset(){clearTimeout(this._ci);clearTimeout(this._tt);this.vis=false;this.open=false;const V=this.V;Object.entries({y:900,so:1,q:0,c:0,to:0,ty:24,ts:.96}).forEach(([k,x])=>this.set(V[k],x));}
}

/* 21 Running-text band: flick on appear, coast, drag and fling */
class Bands extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:460px;padding:24px 0}
 .lb{display:block;padding:0 20px 8px;font:600 12px/1 Manrope,sans-serif;letter-spacing:.03em;text-transform:uppercase;color:${K.ink3}}
 .w{margin-bottom:34px}.tilt{transform:rotate(-3deg);margin:14px -12px 40px}</style>
 <span class="lb">Welcome (1-2) · tilted −3°</span><div class="tilt"><atm-band text="FRESH FROM ATAS • GROUP UP • SAVE ON ONGKIR • " bg="#2B1A12" fg="#FBF3EA" size="15"></atm-band></div>
 <span class="lb">Home (2-1)</span><div class="w"><atm-band text="FRESH FROM ATAS • GROUP UP • SAVE ON ONGKIR • " bg="#2B1A12" fg="#FBF3EA" size="15"></atm-band></div>
 <span class="lb">Discount unlocked (3-3)</span><div class="w"><atm-band text="DISCOUNT UNLOCKED • ONGKIR SORTED • KEEP ADDING • " bg="#2B1A12" fg="#E9FF83" size="13"></atm-band></div>`;
 this.bands=this.qa('atm-band');this.reset();}
sync(){this.bands.forEach(b=>{const r=this.rm?'1':'0',s=String(this.slow);if(b.getAttribute('rm')!==r)b.setAttribute('rm',r);if(b.getAttribute('slow')!==s)b.setAttribute('slow',s);});}
appear(){this.sync();this.bands.forEach((b,i)=>{b.reset&&b.reset();this.after(.3+i*.08,()=>b.flick&&b.flick(-800));});this.hap('None',this.rm?'Appear · Reduce Motion: bands stay still':'Appear · each band flicks once and coasts to a stop');}
reset(){this.sync();this.bands.forEach(b=>b.reset&&b.reset());}
}

/* 22 Empty states */
class Empty extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:640px}
 .hi{margin:0 0 20px;font:700 40px/1.05 Roundo,sans-serif;letter-spacing:-.02em}
 .c{display:flex;flex-direction:column;align-items:center;gap:14px;text-align:center}
 .fr{padding:10px;background:${K.car};border-radius:10px;box-shadow:0 14px 30px rgba(43,26,18,.25);transform-origin:50% 0}
 .fr>div{border:2px dashed rgba(251,243,234,.6);padding:5px;border-radius:4px}.pt{display:block;width:300px;height:167px;background:url(uploads/art/paint-supper.png) center/cover no-repeat,#3A2A22}
 .cap2{font:500 12px Manrope,sans-serif;color:${K.ink3}}.h{font:700 28px/1.1 Roundo,sans-serif}.b{font:500 15px/1.5 Manrope,sans-serif;color:${K.ink2};max-width:300px}
 .ctas{position:absolute;left:16px;right:16px;bottom:24px;display:flex;flex-direction:column;gap:10px}
 .p1{display:flex;align-items:center;justify-content:center;padding:14px 24px;border-radius:999px;background:${K.car};border:4px solid ${K.car};color:${K.cream};font:600 17px/1.25 Manrope,sans-serif}
 .row{display:flex;gap:10px}.row span{flex:1;display:flex;align-items:center;justify-content:center;gap:6px;padding:12px 0;border-radius:999px;background:${K.cream};border:4px solid ${K.peach};font:600 15px Manrope,sans-serif}</style>
 <h2 class="hi">Hi, Putri</h2>
 <div class="c"><div class="fr"><div><span class="pt" role="img" aria-label="The Last Supper Club"></span></div></div><span class="cap2"><i>The Last Supper Club</i> · oil on canvas</span><span class="h">No orders baking…yet!</span><span class="b">Start a group so everyone’s croissants count toward the Rp 200.000 ongkir discount.</span></div>
 <div class="ctas"><span class="p1">Start a group order</span><div class="row"><span>Order for myself</span><span>${ic('link',16)}Paste link</span></div></div>`;
 const $=s=>this.q(s);Object.assign(this,{fr:$('.fr'),cp:$('.cap2'),h:$('.h'),b:$('.b'),p1:$('.p1'),r2:$('.row')});
 const p=()=>{const V=this.V,rm=this.rm;this.fr.style.transform=rm?'rotate(-1.5deg)':`translateY(${V.fy.v}px) rotate(${V.fr.v}deg)`;this.fr.style.opacity=cl(V.fo.v);this.cp.style.opacity=cl(V.co.v);
  [[this.h,V.hy,V.ho],[this.b,V.by,V.bo]].forEach(([e,y,o])=>{e.style.transform=`translateY(${y.v}px)`;e.style.opacity=cl(o.v);});
  [[this.p1,V.py,V.po],[this.r2,V.ry,V.ro]].forEach(([e,y,o])=>{e.style.transform=`translateY(${y.v}px)`;e.style.opacity=cl(o.v);});};
 const V=(x,e)=>this.v(x,p,e);this.V={fy:V(0,.05),fr:V(-1.5,.05),fo:V(1),co:V(1),hy:V(0,.05),ho:V(1),by:V(0,.05),bo:V(1),py:V(0,.05),po:V(1),ry:V(0,.05),ro:V(1)};
 this.reset();}
first(){const V=this.V,rm=this.rm;
 if(rm){['fo','co','ho','bo','po','ro'].forEach((k,i)=>{this.set(V[k],0);this.tw(V[k],1,.2,'easeInOut');});this.hap('None','First view · fades in place');return;}
 this.set(V.fy,-24);this.set(V.fr,-6);this.set(V.fo,0);this.sp(V.fy,0,'bounce');this.sp(V.fr,-1.5,'bounce');this.tw(V.fo,1,.15);
 this.set(V.co,0);this.tw(V.co,1,.2,'easeOut',.18);
 [[V.hy,V.ho,.12],[V.by,V.bo,.18]].forEach(([y,o,d])=>{this.set(y,8);this.set(o,0);this.sp(y,0,'settle',d);this.tw(o,1,.2,'easeOut',d);});
 [[V.py,V.po,.24],[V.ry,V.ro,.30]].forEach(([y,o,d])=>{this.set(y,24);this.set(o,0);this.sp(y,0,'arrive',d);this.tw(o,1,.2,'easeOut',d);});
 this.hap('None','First view this session · the painting drops in and settles');}
again(){this.reset();this.hap('None','Seen before this session · shown still');}
reset(){Object.entries({fy:0,fr:-1.5,fo:1,co:1,hy:0,ho:1,by:0,bo:1,py:0,po:1,ry:0,ro:1}).forEach(([k,x])=>this.set(this.V[k],x));}
}

[['atm-ring',Ring],['atm-signin',SignIn],['atm-sendwa',SendWA],['atm-upload',Upload],['atm-board',Board],['atm-share',Share],['atm-bands',Bands],['atm-empty',Empty]].forEach(([n,c])=>customElements.define(n,c));
})();
