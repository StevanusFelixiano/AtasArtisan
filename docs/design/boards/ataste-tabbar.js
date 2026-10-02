// Ataste custom tab bar (direction 1a "Cocoa sticker"): <at-tab-bar>, <at-tab-icon>
// Springs use the SwiftUI model: stiffness = (2π/response)², damping = 4π·dampingFraction/response, mass 1.
(function(){
if (customElements.get('at-tab-bar')) return;
const COCOA='#2B1A12',CREAM='#FBF3EA',PILL='#F9CFAF',PILLP='#FCE3D0',IDLE='#D1B6BB';
const TABS=[['home','Home'],['history','History'],['profile','Profile']];
const IC={
home:{o:'<path d="M4 10.4L12 4l8 6.4V19a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"/><path d="M16.2 7.4V4.8h2.4v4.5"/><path d="M10 21v-3.6a2 2 0 0 1 4 0V21"/>',
 f:'<path d="M4 10.4L12 4l8 6.4V19a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" fill="currentColor"/><path d="M16.2 7.4V4.8h2.4v4.5z" fill="currentColor"/><path d="M10 22.3v-4.9a2 2 0 0 1 4 0v4.9z" fill="var(--cut)" stroke="none"/>'},
history:{o:'<path d="M4 12a8 8 0 1 0 2.35-5.66L4 8.7"/><path d="M4 4.3v4.4h4.4"/><path d="M12 8v4l2.8 1.8"/>',
 f:'<circle cx="12" cy="12" r="8" fill="currentColor"/><path d="M6.35 6.34L4 8.7"/><path d="M4 4.3v4.4h4.4"/><path d="M12 8v4l2.8 1.8" stroke="var(--cut)"/>'},
profile:{o:'<circle cx="12" cy="8.2" r="3.9"/><path d="M4.8 20.2c.9-3.7 3.8-5.9 7.2-5.9s6.3 2.2 7.2 5.9"/>',
 f:'<circle cx="12" cy="8.2" r="3.9" fill="currentColor"/><path d="M4.8 20.2c.9-3.7 3.8-5.9 7.2-5.9s6.3 2.2 7.2 5.9c.1.5-.3.9-.8.9H5.6c-.5 0-.9-.4-.8-.9z" fill="currentColor"/>'}
};
const svg=(n,f,s=24,st='')=>`<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.25" stroke-linecap="round" stroke-linejoin="round" style="display:block;${st}">${(IC[n]||IC.home)[f?'f':'o']}</svg>`;
function bez(x1,y1,x2,y2){const cx=3*x1,bx=3*(x2-x1)-cx,ax=1-cx-bx,cy=3*y1,by=3*(y2-y1)-cy,ay=1-cy-by;
 const sx=t=>((ax*t+bx)*t+cx)*t,sy=t=>((ay*t+by)*t+cy)*t,ds=t=>(3*ax*t+2*bx)*t+cx;
 return x=>{if(x<=0)return 0;if(x>=1)return 1;let t=x;for(let i=0;i<8;i++){const e=sx(t)-x,d=ds(t);if(Math.abs(e)<1e-5||Math.abs(d)<1e-6)break;t-=e/d;}return sy(Math.min(1,Math.max(0,t)));};}
const EASE={easeOut:bez(0,0,.58,1),easeIn:bez(.42,0,1,1),easeInOut:bez(.42,0,.58,1),linear:x=>x};

class TabIcon extends HTMLElement{static get observedAttributes(){return['name','filled','size','color','cut']}
connectedCallback(){this.r()}attributeChangedCallback(){if(this.isConnected)this.r()}
r(){const sr=this.shadowRoot||this.attachShadow({mode:'open'}),g=n=>this.getAttribute(n),s=g('size')||'24';
sr.innerHTML=`<style>:host{display:inline-flex;flex:none;width:${s}px;height:${s}px}</style>`+svg(g('name')||'home',g('filled')!=null&&g('filled')!=='0',s,`color:${g('color')||'currentColor'};--cut:${g('cut')||PILL}`);}}
customElements.define('at-tab-icon',TabIcon);

const CSS=`:host{display:block;position:relative;height:124px;pointer-events:none;-webkit-tap-highlight-color:transparent}
:host([layout=bare]){width:370px;height:64px}
.fade{position:absolute;inset:0;background:linear-gradient(rgba(251,243,234,0),rgba(251,243,234,.85) 70%)}
:host([layout=bare]) .fade,:host([fade="0"]) .fade{display:none}
.wrap{position:absolute;left:16px;right:16px;bottom:30px;height:64px;pointer-events:auto;transform-origin:50% 100%;--pill:${PILL}}
:host([layout=bare]) .wrap{left:0;right:0;bottom:0}
.bar{position:absolute;inset:0;border-radius:999px;background:${COCOA};box-shadow:0 4px 0 #9D5C1D,0 18px 30px -10px rgba(43,26,18,.45)}
.ind,.pill{position:absolute;top:8px;height:48px;border-radius:999px;background:var(--pill)}
.ind::after,.pill::after{content:"";position:absolute;inset:3px;border-radius:999px;border:1.5px dashed rgba(157,92,29,.55)}
.ind{left:0;width:0;transform-origin:50% 50%}
.tabs{position:absolute;inset:0 8px;display:grid;grid-template-columns:repeat(3,minmax(0,1fr))}
.tab{all:unset;position:relative;display:flex;align-items:center;justify-content:center;height:64px;cursor:pointer;touch-action:manipulation;-webkit-user-select:none;user-select:none}
.tab:focus-visible .grp{outline:2px solid ${PILL};outline-offset:8px;border-radius:999px}
.pill{left:50%;opacity:0}
.halo{position:absolute;top:8px;height:48px;width:64px;left:50%;margin-left:-32px;border-radius:999px;background:rgba(251,243,234,.13);opacity:0}
.grp{position:relative;display:flex;align-items:center;transform-origin:50% 50%}
.ico{position:relative;width:24px;height:24px;flex:none}
.io,.if{position:absolute;inset:0;display:block}
.io{color:${IDLE}}.if{color:${COCOA};opacity:0;--cut:var(--pill)}
.av{position:absolute;left:-1px;top:-1px;width:26px;height:26px;border-radius:50%;box-shadow:0 0 0 2px ${IDLE}}
.clip{display:flex;overflow:hidden;width:0}
.lbl{flex:none;padding-left:7px;font:700 15px/1.2 Roundo,Manrope,sans-serif;color:${COCOA};white-space:nowrap;opacity:0}
.badge{position:absolute;left:14px;top:-8px;min-width:18px;height:18px;padding:0 5px;box-sizing:border-box;border-radius:9px;background:#E9FF83;color:${COCOA};box-shadow:0 0 0 2.5px ${COCOA};font:700 11px/18px Roundo,Manrope,sans-serif;text-align:center;transform:scale(0);opacity:0;overflow:hidden}
.badge.dot{left:17px;top:-3px;min-width:10px;width:10px;height:10px;padding:0;border-radius:5px}
.badge.dot .num{display:none}.num{display:block}`;

class TabBar extends HTMLElement{
static get observedAttributes(){return['active','badge','dot','disabled','pressed','rm','concealed','avatar','stretch','slow','layout','interactive','fade']}
constructor(){super();this.act=new Set();this._raf=0;this._tick=this.tick.bind(this);}
a(n,d){const v=this.getAttribute(n);return v==null||v===''?d:v}
get slow(){return Math.max(.1,+this.a('slow','1')||1)}
get rm(){return this.a('rm','0')==='1'}
idx(k){const i=TABS.findIndex(t=>t[0]===k);return i<0?0:i}
dis(i){return i!==this.cur&&this.a('disabled','').split(',').includes(TABS[i][0])}
connectedCallback(){if(!this._b)this.build();else this.layout();}
attributeChangedCallback(n,o,v){if(!this._b||o===v)return;
 if(n==='active'){const i=this.idx(v);if(i!==this.cur)this.select(i);}
 else if(n==='badge'||n==='dot')this.badge();
 else if(n==='concealed')this.conceal();
 else if(n==='avatar'){this.icons();this.layout();}
 else if(['disabled','pressed','rm','layout'].includes(n))this.layout();}
emit(n,d){this.dispatchEvent(new CustomEvent(n,{detail:d,bubbles:true,composed:true}))}
v(x,p,eps){return {v:x,t:x,vel:0,eps:eps||.001,paint:p,mode:null,delay:0}}
spring(o,t,r,d,delay=0,then){Object.assign(o,{mode:'s',t,r,d,delay,then});this.run(o)}
tween(o,t,dur,ease='easeOut',delay=0,then){Object.assign(o,{mode:'t',t,dur,ease:EASE[ease],el:0,from:null,delay,then,vel:0});this.run(o)}
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

build(){this._b=true;const sr=this.attachShadow({mode:'open'});
 sr.innerHTML=`<style>${CSS}</style><div class="fade"></div><div class="wrap"><div class="bar"></div><div class="ind"></div><div class="tabs" role="tablist">${TABS.map(([k,l],i)=>`<button class="tab" role="tab" aria-label="${l}" data-i="${i}"><span class="pill"></span><span class="halo"></span><span class="grp"><span class="ico"></span><span class="clip"><span class="lbl">${l}</span></span></span></button>`).join('')}</div></div>`;
 const q=s=>sr.querySelector(s);this.wrap=q('.wrap');this.fadeEl=q('.fade');this.ind=q('.ind');
 this.E=[...sr.querySelectorAll('.tab')].map(b=>({btn:b,pill:b.querySelector('.pill'),halo:b.querySelector('.halo'),grp:b.querySelector('.grp'),ico:b.querySelector('.ico'),clip:b.querySelector('.clip'),lbl:b.querySelector('.lbl')}));
 this.cur=this.idx(this.a('active','home'));
 this.T=this.E.map((_,i)=>{const p=()=>this.paintTab(i),px=.05;return{sq:this.v(0,p),halo:this.v(0,p),oo:this.v(1,p),fo:this.v(0,p),icoS:this.v(1,p),hop:this.v(0,p,px),cw:this.v(0,p,px),lo:this.v(0,p),lx:this.v(0,p,px),sh:this.v(0,p,px),pill:this.v(0,p),dim:this.v(1,p)}});
 const pi=()=>this.paintInd();this.L=this.v(0,pi,.05);this.R=this.v(0,pi,.05);
 const pb=()=>this.paintBadge();this.bs=this.v(0,pb);this.br=this.v(0,pb,.05);this.bo=this.v(0,pb);
 const pw=()=>this.paintWrap();this.cy=this.v(0,pw,.05);this.co=this.v(1,pw);this.cs=this.v(1,pw);
 this.icons();this.layout();this.badge();this.conceal();this._init=true;
 this.E.forEach((e,i)=>{const b=e.btn;
  b.addEventListener('pointerdown',ev=>{if(this.a('interactive','0')!=='1')return;this.pi=i;this.inside=true;try{b.setPointerCapture(ev.pointerId)}catch(_){};if(!this.dis(i))this.press(i,true);});
  b.addEventListener('pointermove',ev=>{if(this.pi!==i)return;const r=b.getBoundingClientRect(),inn=ev.clientX>=r.left-8&&ev.clientX<=r.right+8&&ev.clientY>=r.top-16&&ev.clientY<=r.bottom+16;if(inn!==this.inside){this.inside=inn;if(!this.dis(i))this.press(i,inn);}});
  b.addEventListener('pointerup',()=>{if(this.pi!==i)return;this.pi=null;if(this.inside){if(!this.dis(i))this.press(i,false);this.commit(i);}});
  b.addEventListener('pointercancel',()=>{if(this.pi!==i)return;this.pi=null;if(this.inside&&!this.dis(i))this.press(i,false);});
  b.addEventListener('click',ev=>{if(ev.detail===0&&this.a('interactive','0')==='1')this.commit(i);});});
 if(document.fonts&&document.fonts.ready)document.fonts.ready.then(()=>this.layout());
 if(window.ResizeObserver){let w=0;new ResizeObserver(()=>{const nw=this.wrap.clientWidth;if(nw&&nw!==w){w=nw;this.layout();}}).observe(this.wrap);}}
icons(){const av=this.a('avatar','');this.E.forEach((e,i)=>{const k=TABS[i][0];
 e.ico.innerHTML=(k==='profile'&&av)?`<span class="av"><at-avatar i="${av}" size="26"></at-avatar></span>`:`<span class="io">${svg(k,0)}</span><span class="if">${svg(k,1)}</span>`;
 if(i===0)e.ico.insertAdjacentHTML('beforeend','<span class="badge"><span class="num"></span></span>');
 e.io=e.ico.querySelector('.io');e.if=e.ico.querySelector('.if');e.av=e.ico.querySelector('.av');});
 this.bEl=this.E[0].ico.querySelector('.badge');this.num=this.bEl.querySelector('.num');this._bm=null;if(this._init)this.badge(true);}
measure(){this.lw=this.E.map((e,i)=>e.lbl.offsetWidth||[50,64,58][i]);}
pw(i){return 14+24+this.lw[i]+14}
geo(i){const W=this.wrap.clientWidth||370,cw=(W-16)/3,c=8+cw*(i+.5),w=this.pw(i);return[c-w/2,c+w/2];}
layout(){if(!this._b)return;this.measure();const c=this.cur,rm=this.rm,pr=this.a('pressed','');
 [this.L,this.R].forEach(o=>this.act.delete(o));
 this.T.forEach((T,i)=>{Object.values(T).forEach(o=>{this.act.delete(o);o.vel=0;o.mode=null;});const on=i===c,e=this.E[i],p=pr===TABS[i][0];
  T.oo.v=on?0:1;T.fo.v=on?1:0;T.cw.v=on?this.lw[i]:0;T.lo.v=on?1:0;T.lx.v=0;T.icoS.v=1;T.hop.v=0;T.sh.v=0;T.pill.v=on&&rm?1:0;
  T.sq.v=p&&!rm?1:0;T.dim.v=p&&rm?.6:1;T.halo.v=p&&!on?1:0;if(e.io)e.io.style.color=p&&!on?CREAM:IDLE;
  const w=this.pw(i);e.pill.style.width=w+'px';e.pill.style.marginLeft=-w/2+'px';
  e.btn.setAttribute('aria-selected',on);e.btn.setAttribute('aria-disabled',this.dis(i));});
 this.wrap.style.setProperty('--pill',pr&&pr===TABS[c][0]?PILLP:PILL);
 const[l,r]=this.geo(c);this.L.v=l;this.R.v=r;this.setAv();this.T.forEach((_,i)=>this.paintTab(i));this.paintInd();}
setAv(){this.E.forEach((e,i)=>{if(e.av)e.av.style.boxShadow='0 0 0 2px '+(i===this.cur?COCOA:IDLE);});}
paintTab(i){const T=this.T[i],e=this.E[i],sq=T.sq.v;
 e.grp.style.transform=this.rm?`translateX(${T.sh.v}px)`:`translateX(${T.sh.v}px) scale(${1+.08*sq},${1-.12*sq})`;e.grp.style.opacity=T.dim.v;
 e.ico.style.transform=`translateY(${T.hop.v}px) scale(${T.icoS.v})`;
 if(e.io){e.io.style.opacity=Math.max(0,T.oo.v)*(this.dis(i)?.32:1);e.if.style.opacity=Math.max(0,T.fo.v);}else e.ico.style.opacity=this.dis(i)?.32:1;
 e.clip.style.width=Math.max(0,T.cw.v)+'px';e.lbl.style.opacity=Math.max(0,T.lo.v);e.lbl.style.transform=`translateX(${T.lx.v}px)`;
 e.halo.style.opacity=T.halo.v;e.pill.style.opacity=T.pill.v;if(i===this.cur)this.paintInd();}
paintInd(){const s=this.ind.style,sq=this.T[this.cur].sq.v;s.left=this.L.v+'px';s.width=Math.max(0,this.R.v-this.L.v)+'px';s.transform=this.rm?'none':`scale(${1+.04*sq},${1-.08*sq})`;s.opacity=this.rm?0:1;}
paintBadge(){this.bEl.style.transform=`scale(${Math.max(0,this.bs.v)}) rotate(${this.br.v}deg)`;this.bEl.style.opacity=Math.max(0,Math.min(1,this.bo.v));}
paintWrap(){const o=Math.max(0,Math.min(1,this.co.v));this.wrap.style.transform=`translateY(${this.cy.v}px) scale(${this.cs.v})`;this.wrap.style.opacity=o;this.fadeEl.style.opacity=o;}

press(i,on){const T=this.T[i],sel=i===this.cur,e=this.E[i];
 if(this.rm)this.tween(T.dim,on?.6:1,on?.10:.15);else on?this.spring(T.sq,1,.20,.75):this.spring(T.sq,0,.38,.50);
 if(!sel){this.tween(T.halo,on?1:0,on?.08:.15);if(e.io)e.io.style.color=on?CREAM:IDLE;}
 else this.wrap.style.setProperty('--pill',on?PILLP:PILL);}
commit(i){const T=this.T[i],k=TABS[i][0];
 if(this.dis(i)){if(!this.rm)this.keys(T.sh,[[0,0],[.05,4],[.12,-3],[.19,2],[.26,-1],[.32,0]]);
  this.emit('haptic',{type:'.impact(weight: .light, intensity: 0.5)',why:'Disabled tab'});this.emit('tab-blocked',{tab:k});return;}
 if(i===this.cur){if(!this.rm)this.tween(T.hop,-5,.08,'easeOut',0,()=>this.spring(T.hop,0,.30,.45));
  this.emit('haptic',{type:'.impact(weight: .light)',why:'Re-tap · scroll to top'});this.emit('tab-retap',{tab:k});return;}
 const f=this.cur;this.select(i);this.emit('haptic',{type:'.selection',why:'Tab change'});this.emit('tab-select',{tab:k,from:TABS[f][0]});}
select(i){const f=this.cur;if(i===f)return;this.cur=i;const A=this.T[f],B=this.T[i],[l,r]=this.geo(i);
 this.E.forEach((e,j)=>{e.btn.setAttribute('aria-selected',j===i);e.btn.setAttribute('aria-disabled',this.dis(j));if(e.io&&j!==i)e.io.style.color=IDLE;});
 this.wrap.style.setProperty('--pill',PILL);this.setAv();this.set(A.sq,0);this.set(A.halo,0);
 if(this.rm){this.tween(A.pill,0,.2,'easeInOut');this.tween(B.pill,1,.2,'easeInOut');
  this.tween(A.oo,1,.15,'easeInOut');this.tween(A.fo,0,.15,'easeInOut');this.tween(B.oo,0,.15,'easeInOut');this.tween(B.fo,1,.15,'easeInOut');
  this.set(A.cw,0);this.set(A.lo,0);this.set(B.cw,this.lw[i]);this.set(B.lx,0);this.set(B.lo,0);this.tween(B.lo,1,.2,'easeInOut');
  this.set(B.halo,0);this.set(this.L,l);this.set(this.R,r);return;}
 const right=i>f,lead=right?this.R:this.L,trail=right?this.L:this.R,lt=right?r:l,tt=right?l:r;
 if(this.a('stretch','1')!=='0'){this.spring(lead,lt,.30,.78);this.spring(trail,tt,.44,.82);}else{this.spring(lead,lt,.36,.80);this.spring(trail,tt,.36,.80);}
 this.tween(A.oo,1,.12);this.tween(A.fo,0,.12);this.tween(B.oo,0,.12);this.tween(B.fo,1,.12);
 this.tween(B.icoS,.7,.07,'easeOut',0,()=>this.spring(B.icoS,1,.38,.45));
 this.tween(A.lo,0,.10,'easeIn');this.spring(A.cw,0,.32,1);
 this.spring(B.cw,this.lw[i],.40,.86,.04);this.set(B.lo,0);this.set(B.lx,-6);this.tween(B.lo,1,.18,'easeOut',.08);this.tween(B.lx,0,.18,'easeOut',.08);
 this.tween(B.halo,0,.12);}
badge(force){const n=+this.a('badge','0')||0,m=n>0?'n':this.a('dot','0')==='1'?'d':'',p=this._bm,txt=n>9?'9+':String(n),rm=this.rm;this._bm=m;
 if(m){this.bEl.classList.toggle('dot',m==='d');}
 if(!this._init||force){if(m==='n')this.num.textContent=txt;this._bt=txt;this.set(this.bs,m?1:0);this.set(this.bo,m?1:0);this.set(this.br,0);return;}
 if(m&&!p){if(m==='n')this.num.textContent=txt;if(rm){this.set(this.bs,1);this.set(this.br,0);this.set(this.bo,0);this.tween(this.bo,1,.2);}
  else{this.set(this.bo,1);this.set(this.bs,0);this.set(this.br,-12);this.spring(this.bs,1,.32,.50);this.spring(this.br,0,.32,.50);}}
 else if(!m&&p){if(rm)this.tween(this.bo,0,.15,'easeIn');else{this.tween(this.bs,0,.15,'easeIn');this.tween(this.bo,0,.15,'easeIn');}}
 else if(m&&(m!==p||(m==='n'&&txt!==this._bt))){if(m==='n')this.num.textContent=txt;
  if(rm)this.num.animate([{opacity:0},{opacity:1}],{duration:150*this.slow});
  else{this.set(this.bs,1.2);this.spring(this.bs,1,.30,.60);if(m==='n')this.num.animate([{transform:'translateY(8px)',opacity:0},{transform:'none',opacity:1}],{duration:180*this.slow,easing:'cubic-bezier(0,0,.58,1)'});}}
 this._bt=txt;}
conceal(){const m=this.a('concealed','none'),p=this._cm||'none',rm=this.rm,{cy,co,cs}=this;this._cm=m;
 this.wrap.style.pointerEvents=m==='none'?'auto':'none';
 if(!this._init){this.set(cy,m==='push'&&!rm?120:m==='keyboard'&&!rm?24:0);this.set(co,m==='none'?1:0);this.set(cs,m==='none'||rm?1:.96);return;}
 if(m===p)return;
 if(m==='push'){if(rm)this.tween(co,0,.15);else{this.spring(cy,120,.32,1);this.spring(co,0,.32,1);this.spring(cs,.96,.32,1);}}
 else if(m==='keyboard'){if(rm)this.tween(co,0,.12,'easeIn');else{this.tween(cy,24,.16,'easeIn');this.tween(co,0,.16,'easeIn');this.tween(cs,.96,.16,'easeIn');}}
 else{const d=p==='push'?.06:.05;if(rm){this.set(cy,0);this.set(cs,1);this.tween(co,1,.2,'easeOut',d);}
  else{const[r,z]=p==='push'?[.42,.72]:[.40,.80];this.spring(cy,0,r,z,d);this.spring(cs,1,r,z,d);this.tween(co,1,.2,'easeOut',d);}}}
}
customElements.define('at-tab-bar',TabBar);
})();
