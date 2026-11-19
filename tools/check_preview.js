let pw;try{pw=require('playwright');}catch{pw=require(require('node:path').join(require('node:path').dirname(process.execPath),'../node_modules/playwright'));}const {chromium}=pw;
const path=require('node:path'),{pathToFileURL}=require('node:url');
(async()=>{
 let b;
 try{
  b=await chromium.launch({headless:true,channel:'chrome'});
  const page=await b.newPage({viewport:{width:1440,height:1100}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(pathToFileURL(path.resolve(__dirname,'../preview/index.html')).href);
  await page.getByRole('button',{name:/Run simulation/}).first().click();
  console.log(await page.locator('#results-content').innerText());
  await page.screenshot({path:path.resolve(__dirname,'../docs/workbench-desktop.png'),fullPage:true});
  console.log('Errors:',JSON.stringify(errors));
 }catch(e){console.error(e.message);process.exitCode=1;}
 finally{if(b)await b.close();}
})();

