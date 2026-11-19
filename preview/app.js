'use strict';
const $=s=>document.querySelector(s),esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const clone=x=>JSON.parse(JSON.stringify(x));
const META={resistor:{name:'Resistor',sub:'Limit & divide current',unit:'Ω',prefix:'R',value:1000},voltage:{name:'Voltage source',sub:'A little potential',unit:'V',prefix:'V',value:12},current:{name:'Current source',sub:'Keep the current flowing',unit:'A',prefix:'I',value:.001},capacitor:{name:'Capacitor',sub:'Store a little energy',unit:'F',prefix:'C',value:.00001},ground:{name:'Ground',sub:'Your zero-volt reference',unit:'',prefix:'G',value:0}};
let project=clone(SC_EXAMPLES.divider),selected='R2',selectedWire=-1,mode='select',wireStart=null,undo=[],redo=[],result=null,transient=null,dirty=true,zoom=1,view={x:window.innerWidth<=640?140:0,y:0},native=false,apiToken='',drag=null,space=false,busy=false,toastTimer;
function fmt(v,unit='',digits=3){
 if(!Number.isFinite(v))return '—';
 if(Math.abs(v)<1e-15)v=0;
 const a=Math.abs(v);let factor=1,p='';
 for(const [n,s]of [[1e12,'T'],[1e9,'G'],[1e6,'M'],[1e3,'k'],[1,''],[1e-3,'m'],[1e-6,'µ'],[1e-9,'n'],[1e-12,'p']])if(a>=n||n===1e-12){factor=n;p=s;break;}
 if(v===0){factor=1;p='';}
 return Number((v/factor).toPrecision(digits))+' '+p+unit;
}
function parseValue(raw){
 const m=String(raw).trim().match(/^([+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)\s*([TGMkmunpµu]?)(?:Ω|ohm|V|A|F)?$/i);
 if(!m)throw Error('Use a number or an SI value such as 4.7k, 10µ, or 0.001.');
 const factors={T:1e12,G:1e9,M:1e6,k:1e3,m:1e-3,u:1e-6,'µ':1e-6,n:1e-9,p:1e-12,'':1};
 const factor=factors[m[2]];if(factor===undefined)throw Error('SI prefixes are case-sensitive: M = mega, m = milli.');
 const value=Number(m[1])*factor;if(!Number.isFinite(value))throw Error('Enter a finite value.');return value;
}
function notify(text){$('#toast').textContent=text;$('#toast').classList.add('show');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('#toast').classList.remove('show'),3200);}
function snapshot(){undo.push(clone(project));if(undo.length>60)undo.shift();redo=[];}
function changed(){dirty=true;result=null;transient=null;render();renderResults();$('#canvas-status').textContent='Ready to simulate';}
function pin(c,k){if(c.type==='ground')return {x:c.x,y:c.y};let a=(c.rotation||0)*Math.PI/180,d=k?48:-48;return{x:c.x+Math.round(Math.cos(a)*d),y:c.y+Math.round(Math.sin(a)*d)};}
function terminal(name){let [id,k]=name.split(':'),c=project.components.find(x=>x.id===id);return c?pin(c,Number(k)):null;}
function pathFor(w){const a=terminal(w.from),b=terminal(w.to);if(!a||!b)return '';let c=project.components.find(c=>c.id===w.from.split(':')[0]),vertical=c.type==='ground'||(c.rotation||0)%180===90;return 'M'+a.x+' '+a.y+(vertical?'V'+b.y+'H'+b.x:'H'+b.x+'V'+b.y);}
function symbol(type,color='#d9e4d2'){
 const common='fill="none" stroke="'+color+'" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"';
 const shape={resistor:'<path d="M-48 0H-26l6-12 8 24 8-24 8 24 8-24 8 12h28"/>',voltage:'<path d="M-48 0h24m48 0h24"/><circle r="24"/><path d="M-8-13v10m-5-5h10m0 18h10"/>',current:'<path d="M-48 0h24m48 0h24"/><circle r="24"/><path d="M-13 0h26m-8-7 8 7-8 7"/>',capacitor:'<path d="M-48 0h42m12 0h42M-6-23v46m12-46v46"/>',ground:'<path d="M0 0v18m-20 0h40m-33 9h26m-19 9h12"/>'}[type];
 return '<g '+common+'>'+shape+'</g>';
}
function draw(){
 const scene=$('#scene');scene.innerHTML=project.wires.map((w,i)=>'<g class="wire-shape" data-wire="'+i+'"><path class="wire-hit" d="'+pathFor(w)+'"/><path d="'+pathFor(w)+'" fill="none" stroke="'+(i===selectedWire?'#f3c09b':result?'#a5caa0':'#829b78')+'" stroke-width="2.1" stroke-linejoin="round"/></g>').join('')+
 project.components.map(c=>{
  const active=c.id===selected,vertical=(c.rotation||0)%180===90,color=active?'#f3b383':'#dae4d4',count=c.type==='ground'?1:2;
  const lx=vertical?43:0,ly=vertical?-6:-42;
  const reading=result?.components.find(x=>x.id===c.id);
  return '<g class="component-shape" data-component="'+esc(c.id)+'">'+(active?'<rect class="selected-halo" x="'+(c.x-(vertical?33:62))+'" y="'+(c.y-(vertical?62:33))+'" width="'+(vertical?66:124)+'" height="'+(vertical?124:66)+'"/>':'')+
  '<g transform="translate('+c.x+' '+c.y+') rotate('+(c.rotation||0)+')">'+symbol(c.type,color)+'</g>'+
  '<text x="'+(c.x+lx)+'" y="'+(c.y+ly)+'" text-anchor="'+(vertical?'start':'middle')+'" fill="'+color+'" font-family="Consolas,monospace" font-size="13">'+esc(c.label)+'</text>'+
  (c.type!=='ground'?'<text x="'+(c.x+lx)+'" y="'+(c.y+ly+19)+'" text-anchor="'+(vertical?'start':'middle')+'" fill="#819477" font-family="Consolas,monospace" font-size="11">'+esc(fmt(c.value,META[c.type].unit))+'</text>':'')+
  (reading?'<text x="'+(c.x+(vertical?43:0))+'" y="'+(c.y+(vertical?36:53))+'" text-anchor="'+(vertical?'start':'middle')+'" fill="#eab18a" font-family="Consolas,monospace" font-size="11">'+esc(fmt(reading.voltage,'V'))+'</text>':'')+
  Array.from({length:count},(_,k)=>{const p=pin(c,k),t=c.id+':'+k;return '<circle class="pin" data-terminal="'+t+'" cx="'+p.x+'" cy="'+p.y+'" r="5" fill="'+(wireStart===t?'#eea171':'#162019')+'" stroke="'+(wireStart===t?'#eea171':'#9db390')+'" stroke-width="1.7"><title>'+esc(c.label)+(k===0?' + / terminal 1':' − / terminal 2')+(result?' · '+fmt(result.nodeVoltages[t],'V'):'')+'</title></circle>';}).join('')+'</g>';
 }).join('');
 if(wireStart){const p=terminal(wireStart);scene.innerHTML+='<circle cx="'+p.x+'" cy="'+p.y+'" r="10" fill="none" stroke="#eea171" stroke-width="1" stroke-dasharray="3 3"/>';}
 $('#schematic').setAttribute('viewBox',view.x+' '+view.y+' '+(window.innerWidth<=640?640:960)/zoom+' '+620/zoom);
}
function renderPalette(){
 const q=$('#component-search').value.toLowerCase();
 $('#component-list').innerHTML=Object.entries(META).filter(([_,m])=>m.name.toLowerCase().includes(q)).map(([type,m])=>'<button class="component-card" data-add="'+type+'"><img src="../assets/symbols/'+type+'.svg" alt=""><span><strong>'+m.name+'</strong><small>'+m.sub+'</small></span><span>＋</span></button>').join('')||'<p class="count-empty">No matching components.</p>';
}
function renderInspector(){
 const el=$('#inspector-content'),c=project.components.find(c=>c.id===selected);
 if(!c){el.innerHTML='<div class="no-selection"><span class="eyebrow">ROOM TO EXPERIMENT</span><h3>What will you build?</h3><p>Choose a component from the palette. Connect its terminals, add a ground, and bring your idea to life.</p>'+(selectedWire>=0?'<button class="button" data-action="delete">Delete selected wire</button>':'')+'</div>';return;}
 const m=META[c.type];el.innerHTML='<div class="selection-hero"><img src="../assets/symbols/'+c.type+'.svg" alt=""><div><h3>'+esc(m.name)+'</h3><p>'+esc(c.label)+' · '+(c.type==='ground'?'Reference node':'2 terminals')+'</p></div></div>'+
 '<label class="field"><span>REFERENCE LABEL</span><input id="edit-label" value="'+esc(c.label)+'" maxlength="24"></label>'+
 (c.type!=='ground'?'<label class="field"><span>'+({resistor:'RESISTANCE',voltage:'VOLTAGE',current:'CURRENT',capacitor:'CAPACITANCE'}[c.type])+'</span><input id="edit-value" value="'+esc(fmt(c.value,m.unit,8).replace(' ',''))+'" spellcheck="false"><small>SI prefixes: k, M, m, µ, n, p</small></label>':'')+
 '<div class="inspector-sub">CONNECTIONS</div>'+Array.from({length:c.type==='ground'?1:2},(_,k)=>{let n=project.wires.filter(w=>[w.from,w.to].includes(c.id+':'+k)).length;return '<div class="connection"><i></i><span>'+ (c.type==='ground'?'Ground':'Terminal '+(k+1))+'</span><small>'+n+' wire'+(n===1?'':'s')+'</small></div>';}).join('')+
 '<div class="inspector-actions"><button class="button" data-action="rotate">⟳ Rotate</button><button class="button" data-action="duplicate">＋ Duplicate</button></div><button class="delete-action" data-action="delete">⌫ Delete component</button>';
 $('#edit-label').addEventListener('change',e=>{let label=e.target.value.trim();if(!label){notify('Give the component a label.');renderInspector();return;}snapshot();c.label=label;changed();});
 $('#edit-value')?.addEventListener('change',e=>{try{const v=parseValue(e.target.value);const candidate=clone(project);candidate.components.find(x=>x.id===c.id).value=v;const tmp=clone(candidate);if(!tmp.components.some(x=>x.type==='ground'))tmp.components.push({id:'temp_ground',type:'ground',label:'GND',value:0});ShortCircuitSolver.topology(tmp);snapshot();c.value=v;changed();}catch(err){notify(err.message);renderInspector();}});
}
function render(){
 $('#project-title').textContent=project.title;$('#project-description').textContent=project.description||'A little curiosity. A complete circuit.';$('#tab-name').textContent=project.title;
 $('#save-status').textContent=dirty?'Unsaved changes':'Saved on this device';$('#dirty-dot').style.visibility=dirty?'visible':'hidden';
 $('#circuit-count').textContent=project.components.length+' components · '+project.wires.length+' wires';$('#undo-tool').disabled=!undo.length;$('#redo-tool').disabled=!redo.length;
 $('#select-tool').classList.toggle('active',mode==='select');$('#wire-tool').classList.toggle('active',mode==='wire');
 $('#canvas-hint').textContent=wireStart?'Select another terminal to connect · Esc to cancel':mode==='wire'?'Click two terminals to connect them':'Click to inspect · Drag to move · Space + drag to pan';
 draw();renderInspector();
}
function chartSvg(){
 let width=360,height=125,top=10,bottom=103,left=33,right=350;
 if(transient){
  const cap=project.components.find(c=>c.type==='capacitor'),samples=transient.samples,values=samples.map(s=>s.components.find(c=>c.id===cap.id).voltage),max=Math.max(1,...values.map(Math.abs))*1.1,min=Math.min(0,...values)*1.1,range=max-min;
  const y=v=>bottom-(v-min)/range*(bottom-top),points=values.map((v,i)=>(left+i/(values.length-1)*(right-left))+','+y(v)).join(' ');
  let lines=[0,.5,1].map(f=>{let yy=top+f*(bottom-top),v=max-f*range;return '<path d="M'+left+' '+yy+'H'+right+'" stroke="#34482f" stroke-dasharray="3 4"/><text x="0" y="'+(yy+3)+'" fill="#829a76">'+Number(v.toPrecision(2))+' V</text>';}).join('');
  return '<div class="chart-title">'+esc(cap.label)+' charging curve <span>0 V INITIAL</span></div><svg viewBox="0 0 360 125">'+lines+'<path d="M'+left+' '+y(0)+'H'+right+'" stroke="#4a6040"/><polyline points="'+points+'" fill="none" stroke="#eea171" stroke-width="2"/><text x="'+left+'" y="122" fill="#829a76">0 ms</text><text x="315" y="122" fill="#829a76">'+Number((transient.duration*1000).toPrecision(3))+' ms</text></svg><div class="chart-footnote">Backward Euler · 200 steps · DC source applied at t = 0</div>';
 }
 let nets=result.nets,max=Math.max(1,...nets.map(n=>Math.abs(n.voltage)))*1.15,min=Math.min(0,...nets.map(n=>n.voltage))*1.15,range=max-min,y=v=>bottom-(v-min)/range*(bottom-top);
 return '<div class="chart-title">Node potentials <span>RELATIVE TO GROUND</span></div><svg viewBox="0 0 360 125">'+[0,.5,1].map(f=>'<path d="M33 '+(10+f*93)+'H350" stroke="#34482f" stroke-dasharray="3 4"/><text x="0" y="'+(13+f*93)+'" fill="#829a76">'+Number((max-f*range).toPrecision(2))+' V</text>').join('')+nets.slice(0,12).map((n,i)=>{let w=290/Math.min(12,nets.length),x=left+i*w+w*.25,yy=y(n.voltage),zero=y(0);return '<rect x="'+x+'" y="'+Math.min(yy,zero)+'" width="'+w*.5+'" height="'+Math.max(1,Math.abs(zero-yy))+'" rx="3" fill="'+(i%2?'#93b98a':'#eea171')+'"/><text x="'+(x+w*.25)+'" y="121" text-anchor="middle" fill="#829a76">'+esc(n.name)+'</text>';}).join('')+'</svg><div class="chart-footnote">DC operating point · ground reference = 0 V</div>';
}
function renderResults(error){
 const el=$('#results-content');
 if(error){el.className='';el.innerHTML='<div class="error-box"><strong>Check your circuit</strong><br><br>'+esc(error)+'</div>';$('#result-state').textContent='Needs attention';return;}
 if(!result){el.className='results-empty';el.innerHTML='<span class="empty-orbit">ϟ</span><div><h3>Your next discovery is one click away.</h3><p>Build a circuit, choose an analysis, and hit Run simulation.</p></div><button class="button primary" data-action="run">▶ Run simulation</button>';$('#result-state').textContent='Awaiting run';return;}
 $('#result-state').textContent=transient?'Transient complete':'Converged';
 const source=result.components.find(c=>project.components.find(x=>x.id===c.id)?.type==='voltage');
 el.className='result-grid';el.innerHTML='<div class="metrics"><div class="metric"><span class="metric-label">'+(transient?'FINAL SOURCE CURRENT':'SOURCE CURRENT')+'</span><div class="metric-value">'+fmt(Math.abs(source?.current??0),'A')+'</div><small>Magnitude · '+esc(source?.label||'no voltage source')+'</small></div><div class="metric"><span class="metric-label">RESISTOR POWER</span><div class="metric-value">'+fmt(result.dissipatedPower,'W')+'</div><small>Sum across all resistors</small></div></div><div><table class="result-table"><thead><tr><th>REF</th><th>VOLTAGE</th><th>CURRENT</th><th>POWER</th></tr></thead><tbody>'+result.components.map(c=>'<tr><td>'+esc(c.label)+'</td><td>'+fmt(c.voltage,'V')+'</td><td>'+fmt(c.current,'A')+'</td><td>'+fmt(c.power,'W')+'</td></tr>').join('')+'</tbody></table><div class="chart-footnote">Positive current flows terminal 1 → 2. Negative power = supplied.</div></div><div class="chart">'+chartSvg()+'</div>';
}
async function request(r){
 if(native){const response=await fetch('/api/request',{method:'POST',headers:{'Content-Type':'application/json','X-SC-Token':apiToken},body:JSON.stringify(r)});const out=await response.json();if(!out.ok)throw Error(out.error);return out;}
 return ShortCircuitSolver.execute(r);
}
async function run(){
 if(busy)return;busy=true;$('#canvas-status').textContent='Solving…';
 try{const op=$('#analysis-mode').value,duration=Number($('#duration').value)/1000;const response=await request({op,project,duration,steps:200});transient=op==='transient'?response.result:null;result=transient?transient.samples.at(-1):response.result;$('#canvas-status').textContent=transient?'Transient complete':'Operating point solved';render();renderResults();}
 catch(e){result=null;transient=null;draw();renderResults(e.message);$('#canvas-status').textContent='Circuit needs attention';notify(e.message);}
 finally{busy=false;}
}
function add(type){
 if(project.components.length>=128){notify('This workspace supports 128 components.');return;}
 snapshot();mode='select';wireStart=null;const m=META[type];let i=1;while(project.components.some(c=>c.id===m.prefix+i))i++;
 let c={id:m.prefix+i,label:type==='ground'?'GND':m.prefix+i,type,value:m.value,x:480+((project.components.length%4)-1)*24,y:300+((project.components.length%3)-1)*24,rotation:type==='voltage'||type==='current'?90:0};project.components.push(c);selected=c.id;selectedWire=-1;changed();$('.inspector').classList.add('mobile-open');notify(m.name+' added. Drag it into place.');
}
function remove(){if(!selected&&selectedWire<0)return;snapshot();if(selected){project.components=project.components.filter(c=>c.id!==selected);project.wires=project.wires.filter(w=>![w.from,w.to].some(t=>t.split(':')[0]===selected));}else project.wires.splice(selectedWire,1);selected=null;selectedWire=-1;wireStart=null;changed();}
function loadExample(key){snapshot();mode='select';project=clone(SC_EXAMPLES[key]);selected=project.components.find(c=>c.type==='resistor')?.id;selectedWire=-1;wireStart=null;zoom=1;view={x:0,y:0};$('#analysis-mode').value=key==='rc'?'transient':'simulate';$('#duration-label').hidden=key!=='rc';changed();$('#modal').close();notify('Example loaded. Make it your own.');}
function modal(title,content){$('#modal-title').textContent=title;$('#modal-content').innerHTML=content;$('#modal').showModal();}
function examples(){modal('A good place to start',Object.entries(SC_EXAMPLES).map(([k,p],i)=>'<button class="example-card" data-example="'+k+'"><span>0'+(i+1)+'</span><div><h3>'+esc(p.title)+'</h3><p>'+esc(p.description)+'</p></div></button>').join(''));}
function download(name,content,type='application/json'){const url=URL.createObjectURL(new Blob([content],{type})),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
function savedLocal(){try{return JSON.parse(localStorage.getItem('short-circuit-projects')||'{}');}catch{return {};}}
async function saveNamed(){
 const title=$('#project-name').value.trim();if(!title){notify('Enter a project name.');return;}
 snapshot();project.title=title;dirty=true;if(!project.id.startsWith('p-'))project.id='p-'+Date.now().toString(36);
 try{if(native)await request({op:'save',project});else{const saved=savedLocal();saved[project.id]=clone(project);localStorage.setItem('short-circuit-projects',JSON.stringify(saved));}dirty=false;render();$('#modal').close();notify('Project saved on this device.');}
 catch(e){notify('Save failed: '+e.message);}
}
async function projects(){
 try{
 const items=native?(await request({op:'list'})).projects:Object.values(savedLocal()).map(p=>({id:p.id,title:p.title}));
 modal('Your circuit shelf','<div class="saved-list">'+(items.length?items.map(p=>'<button data-load="'+esc(p.id)+'">'+esc(p.title)+' <span style="float:right;color:#eea171">↗</span></button>').join(''):'<p class="guide">No saved projects yet. Build something and give it a name.</p>')+'</div>');
 }catch(e){notify(e.message);}
}
function changeZoom(delta){let old=zoom;zoom=Math.min(2.5,Math.max(.5,zoom+delta));const half=window.innerWidth<=640?320:480;view.x+=half/old-half/zoom;view.y+=310/old-310/zoom;$('#zoom-value').textContent=Math.round(zoom*100)+'%';draw();}
const actions={
 run,select:()=>{mode='select';wireStart=null;render();},wire:()=>{mode='wire';wireStart=null;render();},
 rotate:()=>{const c=project.components.find(c=>c.id===selected);if(!c||c.type==='ground')return;snapshot();c.rotation=((c.rotation||0)+90)%360;changed();},
 duplicate:()=>{const c=project.components.find(c=>c.id===selected);if(!c)return;const copy=clone(c);add(c.type);const added=project.components.at(-1);Object.assign(added,{...copy,id:added.id,label:added.label,x:Math.min(880,copy.x+72),y:Math.min(540,copy.y+72)});render();},
 delete:remove,undo:()=>{if(!undo.length)return;redo.push(clone(project));project=undo.pop();selected=null;selectedWire=-1;wireStart=null;changed();},redo:()=>{if(!redo.length)return;undo.push(clone(project));project=redo.pop();selected=null;selectedWire=-1;wireStart=null;changed();},
 new:()=>modal('Start a new circuit','<p class="guide">Save or export your current work first if you want to keep it. You can also return to it with Undo.</p><input id="new-title" class="modal-field" placeholder="Name your circuit" value="Untitled circuit" maxlength="80"><div class="modal-tools"><button class="button" data-action="close">Keep working</button><button class="button primary" data-action="create">Create circuit</button></div>'),
 create:()=>{snapshot();project={schema:1,id:'p-'+Date.now().toString(36),title:$('#new-title').value.trim()||'Untitled circuit',components:[],wires:[]};selected=null;selectedWire=-1;wireStart=null;changed();$('#modal').close();},
 save:()=>modal('Give your circuit a home','<label class="guide" for="project-name">Project name</label><input id="project-name" class="modal-field" maxlength="80" value="'+esc(project.title)+'"><div class="modal-tools"><button class="button" data-action="close">Cancel</button><button class="button primary" data-action="saveNamed">Save on this device</button></div>'),
 saveNamed,projects,examples,guide:()=>modal('From idea to current','<div class="guide"><p><strong>01 · Place.</strong> Pick a component from the palette. Drag it into position. Select it to change its label and value.</p><p><strong>02 · Connect.</strong> Click a terminal circle, then another terminal. Connected terminal circles form one electrical node. Crossing wires do not connect automatically.</p><p><strong>03 · Ground.</strong> Add a ground reference and wire it to your return node. Multiple ground symbols share the same 0 V reference.</p><p><strong>04 · Run.</strong> DC finds steady-state voltages and currents. Capacitors are open circuits at DC. RC transient starts capacitors at 0 V and applies constant sources at t = 0.</p><p><strong>Make it yours.</strong> Use 4.7k for 4700 Ω or 10µ for 10 µF. Select a wire and press Delete to remove it. Export JSON to move a project between devices.</p><p><strong>Shortcuts:</strong> V select · W wire · R rotate · Enter run · Ctrl+Z undo · Ctrl+Y redo · Delete remove · Esc cancel · Space + drag pan.</p><p>Diodes, transistors, AC analysis and arbitrary waveforms are outside this first build.</p></div>'),
 close:()=>$('#modal').close(),workshop:()=>window.scrollTo({top:0,behavior:'smooth'}),
 export:()=>download(project.id+'.sc.json',JSON.stringify(project,null,2)),import:()=>$('#file-input').click(),
 csv:()=>{if(!result){notify('Run a simulation first.');return;}let rows=transient?[['Time (s)','Component','Voltage (V)','Current (A)','Power (W)'],...transient.samples.flatMap(s=>s.components.map(c=>[s.time,c.label,c.voltage,c.current,c.power]))]:[['Component','Voltage (V)','Current (A)','Power (W)'],...result.components.map(c=>[c.label,c.voltage,c.current,c.power])];const cell=v=>{let s=String(v);if(typeof v==='string'&&/^[=+\-@\t\r]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"';};download(project.id+'-results.csv',rows.map(r=>r.map(cell).join(',')).join('\r\n'),'text/csv');},
 zoomin:()=>changeZoom(.1),zoomout:()=>changeZoom(-.1),fit:()=>{zoom=1;view={x:0,y:0};$('#zoom-value').textContent='100%';draw();}
};
document.addEventListener('click',async e=>{
 const example=e.target.closest('[data-example]');if(example){loadExample(example.dataset.example);return;}
 const load=e.target.closest('[data-load]');if(load){try{snapshot();project=native?(await request({op:'load',id:load.dataset.load})).project:clone(savedLocal()[load.dataset.load]);selected=null;selectedWire=-1;wireStart=null;changed();dirty=false;render();$('#modal').close();}catch(err){notify(err.message);}return;}
 const addButton=e.target.closest('[data-add]');if(addButton){add(addButton.dataset.add);return;}
 const action=e.target.closest('[data-action]');if(action&&actions[action.dataset.action]){e.preventDefault();await actions[action.dataset.action]();}
});
const svg=$('#schematic');
function point(e){const p=svg.createSVGPoint();p.x=e.clientX;p.y=e.clientY;return p.matrixTransform(svg.getScreenCTM().inverse());}
svg.addEventListener('pointerdown',e=>{
 const p=point(e);
 if(space||e.button===1){drag={pan:true,start:p,origin:{...view}};svg.setPointerCapture(e.pointerId);e.preventDefault();return;}
 const t=e.target.closest('[data-terminal]');
 if(t){
  const terminal=t.dataset.terminal;
  if(wireStart&&wireStart!==terminal){
   if(project.wires.length>=512){notify('Maximum 512 wires.');return;}
   if(!project.wires.some(w=>(w.from===wireStart&&w.to===terminal)||(w.to===wireStart&&w.from===terminal))){snapshot();project.wires.push({from:wireStart,to:terminal});wireStart=null;changed();notify('Connected.');}else{wireStart=null;render();}
  }else{wireStart=terminal;mode='wire';render();}
  e.preventDefault();return;
 }
 const c=e.target.closest('[data-component]');
 if(c){selected=c.dataset.component;selectedWire=-1;const item=project.components.find(x=>x.id===selected);drag=mode==='select'?{id:selected,start:p,x:item.x,y:item.y,before:clone(project),moved:false}:null;if(drag)svg.setPointerCapture(e.pointerId);$('.inspector').classList.add('mobile-open');render();return;}
 const w=e.target.closest('[data-wire]');selected=null;selectedWire=w?Number(w.dataset.wire):-1;if(w)$('.inspector').classList.add('mobile-open');render();
});
svg.addEventListener('pointermove',e=>{
 if(!drag)return;const p=point(e);
 if(drag.pan){view.x=drag.origin.x-(p.x-drag.start.x);view.y=drag.origin.y-(p.y-drag.start.y);draw();return;}
 let c=project.components.find(c=>c.id===drag.id),dx=p.x-drag.start.x,dy=p.y-drag.start.y;
 if(!drag.moved&&Math.hypot(dx,dy)<3)return;drag.moved=true;
 const step=$('#grid').checked?24:1;c.x=Math.max(72,Math.min(864,Math.round((drag.x+dx)/step)*step));c.y=Math.max(72,Math.min(528,Math.round((drag.y+dy)/step)*step));draw();
});
function endDrag(){if(drag?.moved){undo.push(drag.before);if(undo.length>60)undo.shift();redo=[];changed();}drag=null;}
svg.addEventListener('pointerup',endDrag);svg.addEventListener('pointercancel',endDrag);
$('#component-search').addEventListener('input',renderPalette);
$('#analysis-mode').addEventListener('change',()=>{$('#duration-label').hidden=$('#analysis-mode').value!=='transient';result=null;transient=null;draw();renderResults();});
$('#file-input').addEventListener('change',async e=>{
 const f=e.target.files[0];if(!f)return;
 try{if(f.size>2097152)throw Error('Project exceeds 2 MB.');const p=JSON.parse(await f.text());if(p.schema!==1||!Array.isArray(p.components)||!Array.isArray(p.wires)||typeof p.title!=='string'||!/^[\w-]{1,64}$/.test(p.id)||p.components.length>128||p.wires.length>512)throw Error('Invalid project format.');
 const ids=new Set();p.components.forEach(c=>{if(!META[c.type]||!/^[\w-]{1,64}$/.test(c.id)||ids.has(c.id)||typeof c.label!=='string'||!Number.isFinite(c.x)||!Number.isFinite(c.y)||!Number.isFinite(c.rotation)||c.rotation%90!==0||!Number.isFinite(c.value))throw Error('Invalid component data.');ids.add(c.id);c.x=Math.max(72,Math.min(864,c.x));c.y=Math.max(72,Math.min(528,c.y));});
 p.wires.forEach(w=>{for(const t of [w.from,w.to]){if(typeof t!=='string')throw Error('Invalid terminal.');let[id,k]=t.split(':'),c=p.components.find(c=>c.id===id);if(!c||!['0','1'].includes(k)||(c.type==='ground'&&k==='1'))throw Error('Wire points to a missing terminal.');}});
 snapshot();project=p;selected=null;selectedWire=-1;wireStart=null;changed();notify('Project imported.');
 }catch(err){notify(err.message);}finally{e.target.value='';}
});
document.addEventListener('keydown',e=>{
 if(e.target.matches('input,select,textarea,[contenteditable]'))return;
 if($('#modal').open)return;
 const key=e.key.toLowerCase();
 if(e.code==='Space'){space=true;e.preventDefault();}
 if(e.key==='Escape'){wireStart=null;mode='select';render();}
 if((e.ctrlKey||e.metaKey)&&key==='z'){e.preventDefault();actions[e.shiftKey?'redo':'undo']();return;}
 if((e.ctrlKey||e.metaKey)&&key==='y'){e.preventDefault();actions.redo();return;}
 const map={v:'select',w:'wire',r:'rotate',enter:'run',delete:'delete',backspace:'delete'};
 if(map[key]){e.preventDefault();actions[map[key]]();}
 if(key==='/'){e.preventDefault();$('#component-search').focus();}
});
document.addEventListener('keyup',e=>{if(e.code==='Space')space=false;});window.addEventListener('blur',()=>{space=false;endDrag();});
window.addEventListener('beforeunload',e=>{if(dirty&&undo.length){e.preventDefault();e.returnValue='';}});
(async()=>{if(location.protocol.startsWith('http'))try{const r=await fetch('/api/status');if(r.ok){const s=await r.json();native=s.native;apiToken=s.token||'';$('#engine-status').textContent=native?'C++17 engine connected':'Browser preview';}}catch{}renderPalette();render();renderResults();})();

