// cspell:ignore RRBG
'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createBridge } = require('../../src/AI/BuildProtocol.cjs');
function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(),'pob-build-'));
  t.after(() => fs.rmSync(dir,{recursive:true,force:true}));
  const state = {schemaVersion:1,session:'session-one',enabled:true,heartbeat:Date.now()/1000,revision:'a'.repeat(40)};
  const captured = {schemaVersion:1,session:state.session,capturedAt:new Date().toISOString(),context:{revision:state.revision,name:'Desktop',level:80,xml:'not returned'},
    catalog:{gems:[{name:'Fireball'}],passives:[{id:123,name:'Life',pathLength:3}],config:[],classes:[]}};
  const write = (name,value) => fs.writeFileSync(path.join(dir,`AI-build-${name}.json`),JSON.stringify(value));
  write('state',state); write('context',captured);
  return {dir,state,captured,write,call:createBridge(path.join(dir,'AI-encounter.json')),proposal:{mode:'new',title:'Fireball candidate',baseRevision:state.revision,
    operations:[{type:'set_character',level:80,className:'Witch',ascendancy:'Elementalist'},{type:'set_skills',groups:[{gems:[{name:'Fireball'}]}]}]}};
}

test('queues reviewed crafting removals with closed project-ID validation', t => {
  const f=fixture(t);const proposal={...f.proposal,mode:'edit',operations:[{type:'remove_crafting_project',projectId:'helmet-guide'}]};
  f.call('propose_build',proposal);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(request.proposal.operations,proposal.operations);assert.equal(f.captured.context.craftingProjects,undefined);
  for(const operation of [{type:'remove_crafting_project',projectId:'../other'},{type:'remove_crafting_project',projectId:''},{type:'remove_crafting_project',projectId:'helmet',project:{}}]) {
    assert.throws(()=>f.call('propose_build',{...proposal,operations:[operation]}),/arguments/);
  }
});

test('queues loot-filter generation, evaluation and reviewed profiles without writing exports', t => {
  const f=fixture(t);const profile={id:'maps',title:'Map pickups',preset:'early_maps',strictness:2,rules:[{id:'base',title:'Craft base',text:'Show\n BaseType == "Iron Hat"',enabled:true}]};
  const filters={schemaVersion:1,activeId:'maps',profiles:[profile]};f.captured.context.lootFilters=filters;f.write('context',f.captured);
  assert.deepEqual(f.call('get_loot_filters',{}).filters,filters);
  for(const name of ['generate_loot_filter','test_loot_filter','export_loot_filter']) {
    f.call(name,{baseRevision:f.state.revision,profile,...(name==='test_loot_filter'?{sample:{BaseType:'Iron Hat',Fated:false,UnidentifiedItemTier:3}}:{})});
    const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(request.kind,name);
    assert.equal(request.profile.id,'maps');assert.equal(request.path,undefined);fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  }
  f.call('propose_loot_filters',{title:'Pickups',baseRevision:f.state.revision,filters});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(request.proposal.operations[0].type,'set_loot_filters');
  assert.throws(()=>f.call('test_loot_filter',{baseRevision:f.state.revision,profile,sample:{},path:'arbitrary'}),/arguments/);
});
test('accepts typed Atlas stages, strategy inputs and explicit failure recovery branches', t => {
  const f=fixture(t);
  const plan={id:'final',title:'Final maps',version:'3.29.1',budget:138,nodes:[],progression:{stage:'final',previousId:'starter'},strategy:{maps:'T16 maps',scarabs:'Supplied scarabs',requirements:'Unlocks complete',avoid:'Reflect',setupCost:{amount:25,currency:'chaos',source:'Manual quote',quotedAt:1700000000}}};
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});
  let request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.proposal.operations[0].plan,plan);
  assert.throws(()=>f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,progression:{stage:'invented'}}}),/arguments/);
  fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  const recipe={steps:[{method:'alchemy',onFailureAction:'restart',recoveryNotes:'Restart within the action budget'}],targets:[]};
  f.call('simulate_crafting',{baseRevision:f.state.revision,itemText:'Rarity: NORMAL\nIron Hat',recipe});
  request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.recipe,recipe);
  assert.throws(()=>f.call('simulate_crafting',{baseRevision:f.state.revision,itemText:'Iron Hat',recipe:{...recipe,steps:[{method:'alchemy',onFailureAction:'sell-for-profit'}]}}),/arguments/);
});

test('queues portable tiers, local modules, whole-filter styles and saved Atlas intentions', t => {
  const f=fixture(t);const rule={id:'chaos',title:'Chaos',text:'Show\n BaseType == "Chaos Orb"'};
  const profile={id:'maps',title:'Maps',preset:'early_maps',strictness:2,rules:[],tiers:[{id:'tier',title:'High currency',text:rule.text,items:['Chaos Orb']}],modules:[{id:'module',title:'Shared rules',rules:[rule]}],appearance:{textColor:[255,220,120,255],alertId:6,alertVolume:0,effectColor:'Purple',disableIcons:true}};
  f.call('propose_loot_filters',{title:'Local filter tools',baseRevision:f.state.revision,filters:{schemaVersion:1,activeId:'maps',profiles:[profile]}});
  let request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.proposal.operations[0].filters.profiles[0],profile);fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('test_loot_filter',{baseRevision:f.state.revision,profile:{...profile,appearance:{textColor:[255,0,0] }},sample:{}}),/arguments/);
  const plan={id:'atlas',title:'Saved intentions',version:'3.30.0-preview',budget:150,nodes:[],desired:[123],avoided:[456]};
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.proposal.operations[0].plan,plan);
});

test('queues full crafting inventory snapshots without imposing a count limit', t => {
  const f=fixture(t);const raw='Rarity: NORMAL\nIron Hat\nItem Level: 86';
  const inventory=Array.from({length:12},(_,i)=>({id:`item-${i}`,title:`Helmet ${i}`,slot:'Helmet',baseItem:raw,at:1700000000,state:{rarity:'NORMAL',affixes:[],quality:0,sockets:[{color:'R',group:0}]}}));
  const project={id:'helmet',title:'Helmet',slot:'Helmet',startingItem:raw,goals:[],steps:[],inventory};
  f.call('propose_crafting_plan',{baseRevision:f.state.revision,project});const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.proposal.operations[0].project.inventory,inventory);
  fs.rmSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,inventory:[{...inventory[0],state:{rarity:'INVENTED',affixes:[]}}]}}),/arguments/);
});

test('accepts typed campaign pickup policies and rejects invented families', t => {
  const f=fixture(t);const profile={id:'campaign',title:'Campaign',preset:'campaign',strictness:1,rules:[],campaign:{weapons:['Bow','Rune Dagger'],defences:['Energy shield'],recipes:['Quality gems'],minAreaLevel:1,maxAreaLevel:70,minLinks:3,upgradeWindow:15}};
  f.call('export_loot_filter',{baseRevision:f.state.revision,profile});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.profile.campaign,profile.campaign);
  for(const campaign of [{weapons:['Invented weapon']},{defences:['All armour']},{recipes:['Guaranteed profit']},{minLinks:7},{upgradeWindow:-1}]) {
    assert.throws(()=>f.call('export_loot_filter',{baseRevision:f.state.revision,profile:{...profile,campaign}}),/arguments/);
  }
});

test('queues exact saved filter examples and named appearance snapshots', t => {
  const f=fixture(t);const profile={id:'test',title:'Test',preset:'early_maps',strictness:2,rules:[],sampleSets:[{id:'early',title:'Early drops',samples:[{BaseType:'Iron Hat',AreaLevel:12,HasInfluence:['Shaper']}]}],palettes:[{id:'muted',title:'Muted',theme:'contrast',appearance:{alertVolume:0,textColor:[255,220,100,255]}}]};
  f.call('propose_loot_filters',{title:'Reusable examples',baseRevision:f.state.revision,filters:{schemaVersion:1,activeId:'test',profiles:[profile]}});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.proposal.operations[0].filters.profiles[0],profile);
  for(const sampleSets of [[{id:'empty',title:'Empty',samples:[]}],[{id:'invalid',title:'Invalid',samples:[{BaseType:{nested:'not a property'}}]}]]) {
    assert.throws(()=>f.call('export_loot_filter',{baseRevision:f.state.revision,profile:{...profile,sampleSets}}),/arguments/);
  }
});

test('queues category styles and palette snapshots without changing rule priority', t => {
  const f=fixture(t);const categoryStyles=[{category:'Currency',appearance:{textColor:[255,220,100,255],alertVolume:0}}];
  const profile={id:'test',title:'Test',preset:'early_maps',strictness:2,rules:[],categoryStyles,palettes:[{id:'saved',title:'Saved',appearance:{},categoryStyles}]};
  f.call('export_loot_filter',{baseRevision:f.state.revision,profile});const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(request.profile,profile);
  assert.throws(()=>f.call('export_loot_filter',{baseRevision:f.state.revision,profile:{...profile,categoryStyles:[{category:'Invented category',appearance:{}}]}}),/arguments/);
});
test('reads journey resources and queues a reviewed replacement without applying', t => {
  const f=fixture(t);
  const journey={schemaVersion:1,milestones:[{id:'links',title:'Get links',kind:'gems',dependencies:[]}],wishlist:[],resources:[],ledger:[],stages:[]};
  f.captured.context.journey=journey;f.captured.context.journeyBudget={};f.captured.context.nextActions=[];f.write('context',f.captured);
  assert.deepEqual(f.call('get_build_journey',{}).journey,journey);
  f.call('propose_journey_plan',{title:'Roadmap',baseRevision:f.state.revision,journey});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.proposal.operations[0].type,'set_build_journey');
  assert.deepEqual(request.proposal.operations[0].journey,journey);
});

test('queues native wishlist measurements against the current revision without applying gear', t => {
  const f=fixture(t);
  f.call('measure_journey_upgrades',{baseRevision:f.state.revision});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(request.kind,'journeyUpgrades');assert.equal(request.baseRevision,f.state.revision);assert.equal(request.proposal,undefined);
});

test('rejects malformed journey data and accepts more than eight entries', t => {
  const f=fixture(t);
  const journey={schemaVersion:1,milestones:[],wishlist:[],resources:[],ledger:[],stages:Array.from({length:20},(_,i)=>({id:`stage-${i}`,title:`Level ${i+1}`,level:i+1}))};
  assert.throws(()=>f.call('propose_journey_plan',{title:'Bad',baseRevision:f.state.revision,journey:{...journey,ledger:[{id:'bad',resourceId:'chaos',kind:'spend',amount:-1,at:1}]}}),/arguments/);
  f.call('propose_journey_plan',{title:'Long guide',baseRevision:f.state.revision,journey});
});

test('reads opted-in desktop context and searches bounded native catalogs', t => {
  const f = fixture(t);
  assert.equal(f.call('get_build_context',{}).context.xml,undefined);
  const result = f.call('search_build_catalog',{kind:'passives',query:'life',limit:1});
  assert.equal(result.total,1); assert.equal(result.matches[0].id,123);
  assert.throws(() => f.call('search_build_catalog',{kind:'gems',query:'Fireball',limit:0}),/arguments/);
});

test('records real client contacts, context receipts and requested test nonces separately', t => {
  const f=fixture(t);f.state.connectionTest={nonce:'test-round-trip'};f.write('state',f.state);
  f.call('get_build_connection',{});
  const receipt=()=>JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-client.json')));
  assert.equal(receipt().testNonce,'test-round-trip');assert.equal(receipt().contextRevision,undefined);
  f.call('get_build_context',{});assert.equal(receipt().contextRevision,f.state.revision);
  f.call('get_proposal_status',{});assert.equal(receipt().contextRevision,f.state.revision);
  f.state.session='another-session';f.write('state',f.state);f.call('get_build_connection',{});assert.equal(receipt().contextRevision,undefined);
});
test('queues a typed proposal bound to session and revision without applying it', t => {
  const f = fixture(t); const result = f.call('propose_build',f.proposal);
  const request = JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(result.status,'queued'); assert.equal(request.id,result.id);
  assert.equal(request.session,f.state.session); assert.deepEqual(request.proposal,f.proposal);
  assert.throws(() => f.call('propose_build',f.proposal),/already queued/);
  assert.equal(f.call('get_build_context',{}).context.level,80);
});
test('rejects disconnected sessions, old context and stale revisions', t => {
  const f = fixture(t);
  f.state.enabled=false; f.write('state',f.state);
  assert.throws(() => f.call('propose_build',f.proposal),/disabled/);
  f.state.enabled=true; f.state.heartbeat=Date.now()/1000-60; f.write('state',f.state);
  assert.throws(() => f.call('get_build_context',{}),/responding/);
  f.state.heartbeat=Date.now()/1000; f.write('state',f.state);
  assert.throws(() => f.call('propose_build',{...f.proposal,baseRevision:'b'.repeat(40)}),/revision changed/);
  f.captured.session='old-session'; f.write('context',f.captured);
  assert.throws(() => f.call('propose_build',f.proposal),/refreshing/);
});
test('rejects unknown operations, arbitrary paths, prototype keys and invalid numbers', t => {
  const f = fixture(t);
  for (const operations of [[{type:'run_lua',code:'anything'}],[{type:'set_character',level:Infinity}],[{type:'equip_item',slot:'Helmet',text:'Item',path:'elsewhere'}]]) {
    assert.throws(() => f.call('propose_build',{...f.proposal,operations}),/arguments/);
  }
  const request = JSON.parse(JSON.stringify(f.proposal).replace('"mode":"new"','"mode":"new","__proto__":{}'));
  assert.throws(() => f.call('propose_build',request),/arguments/);
  assert.equal(fs.existsSync(path.join(f.dir,'AI-build-request.json')),false);
});
test('returns calculated status and blocks replacement while desktop review is pending', t => {
  const f = fixture(t);
  f.state.proposal={id:'candidate-one',status:'review',after:{CombinedDPS:123},warnings:['Check assumptions']}; f.write('state',f.state);
  assert.equal(f.call('get_proposal_status',{}).proposal.after.CombinedDPS,123);
  assert.throws(() => f.call('propose_build',f.proposal),/pending proposal/);
  assert.throws(() => f.call('apply_build',{}),/arguments/);
});


test('diagnoses disabled and stale desktops without requiring an active connection', t => {
  const f=fixture(t);
  f.state.enabled=false; f.write('state',f.state);
  assert.equal(f.call('get_build_connection',{}).status,'disabled');
  f.state.enabled=true; f.state.heartbeat=Date.now()/1000-60; f.write('state',f.state);
  assert.equal(f.call('get_build_connection',{}).status,'stale');
  fs.unlinkSync(path.join(f.dir,'AI-build-state.json'));
  assert.equal(f.call('get_build_connection',{}).status,'unavailable');
});

test('queues goals with finite budgets and known minimum metrics', t => {
  const f=fixture(t);
  assert.throws(() => f.call('set_build_goals',{goal:'survival',budget:10}),/currency/);
  assert.throws(() => f.call('set_build_goals',{goal:'survival',minimums:{invented:10}}),/arguments/);
  f.call('set_build_goals',{goal:'comfort',budget:10,currency:'chaos',minimums:{LifeUnreserved:2000}});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'plan'); assert.equal(queued.plan.goal,'comfort');
});

test('compares bounded alternatives using matching revisions and dated price sources', t => {
  const f=fixture(t);
  const candidate={...f.proposal,quote:{amount:5,currency:'chaos',source:'Manual listing',quotedAt:Math.floor(Date.now()/1000)}};
  assert.throws(() => f.call('compare_build_candidates',{baseRevision:f.state.revision,candidates:[{...candidate,baseRevision:'b'.repeat(40)}]}),/revision/);
  assert.throws(() => f.call('compare_build_candidates',{baseRevision:f.state.revision,candidates:Array(6).fill(candidate)}),/arguments/);
  assert.throws(() => f.call('propose_build',{...candidate,quote:{...candidate.quote,quotedAt:4102444800}}),/capture time/);
  f.call('compare_build_candidates',{baseRevision:f.state.revision,candidates:[candidate]});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'compare'); assert.equal(queued.candidates[0].quote.amount,5);
});

test('queues increasing cumulative milestones and rejects character overrides', t => {
  const f=fixture(t);
  const stages=[{title:'Early',level:12,operations:[]},{title:'Later',level:70,operations:[{type:'set_notes',text:'Later links'}]}];
  assert.throws(() => f.call('plan_leveling_build',{baseRevision:f.state.revision,stages:[stages[1],stages[0]]}),/increase/);
  assert.throws(() => f.call('plan_leveling_build',{baseRevision:f.state.revision,stages:[{...stages[0],operations:[{type:'set_character',level:99}]}]}),/arguments/);
  f.call('plan_leveling_build',{baseRevision:f.state.revision,stages});
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).kind,'leveling');
});

test('returns audit evidence and bounded session history', t => {
  const f=fixture(t);
  f.captured.context.audit={dependencies:[{key:'Str',text:'Requirement shortfall'}]};
  f.captured.context.encounter={observations:['Energy Shield was empty.']}; f.write('context',f.captured);
  f.state.history=[{id:'candidate-one',title:'Upgrade'}];f.state.diagnostics={undoDepth:2};f.write('state',f.state);
  assert.equal(f.call('get_build_analysis',{}).audit.dependencies[0].key,'Str');
  assert.equal(f.call('get_build_history',{}).undoDepth,2);
  assert.equal(f.call('get_build_history',{}).history.length,1);
});


test('retries a brief incomplete desktop refresh without reporting a disconnected session', t => {
  const f=fixture(t);const originalRead=fs.readFileSync;let partial=true;
  fs.readFileSync=function(file,...args){if (partial && file === path.join(f.dir,'AI-build-state.json')) {partial=false;return '{';}return originalRead.call(this,file,...args);};
  try {assert.equal(f.call('get_build_context',{}).context.name,'Desktop');assert.equal(partial,false);} finally {fs.readFileSync=originalRead;}
});


function craftingProject() {return {id:'life-helmet',title:'Life helmet',slot:'Helmet',startingItem:'Rarity: NORMAL\nIron Hat\nItem Level: 86',targetItem:'Rarity: RARE\nPlanned Hat\nIron Hat\n+100 to maximum Life',goals:['100 Life'],steps:[{action:'Choose a suitable method in Craft of Exile',stopWhen:'Target modifiers present',onFailure:'Stop at the budget limit'}]};}

test('queues crafting inspection with exactly one item source and current revision', t => {
  const f=fixture(t);
  assert.throws(()=>f.call('inspect_crafting_item',{baseRevision:f.state.revision}),/exactly one/);
  assert.throws(()=>f.call('inspect_crafting_item',{baseRevision:f.state.revision,slot:'Helmet',itemText:'other'}),/exactly one/);
  f.call('inspect_crafting_item',{baseRevision:f.state.revision,slot:'Helmet',query:'life',limit:5});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'craftInspect');assert.equal(queued.slot,'Helmet');
});

test('proposes crafting metadata and optional target gear through desktop review', t => {
  const f=fixture(t);const project=craftingProject();
  f.call('propose_crafting_plan',{baseRevision:f.state.revision,project,equipTarget:true});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.proposal.operations.map(op=>op.type),['set_crafting_project','equip_item']);
  assert.equal(queued.proposal.operations[1].text,project.targetItem);
  assert.equal(f.call('get_crafting_projects',{}).projects.length,0);
});

test('preserves typed Harvest enchant actions, goals and inventory states', t => {
  const f=fixture(t);const project=craftingProject();
  project.preferredMethod='harvest_enchant';
  project.nativeRecipe={steps:[{method:'harvest_enchant',enchantId:'WeaponCriticalEnchant'}],targets:[],requirements:{harvestEnchant:'WeaponCriticalEnchant'},initialState:{rarity:'NORMAL',affixes:[],harvestEnchant:'WeaponAreaEnchant'}};
  f.call('propose_crafting_plan',{baseRevision:f.state.revision,project});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.proposal.operations[0].project.nativeRecipe,project.nativeRecipe);
});

test('rejects invalid crafting evidence and execution fields', t => {
  const f=fixture(t);const project=craftingProject();
  assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,runCode:'no'}}),/arguments/);
  assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,targetItem:''},equipTarget:true}),/target item/);
  assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,simulation:{patch:'3.29',observedAt:1,trials:10,successes:11}}}),/exceed trials/);
});


test('queues native currency actions without applying desktop equipment', t => {
  const f=fixture(t);
  f.call('apply_crafting_action',{baseRevision:f.state.revision,itemText:craftingProject().startingItem,action:{method:'alchemy'},seed:123});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'craftAction'); assert.equal(queued.action.method,'alchemy');
  assert.equal(queued.proposal,undefined);
});

test('bounds native recipe work and rejects unsupported methods and invalid routes', t => {
  const f=fixture(t);
  const base={baseRevision:f.state.revision,itemText:craftingProject().startingItem,recipe:{steps:[{method:'alchemy'}],targets:[{anyOf:['IncreasedLife1']}]}};
  assert.throws(()=>f.call('simulate_crafting',{...base,options:{trials:2000,maxActions:2000}}),/20000/);
  assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...base.recipe,steps:[{method:'harvest'}]}}),/arguments/);
  assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...base.recipe,steps:[{method:'alchemy',onFailure:3}]}}),/route/);
  assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...base.recipe,steps:[{method:'alchemy',maxAttempts:20}]}}),/target conditions/);
  assert.throws(()=>f.call('simulate_crafting',{...base,options:{prices:{alchemy:1}}}),/currency/);
  f.call('simulate_crafting',{...base,options:{trials:100,maxActions:1,prices:{alchemy:1},currency:'chaos'}});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'craftSimulate'); assert.equal(queued.options.trials,100);
});


test('queues versioned Atlas searches and routing without changing build context', t => {
  const f=fixture(t);
  const plan={id:'atlas',title:'Essence maps',version:'3.29.1',budget:120,nodes:[],notes:'Start with sustain'};
  assert.equal(f.call('get_atlas_plans',{}).plans.length,0);
  f.call('search_atlas_nodes',{baseRevision:f.state.revision,version:'3.29.1',query:'Essence',limit:20});
  let queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'atlasSearch'); assert.equal(queued.proposal,undefined);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('plan_atlas_tree',{baseRevision:f.state.revision,plan,targets:[123],avoid:[456]});
  queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'atlasConnect'); assert.deepEqual(queued.targets,[123]);
  assert.equal(f.call('get_build_context',{}).context.level,80);
});

test('keeps Atlas proposals in the desktop review flow and rejects unsupported versions', t => {
  const f=fixture(t);
  const plan={id:'atlas',title:'Essence maps',version:'3.27.0',budget:120,nodes:[]};
  assert.throws(() => f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,version:'3.28.0'}}),/arguments/);
  assert.throws(() => f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,code:'anything'}}),/arguments/);
  assert.throws(() => f.call('plan_atlas_tree',{baseRevision:f.state.revision,plan,targets:Array(31).fill(123)}),/arguments/);
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.proposal.operations[0].type,'set_atlas_plan');
  assert.equal(queued.proposal.operations[0].plan.version,'3.27.0');
});


test('queues Omen of Trichromatism actions through the typed crafting protocol', t => {
  const f=fixture(t);const args={baseRevision:f.state.revision,itemText:'Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: W-W-W',action:{method:'omen_trichromatism'}};
  f.call('apply_crafting_action',args);
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(request.action,args.action);
});

test('queues advanced crafting states and rejects untyped execution data', t => {
  const f=fixture(t);
  const args={baseRevision:f.state.revision,itemText:craftingProject().startingItem,action:{method:'fossil',fossils:['Metadata/Items/Currency/CurrencyDelveCraftingLife']},initialState:{rarity:'RARE',affixes:[],influences:[],quality:20,sockets:[{color:'W',group:0}],catalyst:8,catalystQuality:20,baseImplicitRanges:[[0,1]],baseImplicit330:true}};
  f.call('apply_crafting_action',args);
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.initialState,args.initialState);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...args.initialState,runCode:'no'}}),/arguments/);
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...args.initialState,baseImplicit330:false}}),/arguments/);
  assert.throws(()=>f.call('apply_crafting_action',{...args,action:{method:'recombine',donorItem:'item',path:'elsewhere'}}),/arguments/);
});

test('preserves typed twice-corruption flags in crafting requests', t => {
  const f=fixture(t);
  const args={baseRevision:f.state.revision,itemText:craftingProject().startingItem,action:{method:'tainted_chromatic'},initialState:{rarity:'NORMAL',affixes:[],corrupted:true,twiceCorrupted:true}};
  f.call('apply_crafting_action',args);
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.deepEqual(queued.initialState,args.initialState);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...args.initialState,twiceCorrupted:'true'}}),/arguments/);
});

test('queues property-only recipes, exact odds and bounded fossil optimization', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  f.call('simulate_crafting',{...base,recipe:{steps:[{method:'quality',maxAttempts:20,untilRequirements:{minQuality:20}}],targets:[],requirements:{minQuality:20}},options:{trials:10,maxActions:20}});
  let queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(queued.kind,'craftSimulate');
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('calculate_crafting',{...base,action:{method:'exalt'},targets:[{anyOf:['IncreasedLife1'],negate:true,atLeast:1}]});
  queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(queued.kind,'craftCalculate');
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('optimize_crafting_fossils',{...base,targets:[{anyOf:['IncreasedLife1']}],options:{fossils:['life','mana'],maxSockets:2,trials:10}});
  queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(queued.kind,'craftOptimize');
});

test('queues crafting cancellation with an explicit request identifier', t => {
  const f=fixture(t);f.state.status='calculating';f.state.id='active-craft';f.write('state',f.state);
  f.call('cancel_crafting_simulation',{requestId:'active-craft'});
  const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
  assert.equal(queued.kind,'craftCancel');assert.equal(queued.requestId,'active-craft');
  assert.equal(queued.proposal,undefined);
});

test('queues observed predictable selections with bounded typed odds', t => {
  const f=fixture(t);
  const args={baseRevision:f.state.revision,itemText:craftingProject().startingItem,action:{method:'recombine_predictable',donorItem:'donor',selectedMods:{left:['IncreasedLife1'],right:['FireResist1']},reportedSuccessChance:40}};
  f.call('apply_crafting_action',args);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,args.action);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('apply_crafting_action',{...args,action:{...args.action,reportedSuccessChance:101}}),/arguments/);
  assert.throws(()=>f.call('apply_crafting_action',{...args,action:{...args.action,selectedMods:{left:[],right:['FireResist1']}}}),/arguments/);
});

test('queues observed Allflame profiles without allowing unbounded ghost work', t => {
  const f=fixture(t);
  const args={baseRevision:f.state.revision,itemText:craftingProject().startingItem,action:{method:'exalt',allflame:{outcomes:4,gainMin:8,gainMax:12,sulphur:100,preferredTargets:[{anyOf:['FireResist1']}]}},initialState:{rarity:'RARE',affixes:[],intangibility:30}};
  f.call('apply_crafting_action',args);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).action,args.action);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('apply_crafting_action',{...args,action:{...args.action,allflame:{...args.action.allflame,outcomes:1000}}}),/arguments/);
  assert.throws(()=>f.call('apply_crafting_action',{...args,initialState:{...args.initialState,intangibility:101}}),/arguments/);
});


test('queues automatic Allflame profiles and typed fracture goals', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  const action={method:'ducat_kishara',allflame:{auto:true,upgradeTier:2}};
  f.call('inspect_crafting_item',{...base,action});
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const recipe={steps:[action],targets:[{anyOf:['IncreasedLife1'],fractured:true,crafted:false}],requirements:{minFractured:1,maxFractured:2,maxIntangibility:50}};
  f.call('simulate_crafting',{...base,recipe,options:{trials:10,maxActions:1,retainSuccesses:3,baseCost:5,currency:"chaos"}});
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  for (const allflame of [{auto:true,outcomes:4},{auto:false},{auto:true,upgradeTier:3}]) {
    assert.throws(()=>f.call('apply_crafting_action',{...base,action:{...action,allflame}}),/arguments/);
  }
  assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...recipe,requirements:{minFractured:7}}}),/arguments/);
});


test('accepts the pinned 150 point Atlas preview without inventing future versions', t => {
  const f=fixture(t);const plan={id:'covens',title:'Covens preview',version:'3.30.0-preview',budget:150,nodes:[]};
  f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan});
  const request=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.equal(request.proposal.operations[0].plan.budget,150);
  assert.throws(()=>f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,budget:151}}),/arguments/);
  assert.throws(()=>f.call('propose_atlas_plan',{baseRevision:f.state.revision,plan:{...plan,version:'3.31.0'}}),/arguments/);
});

test('queues searches and plans for the pinned Ruthless Atlas', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision};const version='3.30.0-preview-ruthless';
  f.call('search_atlas_nodes',{...base,version,query:'Searing Exarch',limit:10});
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).version,version);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('plan_atlas_tree',{...base,plan:{id:'ruthless',title:'Ruthless',version,budget:150,nodes:[]},targets:[57123]});
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).plan.version,version);
});


test('queues offline appearance, colour goals and optimized Atlas routing', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision};
  const profile={id:'local',title:'Local',preset:'campaign',strictness:1,rules:[],appearance:{minimumFontSize:40,alertVolume:0,disableEffects:true}};
  f.call('export_loot_filter',{...base,profile});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).profile.appearance,profile.appearance);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  const recipe={steps:[{method:'chromatic',maxAttempts:10,untilRequirements:{socketColours:'RRBG',linkedColours:true}}],targets:[],requirements:{socketColours:'RRBG',linkedColours:true}};
  f.call('simulate_crafting',{...base,itemText:craftingProject().startingItem,recipe,options:{trials:10,maxActions:10}});
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('calculate_crafting',{...base,itemText:craftingProject().startingItem,action:{method:'chromatic'},targets:[],options:{trials:10,requirements:{socketColours:'RRBG',linkedColours:true}}});
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('plan_atlas_tree',{...base,plan:{id:'atlas',title:'Atlas',version:'3.30.0-preview',budget:150,nodes:[]},targets:[123],optimize:true});
  assert.equal(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).optimize,true);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  assert.throws(()=>f.call('export_loot_filter',{...base,profile:{...profile,appearance:{alertVolume:301}}}),/arguments/);
  assert.throws(()=>f.call('simulate_crafting',{...base,itemText:craftingProject().startingItem,recipe:{...recipe,requirements:{socketColours:'RGX'}}}),/arguments/);
});

test('queues native item stat goals with decimal thresholds and rejects unknown stats', t => {
  const f=fixture(t);const base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  const recipe={steps:[{method:'quality',maxAttempts:20,untilRequirements:{nativeStats:{PhysicalDPS:12.4}}}],targets:[],requirements:{nativeStats:{PhysicalDPS:12.4,AttackRate:1.55}}};
  f.call('simulate_crafting',{...base,recipe,options:{trials:3,maxActions:20}});
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json'))).recipe,recipe);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  for (const nativeStats of [{Life:1},{AttackRate:-1},{PhysicalDPS:1e8},{CritChance:'5'}]) {
    assert.throws(()=>f.call('simulate_crafting',{...base,recipe:{...recipe,requirements:{nativeStats}}}),/arguments/);
  }
});


test('queues saved resource quotes with crafting guides and simulations', t => {
  const f=fixture(t);const priceBook={currency:'chaos',source:'Manual test quote',quotedAt:1700000000,values:{wild_lifeforce:0.1,exalt:0}};
  const project={...craftingProject(),priceBook};f.call('propose_crafting_plan',{baseRevision:f.state.revision,project});
  let queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(queued.proposal.operations[0].project.priceBook,priceBook);
  fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
  f.call('simulate_crafting',{baseRevision:f.state.revision,itemText:project.startingItem,recipe:{steps:[{method:'alchemy'}],targets:[],requirements:{minAffixes:1}},options:{priceBook}});
  queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));assert.deepEqual(queued.options.priceBook,priceBook);
  assert.throws(()=>f.call('propose_crafting_plan',{baseRevision:f.state.revision,project:{...project,priceBook:{...priceBook,values:{exalt:-1}}}}),/arguments/);
});


test('queues exact action totals independently of resource quotes',t=>{
  const f=fixture(t);const priceBook={currency:'chaos',source:'Saved quotes',quotedAt:1700000000,values:{alchemy:1}};
  const base={baseRevision:f.state.revision,itemText:craftingProject().startingItem};
  for(const name of ['simulate_crafting','optimize_crafting_fossils']){
    const args=name==='simulate_crafting'?{...base,recipe:{steps:[{method:'alchemy'}],targets:[],requirements:{minAffixes:1}},options:{priceBook,actionPrices:{alchemy:7}}}:{...base,targets:[],options:{fossils:['life'],priceBook,actionPrices:{'fossil:life':0}}};
    f.call(name,args);const queued=JSON.parse(fs.readFileSync(path.join(f.dir,'AI-build-request.json')));
    assert.deepEqual(queued.options.actionPrices,args.options.actionPrices);assert.deepEqual(queued.options.priceBook,priceBook);
    fs.unlinkSync(path.join(f.dir,'AI-build-request.json'));
    assert.throws(()=>f.call(name,{...args,options:{...args.options,actionPrices:{alchemy:-1}}}),/arguments/);
    assert.throws(()=>f.call(name,{...args,options:{...args.options,actionPrices:{alchemy:Infinity}}}),/arguments/);
    const unquoted={...args.options,actionPrices:{alchemy:7}};delete unquoted.priceBook;delete unquoted.currency;
    assert.throws(()=>f.call(name,{...args,options:unquoted}),/price currency/);
  }
});
