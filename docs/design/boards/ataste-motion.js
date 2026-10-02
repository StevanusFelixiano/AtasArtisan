// Ataste app motion prototypes (Motion board): <atm-buttons>, <atm-basket>, <atm-unlock>, <atm-async>, <atm-copy>, <atm-status>, <atm-band>.
// Same spring model as ataste-tabbar.js: stiffness = (2π/response)², damping = 4π·dampingFraction/response, mass 1.
(function(){
if (customElements.get('atm-band')) return;
const K={cocoa:'#2B1A12',cream:'#FBF3EA',car:'#9D5C1D',carP:'#B5773A',peach:'#F9CFAF',peachP:'#FCE3D0',lime:'#E9FF83',limeP:'#F2FFB8',limeR:'#BCD947',mist:'#EDE2E4',mauve:'#D1B6BB',red:'#E40014',redP:'#EE4D5B',redT:'#FBE0E3',ink2:'#5A4237',ink3:'#7A6257',ink4:'#A08A80'};
// Motion.* springs [response, dampingFraction]
const SP={press:[.20,.75],release:[.38,.50],pop:[.32,.50],bump:[.30,.60],bounce:[.38,.45],lead:[.30,.78],trail:[.44,.82],settle:[.40,.86],arrive:[.42,.72],leave:[.32,1],glide:[.50,1]};
function bez(x1,y1,x2,y2){const cx=3*x1,bx=3*(x2-x1)-cx,ax=1-cx-bx,cy=3*y1,by=3*(y2-y1)-cy,ay=1-cy-by;
 const sx=t=>((ax*t+bx)*t+cx)*t,sy=t=>((ay*t+by)*t+cy)*t,ds=t=>(3*ax*t+2*bx)*t+cx;
 return x=>{if(x<=0)return 0;if(x>=1)return 1;let t=x;for(let i=0;i<8;i++){const e=sx(t)-x,d=ds(t);if(Math.abs(e)<1e-5||Math.abs(d)<1e-6)break;t-=e/d;}return sy(Math.min(1,Math.max(0,t)));};}
const EASE={easeOut:bez(0,0,.58,1),easeIn:bez(.42,0,1,1),easeInOut:bez(.42,0,.58,1),linear:x=>x};
const SHAKE=[[0,0],[.05,4],[.12,-3],[.19,2],[.26,-1],[.32,0]];
const rp=n=>'Rp '+String(Math.round(n/500)*500).replace(/\B(?=(\d{3})+(?!\d))/g,'.');
const ic=(n,s,c,w)=>`<at-icon name="${n}" size="${s||20}"${c?` color="${c}"`:''} sw="${w||2.2}"></at-icon>`;
const GL='background:rgba(251,243,234,.62);backdrop-filter:blur(18px) saturate(1.8);-webkit-backdrop-filter:blur(18px) saturate(1.8);box-shadow:inset 0 1px 0 rgba(255,255,255,.9),inset 0 0 0 1px rgba(255,255,255,.5),0 8px 24px rgba(43,26,18,.13);';
const BASE=`:host{display:block;position:relative;-webkit-tap-highlight-color:transparent;font-family:Manrope,sans-serif;color:${K.cocoa};background:${K.cream};padding:24px 20px;overflow:hidden}*{box-sizing:border-box}
button{all:unset;cursor:pointer;touch-action:manipulation;-webkit-user-select:none;user-select:none;display:block}button:focus-visible{outline:2px solid ${K.car};outline-offset:3px;border-radius:999px}
.cap{display:block;font:600 12px/1 Manrope,sans-serif;letter-spacing:.03em;text-transform:uppercase;color:${K.ink3}}
.roll{position:relative;display:grid}.rl{display:flex;align-items:center;gap:inherit;justify-content:inherit;white-space:nowrap}
.lay{position:absolute;inset:0;display:flex;align-items:center;justify-content:center}`;

class Mo extends HTMLElement{
static get observedAttributes(){return['rm','slow','result']}
constructor(){super();this.act=new Set();this._raf=0;this._tick=this.tick.bind(this);this._to=[];}
get slow(){return Math.max(.1,+this.getAttribute('slow')||1)}
get rm(){return this.getAttribute('rm')==='1'}
connectedCallback(){if(this._b)return;this._b=1;this.sr=this.attachShadow({mode:'open'});this.build();}
attributeChangedCallback(n,o,v){if(this._b&&o!==v&&n==='rm'){this.clearT();this.reset();}}
q(s){return this.sr.querySelector(s)}
qa(s){return [...this.sr.querySelectorAll(s)]}
v(x,paint,eps){return{v:x,t:x,vel:0,eps:eps||.001,paint,mode:null,delay:0}}
sp(o,t,n,delay=0,then){const[r,d]=SP[n];Object.assign(o,{mode:'s',t,r,d,delay,then});this.run(o)}
tw(o,t,dur,ease='easeOut',delay=0,then){Object.assign(o,{mode:'t',t,dur,ease:EASE[ease],el:0,from:null,delay,then,vel:0});this.run(o)}
keys(o,pts){Object.assign(o,{mode:'k',pts,el:0,delay:0,then:null,t:pts[pts.length-1][1]});this.run(o)}
set(o,x){o.v=o.t=x;o.vel=0;o.mode=null;o.then=null;this.act.delete(o);o.paint()}
run(o){this.act.add(o);if(!this._raf){this._last=performance.now();this._raf=requestAnimationFrame(this._tick)}}
tick(now){const dt=Math.min(.05,(now-this._last)/1000)/this.slow;this._last=now;const ps=new Set();
 for(const o of [...this.act]){if(!this.step(o,dt)){this.act.delete(o);if(o.then){const f=o.then;o.then=null;f();}}ps.add(o.paint);}
 ps.forEach(p=>p());this._raf=this.act.size?requestAnimationFrame(this._tick):0;}
step(o,dt){if(o.delay>0){o.delay-=dt;if(o.delay>0)return true;dt=-o.delay;o.delay=0;}
 if(o.mode==='t'){if(o.from==null)o.from=o.v;o.el+=dt;const p=Math.min(1,o.el/o.dur);o.v=o.from+(o.t-o.from)*o.ease(p);return p<1;}
 if(o.mode==='k'){o.el+=dt;const P=o.pts;if(o.el>=P[P.length-1][0]){o.v=o.t;return false;}let j=1;while(j<P.length-1&&P[j][0]<o.el)j++;const[t0,v0]=P[j-1],[t1,v1]=P[j];o.v=v0+(v1-v0)*Math.min(1,(o.el-t0)/(t1-t0));return true;}
 const w=2*Math.PI/o.r,k=w*w,c=2*o.d*w,n=Math.max(1,Math.ceil(dt*240)),h=dt/n;
 for(let i=0;i<n;i++){o.vel+=(-k*(o.v-o.t)-c*o.vel)*h;o.v+=o.vel*h;}
 if(Math.abs(o.v-o.t)<o.eps&&Math.abs(o.vel)<o.eps*10){o.v=o.t;o.vel=0;return false;}return true;}
after(s,f){const id=setTimeout(f,s*1000*this.slow);this._to.push(id);return id}
clearT(){this._to.forEach(clearTimeout);this._to=[]}
hap(type,why){this.dispatchEvent(new CustomEvent('haptic',{detail:{type,why},bubbles:true,composed:true}))}
tr(el,props,dur){el.style.transition=props.map(p=>p+' '+(dur*this.slow)+'s cubic-bezier(0,0,.58,1)').join(',')}
fadeIn(el){el.animate([{opacity:0},{opacity:1}],{duration:200*this.slow,easing:'cubic-bezier(.42,0,.58,1)'})}
roll(box,html,dir=1){const old=[...box.children];old.slice(0,-1).forEach(e=>e.remove());const e=old[old.length-1];
 const n=document.createElement('span');n.className='rl';n.innerHTML=html;
 if(this.rm){if(e)e.remove();box.appendChild(n);n.animate([{opacity:0},{opacity:1}],{duration:150*this.slow});return;}
 if(e){e.style.position='absolute';e.style.inset='0';e.animate([{transform:'none',opacity:1},{transform:`translateY(${-8*dir}px)`,opacity:0}],{duration:180*this.slow,easing:'cubic-bezier(.42,0,1,1)',fill:'forwards'}).onfinish=()=>e.remove();}
 box.appendChild(n);n.animate([{transform:`translateY(${8*dir}px)`,opacity:0},{transform:'none',opacity:1}],{duration:180*this.slow,easing:'cubic-bezier(0,0,.58,1)'});}
mkP(face,sc){const s={};const p=()=>{const q=this.rm?0:s.sq.v,b=s.bs.v;face.style.transform=`translateX(${s.sh.v}px) scale(${b*(1+(sc[0]-1)*q)},${b*(1+(sc[1]-1)*q)})`;face.style.opacity=s.dim.v;};
 s.sq=this.v(0,p);s.dim=this.v(1,p);s.sh=this.v(0,p,.05);s.bs=this.v(1,p);
 s.down=on=>{if(this.rm)this.tw(s.dim,on?.6:1,on?.10:.15);else this.sp(s.sq,on?1:0,on?'press':'release');};
 s.shake=()=>{if(!this.rm)this.keys(s.sh,SHAKE)};
 s.bump=f=>{if(this.rm)return;this.set(s.bs,f||1.2);this.sp(s.bs,1,'bump')};
 s.dip=()=>{if(this.rm)return;this.tw(s.bs,.8,.07,'easeOut',0,()=>this.sp(s.bs,1,'bounce'))};
 s.rest=()=>{this.set(s.sq,0);this.set(s.sh,0);this.set(s.dim,1);this.set(s.bs,1)};return s;}
wire(btn,face,sc,o={}){const P=this.mkP(face,sc);
 const tone=on=>{const t=o.tone&&o.tone();if(!t)return;this.tr(face,['background-color','border-color'],on?.08:.15);face.style.backgroundColor=on?t[1]:t[0];if(t[2])face.style.borderColor=on?t[3]:t[2];};
 let id=null,inn=false;const inert=()=>o.inert&&o.inert(),blk=()=>o.blocked&&o.blocked();
 const fire=()=>{if(blk()){o.onBlocked&&o.onBlocked();}else o.commit&&o.commit();};
 btn.addEventListener('pointerdown',e=>{if(inert())return;id=e.pointerId;inn=true;try{btn.setPointerCapture(id)}catch(_){};if(!blk()){P.down(true);tone(true);}});
 btn.addEventListener('pointermove',e=>{if(e.pointerId!==id)return;const r=btn.getBoundingClientRect(),m=16,i=e.clientX>=r.left-m&&e.clientX<=r.right+m&&e.clientY>=r.top-m&&e.clientY<=r.bottom+m;if(i!==inn){inn=i;if(!blk()){P.down(i);tone(i);}}});
 btn.addEventListener('pointerup',e=>{if(e.pointerId!==id)return;id=null;if(!inn)return;if(!blk()){P.down(false);tone(false);}fire();});
 btn.addEventListener('pointercancel',e=>{if(e.pointerId!==id)return;id=null;if(inn&&!blk()){P.down(false);tone(false);}});
 btn.addEventListener('click',e=>{if(e.detail===0&&!inert())fire();});return P;}
build(){}reset(){}
}

/* 01 Buttons */
class Buttons extends Mo{
build(){
 const ST={primary:[K.car,K.carP,K.car,K.carP,K.cream],dark:[K.cocoa,'#4A3329',K.cocoa,'#4A3329',K.cream],secondary:[K.cream,'#FDF8F2',K.peach,K.peachP,K.cocoa],destructive:[K.red,K.redP,K.red,K.redP,'#fff'],disabled:[K.mauve,K.mauve,K.mauve,K.mauve,K.cream]};
 const pill=(k,kind,l,i)=>{const s=ST[kind];return `<button data-k="${k}" data-kind="${kind}" aria-label="${l}"${kind==='disabled'?' aria-disabled="true"':''}><span class="face" style="background:${s[0]};border-color:${s[2]};color:${s[4]}">${i?ic(i,18):''}${l}</span></button>`;};
 this.sr.innerHTML=`<style>${BASE}
 .wrap{display:flex;flex-direction:column;gap:22px}.grp{display:flex;flex-direction:column;gap:10px}
 .face{display:flex;align-items:center;justify-content:center;gap:8px;padding:14px 24px;border-radius:999px;border:4px solid;font:600 17px/1.25 Manrope,sans-serif;white-space:nowrap}
 .row{display:flex;gap:12px;align-items:center}
 .ib .face{padding:0;width:44px;height:44px;border:0;${GL}}
 .sm .face{display:flex;align-items:center;justify-content:center;padding:0;width:28px;height:28px;border:0;background:${K.peach}}
 .reason{display:flex;gap:6px;align-items:center;padding:0 8px;font:600 13px/1.4 Manrope,sans-serif;color:${K.ink2};opacity:0}</style>
 <div class="wrap">
 <div class="grp"><span class="cap">Pill CTA</span>${pill('cta','primary','Start a group order')}${pill('wa','dark','Continue with WhatsApp','wa')}</div>
 <div class="grp"><span class="cap">Secondary</span>${pill('sec','secondary','Order for myself')}</div>
 <div class="grp"><span class="cap">Destructive</span>${pill('del','destructive','Leave group')}</div>
 <div class="grp"><span class="cap">Icon buttons</span><div class="row">
  <button class="ib" data-k="back" aria-label="Back"><span class="face">${ic('chev-l',22,K.cocoa,2.4)}</span></button>
  <button class="ib" data-k="share" aria-label="Share"><span class="face">${ic('share',22,K.cocoa,2.2)}</span></button>
  <button class="ib" data-k="more" aria-label="More"><span class="face">${ic('more',22,K.cocoa,2.2)}</span></button>
  <button class="sm" data-k="plus" aria-label="Add one"><span class="face">${ic('plus',15,K.cocoa,2.5)}</span></button></div></div>
 <div class="grp"><span class="cap">Disabled</span>${pill('dis','disabled','Lock again','lock')}<span class="reason">${ic('clock',14)}Lock again opens when Dimas finishes his edit.</span></div>
 </div>`;
 const R=this.q('.reason'),pr=()=>{R.style.opacity=this.rv.o.v;R.style.transform=`translateY(${this.rv.y.v}px)`};this.rv={o:this.v(0,pr),y:this.v(0,pr,.05)};
 const names={cta:'Pill CTA · Start a group order',wa:'Pill CTA · Continue with WhatsApp',sec:'Secondary · Order for myself',del:'Destructive · Leave group',back:'Icon button · Back',share:'Icon button · Share',more:'Icon button · More',plus:'Icon button · 28pt plus'};
 this.P=this.qa('button').map(b=>{const k=b.dataset.k,kind=b.dataset.kind,face=b.querySelector('.face'),s=ST[kind],icon=!kind;
  const P=this.wire(b,face,icon?[1.08,.88]:[1.02,.92],{tone:s&&kind!=='disabled'?()=>[s[0],s[1],s[2],s[3]]:k==='plus'?()=>[K.peach,K.peachP]:null,
   blocked:()=>kind==='disabled',onBlocked:()=>this.blocked(),
   commit:()=>this.hap(kind==='destructive'?'.impact(weight: .medium)':'.impact(weight: .light)',names[k])});P.k=k;return P;});
 this.dis=this.P.find(p=>p.k==='dis');}
blocked(){const o=this.rv;this.dis.shake();this.clearT();
 if(this.rm){this.set(o.y,0);this.tw(o.o,1,.2,'easeInOut');}else{if(o.o.v<.5)this.set(o.y,-4);this.sp(o.y,0,'settle');this.tw(o.o,1,.2);}
 this.after(2.4,()=>this.tw(o.o,0,.15,'easeIn'));this.hap('.impact(weight: .light, intensity: 0.5)','Disabled · Lock again');}
reset(){this.P.forEach(p=>p.rest());this.set(this.rv.o,0);this.set(this.rv.y,0);}
}

/* 02 Add item, stepper, basket total */
class Basket extends Mo{
build(){
 const I=this.I=[{k:'bc',n:'Butter Croissant',p:12000,tag:'best'},{k:'pc',n:'Pain Au Chocolate',p:16000,tag:''}];
 this.sr.innerHTML=`<style>${BASE}:host{height:624px}
 .grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:12px}
 .card{background:#fff;border-radius:24px;padding:12px 12px 14px;display:flex;flex-direction:column;gap:10px}
 .ph{position:relative;align-self:center}.tg{position:absolute;left:-2px;top:-2px}
 .nm{font:700 15px/1.25 Manrope,sans-serif;min-height:38px}.ft{display:flex;justify-content:space-between;align-items:flex-end}
 .pr{font:700 16px/1 Roundo,sans-serif}
 .add .face,.sb .face{display:block;position:relative;width:28px;height:28px;border-radius:50%;background:${K.peach}}
 .mine{margin-top:16px;background:#fff;border-radius:32px;padding:18px 18px 8px}.rows{display:flex;flex-direction:column;margin-top:4px}
 .rowc{overflow:hidden;height:0}.row{display:flex;gap:12px;align-items:center;height:76px}
 .rt{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}.rname{font:700 15px Manrope,sans-serif}.rsub{font:500 13px Manrope,sans-serif;color:${K.ink2}}
 .step{display:inline-flex;align-items:center;gap:10px;padding:3px;border-radius:999px;background:${K.cream}}
 .num{min-width:14px;justify-content:center;font:700 16px/1 Roundo,sans-serif}
 .empty{display:block;font:500 14px Manrope,sans-serif;color:${K.ink4};padding:10px 0 12px;opacity:0}
 .bag{position:absolute;left:50%;bottom:24px;display:flex;align-items:center;gap:12px;padding:8px 8px 8px 20px;border-radius:999px;background:${K.cocoa};color:${K.cream};white-space:nowrap}
 .cnt{font:600 15px Manrope,sans-serif}.tot{padding:9px 16px;border-radius:999px;background:${K.car};font:700 15px Roundo,sans-serif;min-width:104px;text-align:center}</style>
 <span class="cap">Viennoiseries</span>
 <div class="grid">${I.map(it=>`<div class="card"><div class="ph"><at-photo size="120" bg="${K.peach}"></at-photo>${it.tag?`<span class="tg"><at-tag kind="${it.tag}" size="s"></at-tag></span>`:''}</div><span class="nm">${it.n}</span><div class="ft"><span class="pr">${rp(it.p)}</span><button class="add" data-k="${it.k}" aria-label="Add ${it.n}"><span class="face"><span class="lay pl">${ic('plus',15,K.cocoa,2.5)}</span><span class="lay ck">${ic('check',15,K.cocoa,2.5)}</span></span></button></div></div>`).join('')}</div>
 <div class="mine"><span class="cap">My items</span><div class="rows">${I.map(it=>`<div class="rowc" data-k="${it.k}"><div class="row"><at-photo size="56" bg="${K.peach}"></at-photo><div class="rt"><span class="rname">${it.n}</span><span class="rsub"></span></div><div class="step"><button class="sb mi" aria-label="Fewer"><span class="face"><span class="lay mn">${ic('minus',15,K.cocoa,2.5)}</span><span class="lay tr">${ic('trash',14,K.red,2)}</span></span></button><span class="roll num"></span><button class="sb up" aria-label="More"><span class="face"><span class="lay">${ic('plus',15,K.cocoa,2.5)}</span></span></button></div></div></div>`).join('')}<span class="empty">Nothing in the oven…yet!</span></div></div>
 <div class="bag"><at-icon name="bag" size="20"></at-icon><span class="roll cnt"></span><span class="tot"></span></div>`;
 this.qn={};this.R={};
 I.forEach(it=>{const k=it.k,card=this.qa('.add').find(b=>b.dataset.k===k),rowc=this.qa('.rowc').find(r=>r.dataset.k===k);
  const r={it,rowc,row:rowc.querySelector('.row'),sub:rowc.querySelector('.rsub'),num:rowc.querySelector('.num'),addF:card.querySelector('.face'),pl:card.querySelector('.pl'),ck:card.querySelector('.ck'),miF:rowc.querySelector('.mi .face'),mn:rowc.querySelector('.mn'),tr:rowc.querySelector('.tr')};
  const p=()=>this.paintItem(r);r.h=this.v(0,p,.05);r.o=this.v(0,p);r.c=this.v(0,p);r.t=this.v(0,p);
  r.Padd=this.wire(card,r.addF,[1.08,.88],{tone:()=>this.qn[k]>0?[K.lime,K.limeP]:[K.peach,K.peachP],commit:()=>this.qn[k]>0?this.setQ(k,this.qn[k]+1,'again'):this.setQ(k,1,'add')});
  r.Pmi=this.wire(rowc.querySelector('.mi'),r.miF,[1.08,.88],{tone:()=>this.qn[k]===1?[K.redT,'#F6C7CB']:[K.peach,K.peachP],commit:()=>this.qn[k]>1?this.setQ(k,this.qn[k]-1,'down'):this.setQ(k,0,'remove')});
  const upF=rowc.querySelector('.up .face');r.Pup=this.wire(rowc.querySelector('.up'),upF,[1.08,.88],{tone:()=>[K.peach,K.peachP],commit:()=>this.setQ(k,this.qn[k]+1,'up')});
  this.R[k]=r;});
 this.bagEl=this.q('.bag');this.cntBox=this.q('.cnt');this.totEl=this.q('.tot');this.emptyEl=this.q('.empty');
 const pb=()=>{this.bagEl.style.transform=`translateX(-50%) translateY(${this.by.v}px) scale(${this.bs.v})`;this.bagEl.style.opacity=Math.max(0,Math.min(1,this.bo.v));this.totEl.textContent=rp(this.tv.v);};
 this.by=this.v(90,pb,.05);this.bo=this.v(0,pb);this.bs=this.v(1,pb);this.tv=this.v(0,pb,1);
 const pe=()=>{this.emptyEl.style.opacity=this.eo.v};this.eo=this.v(0,pe);
 this.reset();}
paintItem(r){r.rowc.style.height=Math.max(0,r.h.v)+'px';r.row.style.opacity=Math.max(0,Math.min(1,r.o.v));const c=r.c.v,t=r.t.v;
 if(this.rm){r.pl.style.transform=r.ck.style.transform=r.mn.style.transform=r.tr.style.transform='none';r.pl.style.opacity=1-c;r.ck.style.opacity=c;r.mn.style.opacity=1-t;r.tr.style.opacity=t;return;}
 r.ck.style.opacity=c>.005?1:0;r.ck.style.transform=`scale(${Math.max(0,c)}) rotate(${-12*(1-c)}deg)`;r.pl.style.opacity=1;r.pl.style.transform=`scale(${Math.max(0,1-c)})`;
 r.tr.style.opacity=t>.005?1:0;r.tr.style.transform=`scale(${Math.max(0,t)}) rotate(${-12*(1-t)}deg)`;r.mn.style.opacity=1;r.mn.style.transform=`scale(${Math.max(0,1-t)})`;}
setQ(k,n,why,ins){const r=this.R[k],p=this.qn[k]||0,rm=this.rm;this.qn[k]=n;
 this.tr(r.addF,['background-color'],rm?.2:.12);this.tr(r.miF,['background-color'],rm?.2:.12);if(ins){r.addF.style.transition=r.miF.style.transition='none';}
 r.addF.style.backgroundColor=n>0?K.lime:K.peach;r.miF.style.backgroundColor=n===1?K.redT:K.peach;
 const anim=(o,to,from)=>{if(ins){this.set(o,to);return;}if(to===from)return;if(rm)this.tw(o,to,.2,'easeInOut');else if(to)this.sp(o,1,'pop',.04);else this.tw(o,0,.12);};
 anim(r.c,n>0?1:0,p>0?1:0);anim(r.t,n===1?1:0,p===1?1:0);
 if(ins){this.set(r.h,n>0?76:0);this.set(r.o,n>0?1:0);}
 else if(p===0&&n>0){this.set(r.o,0);if(rm){this.set(r.h,76);this.tw(r.o,1,.2,'easeInOut');}else{this.sp(r.h,76,'settle');this.tw(r.o,1,.2,'easeOut',.06);}}
 else if(n===0&&p>0){if(rm)this.tw(r.o,0,.2,'easeInOut',0,()=>this.set(r.h,0));else{this.sp(r.h,0,'leave');this.tw(r.o,0,.15,'easeIn');}}
 if(n>0){if(ins||p===0)r.num.innerHTML=`<span class="rl">${n}</span>`;else this.roll(r.num,String(n),n>p?1:-1);r.sub.textContent=rp(r.it.p*n);}
 if(why==='up')r.Pup.dip();if(why==='down')r.Pmi.dip();if(why==='again')r.Padd.bump(1.2);
 this.bag(ins);
 if(!ins){const H={add:['.impact(weight: .light)','Add from menu · '+r.it.n],again:['.increase','Add again · '+r.it.n+' × '+n],up:['.increase','Stepper + · '+n],down:['.decrease','Stepper − · '+n+(n===1?' · now the trash state':'')],remove:['.impact(weight: .medium)','Remove · '+r.it.n]}[why];this.hap(H[0],H[1]);}}
bag(ins){const cnt=this.I.reduce((a,it)=>a+this.qn[it.k],0),tot=this.I.reduce((a,it)=>a+this.qn[it.k]*it.p,0),pc=this._cnt||0,rm=this.rm;this._cnt=cnt;
 const txt=cnt===1?'1 item':cnt+' items';
 if(ins){this.set(this.by,cnt?0:90);this.set(this.bo,cnt?1:0);this.set(this.bs,1);this.set(this.tv,tot);this.cntBox.innerHTML=`<span class="rl">${txt}</span>`;this.set(this.eo,cnt?0:1);return;}
 if(cnt&&!pc){this.cntBox.innerHTML=`<span class="rl">${txt}</span>`;this.set(this.tv,tot);this.tw(this.eo,0,.15,'easeIn');if(rm){this.set(this.by,0);this.tw(this.bo,1,.2,'easeInOut');}else{this.sp(this.by,0,'arrive');this.tw(this.bo,1,.2);}return;}
 if(!cnt&&pc){this.tw(this.eo,1,.2,'easeOut',.15);if(rm)this.tw(this.bo,0,.2,'easeInOut');else{this.sp(this.by,90,'leave');this.tw(this.bo,0,.15,'easeIn');}return;}
 if(cnt!==pc)this.roll(this.cntBox,txt,cnt>pc?1:-1);
 if(rm){this.set(this.tv,tot);this.fadeIn(this.totEl);}else{this.sp(this.tv,tot,'glide');this.set(this.bs,1.06);this.sp(this.bs,1,'bump');}}
reset(){this._cnt=0;this.I.forEach(it=>{const r=this.R[it.k];[r.Padd,r.Pmi,r.Pup].forEach(p=>p.rest());this.qn[it.k]=0;this.setQ(it.k,it.k==='pc'?2:0,'',true);});this.bag(true);}
}

/* Running-text band: flicks once when asked, coasts to rest; drag and fling. Never loops. */
class Band extends Mo{
build(){const g=n=>this.getAttribute(n),t=g('text')||'FRESH FROM ATAS • GROUP UP • SAVE ON ONGKIR • ',fs=+(g('size')||15);
 this.sr.innerHTML=`<style>:host{display:block;touch-action:pan-y;cursor:grab;-webkit-user-select:none;user-select:none}.o{overflow:hidden;background:${g('bg')||K.cocoa};color:${g('fg')||K.cream}}.t{display:flex;width:max-content;font:700 ${fs}px/1 Roundo,Manrope,sans-serif;letter-spacing:.04em;text-transform:uppercase;padding:${Math.round(fs*.7)}px 0}.s{padding-right:.5em;white-space:nowrap}</style><div class="o"><div class="t">${('<span class="s">'+(t+' ').repeat(3)+'</span>').repeat(4)}</div></div>`;
 this.tk=this.q('.t');this.x=0;this.vx=0;let id=null,lx=0,lt=0;
 this.addEventListener('pointerdown',e=>{this.stop();id=e.pointerId;lx=e.clientX;lt=performance.now();this.vx=0;try{this.setPointerCapture(id)}catch(_){};this.style.cursor='grabbing';});
 this.addEventListener('pointermove',e=>{if(e.pointerId!==id)return;const now=performance.now(),dx=e.clientX-lx,dt=Math.max(1,now-lt)/1000;this.x+=dx;this.vx=.7*(dx/dt)+.3*this.vx;lx=e.clientX;lt=now;this.paint();});
 const up=e=>{if(e.pointerId!==id)return;id=null;this.style.cursor='';if(performance.now()-lt>80)this.vx=0;if(!this.rm&&Math.abs(this.vx)>40)this.coast();else this.vx=0;};
 this.addEventListener('pointerup',up);this.addEventListener('pointercancel',up);this.paint();}
paint(){const w=this.q('.s').offsetWidth||600;let x=this.x%w;if(x>0)x-=w;this.tk.style.transform=`translateX(${x}px)`;}
flick(v){if(this.rm)return;this.vx=v||-800;this.coast();}
coast(){cancelAnimationFrame(this._fr);let last=performance.now();const f=now=>{const dt=Math.min(.05,(now-last)/1000)/this.slow;last=now;this.x+=this.vx*dt;this.vx*=Math.pow(.998,dt*1000);this.paint();if(Math.abs(this.vx)>8)this._fr=requestAnimationFrame(f);else this.vx=0;};this._fr=requestAnimationFrame(f);}
stop(){cancelAnimationFrame(this._fr);this.vx=0;}
reset(){this.stop();this.x=0;this.paint();}
}

/* 03 Rp 200.000 bar + Discount unlocked */
class Unlock extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:420px}
 .card{position:relative;border-radius:32px;overflow:hidden;background:#fff}
 .sun{position:absolute;right:-60px;top:-60px;width:260px;height:260px;border-radius:50%;background:repeating-conic-gradient(#fff 0 10deg,transparent 10deg 20deg);opacity:0}
 .masc{position:absolute;right:6px;top:10px;width:130px;height:130px;border-radius:50%;background:url(uploads/art/pose-celebrating.png) center/cover no-repeat;opacity:0}
 .col{position:relative;padding:20px;display:flex;flex-direction:column;gap:12px}
 .hd{height:0;margin-bottom:-12px}.hdt{display:block;font:400 36px/1 Shrikhand,cursive;max-width:200px;transform-origin:10% 80%;opacity:0}
 .nl{display:flex;align-items:baseline;gap:6px}.n{font:700 38px/1 Roundo,sans-serif}.of{font:600 14px Manrope,sans-serif;color:${K.ink3}}
 .bar{position:relative;height:20px;border-radius:999px;background:${K.mist};overflow:hidden}
 .fill{position:absolute;left:0;top:0;bottom:0;border-radius:999px;background:repeating-linear-gradient(-45deg,#F39E60 0 10px,#F6AE78 10px 20px)}
 .cf{position:absolute;inset:0;border-radius:999px;background:${K.cocoa};opacity:0}
 .msg{display:grid}.msg>span{grid-area:1/1;font:600 15px/1.35 Manrope,sans-serif}.m1 b{color:${K.car}}.m2{opacity:0;font-size:14px!important}
 .bw{height:0;overflow:hidden}
 .act{margin-top:12px;background:#fff;border-radius:24px;padding:14px 16px;min-height:64px;display:flex;align-items:center}
 .act .roll{flex:1;min-width:0;gap:12px}.act .rl{white-space:normal}</style>
 <div class="card"><div class="sun"></div><div class="masc" role="img" aria-label="Mascot celebrating"></div>
 <div class="col"><div class="hd"><span class="hdt">Discount unlocked!</span></div>
 <div class="nl"><span class="n"></span><span class="of">/ 200.000</span></div>
 <div class="bar"><div class="fill"><div class="cf"></div></div></div>
 <div class="msg"><span class="m1"><b class="rem"></b> to unlock the ongkir discount</span><span class="m2">Atas applies the ongkir discount when Rani sends the order.</span></div></div>
 <div class="bw"><atm-band text="DISCOUNT UNLOCKED • ONGKIR SORTED • KEEP ADDING • " bg="#2B1A12" fg="#E9FF83" size="13"></atm-band></div></div>
 <div class="act"><span class="roll"></span></div>`;
 const $=s=>this.q(s);const E=this.E={card:$('.card'),sun:$('.sun'),masc:$('.masc'),hd:$('.hd'),hdt:$('.hdt'),n:$('.n'),fill:$('.fill'),cf:$('.cf'),m1:$('.m1'),m2:$('.m2'),rem:$('.rem'),bw:$('.bw'),act:$('.act .roll')};this.band=$('atm-band');
 const p=()=>this.paint(),V=(x,e)=>this.v(x,p,e);
 this.V={f:V(0),nv:V(0,1),hdH:V(0,.05),hdS:V(0),hdO:V(0),fs:V(38,.05),sunO:V(0),sunR:V(0,.05),mO:V(0),mY:V(0,.05),mS:V(1),bwH:V(0,.05),cfO:V(0),m1O:V(1),m2O:V(0)};
 this.reset();}
paint(){const V=this.V,E=this.E,rm=this.rm,c=x=>Math.max(0,Math.min(1,x));
 E.fill.style.width=Math.max(0,V.f.v*100)+'%';E.n.textContent=rp(V.nv.v);E.rem.textContent=rp(Math.max(0,200000-V.nv.v))+' more';
 E.hd.style.height=Math.max(0,V.hdH.v)+'px';E.hd.style.marginBottom=(Math.min(1,Math.max(0,V.hdH.v)/72)*12-12)+'px';
 E.hdt.style.opacity=c(V.hdO.v);E.hdt.style.transform=rm?'none':`scale(${.6+.4*V.hdS.v}) rotate(${-6*(1-V.hdS.v)}deg)`;
 E.n.style.fontSize=V.fs.v+'px';E.sun.style.opacity=c(V.sunO.v);E.sun.style.transform=`rotate(${V.sunR.v}deg)`;
 E.masc.style.opacity=c(V.mO.v);E.masc.style.transform=`translateY(${V.mY.v}px) scale(${V.mS.v})`;
 E.bw.style.height=Math.max(0,V.bwH.v)+'px';E.cf.style.opacity=c(V.cfO.v);E.m1.style.opacity=c(V.m1O.v);E.m2.style.opacity=c(V.m2O.v);}
sync(){['rm','slow'].forEach(a=>{const v=a==='rm'?(this.rm?'1':'0'):String(this.slow);if(this.band.getAttribute(a)!==v)this.band.setAttribute(a,v);});}
change(d,who,i,txt){this.sync();const T=200000,prev=this.total,now=Math.max(0,prev+d);this.total=now;const V=this.V,rm=this.rm,f=Math.min(1,now/T);
 if(rm){this.tw(V.f,f,.25,'easeInOut');this.set(V.nv,now);this.fadeIn(this.E.n);this.fadeIn(this.E.rem);}else{this.sp(V.f,f,'trail');this.sp(V.nv,now,'glide');}
 this.roll(this.E.act,`<at-avatar i="${i}" size="36"></at-avatar><span style="flex:1;min-width:0;font:500 14px/1.4 Manrope,sans-serif"><b>${who}</b> ${txt}</span><span style="font:500 12px Manrope,sans-serif;color:${K.ink3}">now</span>`,1);
 if(prev<T&&now>=T)this.after(.18,()=>{this.unlock();this.hap('.success','Discount unlocked · total crossed Rp 200.000');});
 else if(prev>=T&&now<T){this.relock();this.hap('None','Re-lock · the “Rp X more” line says it');}
 else this.hap('None','Total changed · the bar moves, no haptic');}
unlock(){const V=this.V,E=this.E,rm=this.rm;this.tr(E.card,['background-color','box-shadow'],rm?.2:.2);E.card.style.backgroundColor=K.lime;E.card.style.boxShadow=`inset 0 0 0 2px ${K.limeR}`;
 if(rm){['cfO','hdO','mO','m2O'].forEach(k=>this.tw(V[k],1,.2,'easeInOut'));this.tw(V.m1O,0,.2,'easeInOut');this.tw(V.sunO,.7,.2,'easeInOut');this.set(V.hdH,72);this.set(V.hdS,1);this.set(V.fs,30);this.set(V.sunR,0);this.set(V.mY,0);this.set(V.mS,1);this.set(V.bwH,31);this.band.reset();return;}
 this.tw(V.cfO,1,.12);this.tw(V.m1O,0,.15,'easeIn');this.tw(V.m2O,1,.2,'easeOut',.10);
 this.sp(V.hdH,72,'settle');this.sp(V.fs,30,'settle');this.set(V.hdS,0);this.sp(V.hdS,1,'pop',.08);this.tw(V.hdO,1,.12,'easeOut',.08);
 this.set(V.sunR,-40);this.sp(V.sunR,0,'glide',.08);this.tw(V.sunO,.7,.2,'easeOut',.08);
 this.set(V.mY,60);this.set(V.mS,.8);this.sp(V.mY,0,'bounce',.14);this.sp(V.mS,1,'bounce',.14);this.tw(V.mO,1,.15,'easeOut',.14);
 this.band.reset();this.sp(V.bwH,31,'settle',.20);this.after(.32,()=>this.band.flick(-800));}
relock(){const V=this.V,E=this.E,rm=this.rm;this.tr(E.card,['background-color','box-shadow'],.2);E.card.style.backgroundColor='#fff';E.card.style.boxShadow='none';this.band.stop();
 const out=k=>rm?this.tw(V[k],0,.2,'easeInOut'):this.tw(V[k],0,.15,'easeIn');['cfO','hdO','mO','sunO','m2O'].forEach(out);
 this.tw(V.m1O,1,.2,rm?'easeInOut':'easeOut',rm?0:.05);
 if(rm){this.set(V.hdH,0);this.set(V.fs,38);this.set(V.bwH,0);}else{this.sp(V.hdH,0,'leave');this.sp(V.fs,38,'leave');this.sp(V.bwH,0,'leave');}}
reset(){this.total=155000;const V=this.V,E=this.E;E.card.style.transition='none';E.card.style.backgroundColor='#fff';E.card.style.boxShadow='none';
 Object.entries({f:.775,nv:155000,hdH:0,hdS:0,hdO:0,fs:38,sunO:0,sunR:0,mO:0,mY:0,mS:1,bwH:0,cfO:0,m1O:1,m2O:0}).forEach(([k,x])=>this.set(V[k],x));
 E.act.innerHTML=`<span class="rl"><at-avatar i="D" size="36"></at-avatar><span style="flex:1;min-width:0;font:500 14px/1.4 Manrope,sans-serif"><b>Dimas</b> added 2× Cinnamon Roll 60 gr · Rp 20.000</span><span style="font:500 12px Manrope,sans-serif;color:${K.ink3}">2 min</span></span>`;
 if(this.band.reset)this.band.reset();this.sync();}
}

/* 04 Async button: loading → success / failure */
class Async extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:360px}
 .sum{background:#fff;border-radius:32px;padding:20px;display:flex;flex-direction:column;gap:8px}
 .big{font:700 38px/1 Roundo,sans-serif}.sub{font:500 14px/1.45 Manrope,sans-serif;color:${K.ink2}}
 .err{position:absolute;left:28px;right:28px;bottom:118px;display:flex;gap:6px;align-items:flex-start;font:500 13px/1.4 Manrope,sans-serif;color:${K.red};opacity:0}
 .bar{position:absolute;left:12px;right:12px;bottom:26px;padding:12px;border-radius:36px;${GL}}
 .face{display:block;position:relative;overflow:hidden;height:57px;border-radius:999px;background:${K.car};border:4px solid ${K.car};color:${K.cream};font:600 17px/1.25 Manrope,sans-serif}
 .bar button{width:100%}.fl{position:absolute;left:0;top:0;bottom:0;width:0;background:rgba(251,243,234,.24)}
 .lb{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;gap:8px;white-space:nowrap;opacity:0}.ck{display:inline-flex}</style>
 <div class="sum"><span class="cap">Lock &amp; review</span><span class="big">Rp 155.000</span><span class="sub">4 people have items · cutoff 13:00. Locking stops new items and edits.</span></div>
 <div class="err">${ic('alert',15,K.red)}<span>Couldn’t lock the order. Check your connection and try again.</span></div>
 <div class="bar"><button aria-label="Lock order"><span class="face"><span class="fl"></span>
 <span class="lb" data-s="idle">${ic('lock',18)}Lock order</span><span class="lb" data-s="load">Locking…</span><span class="lb" data-s="ok"><span class="ck">${ic('check',18,null,3)}</span>Locked</span><span class="lb" data-s="fail">${ic('refresh',18)}Try again</span></span></button></div>`;
 this.face=this.q('.face');this.flEl=this.q('.fl');this.errEl=this.q('.err');this.ckEl=this.q('.ck');
 const pf=()=>{this.flEl.style.width=Math.max(0,this.fl.v*100)+'%';this.flEl.style.opacity=this.flo.v;};this.fl=this.v(0,pf);this.flo=this.v(1,pf);
 const pe=()=>{this.errEl.style.opacity=this.eo.v;this.errEl.style.transform=`translateY(${this.ey.v}px)`};this.eo=this.v(0,pe);this.ey=this.v(0,pe,.05);
 const pc=()=>{this.ckEl.style.transform=this.rm?'none':`scale(${Math.max(0,this.ck.v)}) rotate(${-12*(1-this.ck.v)}deg)`};this.ck=this.v(1,pc);
 this.L={};this.qa('.lb').forEach(el=>{const p=()=>{el.style.opacity=Math.max(0,Math.min(1,o.o.v));el.style.transform=`translateY(${o.y.v}px)`};const o={el,o:this.v(0,p),y:this.v(0,p,.05)};this.L[el.dataset.s]=o;});
 this.P=this.wire(this.q('button'),this.face,[1.02,.92],{inert:()=>this.st==='load'||this.st==='ok',tone:()=>this.st==='ok'?null:[K.car,K.carP,K.car,K.carP],commit:()=>this.start()});
 this.reset();}
label(s,ins){const p=this.lab;this.lab=s;const A=this.L[p],B=this.L[s];
 if(ins){Object.values(this.L).forEach(o=>{this.set(o.o,0);this.set(o.y,0)});this.set(B.o,1);return;}
 if(this.rm){if(A)this.tw(A.o,0,.2,'easeInOut');this.set(B.y,0);this.tw(B.o,1,.2,'easeInOut');return;}
 if(A){this.tw(A.o,0,.12,'easeIn');this.tw(A.y,-8,.12,'easeIn');}this.set(B.y,8);this.set(B.o,0);this.sp(B.y,0,'settle');this.tw(B.o,1,.18);}
start(){if(this.st==='load'||this.st==='ok')return;const rm=this.rm;
 if(this.st==='fail'){rm?this.tw(this.eo,0,.2,'easeInOut'):this.tw(this.eo,0,.15,'easeIn');}
 this.st='load';this.label('load');this.set(this.flo,1);this.tw(this.fl,.85,2.4,'easeOut');
 this.hap('.impact(weight: .light)','Lock order · request starts');
 this.after(1.4,()=>this.getAttribute('result')==='fail'?this.fail():this.ok());}
ok(){const rm=this.rm;this.st='ok';
 if(rm)this.tw(this.fl,1,.2,'easeInOut');else this.sp(this.fl,1,'lead');
 this.after(.10,()=>{this.tr(this.face,['background-color','border-color','color'],.2);this.face.style.backgroundColor=K.lime;this.face.style.borderColor=K.limeR;this.face.style.color=K.cocoa;this.tw(this.flo,0,.2);
  this.label('ok');if(!rm){this.P.bump(1.05);this.set(this.ck,0);this.sp(this.ck,1,'pop',.02);}});
 this.hap('.success','Lock order · request returned OK');}
fail(){const rm=this.rm;this.st='fail';
 if(rm)this.tw(this.fl,0,.2,'easeInOut');else this.sp(this.fl,0,'leave');this.P.shake();this.label('fail');
 if(rm){this.set(this.ey,0);this.tw(this.eo,1,.2,'easeInOut');}else{this.set(this.ey,-4);this.sp(this.ey,0,'settle');this.tw(this.eo,1,.2);}
 this.hap('.error','Lock order · request failed');}
reset(){this.st='idle';this.lab=null;this.P.rest();this.face.style.transition='none';this.face.style.backgroundColor=K.car;this.face.style.borderColor=K.car;this.face.style.color=K.cream;
 this.set(this.fl,0);this.set(this.flo,1);this.set(this.eo,0);this.set(this.ey,0);this.set(this.ck,1);this.label('idle',true);}
}

/* 05 Copy → toast */
class Copy extends Mo{
build(){
 const cb=(k,l)=>`<button class="cb" data-k="${k}" aria-label="Copy ${l}"><span class="face"><span class="lay cp">${ic('copy',15,K.cocoa)}</span><span class="lay ok">${ic('check',15,K.cocoa,3)}</span></span></button>`;
 this.sr.innerHTML=`<style>${BASE}:host{height:480px}
 .dk{background:${K.cocoa};color:${K.cream};border-radius:32px;padding:20px;display:flex;flex-direction:column;gap:14px}
 .r{display:flex;justify-content:space-between;align-items:center}.lab{display:block;font:500 12px Manrope,sans-serif;color:${K.mauve}}.val{display:block;font:700 17px/1.3 Manrope,sans-serif}
 .dk .cap{color:${K.mauve}}.bca{font:700 15px Manrope,sans-serif}
 .cb .face{display:block;position:relative;width:32px;height:32px;border-radius:50%;background:${K.peach}}.num26{font:700 26px Roundo,sans-serif!important;letter-spacing:.04em}.bca{padding:3px 12px;border-radius:999px;background:#F39E60;color:${K.cocoa};font:600 11px/1.4 Manrope,sans-serif!important;letter-spacing:.03em}
 .inv{margin-top:14px;background:#fff;border-radius:32px;padding:20px;display:flex;flex-direction:column;gap:12px}
 .link{font:600 16px Manrope,sans-serif}
 .cl{align-self:flex-start}.cl .face{display:flex;align-items:center;gap:8px;padding:8px 18px;border-radius:999px;background:${K.cream};border:4px solid ${K.peach};font:600 15px/1.25 Manrope,sans-serif}
 .cl .ico{position:relative;width:16px;height:16px}
 .toast{position:absolute;left:50%;bottom:28px;display:flex;align-items:center;gap:8px;padding:12px 20px;border-radius:999px;background:${K.cocoa};color:${K.cream};font:600 14px Manrope,sans-serif;white-space:nowrap;opacity:0;pointer-events:none}
 .toast .roll{gap:8px}</style>
 <div class="dk"><div class="r"><span class="cap">Transfer to</span><span class="bca">BCA</span></div>
 <div class="r"><div><span class="lab">Account name</span><span class="val">Rani Pratiwi</span></div>${cb('name','account name')}</div>
 <div class="r"><div><span class="lab">Account number</span><span class="val num26">5271 0099 34</span></div>${cb('num','account number')}</div></div>
 <div class="inv"><span class="cap">Invite link</span><span class="link">ataste.app/j/FRI-7Q2K</span>
 <button class="cl" data-k="link" aria-label="Copy link"><span class="face"><span class="ico"><span class="lay cp">${ic('copy',16)}</span><span class="lay ok">${ic('check',16,null,3)}</span></span>Copy link</span></button></div>
 <div class="toast"><span class="roll"></span></div>`;
 this.toastEl=this.q('.toast');this.tbox=this.q('.toast .roll');
 const pt=()=>{this.toastEl.style.opacity=Math.max(0,Math.min(1,this.to.v));this.toastEl.style.transform=`translateX(-50%) translateY(${this.ty.v}px) scale(${this.ts.v*this.tb.v})`;};
 this.to=this.v(0,pt);this.ty=this.v(24,pt,.05);this.ts=this.v(.96,pt);this.tb=this.v(1,pt);
 const MSG={name:'Account name copied',num:'Account number copied',link:'Link copied'};this.B={};this.tm={};
 this.qa('button').forEach(b=>{const k=b.dataset.k,face=b.querySelector('.face'),cp=b.querySelector('.cp'),ok=b.querySelector('.ok');
  const p=()=>{const c=o.c.v;if(this.rm){cp.style.transform=ok.style.transform='none';cp.style.opacity=1-c;ok.style.opacity=c;return;}ok.style.opacity=c>.005?1:0;ok.style.transform=`scale(${Math.max(0,c)}) rotate(${-12*(1-c)}deg)`;cp.style.opacity=1;cp.style.transform=`scale(${Math.max(0,1-c)})`;};
  const o={c:this.v(0,p)};o.P=this.wire(b,k==='link'?face:face,k==='link'?[1.04,.92]:[1.08,.88],{tone:k==='link'?()=>[K.cream,'#FDF8F2',K.peach,K.peachP]:()=>[K.peach,K.peachP],commit:()=>this.copy(k,MSG[k])});this.B[k]=o;});
 this.reset();}
copy(k,msg){const o=this.B[k],rm=this.rm;clearTimeout(this.tm[k]);
 if(rm)this.tw(o.c,1,.2,'easeInOut');else if(o.c.t>=1)o.P.bump(1.15);else{this.set(o.c,0);this.sp(o.c,1,'pop');}
 this.tm[k]=setTimeout(()=>rm?this.tw(o.c,0,.2,'easeInOut'):this.tw(o.c,0,.2),1600*this.slow);
 const shown=this.to.t>0;
 if(!shown){this.tbox.innerHTML=`<span class="rl">${ic('check',16,K.lime,3)}${msg}</span>`;if(rm){this.set(this.ty,0);this.set(this.ts,1);this.tw(this.to,1,.2,'easeInOut');}else{this.set(this.ty,24);this.set(this.ts,.96);this.sp(this.ty,0,'arrive');this.sp(this.ts,1,'arrive');this.tw(this.to,1,.2);}}
 else{if(this._msg!==msg)this.roll(this.tbox,`${ic('check',16,K.lime,3)}${msg}`,1);if(!rm){this.set(this.tb,1.06);this.sp(this.tb,1,'bump');}}
 this._msg=msg;clearTimeout(this.tm.toast);this.tm.toast=setTimeout(()=>{if(this.rm)this.tw(this.to,0,.2,'easeInOut');else{this.tw(this.ty,8,.15,'easeIn');this.tw(this.to,0,.15,'easeIn');}},1800*this.slow);
 this.hap('.impact(weight: .light)',msg+(shown?' · toast reused, timer restarts':''));}
reset(){Object.values(this.tm||{}).forEach(clearTimeout);this.tm={};Object.values(this.B).forEach(o=>{o.P.rest();this.set(o.c,0)});this.set(this.to,0);this.set(this.ty,24);this.set(this.ts,.96);this.set(this.tb,1);this._msg='';}
}

/* 06 Status chips + order timeline */
const CH={open:['Open','#E9FF83',K.cocoa,'#5E7A00'],locked:['Locked',K.mist,K.cocoa,K.cocoa],edits:['Edits requested','#F9B7D2',K.cocoa,'#B0005A'],sent:['Sent to Atas',K.peach,K.cocoa,K.car],confirmed:['Confirmed by Atas',K.car,K.cream,K.peach],delivered:['Delivered',K.cocoa,K.lime,K.lime],closed:['Closed','#fff',K.ink3,K.mauve,`inset 0 0 0 1.5px ${K.mauve}`],cancelled:['Cancelled','#FDE3E5','#B00010',K.red],
 unpaid:['Unpaid','#fff',K.cocoa,'',`inset 0 0 0 1.5px ${K.mauve}`],says:['Says paid',K.peach,K.cocoa,''],paid:['Paid',K.lime,K.cocoa,'',`inset 0 0 0 1.5px ${K.limeR}`,1]};
const STEPS=[['Open','users','Thu 2 Oct, 08:02','open'],['Locked','lock','Thu 2 Oct, 13:00 · at cutoff','locked'],['Sent to Atas','send','Thu 2 Oct, 13:20','sent'],['Confirmed by Atas','verified','Thu 2 Oct, 14:05 · bill frozen','confirmed'],['Delivered','truck','Fri 3 Oct, 10:00 WITA','delivered'],['Closed','check','','closed']];
const SHAP={locked:['None','Locked · watchers get no haptic; the host’s Lock order tap gave .success'],sent:['None','Sent to Atas · no haptic for watchers'],confirmed:['.success','Confirmed by Atas · the bill is frozen'],delivered:['.success','Delivered'],closed:['None','Closed'],edits:['.warning','Edits requested · for the member asked'],cancelled:['.error','Cancelled'],back:['None','Edits done · back to Locked'],says:['None','Says paid · your own I’ve paid tap gave .impact(weight: .light)'],paid:['.success','Paid · Rani confirmed your transfer']};
class Status extends Mo{
build(){
 this.sr.innerHTML=`<style>${BASE}:host{height:580px}
 .title{display:block;font:700 26px/1.1 Roundo,sans-serif;margin-bottom:10px}
 .chip{display:inline-flex;align-items:center;gap:6px;height:23px;padding:0 14px 0 10px;border-radius:999px;font:600 11px/1.4 Manrope,sans-serif;letter-spacing:.03em;text-transform:uppercase;white-space:nowrap;overflow:hidden;transform-origin:0 50%;vertical-align:middle}
 .chip.pay{padding:0 14px}.pay .dot{display:none}.dot{width:7px;height:7px;border-radius:50%;flex:none}.chip .roll{gap:6px}
 .meas{position:absolute;left:0;top:0;visibility:hidden}
 .tl{margin-top:16px;background:#fff;border-radius:32px;padding:20px 20px 8px}
 .st{display:flex;gap:14px}.rail{display:flex;flex-direction:column;align-items:center;width:22px}
 .node{position:relative;width:22px;height:22px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center}.ico{display:flex}
 .ln{position:relative;width:2px;flex:1;min-height:14px;background:${K.mist}}.lnf{position:absolute;left:0;top:0;width:100%;height:0;background:${K.limeR}}
 .tx{display:flex;flex-direction:column;gap:2px;padding-bottom:12px}.sl{font:700 15px/22px Manrope,sans-serif}.sm{font:500 12px/1.4 Manrope,sans-serif;color:${K.ink3};min-height:17px}
 .bill{margin-top:12px;background:#fff;border-radius:24px;padding:14px 18px;display:flex;justify-content:space-between;align-items:center}
 .bl{display:flex;flex-direction:column;gap:4px}.amt{font:700 24px/1 Roundo,sans-serif}</style>
 <span class="title">Academy Bali Friday Treats</span><span class="chip ord"><span class="dot"></span><span class="roll lbx"></span></span>
 <div class="tl">${STEPS.map((s,i)=>`<div class="st"><div class="rail"><span class="node"><span class="ico"></span></span>${i<STEPS.length-1?'<span class="ln"><span class="lnf"></span></span>':''}</div><div class="tx"><span class="sl">${s[0]}</span><span class="sm">${s[2]}</span></div></div>`).join('')}</div>
 <div class="bill"><div class="bl"><span class="cap">Your bill</span><span class="amt">Rp 99.500</span></div><span class="chip pay"><span class="dot"></span><span class="roll lbx"></span></span></div>
 <span class="chip meas"><span class="dot"></span><span class="lbx"></span></span>`;
 this.meas=this.q('.meas');this.tlEl=this.q('.tl');
 const mk=el=>{const c={el,dot:el.querySelector('.dot'),lbx:el.querySelector('.lbx'),pay:el.classList.contains('pay')};const p=()=>{el.style.width=c.w.v+'px';el.style.transform=`scale(${c.bs.v})`};c.w=this.v(60,p,.05);c.bs=this.v(1,p);return c;};
 this.ord=mk(this.q('.ord'));this.pay=mk(this.q('.pay'));
 this.N=this.qa('.st').map((st,i)=>{const n={node:st.querySelector('.node'),ico:st.querySelector('.ico'),lnf:st.querySelector('.lnf'),sl:st.querySelector('.sl'),sm:st.querySelector('.sm')};
  const p=()=>{n.node.style.transform=`scale(${n.ns.v})`;n.ico.style.transform=this.rm?'none':`scale(${Math.max(0,n.is.v)})`;if(n.lnf){n.lnf.style.height=Math.max(0,Math.min(1,n.lf.v))*100+'%';n.lnf.style.opacity=n.lo.v;}n.sm.style.opacity=n.mo.v;};
  n.ns=this.v(1,p);n.is=this.v(1,p);n.lf=this.v(0,p);n.lo=this.v(1,p);n.mo=this.v(0,p);return n;});
 const pt=()=>{this.tlEl.style.opacity=this.tlo.v};this.tlo=this.v(1,pt);
 this.reset();if(document.fonts&&document.fonts.ready)document.fonts.ready.then(()=>{if(!this._touched)this.reset();});}
cw(kind){const s=CH[kind];this.meas.classList.toggle('pay',!CH[kind][3]);this.meas.querySelector('.lbx').innerHTML=`<span class="rl" style="gap:6px">${s[5]?ic('check',11,null,3):''}${s[0]}</span>`;return this.meas.offsetWidth;}
chip(c,kind,ins){const s=CH[kind],rm=this.rm,html=(s[5]?ic('check',11,null,3):'')+s[0];c.kind=kind;
 if(ins)c.el.style.transition='none';else this.tr(c.el,['background-color','color','box-shadow'],rm?.2:.12);
 c.el.style.backgroundColor=s[1];c.el.style.color=s[2];c.el.style.boxShadow=s[4]||'none';c.dot.style.backgroundColor=s[3]||'transparent';c.dot.style.transition=c.el.style.transition;
 const w=this.cw(kind);if(ins){c.lbx.innerHTML=`<span class="rl">${html}</span>`;this.set(c.w,w);this.set(c.bs,1);return;}
 this.roll(c.lbx,html,1);if(rm)this.set(c.w,w);else{this.sp(c.w,w,'lead');this.after(.06,()=>{this.set(c.bs,1.08);this.sp(c.bs,1,'bump');});}}
node(i,st,ins){const n=this.N[i],S=STEPS[i],rm=this.rm;
 const L={done:[K.lime,`inset 0 0 0 1.5px ${K.limeR}`,'check',K.cocoa,K.cocoa],now:[K.car,`0 0 0 5px ${K.peach}`,S[1],K.cream,K.cocoa],todo:['#fff',`inset 0 0 0 2px ${K.mauve}`,'more',K.cocoa,K.ink4]}[st];
 if(ins)n.node.style.transition=n.sl.style.transition='none';else{this.tr(n.node,['background-color','box-shadow'],.2);this.tr(n.sl,['color'],.2);}
 n.node.style.backgroundColor=L[0];n.node.style.boxShadow=L[1];n.sl.style.color=L[4];n.ico.innerHTML=ic(L[2],12,L[3],3);
 const showMeta=st!=='todo'||i===4;if(ins){this.set(n.mo,showMeta?1:0);return;}
 if(rm)this.fadeIn(n.ico);else{this.set(n.is,0);this.sp(n.is,1,'pop');}
 if(st==='now'){if(!rm){this.set(n.ns,.6);this.sp(n.ns,1,'pop');}if(n.mo.v<1){this.set(n.mo,0);this.tw(n.mo,1,.2,rm?'easeInOut':'easeOut',rm?0:.08);}}}
next(){this._touched=1;if(this.cancelled)return;
 if(this.ord.kind==='edits'){this.chip(this.ord,'locked');this.hap(...SHAP.back);return;}
 if(this.cur>=STEPS.length-1)return;const i=this.cur,rm=this.rm,n=this.N[i];this.cur++;
 if(rm){this.set(n.lf,1);this.set(n.lo,0);this.tw(n.lo,1,.2,'easeInOut');}else{this.set(n.lo,1);this.sp(n.lf,1,'trail');}
 const live=x=>x<this.cur?'done':x===this.cur?'now':'todo';this.after(rm?0:.08,()=>this.node(i,live(i)));this.after(rm?0:.20,()=>this.node(i+1,live(i+1)));
 const k=STEPS[this.cur][3];this.chip(this.ord,k);this.hap(...SHAP[k]);}
edits(){this._touched=1;if(this.cancelled||this.cur!==1||this.ord.kind==='edits')return;this.chip(this.ord,'edits');this.hap(...SHAP.edits);}
cancel(){this._touched=1;if(this.cancelled||this.cur>=4)return;this.cancelled=1;this.chip(this.ord,'cancelled');this.tw(this.tlo,.45,.2,this.rm?'easeInOut':'easeOut');this.hap(...SHAP.cancelled);}
payNext(){this._touched=1;const o=['unpaid','says','paid'],i=o.indexOf(this.pay.kind);if(i>=2)return;const k=o[i+1];this.chip(this.pay,k);this.hap(...SHAP[k]);}
reset(){this.cur=0;this.cancelled=0;this.chip(this.ord,'open',true);this.chip(this.pay,'unpaid',true);this.set(this.tlo,1);
 this.N.forEach((n,i)=>{this.set(n.ns,1);this.set(n.is,1);this.set(n.lf,0);this.set(n.lo,1);this.node(i,i===0?'now':'todo',true);});}
}

window.AtMotion={Mo,K,SP,EASE,SHAKE,rp,ic,GL,BASE};
customElements.define('atm-band',Band);customElements.define('atm-buttons',Buttons);customElements.define('atm-basket',Basket);
customElements.define('atm-unlock',Unlock);customElements.define('atm-async',Async);customElements.define('atm-copy',Copy);customElements.define('atm-status',Status);
})();
