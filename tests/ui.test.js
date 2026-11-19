const path=require('node:path'),fs=require('node:fs'),assert=require('node:assert/strict'),{pathToFileURL}=require('node:url');
let pw;try{pw=require('playwright');}catch{pw=require(path.join(path.dirname(process.execPath),'../node_modules/playwright'));}
(async()=>{
let b;const errors=[],checks=[];
try{
 b=await pw.chromium.launch({headless:true,channel:process.env.SC_BROWSER_CHANNEL||'chrome'});
 const page=await b.newPage({viewport:{width:1440,height:1100}});
 page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
 const url=pathToFileURL(path.resolve(__dirname,'../preview/index.html')).href;
 await page.goto(url);
 const run=async()=>page.getByRole('button',{name:/Run simulation/}).first().click();
 await run();assert.match(await page.locator('#results-content').innerText(),/8 V/);checks.push('divider run and result table');
 await page.locator('#edit-value').fill('1k');await page.locator('#edit-label').click();await run();
 assert.match(await page.locator('#results-content').innerText(),/6 V/);checks.push('property editing changes output to 6 V');
 await page.locator('#undo-tool').click();await run();assert.match(await page.locator('#results-content').innerText(),/8 V/);checks.push('undo restores circuit');
 await page.locator('[data-add=resistor]').click();assert.equal(await page.locator('[data-component]').count(),5);
 await page.locator('[data-action=delete]').click();assert.equal(await page.locator('[data-component]').count(),4);checks.push('component placement and deletion');
 await page.locator('[data-terminal="V1:0"]').click();await page.locator('[data-terminal="R2:0"]').click();
 assert.match(await page.locator('#circuit-count').innerText(),/5 wires/);checks.push('terminal-to-terminal wiring');
 await page.locator('#undo-tool').click();
 await page.getByRole('button',{name:/Save project/}).click();await page.locator('#project-name').fill('Moiz test circuit');await page.getByRole('button',{name:'Save on this device',exact:true}).click();
 assert.equal(await page.locator('#save-status').innerText(),'Saved on this device');
 await page.getByRole('button',{name:/My projects/}).click();await page.locator('[data-load]').filter({hasText:'Moiz test circuit'}).click();
 assert.equal(await page.locator('#project-title').innerText(),'Moiz test circuit');checks.push('saved project roundtrip');
 await page.getByRole('button',{name:'Examples',exact:true}).click();await page.locator('[data-example=rc]').click();await run();
 assert.equal(await page.locator('#result-state').innerText(),'Transient complete');assert.match(await page.locator('#results-content').innerText(),/4.96 V/);checks.push('RC transient and charging plot');
 await page.getByRole('button',{name:'Examples',exact:true}).click();await page.locator('[data-example=divider]').click();await run();
 await page.screenshot({path:path.resolve(__dirname,'../docs/workbench-desktop.png'),fullPage:true});
 await page.locator('#select-tool').click();
 const before=await page.locator('[data-component=R1]').boundingBox();
 await page.mouse.move(before.x+before.width/2,before.y+before.height/2+12);await page.mouse.down();await page.mouse.move(before.x+before.width/2+60,before.y+before.height/2+60,{steps:6});await page.mouse.up();
 const after=await page.locator('[data-component=R1]').boundingBox();assert.ok(Math.abs(after.x-before.x)>15);checks.push('dragging updates component geometry');
 await page.locator('#undo-tool').click();
 const mobile=await b.newPage({viewport:{width:390,height:844},isMobile:true,hasTouch:true});
 mobile.on('pageerror',e=>errors.push(e.message));await mobile.goto(url);await mobile.getByRole('button',{name:/Run simulation/}).first().click();
 assert.equal(await mobile.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);checks.push('390 px mobile layout has no horizontal overflow');
 await mobile.screenshot({path:path.resolve(__dirname,'../docs/workbench-mobile.png'),fullPage:true});
 await page.locator('[data-action=new]').click();await page.locator('[data-action=create]').click();await run();
 assert.match(await page.locator('#results-content').innerText(),/ground reference/);checks.push('missing ground error shown');
 await page.locator('#component-search').fill('xyz');assert.match(await page.locator('#component-list').innerText(),/No matching/);checks.push('component search empty state');
 assert.deepEqual(errors,[]);checks.push('no uncaught browser errors');
 fs.writeFileSync(path.resolve(__dirname,'../docs/ui-validation.json'),JSON.stringify({passed:checks.length,checks,errors},null,2));
 console.log('PASS: '+checks.length+' UI checks\n'+checks.join('\n'));
}catch(e){console.error(e.stack);process.exitCode=1;}finally{if(b)await b.close();}
})();

