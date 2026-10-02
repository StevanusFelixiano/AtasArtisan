// Ataste Motion board, part 2 (ranks 7–15). Builds on ataste-motion.js (load it first): same Mo engine and Motion.* springs.
(function(){
if (customElements.get('atm-sheets')) return;
const A=window.AtMotion;if(!A){console.warn('Load ataste-motion.js before ataste-motion-2.js');return;}
const {Mo,K,rp,ic,GL,BASE}=A;
const rub=(x,d,c=.55)=>(1-1/(x*c/d+1))*d;
const cl=(x,a=0,b=1)=>Math.max(a,Math.min(b,x));
const PRESS_CARD=[1.015,.97];
const skipBtn=e=>e.composedPath().some(n=>n.tagName==='BUTTON');
function drag(el,o){let id=null,y0=0,ly=0,lt=0,vy=0;
 el.addEventListener('pointerdown',e=>{if(o.skip&&o.skip(e))return;id=e.pointerId;y0=ly=e.clientY;lt=performance.now();vy=0;try{el.setPointerCapture(id)}catch(_){};o.start&&o.start(e);});
 el.addEventListener('pointermove',e=>{if(e.pointerId!==id)return;const now=performance.now(),dt=Math.max(1,now-lt)/1000;vy=.7*((e.clientY-ly)/dt)+.3*vy;ly=e.clientY;lt=now;o.move&&o.move(e.clientY-y0);});
 const up=e=>{if(e.pointerId!==id)return;id=null;if(performance.now()-lt>80)vy=0;o.end&&o.end(ly-y0,vy);};
 el.addEventListener('pointerup',up);el.addEventListener('pointercancel',up);}
const relRect=(host,el)=>{const h=host.getBoundingClientRect(),r=el.getBoundingClientRect(),s=h.width/(host.offsetWidth||h.width)||1;return{x:(r.left-h.left)/s,y:(r.top-h.top)/s,w:r.width/s,h:r.height/s,W:host.offsetWidth,H:host.offsetHeight};};
const AVC={R:'#F39E60',P:'#E9FF83',K:'#F9B7D2',D:'#F9CFAF',N:'#D1B6BB',A:'#BCD947'};

/* 07 Sheets and confirms */
class Sheets extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:720px}
 .title{display:block;font:700 26px/1.1 Roundo,sans-serif;margin:10px 0 16px}
 .card{background:#fff;border-radius:32px;padding:18px 18px 8px}.rowc{overflow:hidden}
 .row{display:flex;gap:12px;align-items:center;height:76px}.rname{font:700 15px Manrope,sans-serif}.rsub{font:500 13px Manrope,sans-serif;color:${K.ink2}}
 .step{display:inline-flex;align-items:center;gap:10px;padding:3px;border-radius:999px;background:${K.cream}}
 .sb .face,.sbs{position:relative;display:block;width:28px;height:28px;border-radius:50%;background:${K.peach}}.tr .face{background:${K.redT}}
 .num{font:700 16px/1 Roundo,sans-serif;min-width:14px;text-align:center}
 .empty{display:block;font:500 14px/44px Manrope,sans-serif;color:${K.ink4};opacity:0;height:0;overflow:hidden}
 .host{margin-top:16px;display:flex;flex-direction:column;gap:10px}
 .sec .face{display:flex;align-items:center;justify-content:center;gap:8px;padding:12px 24px;border-radius:999px;background:${K.cream};border:4px solid ${K.peach};font:600 16px/1.25 Manrope,sans-serif}
 .scrim{position:absolute;inset:0;background:rgba(43,26,18,.3);opacity:0;pointer-events:none}
 .sh{position:absolute;left:8px;right:8px;bottom:8px;border-radius:40px;${GL}visibility:hidden;touch-action:none}
 .sh.cf{padding:10px 20px 36px}.sh.ed{top:62px;padding:10px 18px 18px}
 .grab{display:block;margin:0 auto;width:36px;height:5px;border-radius:3px;background:${K.mauve}}
 .col{display:flex;flex-direction:column;gap:14px}.ed .col{height:100%}
 .h{font:700 24px/1.1 Roundo,sans-serif}.p{font:500 15px/1.5 Manrope,sans-serif;color:${K.ink2}}
 .two{display:flex;gap:10px;margin-top:6px}.two button{flex:1}.two .face{display:block;text-align:center;padding:13px 0;border-radius:999px;border:4px solid;font:600 16px Manrope,sans-serif}
 .hdr{display:flex;justify-content:space-between;align-items:center}.cancel{font:600 16px Manrope,sans-serif;color:${K.car}}.ht{font:700 17px Manrope,sans-serif}
 .chips{display:flex;gap:8px}.chip{display:inline-flex;align-items:center;gap:6px;padding:5px 12px 5px 5px;border-radius:999px;background:#fff;font:600 14px Manrope,sans-serif;flex:none}.chip.on{background:${K.cocoa};color:${K.cream}}
 .field{height:48px;border-radius:12px;background:#fff;box-shadow:inset 0 0 0 1.5px ${K.mist};display:flex;align-items:center;padding:0 14px;font:500 15px Manrope,sans-serif}
 .cta{margin-top:auto}.cta .face{display:flex;align-items:center;justify-content:center;padding:14px 0;border-radius:999px;background:${K.car};border:4px solid ${K.car};color:${K.cream};font:600 17px/1.25 Manrope,sans-serif}</style>
 <at-tag kind="open"></at-tag><span class="title">Academy Bali Friday Treats</span>
 <div class="card"><span class="cap">My items</span><div class="rowc"><div class="row"><at-photo size="56" bg="${K.peach}"></at-photo><div style="flex:1;display:flex;flex-direction:column;gap:2px"><span class="rname">Pain Au Chocolate</span><span class="rsub">Rp 16.000</span></div><div class="step"><button class="sb tr" aria-label="Remove"><span class="face"><span class="lay">${ic('trash',14,K.red,2)}</span></span></button><span class="num">1</span><span class="sbs"><span class="lay">${ic('plus',15,K.cocoa,2.5)}</span></span></div></div></div><span class="empty">Nothing in the oven…yet!</span></div>
 <div class="host"><span class="cap">Host</span><button class="sec rq"><span class="face">${ic('edit',18)}Request an edit</span></button></div>
 <div class="scrim"></div>
 <div class="sh cf" role="dialog"><div class="col"><span class="grab"></span><span class="h">Remove Pain Au Chocolate?</span><span class="p">It comes out of your order. You can add it again while the group is open.</span><div class="two"><button class="keep"><span class="face" style="background:${K.cream};border-color:${K.mist}">Keep</span></button><button class="rmv"><span class="face" style="background:${K.red};border-color:${K.red};color:#fff">Remove</span></button></div></div></div>
 <div class="sh ed" role="dialog"><div class="col"><span class="grab"></span><div class="hdr"><button class="cancel">Cancel</button><span class="ht">Request an edit</span><span style="width:52px"></span></div>
  <span class="cap">Member</span><div class="chips"><span class="chip on"><at-avatar i="D" size="24"></at-avatar>Dimas</span><span class="chip"><at-avatar i="P" size="24"></at-avatar>Putri</span><span class="chip"><at-avatar i="K" size="24"></at-avatar>Kevin</span></div>
  <span class="cap">Reason</span><div class="field">Croissant sold out today, can you swap it?</div>
  <button class="cta"><span class="face">Send request</span></button></div></div>`;
 const $=s=>this.q(s);this.scrim=$('.scrim');this.rowc=$('.rowc');this.empty=$('.empty');
 const pr=()=>{this.rowc.style.height=Math.max(0,this.rh.v)+'px';this.rowc.style.opacity=cl(this.ro.v);this.empty.style.opacity=1-cl(this.ro.v);this.empty.style.height=(1-cl(this.rh.v/76))*44+'px';};this.rh=this.v(76,pr,.05);this.ro=this.v(1,pr);
 const mk=el=>{const s={el,vis:false,open:false,pb:parseFloat(getComputedStyle(el).paddingBottom)||0};const p=()=>{const y=s.y.v;el.style.visibility=s.vis?'visible':'hidden';el.style.transform=`translateY(${Math.max(0,y)}px)`;el.style.paddingBottom=(s.pb+Math.max(0,-y))+'px';el.style.opacity=cl(s.o.v);this.paintScrim();};s.y=this.v(900,p,.05);s.o=this.v(1,p);
  drag(el,{skip:skipBtn,start:()=>{s.y0=s.y.v;this.set(s.y,s.y.v);},move:dy=>{if(!s.open)return;const y=s.y0+dy;this.set(s.y,y<0?-rub(-y,s.h||400):y);},
   end:(dy,vy)=>{if(!s.open)return;const y=s.y.v;if(y>s.h*.3||vy>800){this.dismiss(s,vy);this.hap('None','Sheet dragged away · no haptic');}else{s.y.vel=vy;this.sp(s.y,0,this.rm?'leave':'arrive');}}});return s;};
 this.C=mk($('.cf'));this.E=mk($('.ed'));
 this.scrim.addEventListener('click',()=>{const s=[this.E,this.C].find(x=>x.open);if(s){this.dismiss(s);this.hap('None','Scrim tap · dismiss, no haptic');}});
 this.wire($('.tr'),$('.tr .face'),[1.08,.88],{tone:()=>[K.redT,'#F6C7CB'],inert:()=>this.rh.t===0,commit:()=>{this.present(this.C);this.hap('.impact(weight: .light)','Trash · opens the remove confirm');}});
 this.wire($('.rq'),$('.rq .face'),[1.02,.92],{tone:()=>[K.cream,'#FDF8F2',K.peach,K.peachP],commit:()=>{this.present(this.E);this.hap('.impact(weight: .light)','Request an edit · opens the sheet');}});
 this.wire($('.keep'),$('.keep .face'),[1.04,.92],{tone:()=>[K.cream,'#FDF8F2',K.mist,K.mist],commit:()=>{this.dismiss(this.C);this.hap('.impact(weight: .light)','Keep · confirm closes');}});
 this.wire($('.rmv'),$('.rmv .face'),[1.04,.92],{tone:()=>[K.red,K.redP,K.red,K.redP],commit:()=>{this.dismiss(this.C);this.after(.12,()=>this.removeRow());this.hap('.impact(weight: .medium)','Remove · confirmed');}});
 this.wire($('.cancel'),$('.cancel'),[1.04,.92],{commit:()=>{this.dismiss(this.E);this.hap('None','Cancel · text buttons give no haptic');}});
 this.wire($('.cta'),$('.cta .face'),[1.02,.92],{tone:()=>[K.car,K.carP,K.car,K.carP],commit:()=>{this.dismiss(this.E);this.hap('.impact(weight: .light)','Send request · Dimas’s chip turns Edits requested (.warning on his phone)');}});
 this.reset();}
paintScrim(){const pr=[this.C,this.E].filter(s=>s&&s.vis).map(s=>cl(1-Math.max(0,s.y.v)/(s.h||400))*cl(s.o.v));const m=pr.length?Math.max(...pr):0;this.scrim.style.opacity=m;this.scrim.style.pointerEvents=[this.C,this.E].some(s=>s&&s.open)?'auto':'none';}
present(s){s.vis=true;s.open=true;s.h=s.el.offsetHeight;if(this.rm){this.set(s.y,0);this.set(s.o,0);this.tw(s.o,1,.2,'easeInOut');}else{this.set(s.o,1);this.set(s.y,s.h+16);this.sp(s.y,0,'arrive');}}
dismiss(s,vy=0){s.open=false;const done=()=>{s.vis=false;s.y.paint();};if(this.rm){this.tw(s.o,0,.2,'easeInOut',0,done);return;}s.y.vel=vy;this.sp(s.y,(s.h||400)+16,'leave',0,done);this.paintScrim();}
removeRow(){if(this.rm){this.tw(this.ro,0,.2,'easeInOut',0,()=>this.set(this.rh,0));}else{this.sp(this.rh,0,'leave');this.tw(this.ro,0,.15,'easeIn');}}
reset(){[this.C,this.E].forEach(s=>{s.open=false;s.vis=false;this.set(s.o,1);this.set(s.y,900);});this.set(this.rh,76);this.set(this.ro,1);this.paintScrim();}
}

/* 08 Notifications while the app is open */
const NT={edit:['Rani asked you to edit an item','Almond Croissant: “Croissant sold out today, can you swap it?”','.warning','Edit request · for the member asked'],
 join:['Nadia joined Friday Treats','6 members now · Rp 155.000 of Rp 200.000.','.impact(weight: .light)','Someone joined · host only'],
 final:['Atas confirmed — your bill is final: Rp 99.500','The order is in — pay when you can. Transfer to Rani, BCA.','.success','Bill final'],
 cutoff:['Friday Treats locks in 30 minutes','Get your order in before 13:00. Rp 45.000 to go for the ongkir discount.','None','Reminder · information only, no haptic']};
class Banner extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:560px;padding:0}
 .bg{position:absolute;top:66px;left:20px;right:20px;display:flex;flex-direction:column;gap:2px}.bg span{font:500 15px Manrope,sans-serif;color:${K.ink2}}.bg h2{margin:0;font:700 40px/1.05 Roundo,sans-serif}
 .blocks{position:absolute;top:170px;left:16px;right:16px;display:grid;grid-template-columns:1fr 1fr;gap:12px}.blocks div{height:200px;border-radius:32px}
 .wb{position:absolute;top:384px;left:16px;right:16px;height:220px;border-radius:32px;background:#fff}
 .bn{position:absolute;top:54px;left:10px;right:10px;display:flex;gap:10px;align-items:flex-start;padding:12px 14px;border-radius:24px;background:rgba(251,243,234,.82);backdrop-filter:blur(22px) saturate(1.6);-webkit-backdrop-filter:blur(22px) saturate(1.6);box-shadow:inset 0 1px 0 rgba(255,255,255,.9),0 12px 30px rgba(43,26,18,.22);touch-action:none;cursor:pointer;visibility:hidden;transform-origin:50% 0}
 .ai{position:relative;width:38px;height:38px;border-radius:9px;background:${K.car};overflow:hidden;flex:none}.ai i{position:absolute;left:6px;top:3px;width:26px;height:26px;background:url(uploads/art/icon-head.png) center/cover no-repeat}.ai b{position:absolute;left:5px;right:5px;top:27px;height:7px;border-radius:5px;background:${K.cream};box-shadow:0 1.5px 0 ${K.cocoa}}
 .bt{flex:1;min-width:0}.bt .rl{display:flex;flex-direction:column;align-items:stretch;gap:1px;white-space:normal}
 .t1{display:flex;justify-content:space-between;gap:8px}.t1 span:first-child{font:600 15px/1.3 -apple-system,system-ui,sans-serif}.t1 span:last-child{font:400 13px -apple-system,system-ui,sans-serif;color:rgba(0,0,0,.5);flex:none}
 .t2{font:400 15px/1.3 -apple-system,system-ui,sans-serif}</style>
 <at-status style="position:absolute;top:0;left:0"></at-status>
 <div class="bg"><span>Thursday, 2 October</span><h2>Hi, Dimas</h2></div>
 <div class="blocks"><div style="background:#F9B7D2"></div><div style="background:${K.car}"></div></div><div class="wb"></div>
 <div class="bn" role="status"><div class="ai"><i></i><b></b></div><div class="bt roll"></div></div>`;
 this.bn=this.q('.bn');this.box=this.q('.bt');
 const p=()=>{const y=this.y.v;this.bn.style.visibility=this.vis?'visible':'hidden';this.bn.style.transform=`translateY(${Math.min(0,y)}px) scale(${this.bs.v*(1+(PRESS_CARD[0]-1)*this.sq.v)},${this.bs.v*(1+(PRESS_CARD[1]-1)*this.sq.v)})`;this.bn.style.paddingBottom=(12+Math.max(0,y))+'px';this.bn.style.opacity=cl(this.o.v)*this.dim.v;};
 this.y=this.v(-200,p,.05);this.o=this.v(1,p);this.bs=this.v(1,p);this.sq=this.v(0,p);this.dim=this.v(1,p);
 let moved=false;
 drag(this.bn,{start:()=>{if(!this.open)return;moved=false;clearTimeout(this._ht);this.y0=this.y.v;this.press(true);},
  move:dy=>{if(!this.open)return;if(Math.abs(dy)>6&&!moved){moved=true;this.press(false);}if(!moved)return;const y=this.y0+dy;this.set(this.y,y>0?rub(y,120):y);},
  end:(dy,vy)=>{if(!this.open)return;if(!moved){this.press(false);this.hide();this.hap('None','Tap · opens the screen; navigation has no haptic');return;}
   if(this.y.v<-24||vy<-300){this.y.vel=vy;this.hide(true);this.hap('None','Swiped away');}else{this.y.vel=vy;this.sp(this.y,0,this.rm?'leave':'arrive');this.timer();}}});
 this.reset();}
press(on){if(this.rm)this.tw(this.dim,on?.6:1,on?.10:.15);else this.sp(this.sq,on?1:0,on?'press':'release');}
html(k){const n=NT[k];return `<span class="t1"><span>${n[0]}</span><span>now</span></span><span class="t2">${n[1]}</span>`;}
show(k){const n=NT[k],rm=this.rm;
 if(!this.open){this.box.innerHTML=`<span class="rl">${this.html(k)}</span>`;this.open=true;this.vis=true;const h=this.bn.offsetHeight;
  if(rm){this.set(this.y,0);this.set(this.o,0);this.tw(this.o,1,.2,'easeInOut');}else{this.set(this.o,1);this.set(this.y,-(h+70));this.sp(this.y,0,'arrive');}}
 else{this.roll(this.box,this.html(k),1);if(!rm){this.set(this.bs,1.06);this.sp(this.bs,1,'bump');}}
 this.timer();this.hap(n[2],n[3]);}
timer(){clearTimeout(this._ht);this._ht=setTimeout(()=>this.hide(),4000*this.slow);}
hide(keepVel){if(!this.open)return;this.open=false;clearTimeout(this._ht);const h=this.bn.offsetHeight,done=()=>{this.vis=false;this.y.paint();};
 if(this.rm){this.tw(this.o,0,.2,'easeInOut',0,done);return;}if(!keepVel)this.y.vel=0;this.sp(this.y,-(h+70),'leave',0,done);}
reset(){clearTimeout(this._ht);this.open=false;this.vis=false;this.set(this.o,1);this.set(this.bs,1);this.set(this.sq,0);this.set(this.dim,1);this.set(this.y,-200);}
}

/* 09 Home choice cards and group cards opening */
class Cards extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:600px;padding:0}
 .top{position:absolute;top:28px;left:20px;right:20px;display:flex;flex-direction:column;gap:2px}.top span{font:500 15px Manrope,sans-serif;color:${K.ink2}}.top h2{margin:0;font:700 40px/1.05 Roundo,sans-serif;letter-spacing:-.02em}
 .grid{position:absolute;top:112px;left:16px;right:16px;display:grid;grid-template-columns:1fr 1fr;gap:12px}
 .cd{position:relative;overflow:hidden;border-radius:32px;cursor:pointer}.cd .in{height:200px;padding:16px;display:flex;flex-direction:column;justify-content:space-between}
 .cd.self{background:#F9B7D2}.cd.grp{background:${K.car};color:${K.cream}}
 .mas{position:absolute;right:-18px;top:-14px;width:120px;height:120px;border-radius:50%;background:url(uploads/art/pose-cakebox.png) center/cover no-repeat}
 .ct{display:flex;flex-direction:column;gap:4px}.ct b{font:700 22px/1.05 Roundo,sans-serif}.ct span{font:500 12px/1.35 Manrope,sans-serif}
 .lab{position:absolute;top:338px;left:20px;right:20px;display:flex;justify-content:space-between}.lab b{font:600 13px Manrope,sans-serif;color:${K.car}}
 .ord{position:absolute;top:364px;left:16px;right:16px;background:#fff}.ord .in{padding:20px;display:flex;flex-direction:column;gap:14px}
 .oh{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}.on{font:700 20px/1.15 Roundo,sans-serif}.os{display:flex;align-items:center;gap:6px;font:500 13px Manrope,sans-serif;color:${K.ink2};margin-top:4px}
 .pb{height:10px;border-radius:999px;background:${K.mist};overflow:hidden}.pb i{display:block;width:77.5%;height:100%;border-radius:999px;background:#F39E60}.pt{font:500 12px Manrope,sans-serif;color:${K.ink2}}.pt b{color:${K.car}}
 .zm{position:absolute;overflow:hidden;visibility:hidden;z-index:5}
 .src{position:absolute;left:0;top:0}.dst{position:absolute;left:0;top:0;width:402px;height:600px;opacity:0}
 .dh{display:flex;align-items:center;justify-content:space-between;gap:8px;padding:24px 16px 0}.dt{flex:1;text-align:center;font:600 17px/1.2 Manrope,sans-serif;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
 .back .face{width:44px;height:44px;border-radius:50%;display:flex;align-items:center;justify-content:center;${GL}}
 .db{padding:20px 16px;display:flex;flex-direction:column;gap:12px}.db .blk{border-radius:32px;background:#fff}</style>
 <div class="top"><span>Thursday, 2 October</span><h2>Hi, Putri</h2></div>
 <div class="grid">
  <div class="cd self" data-k="self" role="button" aria-label="Order for myself"><div class="in"><div class="mas"></div><span></span><div class="ct"><b>Order for myself</b><span>Just you. No invite, no split.</span></div></div></div>
  <div class="cd grp" data-k="grp" role="button" aria-label="Start a group order"><div class="in"><div style="display:flex"><at-avatar i="R" size="40" ring="#9D5C1D"></at-avatar><span style="margin-left:-10px"><at-avatar i="D" size="40" ring="#9D5C1D"></at-avatar></span><span style="margin-left:-10px"><at-avatar i="K" size="40" ring="#9D5C1D"></at-avatar></span></div><div class="ct"><b>Start a group order</b><span style="color:${K.peach}">Reach Rp 200.000 together, save on ongkir.</span></div></div></div>
 </div>
 <div class="lab"><span class="cap" style="color:${K.cocoa}">Active orders</span><b>1</b></div>
 <div class="cd ord" data-k="ord" role="button" aria-label="Academy Bali Friday Treats"><div class="in"><div class="oh"><div><div class="on">Academy Bali Friday Treats</div><div class="os"><at-avatar i="R" size="18"></at-avatar>Rani · Fri 3 Oct, 10:00 WITA</div></div><at-tag kind="open"></at-tag></div><div style="display:flex;flex-direction:column;gap:6px"><div class="pb"><i></i></div><span class="pt"><b>Rp 45.000 more</b> to unlock the ongkir discount</span></div></div></div>
 <div class="zm"><div class="src"></div><div class="dst"><div class="dh"><button class="back" aria-label="Back"><span class="face">${ic('chev-l',22,K.cocoa,2.4)}</span></button><span class="dt"></span><span style="width:44px"></span></div><div class="db"><span class="dtag"></span><div class="blk" style="height:150px"></div><div class="blk" style="height:220px"></div></div></div></div>`;
 this.zm=this.q('.zm');this.src=this.q('.src');this.dst=this.q('.dst');
 const p=()=>{const z=this.zm.style;z.left=this.L.v+'px';z.top=this.T.v+'px';z.right=this.R.v+'px';z.bottom=this.B.v+'px';z.borderRadius=Math.max(0,this.rad.v)+'px';z.visibility=this.vis?'visible':'hidden';z.opacity=cl(this.zo.v);this.src.style.opacity=cl(this.so.v);this.dst.style.opacity=cl(this.do_.v);};
 this.L=this.v(0,p,.05);this.T=this.v(0,p,.05);this.R=this.v(0,p,.05);this.B=this.v(0,p,.05);this.rad=this.v(32,p,.05);this.zo=this.v(1,p);this.so=this.v(1,p);this.do_=this.v(0,p);
 const D={self:['Personal order',''],grp:['Create group',''],ord:['Academy Bali Friday Treats','open']};
 this.qa('.cd').forEach(c=>this.wire(c,c,PRESS_CARD,{inert:()=>this.vis,commit:()=>this.open(c,D[c.dataset.k])}));
 this.wire(this.q('.back'),this.q('.back .face'),[1.08,.88],{commit:()=>{this.close();this.hap('None','Back · navigation has no haptic');}});
 this.reset();}
open(c,d){const r=relRect(this,c),rm=this.rm;this.card=c;this.r=r;this.vis=true;
 this.q('.dt').textContent=d[0];this.q('.dtag').innerHTML=d[1]?`<at-tag kind="${d[1]}"></at-tag>`:'';
 const bg=getComputedStyle(c).backgroundColor;this.cbg=bg;this.src.innerHTML=c.innerHTML;this.src.style.width=r.w+'px';this.src.style.height=r.h+'px';this.src.style.color=getComputedStyle(c).color;
 this.zm.style.transition='none';this.zm.style.backgroundColor=bg;
 if(rm){[this.L,this.T,this.R,this.B].forEach(o=>this.set(o,0));this.set(this.rad,0);this.set(this.so,0);this.set(this.do_,1);this.zm.style.backgroundColor=K.cream;this.set(this.zo,0);this.tw(this.zo,1,.2,'easeInOut');}
 else{this.set(this.zo,1);this.set(this.L,r.x);this.set(this.T,r.y);this.set(this.R,r.W-r.x-r.w);this.set(this.B,r.H-r.y-r.h);this.set(this.rad,32);this.set(this.so,1);this.set(this.do_,0);
  c.style.visibility='hidden';this.sp(this.L,0,'lead');this.sp(this.T,0,'lead');this.sp(this.R,0,'lead');this.sp(this.B,0,'trail');this.sp(this.rad,0,'lead');
  this.tw(this.so,0,.15,'easeIn');this.tw(this.do_,1,.2,'easeOut',.12);requestAnimationFrame(()=>{this.tr(this.zm,['background-color'],.2);this.zm.style.transitionDelay=(.06*this.slow)+'s';this.zm.style.backgroundColor=K.cream;});}
 this.hap('None','Open · navigation has no haptic');}
close(){const r=this.r,c=this.card,rm=this.rm,done=()=>{this.vis=false;c.style.visibility='';this.zo.paint();};if(!c)return;
 if(rm){this.tw(this.zo,0,.2,'easeInOut',0,done);return;}
 this.tw(this.do_,0,.15,'easeIn');this.tw(this.so,1,.2,'easeOut',.06);this.tr(this.zm,['background-color'],.2);this.zm.style.transitionDelay='0s';this.zm.style.backgroundColor=this.cbg;
 this.sp(this.L,r.x,'lead');this.sp(this.T,r.y,'lead');this.sp(this.R,r.W-r.x-r.w,'lead');this.sp(this.rad,32,'lead');this.sp(this.B,r.H-r.y-r.h,'trail',0,done);}
reset(){this.vis=false;this.qa('.cd').forEach(c=>c.style.visibility='');this.set(this.zo,1);this.set(this.do_,0);}
}

/* 10 Split: assigning shares to people */
const PPL=[['R','Rani'],['P','You'],['K','Kevin'],['D','Dimas'],['N','Nadia'],['A','Arief']];
class Split extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:700px}
 .it{display:flex;gap:12px;align-items:center;padding:12px;border-radius:24px;background:#fff}.itn{font:700 16px Manrope,sans-serif}.its{font:500 13px Manrope,sans-serif;color:${K.ink2}}
 .sec{display:flex;flex-direction:column;gap:8px;margin-top:14px}.hd{display:flex;justify-content:space-between;align-items:baseline;padding:0 4px}
 .chips{display:flex;gap:8px;flex-wrap:wrap}.ch .face{display:inline-flex;align-items:center;gap:6px;padding:5px 12px 5px 5px;border-radius:999px;background:#fff;box-shadow:inset 0 0 0 1.5px ${K.mauve};font:600 14px Manrope,sans-serif;white-space:nowrap}
 .even{font:600 12px Manrope,sans-serif;color:${K.car}}
 .bar{position:relative;height:16px;border-radius:999px;overflow:hidden;background:${K.mist}}.seg{position:absolute;top:0;bottom:0;left:0;width:0}
 .rows{background:#fff;border-radius:24px;padding:2px 14px}.rc{overflow:hidden;height:0}.row{display:flex;align-items:center;gap:10px;padding:11px 0;border-bottom:1px solid ${K.mist}}
 .rn{font:700 15px Manrope,sans-serif}.rs{font:500 12px Manrope,sans-serif;color:${K.ink2}}
 .step{display:inline-flex;align-items:center;gap:10px;padding:3px;border-radius:999px;background:${K.cream}}.sb .face{display:block;position:relative;width:28px;height:28px;border-radius:50%;background:${K.peach}}
 .num{min-width:52px;justify-content:center;font:700 15px/1 Roundo,sans-serif}
 .tot{display:flex;align-items:center;padding-left:4px;font:600 13px Manrope,sans-serif;gap:6px}</style>
 <div class="it"><at-photo size="56" bg="${K.peach}"></at-photo><div style="flex:1;display:flex;flex-direction:column;gap:2px"><span class="itn">Burnt Cheesecake 20 cm</span><span class="its">Rp 260.000 · under Rani’s name</span></div></div>
 <div class="sec"><span class="cap" style="color:${K.cocoa};padding-left:4px">Who’s sharing</span><div class="chips">${PPL.map(([i,n])=>`<button class="ch" data-k="${i}" aria-label="${n}"><span class="face"><at-avatar i="${i}" size="24"></at-avatar>${n}</span></button>`).join('')}</div></div>
 <div class="sec"><div class="hd"><span class="cap" style="color:${K.cocoa}">Shares · in slices of 12</span><button class="even">Split evenly</button></div>
  <div class="bar">${PPL.map(([i])=>`<span class="seg" data-k="${i}" style="background:${AVC[i]}"></span>`).join('')}</div>
  <div class="rows">${PPL.map(([i,n])=>`<div class="rc" data-k="${i}"><div class="row"><at-avatar i="${i}" size="32"></at-avatar><div style="flex:1;display:flex;flex-direction:column;gap:1px"><span class="rn">${n}</span><span class="rs"></span></div><div class="step"><button class="sb mi" aria-label="Fewer slices"><span class="face"><span class="lay">${ic('minus',14,K.cocoa,2.5)}</span></span></button><span class="roll num"></span><button class="sb pl" aria-label="More slices"><span class="face"><span class="lay">${ic('plus',14,K.cocoa,2.5)}</span></span></button></div></div></div>`).join('')}</div>
  <span class="tot roll"></span></div>`;
 this.barEl=this.q('.bar');this.totEl=this.q('.tot');this.S={};
 const pb=()=>this.paintBar();
 PPL.forEach(([i])=>{const rc=this.qa('.rc').find(e=>e.dataset.k===i),ch=this.qa('.ch').find(e=>e.dataset.k===i),seg=this.qa('.seg').find(e=>e.dataset.k===i);
  const s={i,rc,ch,seg,face:ch.querySelector('.face'),rs:rc.querySelector('.rs'),num:rc.querySelector('.num'),miF:rc.querySelector('.mi .face'),plF:rc.querySelector('.pl .face')};
  const pr=()=>{rc.style.height=Math.max(0,s.h.v)+'px';rc.style.opacity=cl(s.o.v);};s.h=this.v(0,pr,.05);s.o=this.v(0,pr);s.fr=this.v(0,pb,.0005);
  s.Pch=this.wire(ch,s.face,[1.04,.92],{blocked:()=>i==='R'&&s.on,onBlocked:()=>{s.Pch.shake();this.hap('.impact(weight: .light, intensity: 0.5)','Rani owns the item and stays in the split');},commit:()=>this.toggle(i)});
  s.Pmi=this.wire(rc.querySelector('.mi'),s.miF,[1.08,.88],{tone:()=>[K.peach,K.peachP],blocked:()=>s.n<=0,onBlocked:()=>this.blocked(),commit:()=>this.step(i,-1)});
  s.Ppl=this.wire(rc.querySelector('.pl'),s.plF,[1.08,.88],{tone:()=>[K.peach,K.peachP],blocked:()=>this.total()>=12,onBlocked:()=>this.blocked(),commit:()=>this.step(i,1)});
  this.S[i]=s;});
 this.Ptot=this.mkP(this.totEl,[1,1]);
 this.wire(this.q('.even'),this.q('.even'),[1.04,.92],{commit:()=>this.even()});
 this.reset();}
total(){return PPL.reduce((a,[i])=>a+(this.S[i].on?this.S[i].n:0),0)}
paintBar(){const W=this.barEl.clientWidth||322;let x=0;PPL.forEach(([i])=>{const s=this.S[i],w=Math.max(0,s.fr.v)*W;s.seg.style.left=x+'px';s.seg.style.width=Math.max(0,w-(w>2.5?2:w))+'px';x+=w;});}
chipLook(s,ins){s.face.style.transition=ins?'none':`background-color ${(this.rm?.2:.12)*this.slow}s,color ${(this.rm?.2:.12)*this.slow}s,box-shadow ${(this.rm?.2:.12)*this.slow}s`;s.face.style.backgroundColor=s.on?K.cocoa:'#fff';s.face.style.color=s.on?K.cream:K.cocoa;s.face.style.boxShadow=s.on?'none':`inset 0 0 0 1.5px ${K.mauve}`;}
upd(ins,dirs){const rm=this.rm;PPL.forEach(([i])=>{const s=this.S[i],n=s.on?s.n:0,f=n/12;
  s.rs.textContent=Math.round(f*100)+'% · '+rp(260000*f);
  if(ins||s.shown!==n){const d=dirs&&dirs[i];if(ins||!d)s.num.innerHTML=`<span class="rl">${n}</span>`;else this.roll(s.num,String(n),d);s.shown=n;}
  if(ins)this.set(s.fr,f);else if(rm)this.tw(s.fr,f,.25,'easeInOut');else this.sp(s.fr,f,'trail');
  s.plF.firstElementChild.style.opacity=this.total()>=12?.4:1;s.miF.firstElementChild.style.opacity=n<=0?.4:1;});
 const t=this.total(),done=t===12,html=done?`${ic('check',14,'#5E7A00',3)}<span style="color:#5E7A00">12 of 12 slices · 100%</span>`:`${ic('pie',14,K.car,2.2)}<span style="color:${K.car}">${t} of 12 slices · ${12-t} left</span>`;
 if(ins||this._tt===undefined)this.totEl.innerHTML=`<span class="rl">${html}</span>`;else if(this._tt!==t)this.roll(this.totEl,html,t>this._tt?1:-1);this._tt=t;}
row(s,open,ins){const h=s.rc.querySelector('.row').offsetHeight||57;if(ins){this.set(s.h,open?h:0);this.set(s.o,open?1:0);return;}
 if(open){this.set(s.o,0);if(this.rm){this.set(s.h,h);this.tw(s.o,1,.2,'easeInOut');}else{this.sp(s.h,h,'settle',.04);this.tw(s.o,1,.2,'easeOut',.08);}}
 else{if(this.rm)this.tw(s.o,0,.2,'easeInOut',0,()=>this.set(s.h,0));else{this.sp(s.h,0,'leave');this.tw(s.o,0,.15,'easeIn');}}}
toggle(i){const s=this.S[i];s.on=!s.on;if(!s.on)s.n=0;this.chipLook(s);this.row(s,s.on);this.upd();this.hap('.selection',(s.on?'Added ':'Removed ')+(i==='P'?'you':PPL.find(p=>p[0]===i)[1])+' · shares');}
step(i,d){const s=this.S[i];s.n+=d;(d>0?s.Ppl:s.Pmi).dip();this.upd(false,{[i]:d});this.hap(d>0?'.increase':'.decrease','Slices · '+s.n+' of 12');}
blocked(){this.Ptot.shake();this.hap('.impact(weight: .light, intensity: 0.5)','Slices · all 12 assigned, or none to take away');}
even(){const on=PPL.filter(([i])=>this.S[i].on),n=on.length,b=Math.floor(12/n);let r=12-b*n;const dirs={};on.forEach(([i])=>{const s=this.S[i],v=b+(r>0?1:0);if(r>0)r--;dirs[i]=v>s.n?1:v<s.n?-1:0;s.n=v;});this.upd(false,dirs);this.hap('.selection','Split evenly · '+n+' people');}
reset(){const init={R:6,P:3,K:3};PPL.forEach(([i])=>{const s=this.S[i];s.on=i in init;s.n=init[i]||0;s.shown=undefined;[s.Pch,s.Pmi,s.Ppl].forEach(p=>p.rest());this.chipLook(s,true);this.row(s,s.on,true);});this._tt=undefined;this.Ptot.rest();this.upd(true);
 if(document.fonts&&!this._fr){this._fr=1;document.fonts.ready.then(()=>PPL.forEach(([i])=>this.row(this.S[i],this.S[i].on,true)));}}
}

/* 11 Avatars joining a group */
const MEM={R:['Rani','· host','Rp 57.000','2× Butter Croissant · 1× Classic Sourdough · 1000 gr · Sliced 15mm'],D:['Dimas','','Rp 44.000','1× Almond Croissant · 2× Cinnamon Roll 60 gr'],K:['Kevin','','Rp 22.000','1× Brioche Bun · 1× English Muffin · 1× Pretzel 120 gr'],N:['Nadia','','Rp 0',''],A:['Arief','','Rp 0','']};
class Members extends Mo{
build(){
 const ids=Object.keys(MEM);
 this.sr.innerHTML=`<style>${BASE}:host{height:640px}
 .gh{display:flex;align-items:center;justify-content:space-between;background:#fff;border-radius:32px;padding:18px 20px}
 .stack{position:relative;height:40px;width:170px}.av{position:absolute;left:0;top:0;transform-origin:50% 60%}
 .hd{display:flex;justify-content:space-between;align-items:baseline;padding:16px 4px 10px}.hd .roll{font:600 12px/1 Manrope,sans-serif;letter-spacing:.03em;text-transform:uppercase}
 .inv{display:inline-flex;align-items:center;gap:4px;font:600 13px Manrope,sans-serif;color:${K.car}}
 .list{background:#fff;border-radius:32px;padding:4px 18px}.rc{overflow:hidden;height:0}
 .row{display:flex;gap:12px;padding:14px 0;border-bottom:1px solid ${K.mist}}.ra{transform-origin:50% 60%}
 .nm{font:700 16px Manrope,sans-serif}.rl2{font:500 12px Manrope,sans-serif;color:${K.ink3}}.sub{font:700 16px Roundo,sans-serif}.its{font:500 13px/1.45 Manrope,sans-serif}</style>
 <div class="gh"><div style="display:flex;flex-direction:column;gap:4px"><span style="font:700 20px/1.15 Roundo,sans-serif">Friday Treats</span><at-tag kind="open" size="s"></at-tag></div><div class="stack">${ids.map(i=>`<span class="av" data-k="${i}"><at-avatar i="${i}" size="40" ring="#fff"></at-avatar></span>`).join('')}</div></div>
 <div class="hd"><span class="roll cnt"></span><span class="inv">${ic('share',14)}Invite</span></div>
 <div class="list">${ids.map(i=>{const m=MEM[i];return `<div class="rc" data-k="${i}"><div class="row"><span class="ra"><at-avatar i="${i}" size="40"></at-avatar></span><div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:4px"><div style="display:flex;justify-content:space-between;align-items:center"><span class="nm">${m[0]} <span class="rl2">${m[1]}</span></span><span class="sub">${m[2]}</span></div><span class="its" style="color:${m[3]?K.ink2:K.ink4}">${m[3]||'Nothing in the oven…yet!'}</span></div></div></div>`;}).join('')}</div>`;
 this.cnt=this.q('.cnt');this.M={};
 ids.forEach(i=>{const av=this.qa('.av').find(e=>e.dataset.k===i),rc=this.qa('.rc').find(e=>e.dataset.k===i),ra=rc.querySelector('.ra'),m={av,rc,ra};
  const p=()=>{av.style.transform=this.rm?`translateX(${m.x.v}px)`:`translateX(${m.x.v}px) scale(${Math.max(0,m.s.v)}) rotate(${-12*(1-m.s.v)}deg)`;av.style.opacity=cl(m.o.v);rc.style.height=Math.max(0,m.h.v)+'px';rc.style.opacity=cl(m.ro.v);ra.style.transform=this.rm?'none':`scale(${Math.max(0,m.rs.v)}) rotate(${-12*(1-m.rs.v)}deg)`;};
  m.x=this.v(0,p,.05);m.s=this.v(1,p);m.o=this.v(1,p);m.h=this.v(0,p,.05);m.ro=this.v(1,p);m.rs=this.v(1,p);this.M[i]=m;});
 this.reset();}
order(){return this.list}
layout(ins){this.list.forEach((i,j)=>{const m=this.M[i];if(ins||this.rm)this.set(m.x,j*30);else this.sp(m.x,j*30,'settle');});}
setCount(ins){const t='Members · '+this.list.length;if(ins)this.cnt.innerHTML=`<span class="rl">${t}</span>`;else this.roll(this.cnt,t,this.list.length>this._n?1:-1);this._n=this.list.length;}
join(i){if(this.list.includes(i))return;const m=this.M[i],rm=this.rm,h=m.rc.querySelector('.row').offsetHeight||69;this.list.push(i);
 this.set(m.x,(this.list.length-1)*30);
 if(rm){this.set(m.s,1);this.set(m.o,0);this.tw(m.o,1,.2,'easeInOut');this.set(m.h,h);this.set(m.ro,0);this.tw(m.ro,1,.2,'easeInOut');this.set(m.rs,1);}
 else{this.set(m.o,1);this.set(m.s,0);this.sp(m.s,1,'pop');this.set(m.ro,0);this.set(m.h,0);this.sp(m.h,h,'settle',.06);this.tw(m.ro,1,.2,'easeOut',.06);this.set(m.rs,0);this.sp(m.rs,1,'pop',.06);}
 this.setCount();this.hap('None',MEM[i][0]+' joined · the banner (08) carries the host’s haptic');}
leave(i){const j=this.list.indexOf(i);if(j<0)return;const m=this.M[i],rm=this.rm;this.list.splice(j,1);
 if(rm){this.tw(m.o,0,.2,'easeInOut');this.tw(m.ro,0,.2,'easeInOut',0,()=>this.set(m.h,0));}
 else{this.tw(m.s,0,.15,'easeIn');this.tw(m.o,0,.15,'easeIn');this.sp(m.h,0,'leave');this.tw(m.ro,0,.15,'easeIn');}
 this.layout();this.setCount();this.hap('None',MEM[i][0]+' left · no haptic for watchers');}
reset(){this.list=['R','D','K'];Object.entries(this.M).forEach(([i,m])=>{const on=this.list.includes(i);this.set(m.s,1);this.set(m.rs,1);this.set(m.o,on?1:0);this.set(m.ro,on?1:0);this.set(m.h,on?(m.rc.querySelector('.row').offsetHeight||69):0);});this.layout(true);this._n=3;this.setCount(true);
 if(document.fonts&&!this._fr){this._fr=1;document.fonts.ready.then(()=>Object.entries(this.M).forEach(([i,m])=>{if(this.list.includes(i)&&!m.h.mode)this.set(m.h,m.rc.querySelector('.row').offsetHeight||69);}));}}
}

/* 12 The bill settling into final numbers */
const BC={notfinal:['Not final yet',K.mist,K.cocoa,'none'],final:['Final',K.lime,K.cocoa,`inset 0 0 0 1.5px ${K.limeR}`],unpaid:['Unpaid','#fff',K.cocoa,`inset 0 0 0 1.5px ${K.mauve}`]};
class Bill extends Mo{
build(){
 const L=[['2× Pain Au Chocolate','my items','Rp 32.000'],['Burnt Cheesecake · 25%','split with Rani and Kevin · under Rani','Rp 65.000'],['Ongkir share','Rp 30.000 ÷ 6','Rp 5.000'],['Discount share','Rp 15.000 ÷ 6','− Rp 2.500']];
 this.sr.innerHTML=`<style>${BASE}:host{height:660px}
 .card{background:#fff;border-radius:32px;padding:20px;display:flex;flex-direction:column;gap:12px}
 .chips{display:flex;justify-content:space-between;align-items:center;height:23px}
 .chip{display:inline-flex;align-items:center;height:23px;padding:0 14px;border-radius:999px;font:600 11px/1.4 Manrope,sans-serif;letter-spacing:.03em;text-transform:uppercase;white-space:nowrap;overflow:hidden;transform-origin:0 50%}.chip.r{transform-origin:100% 50%}
 .meas{position:absolute;left:0;top:0;visibility:hidden}
 .amt{display:flex;align-items:baseline;font:700 46px/1 Roundo,sans-serif;letter-spacing:-.02em;white-space:nowrap}.ap{display:inline-block;overflow:hidden}
 .cap2{display:grid}.cap2>span{grid-area:1/1;font:500 13px/1.45 Manrope,sans-serif;color:${K.ink2}}
 .lines{display:flex;flex-direction:column;gap:8px;padding-top:12px;border-top:1px dashed ${K.mauve}}
 .ln{display:flex;justify-content:space-between;gap:12px}.ll{font:600 14px Manrope,sans-serif}.lm{display:block;overflow:hidden;height:0;font:500 12px/16px Manrope,sans-serif;color:${K.ink3}}.lv{font:600 14px Manrope,sans-serif;white-space:nowrap}
 .lc{overflow:hidden}
 .wait{margin-top:14px;overflow:hidden}.wi{display:flex;gap:12px;align-items:center;padding:16px;border-radius:24px;background:${K.mist}}.wm{width:56px;height:56px;border-radius:50%;background:#fff url(uploads/art/pose-waiting.png) center/cover no-repeat;flex:none}
 .bar{position:absolute;left:12px;right:12px;bottom:26px;padding:12px;border-radius:36px;${GL}}
 .pay{display:flex;align-items:center;justify-content:center;padding:14px 0;border-radius:999px;border:4px solid;font:600 17px/1.25 Manrope,sans-serif;color:${K.cream}}</style>
 <div class="card"><div class="chips"><span class="chip l"><span class="roll"></span></span><span class="chip r"><span class="roll"></span></span></div>
  <div class="amt"><span class="ap">≈&nbsp;</span><span class="av"></span></div>
  <div class="cap2"><span class="c1">Your items so far. Ongkir and any discount get added when Atas confirms.</span><span class="c2" style="opacity:0">to Rani · Friday Treats</span></div>
  <div class="lines">${L.map(([a,m,v],j)=>`<div class="lc" data-j="${j}"><div class="ln"><div><span class="ll">${a}</span><span class="lm">${m}</span></div><span class="lv roll"></span></div></div>`).join('')}</div></div>
 <div class="wait"><div class="wi"><div class="wm" role="img" aria-label="Mascot waiting"></div><span style="font:600 14px/1.45 Manrope,sans-serif">The order is in — pay when you can. We’ll tell you the final amount.</span></div></div>
 <div class="bar"><span class="pay">I’ve paid</span></div><span class="chip meas"></span>`;
 this.L=L;const $=s=>this.q(s);this.cl=$('.chip.l');this.cr=$('.chip.r');this.meas=$('.meas');this.ap=$('.ap');this.av=$('.av');this.amt=$('.amt');this.c1=$('.c1');this.c2=$('.c2');this.wait=$('.wait');this.pay=$('.pay');
 this.lc=this.qa('.lc');this.lm=this.qa('.lm');this.lv=this.qa('.lv');this.ll=this.qa('.ll');
 const p=()=>{this.cl.style.width=this.wl.v+'px';this.cl.style.transform=`scale(${this.bl.v})`;this.cr.style.opacity=cl(this.ro.v);this.cr.style.transform=this.rm?'none':`scale(${Math.max(0,this.rs.v)})`;
  this.ap.style.width=Math.max(0,this.apw.v)+'px';this.ap.style.opacity=cl(this.apo.v);this.amt.style.fontSize=this.fs.v+'px';this.av.textContent=rp(this.n.v);this.c1.style.opacity=cl(this.c1o.v);this.c2.style.opacity=1-cl(this.c1o.v);
  this.lm.forEach((e,j)=>e.style.height=Math.max(0,this.mh[j].v)+'px');this.lc[3].style.height=Math.max(0,this.dh.v)+'px';this.lc[3].style.opacity=cl(this.do_.v);
  this.wait.style.height=Math.max(0,this.wh.v)+'px';this.wait.style.opacity=cl(this.wo.v);this.pay.style.transform=`scale(${this.pb.v})`;};
 const V=(x,e)=>this.v(x,p,e);this.wl=V(80,.05);this.bl=V(1);this.ro=V(0);this.rs=V(1);this.apw=V(0,.05);this.apo=V(1);this.fs=V(46,.05);this.n=V(97000,1);this.c1o=V(1);this.mh=L.map(()=>V(0,.05));this.dh=V(0,.05);this.do_=V(0);this.wh=V(0,.05);this.wo=V(1);this.pb=V(1);
 this.reset();if(document.fonts)document.fonts.ready.then(()=>{if(!this.done)this.reset();});}
cw(k){this.meas.innerHTML=BC[k][0];return this.meas.offsetWidth;}
look(el,k,ins){const s=BC[k];el.style.transition=ins?'none':`background-color ${(this.rm?.2:.12)*this.slow}s,box-shadow ${(this.rm?.2:.12)*this.slow}s`;el.style.backgroundColor=s[1];el.style.color=s[2];el.style.boxShadow=s[3];}
colors(fin,ins){const t=ins?'none':`color ${.2*this.slow}s cubic-bezier(0,0,.58,1)`;this.amt.style.transition=t;this.amt.style.color=fin?K.cocoa:K.ink3;
 this.ll[2].style.transition=this.lv[2].style.transition=t;this.ll[2].style.color=this.lv[2].style.color=fin?K.cocoa:K.ink3;this.lv[3].style.color='#5E7A00';
 this.pay.style.transition=ins?'none':`background-color ${.2*this.slow}s,border-color ${.2*this.slow}s`;this.pay.style.backgroundColor=this.pay.style.borderColor=fin?K.car:K.mauve;}
confirm(){if(this.done)return;this.done=1;const rm=this.rm,V=this;
 this.look(this.cl,'final');this.roll(this.cl.firstElementChild,BC.final[0],1);this.look(this.cr,'unpaid');
 if(rm){this.set(this.wl,this.cw('final'));this.tw(this.ro,1,.2,'easeInOut');}
 else{this.sp(this.wl,this.cw('final'),'lead');this.after(.06,()=>{this.set(this.bl,1.08);this.sp(this.bl,1,'bump');this.set(this.ro,1);this.set(this.rs,0);this.sp(this.rs,1,'pop');});}
 this.hap('.success','Atas confirmed · the bill is final');
 const metaH=16;
 this.mh.forEach((m,j)=>{if(j===3)return;if(rm)this.set(m,metaH);else this.sp(m,metaH,'settle',.10+.04*j);});
 this.after(rm?0:.10,()=>this.roll(this.lv[2],'Rp 5.000',1));
 const dh=this.lc[3].firstElementChild.offsetHeight+metaH;this.set(this.mh[3],metaH);
 if(rm){this.set(this.dh,dh);this.tw(this.do_,1,.2,'easeInOut');}else{this.sp(this.dh,dh,'settle',.18);this.tw(this.do_,1,.2,'easeOut',.22);}
 this.after(rm?0:.24,()=>{this.colors(true);
  if(rm){this.set(this.apw,0);this.set(this.apo,0);this.set(this.fs,52);this.set(this.n,99500);this.fadeIn(this.av);this.set(this.c1o,0);this.fadeIn(this.c2);}
  else{this.sp(this.apw,0,'settle');this.tw(this.apo,0,.15,'easeIn');this.sp(this.fs,52,'settle');this.sp(this.n,99500,'glide');this.tw(this.c1o,0,.2);}});
 if(rm){this.tw(this.wo,0,.2,'easeInOut',0,()=>this.set(this.wh,0));}else this.after(.30,()=>{this.sp(this.wh,0,'leave');this.tw(this.wo,0,.15,'easeIn');});
 this.after(rm?0:.40,()=>{if(!rm){this.set(this.pb,1.05);this.sp(this.pb,1,'bump');}});}
reset(){this.done=0;this.look(this.cl,'notfinal',true);this.look(this.cr,'unpaid',true);this.cl.firstElementChild.innerHTML=`<span class="rl">${BC.notfinal[0]}</span>`;this.cr.firstElementChild.innerHTML=`<span class="rl">${BC.unpaid[0]}</span>`;
 this.set(this.wl,this.cw('notfinal'));this.set(this.bl,1);this.set(this.ro,0);this.set(this.rs,1);this.ap.style.width='auto';const w=this.ap.offsetWidth||40;this.set(this.apw,w);this.set(this.apo,1);this.set(this.fs,46);this.set(this.n,97000);this.set(this.c1o,1);
 this.mh.forEach(m=>this.set(m,0));this.set(this.dh,0);this.set(this.do_,0);this.wait.style.height='auto';this.set(this.wh,this.wait.offsetHeight||102);this.set(this.wo,1);this.set(this.pb,1);
 this.L.forEach((l,j)=>{this.lv[j].innerHTML=`<span class="rl">${j===2?'After Atas confirms':l[2]}</span>`;});this.colors(false,true);}
}

/* 13 Variant and option chips */
const OPT=[['Weight',[['600 gr',21000],['1000 gr',33000]],1],['Slice',[['Whole Sourdough'],['Sliced 15mm']],1]];
class Options extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:500px}
 .tt{display:flex;justify-content:space-between;align-items:flex-start;gap:12px}.tn{font:700 28px/1.1 Roundo,sans-serif}.tp{font:700 22px/1.1 Roundo,sans-serif}
 .ds{display:block;margin-top:14px;font:500 14px/1.45 Manrope,sans-serif;color:${K.ink2}}
 .g{display:flex;flex-direction:column;gap:8px;margin-top:16px}.gr{position:relative;display:flex;gap:8px}
 .bgp{position:absolute;top:0;border-radius:999px;background:#fff;box-shadow:inset 0 0 0 1.5px ${K.mauve}}
 .ind{position:absolute;top:0;border-radius:999px;background:${K.cocoa}}
 .oc{position:relative;z-index:1;display:flex;flex-direction:column;align-items:center;gap:1px;padding:8px 18px;border-radius:999px;font:600 14px/1.2 Manrope,sans-serif;white-space:nowrap}
 .oc.s{padding:11px 18px}.oc small{font:500 11px Manrope,sans-serif;opacity:.75}
 .bar{position:absolute;left:12px;right:12px;bottom:26px;padding:12px;border-radius:36px;${GL};display:flex;gap:10px;align-items:center}
 .stp{display:inline-flex;align-items:center;gap:12px;padding:6px;border-radius:999px;background:#fff}.sb{width:28px;height:28px;border-radius:50%;background:${K.peach};display:flex;align-items:center;justify-content:center}
 .cta{flex:1;display:flex;align-items:center;justify-content:center;padding:14px 0;border-radius:999px;background:${K.car};border:4px solid ${K.car};color:${K.cream};font:600 16px/1.25 Manrope,sans-serif}</style>
 <div class="tt"><span class="tn">Classic Sourdough</span><span class="tp roll"></span></div>
 <span class="ds">Long-fermented country loaf with a crackly crust.</span>
 ${OPT.map(([t,o],g)=>`<div class="g"><span class="cap" style="color:${K.cocoa}">${t}</span><div class="gr" data-g="${g}">${o.map(()=>'<span class="bgp"></span>').join('')}<span class="ind"></span>${o.map(([l,p],j)=>`<button class="oc${p?'':' s'}" data-j="${j}" aria-label="${l}">${l}${p?`<small>${rp(p)}</small>`:''}</button>`).join('')}</div></div>`).join('')}
 <div class="bar"><div class="stp"><span class="sb">${ic('minus',15,K.cocoa,2.5)}</span><span style="font:700 18px/1 Roundo,sans-serif">1</span><span class="sb">${ic('plus',15,K.cocoa,2.5)}</span></div><span class="cta">Add to my order</span></div>`;
 this.tp=this.q('.tp');
 this.G=this.qa('.gr').map((gr,g)=>{const G={gr,bgs:[...gr.querySelectorAll('.bgp')],ind:gr.querySelector('.ind'),btn:[...gr.querySelectorAll('.oc')],opts:OPT[g][1],sel:OPT[g][2],rect:[]};
  const pi=()=>{const sq=G.sq[G.sel].v,s=this.rm?0:sq;G.ind.style.left=G.L.v+'px';G.ind.style.width=Math.max(0,G.R.v-G.L.v)+'px';G.ind.style.transform=`scale(${1+.04*s},${1-.08*s})`;G.ind.style.opacity=cl(G.io.v);};
  G.L=this.v(0,pi,.05);G.R=this.v(0,pi,.05);G.io=this.v(1,pi);
  G.sq=G.btn.map((b,j)=>{const o=this.v(0,()=>{const s=this.rm?0:o.v,t=`scale(${1+.04*s},${1-.08*s})`;b.style.transform=t;G.bgs[j].style.transform=t;if(j===G.sel)pi();b.style.opacity=G.dim[j].v;});return o;});
  G.dim=G.btn.map((b,j)=>this.v(1,()=>{b.style.opacity=G.dim[j].v;}));
  G.btn.forEach((b,j)=>{let id=null,inn=false;const down=on=>{if(this.rm)this.tw(G.dim[j],on?.6:1,on?.10:.15);else this.sp(G.sq[j],on?1:0,on?'press':'release');};
   b.addEventListener('pointerdown',e=>{id=e.pointerId;inn=true;try{b.setPointerCapture(id)}catch(_){};down(true);});
   b.addEventListener('pointermove',e=>{if(e.pointerId!==id)return;const r=b.getBoundingClientRect(),m=16,i=e.clientX>=r.left-m&&e.clientX<=r.right+m&&e.clientY>=r.top-m&&e.clientY<=r.bottom+m;if(i!==inn){inn=i;down(i);}});
   b.addEventListener('pointerup',e=>{if(e.pointerId!==id)return;id=null;if(inn){down(false);this.pick(g,j);}});
   b.addEventListener('pointercancel',e=>{if(e.pointerId!==id)return;id=null;if(inn)down(false);});
   b.addEventListener('click',e=>{if(e.detail===0)this.pick(g,j);});});
  return G;});
 this.reset();if(document.fonts)document.fonts.ready.then(()=>this.measure(true));}
measure(ins){this.G.forEach(G=>{G.rect=G.btn.map(b=>[b.offsetLeft,b.offsetWidth,b.offsetHeight]);G.rect.forEach(([x,w,h],j)=>{const s=G.bgs[j].style;s.left=x+'px';s.width=w+'px';s.height=h+'px';});G.ind.style.height=G.rect[0][2]+'px';if(ins){const[x,w]=G.rect[G.sel];this.set(G.L,x);this.set(G.R,x+w);}});}
ink(G,ins){G.btn.forEach((b,j)=>{b.style.transition=ins?'none':`color ${(this.rm?.2:.12)*this.slow}s cubic-bezier(0,0,.58,1) ${j===G.sel&&!this.rm?.04*this.slow:0}s`;b.style.color=j===G.sel?K.cream:K.cocoa;});}
price(){return this.G[0].opts[this.G[0].sel][1]}
pick(g,j){const G=this.G[g],o=G.sel;if(j===o)return;const p0=this.price();G.sel=j;const[x,w]=G.rect[j];this.ink(G);
 if(this.rm){this.set(G.L,x);this.set(G.R,x+w);this.set(G.io,0);this.tw(G.io,1,.2,'easeInOut');}
 else{const right=j>o;this.sp(right?G.R:G.L,right?x+w:x,'lead');this.sp(right?G.L:G.R,right?x:x+w,'trail');}
 const p1=this.price();if(p1!==p0)this.roll(this.tp,rp(p1),p1>p0?1:-1);this.hap('.selection',OPT[g][0]+' · '+G.opts[j][0]);}
reset(){this.G.forEach((G,g)=>{G.sel=OPT[g][2];G.sq.forEach(o=>this.set(o,0));G.dim.forEach(o=>this.set(o,1));this.set(G.io,1);this.ink(G,true);});this.measure(true);this.tp.innerHTML=`<span class="rl">${rp(this.price())}</span>`;}
}

/* 14 Skeleton rows turning into content */
const HIS=[['October','03','OCT','Academy Bali Friday Treats','Rani · 6 people','Rp 99.500','closed','#F9CFAF',1],['September','27','SEP','Weekend loaf','Just me','Rp 70.000','closed','#E9FF83',1],['','19','SEP','Demo Day snacks','Kevin · 9 people','Rp 64.500','closed','#F9B7D2',1],['','09','SEP','Rainy Tuesday','Nadia · 3 people','—','cancelled','#EDE2E4',.65],['August','29','AUG','Brownie Friday','You hosted · 5 people','Rp 48.000','closed','#F9CFAF',1]];
const hrow=h=>`<div class="hr" style="opacity:${h[8]}"><div class="dt" style="background:${h[7]}"><span style="font:700 17px/1 Roundo,sans-serif">${h[1]}</span><span style="font:600 9px Manrope,sans-serif;letter-spacing:.04em">${h[2]}</span></div><div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:3px"><span style="font:700 15px Manrope,sans-serif;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${h[3]}</span><span style="font:500 12px Manrope,sans-serif;color:${K.ink3}">${h[4]}</span></div><div style="display:flex;flex-direction:column;align-items:flex-end;gap:4px"><span style="font:700 15px Roundo,sans-serif">${h[5]}</span><at-tag kind="${h[6]}" size="s"></at-tag></div></div>`;
const HCSS=`.hr{display:flex;align-items:center;gap:12px}.dt{width:46px;height:46px;border-radius:14px;display:flex;flex-direction:column;align-items:center;justify-content:center;flex:none}
 .card{background:#fff;border-radius:24px;padding:14px 16px;display:grid}.card>*{grid-area:1/1}.mo{display:block;overflow:hidden;font:600 12px/1 Manrope,sans-serif;letter-spacing:.03em;text-transform:uppercase;padding:0 4px}`;
class Skeleton extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:600px}${HCSS}
 .h{margin:0 0 14px;font:700 40px/1.05 Roundo,sans-serif}.list{display:flex;flex-direction:column;gap:10px}.it{display:flex;flex-direction:column}
 .sk{display:flex;align-items:center;gap:12px}.sk i{display:block;background:${K.mist}}</style>
 <h2 class="h">History</h2><div class="list">${HIS.map((h,j)=>`<div class="it"><span class="mo">${h[0]}</span><div class="card"><div class="sk"><i style="width:46px;height:46px;border-radius:14px"></i><div style="flex:1;display:flex;flex-direction:column;gap:8px"><i style="height:14px;width:${['70%','55%','80%','60%','75%'][j]};border-radius:7px"></i><i style="height:12px;width:40%;border-radius:6px"></i></div><i style="width:64px;height:16px;border-radius:8px"></i></div><div class="ct">${hrow(h)}</div></div></div>`).join('')}</div>`;
 this.R=this.qa('.it').map((it,j)=>{const r={mo:it.querySelector('.mo'),sk:it.querySelector('.sk'),ct:it.querySelector('.ct'),has:!!HIS[j][0]};
  const p=()=>{r.mo.style.height=Math.max(0,r.mh.v)+'px';r.mo.style.paddingTop=Math.max(0,r.mh.v)/30*12+'px';r.mo.style.opacity=cl(r.mh.v/30);r.sk.style.opacity=cl(r.so.v);r.ct.style.opacity=cl(r.co.v);r.ct.style.transform=`translateY(${r.cy.v}px)`;};
  r.mh=this.v(0,p,.05);r.so=this.v(1,p);r.co=this.v(0,p);r.cy=this.v(0,p,.05);return r;});
 this.reset();}
arrive(){if(this.loaded)return;this.loaded=1;const rm=this.rm;
 this.R.forEach((r,j)=>{const d=rm?0:Math.min(.32,j*.04);
  if(rm){this.tw(r.so,0,.2,'easeInOut');this.tw(r.co,1,.2,'easeInOut');if(r.has)this.set(r.mh,30);return;}
  this.tw(r.so,0,.15,'easeIn',d);this.set(r.cy,6);this.sp(r.cy,0,'settle',d);this.tw(r.co,1,.2,'easeOut',d);if(r.has)this.sp(r.mh,30,'settle',d);});
 this.hap('None','Content arrived · no haptic');}
reset(){this.loaded=0;this.R.forEach(r=>{this.set(r.mh,0);this.set(r.so,1);this.set(r.co,0);this.set(r.cy,0);});}
}

/* 15 Pull to refresh */
class Refresh extends Mo{
build(){
 const C=2*Math.PI*28;this.C=C;
 this.sr.innerHTML=`<style>${BASE}:host{height:600px}${HCSS}
 .h{margin:0 0 6px;font:700 40px/1.05 Roundo,sans-serif}
 .vp{position:relative;height:510px;overflow:hidden;touch-action:none;cursor:grab;-webkit-user-select:none;user-select:none}
 .ind{position:absolute;left:50%;top:6px;width:60px;height:60px;margin-left:-30px;opacity:0}
 .ms{position:absolute;inset:6px;border-radius:50%;background:#fff url(uploads/art/pose-waiting.png) center/cover no-repeat}
 .ind svg{position:absolute;inset:0;transform:rotate(-90deg)}
 .lst{display:flex;flex-direction:column;gap:10px;padding-top:8px}.it{display:flex;flex-direction:column;gap:8px}.nw{overflow:hidden;height:0}</style>
 <h2 class="h">History</h2><div class="vp"><div class="ind"><span class="ms" role="img" aria-label="Mascot waiting"></span><svg width="60" height="60" viewBox="0 0 60 60"><circle cx="30" cy="30" r="28" fill="none" stroke="${K.mist}" stroke-width="3"></circle><circle class="rg" cx="30" cy="30" r="28" fill="none" stroke="${K.car}" stroke-width="3" stroke-linecap="round" stroke-dasharray="${C}" stroke-dashoffset="${C}"></circle></svg></div>
 <div class="lst"><div class="nw"><div class="it" style="padding-bottom:10px"><span class="mo" style="padding-top:2px">${HIS[0][0]}</span><div class="card">${hrow(HIS[0])}</div></div></div>${HIS.slice(1).map(h=>`<div class="it">${h[0]?`<span class="mo" style="padding-top:10px">${h[0]}</span>`:''}<div class="card">${hrow(h)}</div></div>`).join('')}</div></div>`;
 this.vp=this.q('.vp');this.ind=this.q('.ind');this.ms=this.q('.ms');this.rg=this.q('.rg');this.lst=this.q('.lst');this.nw=this.q('.nw');
 const p=()=>{const y=this.p.v;this.lst.style.transform=`translateY(${y}px)`;const f=cl(y/72);this.ind.style.opacity=this.loading?cl(this.io.v):cl(y/40)*cl(this.io.v);
  this.ms.style.transform=this.rm?'none':`scale(${(.6+.4*f)*this.mb.v})`;this.rg.setAttribute('stroke-dashoffset',String(this.C*(1-cl(this.ring.v))));this.nw.style.height=Math.max(0,this.nh.v)+'px';this.nw.style.opacity=cl(this.no.v);this.ms.style.marginLeft=this.sh.v+'px';};
 this.p=this.v(0,p,.05);this.mb=this.v(1,p);this.ring=this.v(0,p);this.io=this.v(1,p);this.nh=this.v(0,p,.05);this.no=this.v(0,p);this.sh=this.v(0,p,.05);
 let armed=false;
 drag(this.vp,{start:()=>{if(this.loading)return;this.set(this.io,1);this.set(this.p,this.p.v);armed=this.p.v>=72;},
  move:dy=>{if(this.loading)return;const y=rub(Math.max(0,dy),510);this.set(this.p,y);if(y>=72&&!armed){armed=true;if(!this.rm){this.set(this.mb,1.12);this.sp(this.mb,1,'bump');}this.hap('.impact(weight: .light)','Pull past 72pt · release to refresh');}else if(y<72)armed=false;},
  end:()=>{if(this.loading)return;if(this.p.v>=72)this.load();else this.sp(this.p,0,'leave');}});
 this.reset();}
load(){this.loading=true;this.set(this.io,1);this.sp(this.p,64,'settle');this.set(this.ring,0);this.tw(this.ring,.85,2.4,'easeOut');
 this.after(1.2,()=>this.getAttribute('result')==='fail'?this.fail():this.ok());}
ok(){const rm=this.rm;if(rm)this.tw(this.ring,1,.2,'easeInOut');else this.sp(this.ring,1,'lead');
 this.after(.2,()=>{this.sp(this.p,0,rm?'leave':'arrive');this.tw(this.io,0,.15,'easeIn');if(!this.added){this.added=1;const h=this.nw.firstElementChild.offsetHeight;this.set(this.no,0);if(rm){this.set(this.nh,h);this.tw(this.no,1,.2,'easeInOut');}else{this.sp(this.nh,h,'settle');this.tw(this.no,1,.2,'easeOut',.06);}}
  this.after(.3,()=>{this.loading=false;});});this.hap('None','Refreshed · no haptic');}
fail(){const rm=this.rm;if(rm)this.tw(this.ring,0,.2,'easeInOut');else{this.sp(this.ring,0,'leave');this.keys(this.sh,[[0,0],[.05,4],[.12,-3],[.19,2],[.26,-1],[.32,0]]);}
 this.after(.32,()=>{this.sp(this.p,0,'leave');this.tw(this.io,0,.15,'easeIn');this.after(.3,()=>{this.loading=false;});});this.hap('.error','Refresh failed · then the connection toast');}
reset(){this.loading=false;this.added=0;this.set(this.p,0);this.set(this.mb,1);this.set(this.ring,0);this.set(this.io,1);this.set(this.nh,0);this.set(this.no,0);this.set(this.sh,0);}
}

[['atm-sheets',Sheets],['atm-banner',Banner],['atm-cards',Cards],['atm-split',Split],['atm-members',Members],['atm-bill',Bill],['atm-options',Options],['atm-skeleton',Skeleton],['atm-refresh',Refresh]].forEach(([n,c])=>customElements.define(n,c));
})();
