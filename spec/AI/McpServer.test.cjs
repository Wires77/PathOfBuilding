'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { createInterface } = require('node:readline');
const server = path.resolve(__dirname, '../../src/AI/McpServer.cjs');
function client(t, reportPath) {
  const child = spawn(process.execPath, [server, reportPath], { stdio: ['pipe','pipe','pipe'] });
  t.after(() => child.kill());
  const pending = new Map();
  let id = 0;
  createInterface({ input: child.stdout }).on('line', line => {
    const message = JSON.parse(line);
    const item = pending.get(message.id);
    if (item) { clearTimeout(item.timer); pending.delete(message.id); item.resolve(message); }
  });
  const request = (method, params) => new Promise((resolve,reject) => {
    const current = ++id;
    pending.set(current,{ resolve,timer:setTimeout(() => reject(new Error('MCP response timed out')),5000) });
    child.stdin.write(JSON.stringify({jsonrpc:'2.0',id:current,method,params})+'\n');
  });
  return { child,request,async initialize(version = '2025-11-25') {
    const result = await request('initialize',{protocolVersion:version,capabilities:{},clientInfo:{name:'test',version:'1'}});
    child.stdin.write(JSON.stringify({jsonrpc:'2.0',method:'notifications/initialized'})+'\n');
    return result;
  } };
}
function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(),'pob-mcp-'));
  t.after(() => fs.rmSync(dir,{recursive:true,force:true}));
  const file = path.join(dir,'report.json');
  const report = { schemaVersion:1,capturedAt:'2026-01-01T00:00:00Z',source:'desktop-explicit-snapshot',summary:{SurvivalChance:0},settings:{simulateRecovery:true},
    trace:{trial:2,time:3,cause:'Cold hit',deathDetails:{before:{Life:500}},rows:[{event:'Start'},{event:'Sample'},{event:'Cold hit'},{event:'Death'}]},
    limitations:['Explicit snapshot'],checks:[],assumptions:['No kill charges'] };
  fs.writeFileSync(file,JSON.stringify(report));
  return {file,report};
}
test('negotiates versions, requires initialization, and keeps applying builds in the desktop UI', async t => {
  const {file} = fixture(t); const c = client(t,file);
  assert.equal((await c.request('tools/list')).error.code,-32000);
  assert.equal((await c.initialize('2025-03-26')).result.protocolVersion,'2025-03-26');
  const list = (await c.request('tools/list')).result.tools;
  assert.equal(list.length,34);
  assert.ok(list.every(tool => !tool.annotations.openWorldHint));
  assert.equal(list.filter(tool => !tool.annotations.readOnlyHint).length,21);
  assert.ok(list.some(tool => tool.name === 'propose_build' && !tool.annotations.readOnlyHint));
  assert.ok(!list.some(tool => /apply_build|save/.test(tool.name)));
  assert.ok(list.some(tool => tool.name === 'apply_crafting_action'));
  assert.ok(list.some(tool => tool.name === 'test_loot_filter_examples'));
  assert.equal((await c.request('tools/call',{name:'get_encounter_report',arguments:{path:'elsewhere'}})).error.code,-32602);
  assert.equal((await c.request('run_lua',{code:'anything'})).error.code,-32601);
});
test('reads refreshed reports per call, discloses age and returns selected death events', async t => {
  const {file,report} = fixture(t); const c = client(t,file); await c.initialize();
  const first = (await c.request('tools/call',{name:'get_encounter_report'})).result.structuredContent;
  assert.ok(first.snapshot.ageSeconds > 0);
  assert.match(first.snapshot.freshness,/cannot detect unsaved changes/);
  const death = (await c.request('tools/call',{name:'get_death_details'})).result.structuredContent;
  assert.equal(death.trial,2); assert.equal(death.deathDetails.before.Life,500);
  assert.deepEqual(death.precedingEvents.map(r => r.event),['Start','Cold hit','Death']);
  report.summary.SurvivalChance = 100; fs.writeFileSync(file,JSON.stringify(report));
  assert.equal((await c.request('tools/call',{name:'get_encounter_report'})).result.structuredContent.report.summary.SurvivalChance,100);
});
test('missing, partial and incompatible reports produce actionable errors', async t => {
  const {file} = fixture(t); const c = client(t,file); await c.initialize();
  for (const contents of ['{','{}']) {
    fs.writeFileSync(file,contents);
    assert.equal((await c.request('tools/call',{name:'get_encounter_report'})).result.isError,true);
  }
  fs.unlinkSync(file);
  assert.match((await c.request('tools/call',{name:'get_encounter_report'})).result.content[0].text,/Refresh MCP context/);
});
test('AI prompts include captured evidence and distinguish hypotheses', async t => {
  const {file} = fixture(t); const c = client(t,file); await c.initialize();
  assert.equal((await c.request('prompts/list')).result.prompts.length,3);
  const prompt = (await c.request('prompts/get',{name:'explain_death'})).result.messages[0];
  assert.equal(prompt.role,'user'); assert.match(prompt.content.text,/hypotheses/); assert.match(prompt.content.text,/Cold hit/);
  assert.equal((await c.request('prompts/get',{name:'missing'})).error.code,-32602);
});
