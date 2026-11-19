/* Development reference adapter. The Flutter application always uses C++ via FFI. */
(function(root){
'use strict';
function topology(project){
 if(project.schema!==1||!Array.isArray(project.components)||!Array.isArray(project.wires))throw Error('Unsupported project format.');
 if(project.components.length>128||project.wires.length>512)throw Error('Limit: 128 components and 512 wires.');
 const cs=project.components,terminals=[],ids=new Set(),ground=[];
 cs.forEach(c=>{
  if(!/^[\w-]{1,64}$/.test(c.id)||ids.has(c.id))throw Error('Invalid or duplicate component ID.');ids.add(c.id);
  if(!['resistor','voltage','current','capacitor','ground'].includes(c.type))throw Error('Unsupported component.');
  if(!Number.isFinite(c.value)||Math.abs(c.value)>1e12)throw Error('Value outside supported range.');
  if(c.type==='resistor'&&(c.value<1e-6||c.value>1e12))throw Error('Resistance must be 1 µΩ to 1 TΩ.');
  if(c.type==='capacitor'&&(c.value<1e-12||c.value>1))throw Error('Capacitance must be 1 pF to 1 F.');
  if(['voltage','current'].includes(c.type)&&Math.abs(c.value)>1e6)throw Error('Source value exceeds supported range.');
  for(let k=0;k<(c.type==='ground'?1:2);k++){let t=c.id+':'+k;terminals.push(t);if(c.type==='ground')ground.push(t);}
 });
 if(!ground.length)throw Error('Add a ground reference before running.');
 if(cs.length===ground.length)throw Error('Add a source and components.');
 const parent=Object.fromEntries(terminals.map(t=>[t,t]));
 const find=t=>parent[t]===t?t:(parent[t]=find(parent[t]));
 const join=(a,b)=>{if(!(a in parent)||!(b in parent))throw Error('Wire points to a missing terminal.');parent[find(a)]=find(b);};
 ground.forEach(t=>join(t,ground[0]));project.wires.forEach(w=>join(w.from,w.to));
 const groundRoot=find(ground[0]),nets=new Map(),node={};
 terminals.forEach(t=>{let r=find(t);if(r===groundRoot)node[t]=-1;else{if(!nets.has(r))nets.set(r,nets.size);node[t]=nets.get(r);}});
 const components=cs.map(c=>({...c,p:node[c.id+':0'],n:c.type==='ground'?-1:node[c.id+':1']}));
 components.forEach(c=>{if(c.type==='voltage'&&c.p===c.n)throw Error(c.label+': source terminals are shorted.');});
 return {components,node,count:nets.size};
}
function gaussian(a,z){
 let n=z.length;
 for(let r=0;r<n;r++){let scale=Math.max(...a[r].map(Math.abs));if(!scale)throw Error('Floating node. Connect every network to ground.');a[r]=a[r].map(v=>v/scale);z[r]/=scale;}
 for(let c=0;c<n;c++){
  let p=c;for(let r=c+1;r<n;r++)if(Math.abs(a[r][c])>Math.abs(a[p][c]))p=r;
  if(Math.abs(a[p][c])<1e-13)throw Error('Floating nodes, conflicting sources or redundant ideal-source loops.');
  [a[c],a[p]]=[a[p],a[c]];[z[c],z[p]]=[z[p],z[c]];
  for(let r=c+1;r<n;r++){let f=a[r][c]/a[c][c];for(let k=c;k<n;k++)a[r][k]-=f*a[c][k];z[r]-=f*z[c];}
 }
 const x=Array(n).fill(0);for(let r=n-1;r>=0;r--){let v=z[r];for(let k=r+1;k<n;k++)v-=a[r][k]*x[k];x[r]=v/a[r][r];if(!Number.isFinite(x[r]))throw Error('Numerical overflow.');}return x;
}
function solve(t,dt=0,initial=false,previous=[]){
 const branches={};let size=t.count;
 t.components.forEach(c=>{if(c.type==='voltage'||(c.type==='capacitor'&&initial))branches[c.id]=size++;});
 const a=Array.from({length:size},()=>Array(size).fill(0)),z=Array(size).fill(0);
 const add=(r,c,v)=>{if(r>=0&&c>=0)a[r][c]+=v;},rhs=(r,v)=>{if(r>=0)z[r]+=v;};
 const old=i=>i<0?0:previous[i];
 const conduct=(p,n,g)=>{add(p,p,g);add(n,n,g);add(p,n,-g);add(n,p,-g);};
 t.components.forEach(c=>{
  let {p,n,value:v}=c,b=branches[c.id];
  if(c.type==='resistor')conduct(p,n,1/v);
  if(c.type==='current'){rhs(p,-v);rhs(n,v);}
  if(c.type==='voltage'||(c.type==='capacitor'&&initial)){add(p,b,1);add(n,b,-1);add(b,p,1);add(b,n,-1);rhs(b,c.type==='voltage'?v:0);}
  if(c.type==='capacitor'&&!initial&&dt){let g=v/dt,h=g*(old(p)-old(n));conduct(p,n,g);rhs(p,h);rhs(n,-h);}
 });
 const x=gaussian(a,z),voltage=i=>i<0?0:x[i];
 let dissipatedPower=0,powerBalance=0;
 const components=t.components.filter(c=>c.type!=='ground').map(c=>{
  let v=voltage(c.p)-voltage(c.n),i=0;
  if(c.type==='resistor')i=v/c.value;else if(c.type==='current')i=c.value;else if(c.type==='voltage'||(c.type==='capacitor'&&initial))i=x[branches[c.id]];
  else if(c.type==='capacitor'&&dt)i=c.value/dt*(v-old(c.p)+old(c.n));
  let power=v*i;powerBalance+=power;if(c.type==='resistor')dissipatedPower+=power;
  return {id:c.id,label:c.label,voltage:v,current:i,power};
 });
 return {components,nodeVoltages:Object.fromEntries(Object.entries(t.node).map(([k,i])=>[k,voltage(i)])),nets:x.slice(0,t.count).map((voltage,i)=>({name:'N'+(i+1),voltage})),dissipatedPower,powerBalance,next:x.slice(0,t.count)};
}
function execute(request){
 const t=topology(request.project);
 if(request.op==='validate')return {ok:true,netCount:t.count};
 if(request.op==='simulate')return {ok:true,result:solve(t)};
 if(request.op==='transient'){
  let duration=request.duration??.05,steps=request.steps??200;
  if(!Number.isFinite(duration)||duration<=0||duration>3600||!Number.isInteger(steps)||steps<2||steps>1000)throw Error('Use 2–1000 steps and 0–3600 seconds.');
  if(!t.components.some(c=>c.type==='capacitor'))throw Error('Add a capacitor for RC transient.');
  let first=solve(t,0,true),samples=[{...first,time:0}],previous=first.next;
  for(let k=1;k<=steps;k++){let frame=solve(t,duration/steps,false,previous);samples.push({...frame,time:k*duration/steps});previous=frame.next;}
  return {ok:true,result:{samples,duration,method:'Backward Euler; zero initial capacitor voltage; DC sources step at t=0'}};
 }
 throw Error('Unknown operation.');
}
root.ShortCircuitSolver={execute,topology,solve};
if(typeof module!=='undefined')module.exports=root.ShortCircuitSolver;
})(typeof window!=='undefined'?window:globalThis);

