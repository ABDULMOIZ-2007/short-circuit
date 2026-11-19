const fs=require('node:fs'),path=require('node:path');
let sharp;try{sharp=require('sharp');}catch{sharp=require(path.join(path.dirname(process.execPath),'../node_modules/sharp'));}
const root=path.join(__dirname,'..','assets');
fs.mkdirSync(path.join(root,'brand','android'),{recursive:true});
const svg=(body,w=96,h=64)=>'<svg xmlns="http://www.w3.org/2000/svg" width="'+w+'" height="'+h+'" viewBox="0 0 '+w+' '+h+'"><g fill="none" stroke="#e7e5df" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">'+body+'</g></svg>';
const shapes={
resistor:'<path d="M0 32H22l5-12 9 24 9-24 9 24 9-24 6 12h27"/>',
voltage:'<path d="M0 32H24m48 0h24"/><circle cx="48" cy="32" r="24"/><path d="M36 26h12m-6-6v12m12 7h8"/>',
current:'<path d="M0 32H24m48 0h24"/><circle cx="48" cy="32" r="24"/><path d="M34 32h28m-9-8 9 8-9 8"/>',
capacitor:'<path d="M0 32h42m12 0h42M42 12v40m12-40v40"/>',
ground:'<path d="M48 0v25m-24 0h48m-40 10h32m-24 10h16"/>',
wire:'<path d="M10 48h30V16h46"/><circle cx="10" cy="48" r="4"/><circle cx="86" cy="16" r="4"/>'
};
for(const [n,b]of Object.entries(shapes))fs.writeFileSync(path.join(root,'symbols',n+'.svg'),svg(b));
fs.writeFileSync(path.join(root,'textures','dot-grid.svg'),'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="1" cy="1" r="1" fill="#353b3b"/></svg>');
fs.writeFileSync(path.join(root,'textures','line-grid.svg'),'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><path d="M24 0H0v24" fill="none" stroke="#2a3030" stroke-width=".6"/></svg>');
fs.writeFileSync(path.join(root,'textures','paper-grid.svg'),'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><path d="M24 0H0v24" fill="none" stroke="#dce5df" stroke-width=".6"/></svg>');
fs.writeFileSync(path.join(root,'textures','panel-grain.svg'),'<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><filter id="n"><feTurbulence type="fractalNoise" baseFrequency=".75" numOctaves="3" stitchTiles="stitch"/></filter><rect width="100%" height="100%" opacity=".035" filter="url(#n)"/></svg>');
const logo='<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" rx="116" fill="#171e1d"/><rect x="18" y="18" width="476" height="476" rx="100" fill="none" stroke="#3a443e" stroke-width="3"/><path d="M304 101 160 269h95l-43 142 143-178h-99z" fill="#ee9c63"/><circle cx="161" cy="270" r="15" fill="#171e1d" stroke="#ee9c63" stroke-width="9"/><circle cx="354" cy="233" r="15" fill="#171e1d" stroke="#ee9c63" stroke-width="9"/></svg>';
fs.writeFileSync(path.join(root,'brand','logo.svg'),logo);
(async()=>{await sharp(Buffer.from(logo)).resize(512).png().toFile(path.join(root,'brand','icon-512.png'));await sharp(Buffer.from(logo)).resize(192).png().toFile(path.join(root,'brand','icon-192.png'));await sharp(path.join(root,'textures','pcb-copper.png')).resize(1536).webp({quality:83}).toFile(path.join(root,'textures','pcb-copper.webp'));for(const [density,size]of Object.entries({mdpi:48,hdpi:72,xhdpi:96,xxhdpi:144,xxxhdpi:192}))await sharp(Buffer.from(logo)).resize(size).png().toFile(path.join(root,'brand','android','ic_launcher-'+density+'.png'));console.log('Vector symbols, grids, texture and launcher icons generated.');})();

