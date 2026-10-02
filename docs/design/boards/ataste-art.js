// Ataste shared art: <at-icon>, <at-marquee>, <at-spin>, <at-status>, <at-homebar>, <at-qr>
(function(){
const COCOA='#2B1A12';
const I={
plus:'<path d="M12 5v14M5 12h14"/>',minus:'<path d="M5 12h14"/>',check:'<path d="M20 6L9 17l-5-5"/>',x:'<path d="M18 6L6 18M6 6l12 12"/>',
'chev-l':'<path d="M15 18l-6-6 6-6"/>','chev-r':'<path d="M9 18l6-6-6-6"/>','chev-d':'<path d="M6 9l6 6 6-6"/>','chev-u':'<path d="M18 15l-6-6-6 6"/>',
search:'<circle cx="11" cy="11" r="7.5"/><path d="M21 21l-4.3-4.3"/>',
copy:'<rect x="8" y="8" width="13" height="13" rx="3"/><path d="M4 16c-1.1 0-2-.9-2-2V5c0-1.7 1.3-3 3-3h9c1.1 0 2 .9 2 2"/>',
share:'<path d="M4 12v7a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7M16 6l-4-4-4 4M12 2v13"/>',
bag:'<path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><path d="M3 6h18M16 10a4 4 0 0 1-8 0"/>',
clock:'<circle cx="12" cy="12" r="9.5"/><path d="M12 7v5l3.5 2"/>',
bell:'<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"/>',
user:'<circle cx="12" cy="8" r="4.5"/><path d="M20 21a8 8 0 0 0-16 0"/>',
users:'<circle cx="9" cy="8" r="4"/><path d="M2 21a7 7 0 0 1 14 0M16 4a4 4 0 0 1 0 8M22 21a7 7 0 0 0-4-6.3"/>',
lock:'<rect x="4" y="11" width="16" height="11" rx="3"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
unlock:'<rect x="4" y="11" width="16" height="11" rx="3"/><path d="M8 11V7a4 4 0 0 1 7.8-1.2"/>',
edit:'<path d="M17 3a2.8 2.8 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5z"/>',
trash:'<path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
pin:'<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z"/><circle cx="12" cy="10" r="3"/>',
cal:'<rect x="3" y="4" width="18" height="18" rx="3"/><path d="M16 2v4M8 2v4M3 10h18"/>',
camera:'<path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3z"/><circle cx="12" cy="13" r="3.5"/>',
image:'<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="9" cy="9" r="2"/><path d="M21 15l-3.1-3.1a2 2 0 0 0-2.8 0L6 21"/>',
more:'<circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/>',
link:'<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>',
qr:'<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><path d="M14 14h3v3h-3zM18 18h3v3h-3z"/>',
home:'<path d="M3 10l9-7 9 7v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><path d="M9 22V12h6v10"/>',
history:'<path d="M3 12a9 9 0 1 0 9-9 9.8 9.8 0 0 0-6.7 2.7L3 8"/><path d="M3 3v5h5M12 7v5l4 2"/>',
receipt:'<path d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1z"/><path d="M8 8h8M8 12h8M8 16h5"/>',
alert:'<path d="M10.3 3.9L1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/><path d="M12 9v4M12 17h.01"/>',
'wifi-off':'<path d="M2 2l20 20M8.5 16.5a5 5 0 0 1 7 0M2 8.8a15 15 0 0 1 4.2-2.8M22 8.8A15 15 0 0 0 10.7 5M5 12.9a10 10 0 0 1 5.2-2.7M19 12.9a10 10 0 0 0-2.4-1.6M12 20h.01"/>',
wa:'<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22z"/><path d="M9 9.2c.2 2.6 3 5.4 5.8 5.8l1.2-1.4-1.9-1-.9.7c-.9-.4-1.6-1.1-2-2l.7-.9-1-1.9z"/>',
pie:'<path d="M21.2 15.9A10 10 0 1 1 8 2.8"/><path d="M22 12A10 10 0 0 0 12 2v10z"/>',
send:'<path d="M22 2L11 13M22 2l-7 20-4-9-9-4z"/>',
refresh:'<path d="M3 12a9 9 0 0 1 9-9 9.8 9.8 0 0 1 6.7 2.7L21 8M21 3v5h-5M21 12a9 9 0 0 1-9 9 9.8 9.8 0 0 1-6.7-2.7L3 16M8 16H3v5"/>',
logout:'<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>',
verified:'<circle cx="12" cy="12" r="9.5"/><path d="M8.5 12l2.5 2.5 4.5-5"/>',
upload:'<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12"/>',
sliders:'<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M1 14h6M9 8h6M17 16h6"/>',
arrow:'<path d="M5 12h14M12 5l7 7-7 7"/>',
note:'<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6M8 13h8M8 17h5"/>',
truck:'<path d="M14 18V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v11a1 1 0 0 0 1 1h2M15 18H9M19 18h2a1 1 0 0 0 1-1v-3.6a1 1 0 0 0-.2-.6l-3.5-4.4a1 1 0 0 0-.8-.4H14"/><circle cx="17" cy="18" r="2"/><circle cx="7" cy="18" r="2"/>'
};
const KF='@keyframes atMarqL{from{transform:translateX(0)}to{transform:translateX(-50%)}}@keyframes atMarqR{from{transform:translateX(-50%)}to{transform:translateX(0)}}@keyframes atSpin{to{transform:rotate(360deg)}}';const kf=()=>{};
class Base extends HTMLElement{get _r(){return this.shadowRoot||this.attachShadow({mode:'open'})}connectedCallback(){this.render()}attributeChangedCallback(){if(this.isConnected)this.render()}a(n,d){const v=this.getAttribute(n);return v==null?d:v}}
const H=(css)=>'<style>:host{'+css+'}'+KF+'</style>';
class Icon extends Base{static get observedAttributes(){return['name','size','color','sw']}
render(){const s=this.a('size','20'),c=this.a('color','currentColor'),w=this.a('sw','2');
this._r.innerHTML=H(`display:inline-flex;flex:none;width:${s}px;height:${s}px`)+`<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="${c}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${I[this.a('name','plus')]||''}</svg>`;}}
class Marquee extends Base{static get observedAttributes(){return['text','bg','fg','dir','speed','size','rot']}
render(){const t=this.a('text','FRESH FROM ATAS • GROUP UP • SAVE ON ONGKIR • '),bg=this.a('bg',COCOA),fg=this.a('fg','#FBF3EA'),d=this.a('dir','l')==='r'?'R':'L',sp=this.a('speed','28'),fs=this.a('size','15'),rot=this.a('rot','');
const run=`<span style="padding-right:.5em;white-space:nowrap">${(t+' ').repeat(6)}</span>`;
this._r.innerHTML=H('display:block')+`<div style="overflow:hidden;background:${bg};color:${fg};${rot?'transform:rotate('+rot+'deg);margin:0 -12px':''}"><div style="display:flex;width:max-content;animation:atMarq${d} ${sp}s linear infinite;font:700 ${fs}px/1 Roundo,'Manrope',sans-serif;letter-spacing:.04em;text-transform:uppercase;padding:${Math.round(fs*0.7)}px 0">${run}${run}</div></div>`;}}
class Spin extends Base{static get observedAttributes(){return['size','color','speed']}
render(){const s=this.a('size','200'),c=this.a('color','#9D5C1D');
this._r.innerHTML=H(`display:block;width:${s}px;height:${s}px`)+`<svg width="${s}" height="${s}" viewBox="0 0 100 100" style="display:block;animation:atSpin ${this.a('speed','14')}s linear infinite"><circle cx="50" cy="50" r="49" fill="none" stroke="${c}" stroke-width="${120/s}" stroke-dasharray="3 3"/></svg>`;}}
class Status extends Base{static get observedAttributes(){return['dark','time']}
render(){const c=this.hasAttribute('dark')?'#fff':COCOA;
this._r.innerHTML=H(`display:flex;align-items:center;justify-content:space-between;height:54px;padding:4px 34px 0 50px;box-sizing:border-box;color:${c};width:402px;max-width:100%`)+`<span style="font:600 17px/1 -apple-system,'SF Pro Text',system-ui,sans-serif;letter-spacing:-.01em;white-space:nowrap">${this.a('time','9:41')}</span><span style="display:flex;gap:6px;align-items:center"><svg width="18" height="12" viewBox="0 0 18 12" fill="${c}"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg><svg width="16" height="12" viewBox="0 0 16 12" fill="${c}"><path d="M8 2.6c2.2 0 4.2.8 5.7 2.2l1.2-1.2C13.1 1.9 10.7 1 8 1S2.9 1.9 1.1 3.6l1.2 1.2C3.8 3.4 5.8 2.6 8 2.6zm0 3.2c1.3 0 2.5.5 3.4 1.3l1.2-1.2A6.6 6.6 0 0 0 8 4.2c-1.8 0-3.4.7-4.6 1.7l1.2 1.2c.9-.8 2.1-1.3 3.4-1.3zM8 9l-2 2 2 1 2-1z"/></svg><svg width="27" height="13" viewBox="0 0 27 13"><rect x=".5" y=".5" width="23" height="12" rx="3.8" fill="none" stroke="${c}" opacity=".4"/><rect x="2" y="2" width="20" height="9" rx="2.5" fill="${c}"/><path d="M25 4.5v4a2 2 0 0 0 0-4z" fill="${c}" opacity=".4"/></svg></span>`;}}
class Homebar extends Base{static get observedAttributes(){return['dark']}
render(){this._r.innerHTML=H('display:flex;justify-content:center;align-items:flex-end;height:34px;padding-bottom:8px;box-sizing:border-box;width:100%;pointer-events:none')+`<span style="width:140px;height:5px;border-radius:3px;background:${this.hasAttribute('dark')?'#fff':COCOA}"></span>`;}}
class QR extends Base{static get observedAttributes(){return['size','seed','color']}
render(){const s=+this.a('size','180'),c=this.a('color',COCOA),n=25,u=s/n;let seed=+this.a('seed','7');const r=()=>{seed=(seed*9301+49297)%233280;return seed/233280};
const inF=(x,y)=>[[0,0],[n-7,0],[0,n-7]].some(([a,b])=>x>=a-1&&x<a+8&&y>=b-1&&y<b+8);let p='';
for(let y=0;y<n;y++)for(let x=0;x<n;x++){if(inF(x,y))continue;if(r()>.52)p+=`<rect x="${x*u}" y="${y*u}" width="${u}" height="${u}" rx="${u*.3}"/>`;}
const f=(a,b)=>`<rect x="${a*u+u/2}" y="${b*u+u/2}" width="${6*u}" height="${6*u}" rx="${u*1.6}" fill="none" stroke="${c}" stroke-width="${u}"/><rect x="${(a+2)*u}" y="${(b+2)*u}" width="${3*u}" height="${3*u}" rx="${u*.8}"/>`;
this._r.innerHTML=H(`display:block;width:${s}px;height:${s}px`)+`<svg width="${s}" height="${s}" viewBox="0 0 ${s} ${s}" fill="${c}">${p}${f(0,0)}${f(n-7,0)}${f(0,n-7)}</svg>`;}}
const def=(n,c)=>{if(!customElements.get(n))customElements.define(n,c)};
def('at-icon',Icon);def('at-marquee',Marquee);def('at-spin',Spin);def('at-status',Status);def('at-homebar',Homebar);def('at-qr',QR);
const GL='background:rgba(251,243,234,.62);backdrop-filter:blur(18px) saturate(1.8);-webkit-backdrop-filter:blur(18px) saturate(1.8);box-shadow:inset 0 1px 0 rgba(255,255,255,.9),inset 0 0 0 1px rgba(255,255,255,.5),0 8px 24px rgba(43,26,18,.13);';
const GLD='background:rgba(43,26,18,.45);backdrop-filter:blur(18px) saturate(1.6);-webkit-backdrop-filter:blur(18px) saturate(1.6);box-shadow:inset 0 1px 0 rgba(255,255,255,.25),inset 0 0 0 1px rgba(255,255,255,.12),0 8px 24px rgba(0,0,0,.2);';
class Glass extends Base{static get observedAttributes(){return['dark','radius']}
render(){this._r.innerHTML=H((this.hasAttribute('dark')?GLD:GL)+'display:block;border-radius:'+this.a('radius','999')+'px')+'<slot></slot>';}}
class Nav extends Base{static get observedAttributes(){return['title','back','right','dark','close']}
render(){const dk=this.hasAttribute('dark'),c=dk?'#FBF3EA':COCOA,g=dk?GLD:GL;const r=this.a('right','').split(',').filter(Boolean);
const btn=(n)=>'<span style="display:flex;align-items:center;justify-content:center;width:44px;height:44px"><at-icon name="'+n+'" size="22" sw="2.2" color="'+c+'"></at-icon></span>';
const left=this.hasAttribute('back')?'<span style="'+g+'width:44px;height:44px;border-radius:50%;display:flex;align-items:center;justify-content:center"><at-icon name="'+(this.hasAttribute('close')?'x':'chev-l')+'" size="22" sw="2.4" color="'+c+'"></at-icon></span>':'<span style="width:44px"></span>';
const right=r.length?'<span style="'+g+'height:44px;border-radius:22px;display:flex;align-items:center;padding:0 '+(r.length>1?4:0)+'px">'+r.map(btn).join('')+'</span>':'<span style="width:44px"></span>';
this._r.innerHTML=H('display:flex;align-items:center;justify-content:space-between;height:52px;padding:0 16px;box-sizing:border-box;width:100%;gap:8px')+left+'<span style="flex:1;min-width:0;text-align:center;font:600 17px/1.2 Manrope,sans-serif;color:'+c+';white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'+this.a('title','')+'</span>'+right;}}
class Tabbar extends Base{static get observedAttributes(){return['active','fab']}
render(){const act=this.a('active','home');const t=[['home','Home','home'],['history','History','history'],['profile','Profile','user']];
const items=t.map(([k,l,i])=>'<span style="flex:1;display:flex;flex-direction:column;align-items:center;gap:3px;padding:7px 0;border-radius:999px;'+(k===act?'background:rgba(157,92,29,.14);color:#9D5C1D':'color:'+COCOA)+'"><at-icon name="'+i+'" size="22"></at-icon><span style="font:600 10px Manrope,sans-serif">'+l+'</span></span>').join('');
const fab=this.a('fab','');
this._r.innerHTML=H('display:flex;align-items:center;gap:10px;width:100%;box-sizing:border-box;padding:0 16px')+'<span style="'+GL+'flex:1;display:flex;padding:6px;border-radius:999px">'+items+'</span>'+(fab?'<span style="'+GL+'width:62px;height:62px;border-radius:50%;display:flex;align-items:center;justify-content:center;flex:none"><at-icon name="'+fab+'" size="24"></at-icon></span>':'');}}
const TAGS={open:['Open','#E9FF83',COCOA,'#5E7A00'],locked:['Locked','#EDE2E4',COCOA,COCOA],edits:['Edits requested','#F9B7D2',COCOA,'#B0005A'],sent:['Sent to Atas','#F9CFAF',COCOA,'#9D5C1D'],confirmed:['Confirmed by Atas','#9D5C1D','#FBF3EA','#F9CFAF'],delivered:['Delivered',COCOA,'#E9FF83','#E9FF83'],closed:['Closed','#fff','#7A6257','#D1B6BB'],cancelled:['Cancelled','#FDE3E5','#B00010','#E40014'],
unpaid:['Unpaid','#fff',COCOA,'','inset 0 0 0 1.5px #D1B6BB'],says:['Says paid','#F9CFAF',COCOA,''],paid:['Paid','#E9FF83',COCOA,'','inset 0 0 0 1.5px #BCD947'],soldout:['Sold out','#EDE2E4',COCOA,''],promo:['Promo 15%','#F9B7D2',COCOA,''],new:['New','#E9FF83',COCOA,''],best:['Best seller','#F9CFAF',COCOA,''],host:['Host',COCOA,'#FBF3EA',''],pending:['Pending','#F9CFAF',COCOA,''],declined:['Declined','#FDE3E5','#B00010',''],accepted:['Accepted','#E9FF83',COCOA,'','inset 0 0 0 1.5px #BCD947'],final:['Final','#E9FF83',COCOA,'','inset 0 0 0 1.5px #BCD947'],notfinal:['Not final yet','#EDE2E4',COCOA,'']};
class Tag extends Base{static get observedAttributes(){return['kind','text','size']}
render(){if(this.a('kind','')==='none'){this._r.innerHTML='';return;}const k=TAGS[this.a('kind','open')]||TAGS.open;const sm=this.a('size','')==='s';const lbl=this.a('text',k[0]);
this._r.innerHTML=H('display:inline-flex;flex:none')+'<span style="display:inline-flex;align-items:center;gap:6px;white-space:nowrap;padding:'+(sm?'2px 10px':'4px 14px')+(k[3]?';padding-left:'+(sm?8:10)+'px':'')+';border-radius:999px;background:'+k[1]+';color:'+k[2]+';box-shadow:'+(k[4]||'none')+';font:600 '+(sm?10:11)+'px/1.4 Manrope,sans-serif;letter-spacing:.03em;text-transform:uppercase">'+(k[3]?'<span style="width:7px;height:7px;border-radius:50%;background:'+k[3]+'"></span>':'')+(this.a('kind')==='paid'||this.a('kind')==='accepted'?'<at-icon name="check" size="11" sw="3"></at-icon>':'')+lbl+'</span>';}}
const AV={R:'#F39E60',D:'#F9B7D2',P:'#E9FF83',K:'#F9CFAF',N:'#EDE2E4',A:'#D1B6BB'};
const ART={};
[['neutral','#F9CFAF'],['waving','#F9B7D2'],['cakebox','#F9CFAF'],['waiting','#EDE2E4'],['celebrating','#E9FF83'],['confused','#F9B7D2'],['sleeping','#EDE2E4'],['delivery','#F9CFAF'],['phone','#E9FF83'],['splitting','#F9B7D2']].forEach(([k,bg])=>{ART['pose-'+k]={src:'uploads/art/pose-'+k+'.png',bg};});
[['croissant',716,1113,.42,.3,.8],['creation',1140,735,.5,.5,.42],['brioche',900,1117,.52,.3,.7],['monalisa',900,1117,.52,.26,.62],['scream',900,1117,.52,.3,.64],['gothic',900,1117,.5,.3,1],['sonofbun',900,1117,.5,.28,.62],['vangogh',900,1117,.47,.28,.62],['supper',1400,781,.5,.4,.45]].forEach(([k,w,h,cx,cy,cw])=>{ART['paint-'+k]={src:'uploads/art/paint-'+k+'.png',w,h,cx,cy,cw};});
const AVART={R:{art:'pose-waving',bg:'#F39E60'},P:{art:'pose-cakebox',bg:'#E9FF83'},D:{art:'paint-vangogh'},K:{art:'paint-sonofbun'}};
function artBg(key,s,cb){const a=ART[key];if(!a)return null;if(!a.w)return "url('"+a.src+"') center bottom/cover no-repeat,"+(cb||a.bg);
const bw=s/a.cw,bh=bw*a.h/a.w;let x=s/2-a.cx*bw,y=s/2-a.cy*bh;x=Math.min(0,Math.max(s-bw,x));y=Math.min(0,Math.max(s-bh,y));
return "url('"+a.src+"') "+x.toFixed(1)+'px '+y.toFixed(1)+'px/'+bw.toFixed(1)+'px '+bh.toFixed(1)+"px no-repeat,#2B1A12";}
class Avatar extends Base{static get observedAttributes(){return['i','size','host','ring','art','bg']}
render(){const i=this.a('i',''),s=+this.a('size','40');const ring=this.a('ring','');const d=AVART[i]||{};const ak=this.a('art',d.art||'');const cb=this.a('bg',d.bg||'');const bg=ak&&ak!=='none'?artBg(ak,s,cb):null;const base=cb||AV[i]||'#EDE2E4';const ink=base==='#9D5C1D'?'#FBF3EA':COCOA;
this._r.innerHTML=H('display:inline-flex;flex:none;position:relative;width:'+s+'px;height:'+s+'px')+'<span style="width:'+s+'px;height:'+s+'px;border-radius:50%;background:'+(bg||base)+';display:flex;align-items:center;justify-content:center;font:700 '+Math.round(s*.4)+'px/1 Roundo,sans-serif;color:'+ink+';box-sizing:border-box;'+(ring?'border:'+Math.max(2,s/14)+'px solid '+ring:'')+'">'+(bg?'':i)+'</span>'+(this.hasAttribute('host')?'<span style="position:absolute;right:-6px;bottom:-4px;padding:1px 5px;border-radius:999px;background:'+COCOA+';color:#FBF3EA;font:700 8px/1.5 Manrope,sans-serif;letter-spacing:.04em;border:2px solid #fff">HOST</span>':'');}}
class Photo extends Base{static get observedAttributes(){return['size','bg','label','ring']}
render(){const s=+this.a('size','140'),bg=this.a('bg','#F9CFAF'),l=this.a('label','product photo');const pad=Math.max(4,Math.round(s*.055));
this._r.innerHTML=H('display:block;position:relative;flex:none;width:'+s+'px;height:'+s+'px')+(this.a('ring','1')!=='0'?'<span style="position:absolute;inset:0;border-radius:50%;border:1.5px dashed rgba(157,92,29,.6)"></span>':'')+'<span style="position:absolute;inset:'+pad+'px;border-radius:50%;background:'+bg+';overflow:hidden;display:flex;align-items:center;justify-content:center;text-align:center"><span style="position:absolute;inset:0;background:repeating-linear-gradient(135deg,rgba(43,26,18,.07) 0 6px,transparent 6px 12px)"></span>'+(s>=64?'<span style="position:relative;font:500 '+(s>110?10:8)+'px/1.3 ui-monospace,Menlo,monospace;color:#7A6257;padding:0 10px">'+l+'</span>':'')+'</span>';}}
class Keypad extends Base{render(){const k=[['1',''],['2','ABC'],['3','DEF'],['4','GHI'],['5','JKL'],['6','MNO'],['7','PQRS'],['8','TUV'],['9','WXYZ'],['',''],['0',''],['del','']];
this._r.innerHTML=H('display:block;width:100%')+'<div style="background:rgba(214,206,200,.75);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);padding:8px 6px 42px;display:grid;grid-template-columns:repeat(3,1fr);gap:7px;border-radius:28px 28px 0 0">'+k.map(([n,l])=>n===''?'<span></span>':n==='del'?'<span style="display:flex;align-items:center;justify-content:center;height:46px"><at-icon name="chev-l" size="24"></at-icon></span>':'<span style="height:46px;border-radius:8px;background:#fff;box-shadow:0 1px 0 rgba(0,0,0,.25);display:flex;flex-direction:column;align-items:center;justify-content:center;font:400 25px/1 -apple-system,system-ui,sans-serif;color:#000">'+n+(l?'<span style="font:600 9px/1 -apple-system,system-ui;letter-spacing:.12em;margin-top:1px">'+l+'</span>':'')+'</span>').join('')+'</div>';}}
const def2=(n,c)=>{if(!customElements.get(n))customElements.define(n,c)};
def2('at-glass',Glass);def2('at-nav',Nav);def2('at-tabbar',Tabbar);def2('at-tag',Tag);def2('at-avatar',Avatar);def2('at-photo',Photo);def2('at-keypad',Keypad);

})();
