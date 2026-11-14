// cspell:ignore RGBW
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const string = maxLength => ({type:'string',maxLength});
const integer = (minimum,maximum) => ({type:'integer',minimum,maximum});
const object = (properties,required = []) => ({type:'object',properties,required,additionalProperties:false});
const array = (items,maxItems) => ({type:'array',items,maxItems});
const boolean = {type:'boolean'};
const number = (minimum,maximum) => ({type:'number',minimum,maximum});
const quoteSchema = object({amount:number(0,1e12),currency:{type:'string',pattern:'^[A-Za-z][A-Za-z0-9 _-]{0,23}$'},quotedAt:integer(0,4102444800),source:string(240)},['amount','currency','quotedAt','source']);
const journeyId={type:'string',pattern:'^[A-Za-z0-9_-]{1,64}$'};
const journeyList=items=>({type:'array',items});
const lootRule=object({id:string(100),title:string(160),text:string(24000),enabled:boolean,origin:string(240)},['id','title','text']);
const lootModule=object({id:string(100),title:string(160),enabled:boolean,rules:journeyList(lootRule)},['id','title','rules']);
const lootTier=object({id:string(100),title:string(160),enabled:boolean,text:string(24000),items:journeyList(string(240))},['id','title','text','items']);
const lootColour={type:'array',minItems:4,maxItems:4,items:integer(0,255)};
const lootCampaign=object({enabled:boolean,weapons:array({enum:['Bow','Claw','Dagger','Rune Dagger','Fishing Rod','One Handed Axe','One Handed Mace','One Handed Sword','Thrusting Sword','Sceptre','Staff','Warstaff','Two Handed Axe','Two Handed Mace','Two Handed Sword','Wand','Shield','Quiver']},18),defences:array({enum:['Armour','Evasion','Energy shield','Armour / Evasion','Armour / Energy shield','Evasion / Energy shield','All three defences','Ward']},8),recipes:array({enum:['Three-colour linked equipment','Six-socket equipment','Six-link equipment','Quality gems']},4),minAreaLevel:integer(1,100),maxAreaLevel:integer(1,100),minDropLevel:integer(0,100),minLinks:integer(0,6),upgradeWindow:integer(0,100)});
const lootSample={type:'object',maxProperties:80,additionalProperties:{oneOf:[string(1000),number(-1e9,1e9),boolean,array(string(240),40)]}};
const lootAppearance=object({minimumFontSize:integer(1,45),alertVolume:integer(0,300),alertId:integer(1,16),disableEffects:boolean,disableIcons:boolean,effectColor:{enum:['Blue','Brown','Cyan','Green','Grey','Orange','Pink','Purple','Red','White','Yellow']},textColor:lootColour,borderColor:lootColour,backgroundColor:lootColour});
const lootCategoryStyles=journeyList(object({category:{enum:['Build targets','Campaign','Currency','Special currency','Equipment','Unique items','Flasks','Tinctures','Jewels','Divination cards','Maps & fragments','Gems','Recipes','League items','Other']},enabled:boolean,appearance:lootAppearance},['category','appearance']));
const lootProfile=object({id:journeyId,title:string(120),preset:{enum:['campaign','early_maps','endgame']},strictness:integer(0,6),theme:{enum:['default','contrast']},mode:{enum:['Normal','Ruthless']},baseCommit:string(40),campaign:lootCampaign,categoryStyles:lootCategoryStyles,sampleSets:journeyList(object({id:journeyId,title:string(120),samples:{type:'array',minItems:1,items:lootSample}},['id','title','samples'])),palettes:journeyList(object({id:journeyId,title:string(120),theme:{enum:['default','contrast']},categoryStyles:lootCategoryStyles,appearance:lootAppearance},['id','title','appearance'])),appearance:lootAppearance,template:string(2000000),importFiles:journeyList(object({name:string(240),text:string(2000000)},['name','text'])),rules:journeyList(lootRule),tiers:journeyList(lootTier),modules:journeyList(lootModule)},['id','title','preset','strictness','rules']);
const lootFilters=object({schemaVersion:{const:1},activeId:string(64),profiles:journeyList(lootProfile)},['schemaVersion','activeId','profiles']);
const journeyLinks={projectId:journeyId,atlasId:journeyId,stageId:journeyId,wishlistId:journeyId};
const journeyEntry={id:journeyId,title:string(120),notes:string(8000),level:integer(1,100),...journeyLinks};
const journeySchema=object({schemaVersion:{const:1},
  milestones:journeyList(object({...journeyEntry,kind:{enum:['task','passives','gems','gear','craft','atlas','quest','ascendancy']},priority:integer(1,5),done:boolean,dependencies:journeyList(journeyId)},['id','title'])),
  wishlist:journeyList(object({...journeyEntry,slot:string(80),route:{enum:['buy','craft','farm','owned']},stage:{enum:['next','final','alternative']},status:{enum:['planned','owned','skipped']},priority:integer(1,5),reserve:boolean,targetItem:string(24000),resourceId:journeyId,estimate:number(0,1e12)},['id','title','slot','route'])),
  resources:journeyList(object({...journeyEntry,unit:string(40)},['id','title'])),
  ledger:journeyList(object({id:journeyId,resourceId:journeyId,kind:{enum:['add','spend']},amount:number(0.000001,1e12),at:integer(0,4102444800),note:string(1000),projectId:journeyId},['id','resourceId','kind','amount','at'])),
  stages:journeyList(object({...journeyEntry,gems:string(12000),passives:string(12000),gear:string(12000),ascendancy:string(12000),quests:string(12000),transition:string(12000),questChecks:journeyList(string(1000))},['id','title','level']))
},['schemaVersion','milestones','wishlist','resources','ledger','stages']);
const atlasVersion={enum:['3.27.0','3.29.1','3.29.3','3.30.0-preview','3.30.0-preview-ruthless']};
const atlasPlan=object({id:{type:'string',pattern:'^[A-Za-z0-9_-]{1,64}$'},title:string(120),version:atlasVersion,budget:integer(0,150),nodes:array(integer(1,65535),300),desired:array(integer(1,65535),300),avoided:array(integer(1,65535),300),notes:string(8000),progression:object({stage:{enum:['starter','intermediate','final']},previousId:string(64)},['stage']),strategy:object({maps:string(4000),scarabs:string(4000),requirements:string(4000),avoid:string(4000),notes:string(4000),setupCost:object({amount:number(0,1e12),currency:string(40),source:string(240),quotedAt:integer(0,4102444800)},['amount','currency','quotedAt'])})},['id','title','version','budget','nodes']);
const craftingMethods=['beast_max_links','socket_white_bench','omen_jeweller','omen_trichromatism','omen_connections','transmute','alteration','augmentation','regal','alchemy','chaos','exalt','annul','scour','divine','bench','remove_crafted','essence','fossil','harvest_reforge','harvest_augment','harvest_resistance','harvest_enchant','fracture','influence_exalt','awakener','veiled_orb','unveil','dominance','beast_aspect','beast_prefix_suffix','beast_suffix_prefix','beast_imprint','beast_talisman_imprint','restore_imprint','bench_reroll','eldritch_implicit','eldritch_exalt','eldritch_annul','eldritch_chaos','blessed','sacred','socket_bench','binding','quality','catalyst','tainted_quality','tainted_catalyst','conflict','recombine','vaal','tainted_exalt','tainted_chaos','chromatic','socket_colour_bench','tainted_chromatic','tainted_jeweller','tainted_fusing','ducat_cyaxan','ducat_brinehook','ducat_genteel','ducat_merrick','beast_meta','beast_influence','locus','remembrance','unravelling','foulborn_augmentation','foulborn_regal','foulborn_exalt','recombine_predictable','ducat_rotmother','beast_talisman_fracture','ducat_tzamoto','ducat_kishara'];
const craftingTargets={type:'array',minItems:1,maxItems:6,items:object({anyOf:{type:'array',minItems:1,maxItems:30,items:string(160)},atLeast:integer(1,6),minRoll:number(0,1),negate:boolean,fractured:boolean,crafted:boolean,scope:{enum:['explicit','implicit']}},['anyOf'])};
const influence={enum:['shaper','elder','adjudicator','basilisk','crusader','eyrie']};
const craftingAffix=object({id:string(160),range:{oneOf:[number(-100,100),{type:'array',minItems:1,maxItems:20,items:number(-100,100)}]},fractured:boolean,crafted:boolean,legacyLightRadius:boolean},['id']);
const craftingStateProperties={rarity:{enum:['NORMAL','MAGIC','RARE']},affixes:array(craftingAffix,6),baseItem:string(24000),origin:{type:'string',pattern:'^[a-f0-9]{40}$'},influences:array(influence,2),corrupted:boolean,twiceCorrupted:boolean,mirrored:boolean,destroyed:boolean,memoryStrands:integer(0,100),intangibility:integer(0,100),quality:integer(0,30),catalyst:integer(1,12),catalystQuality:integer(0,20),
  sockets:array(object({color:{enum:['R','G','B','W','A']},group:integer(0,6)},['color','group']),6),percentiles:object({Armour:number(0,1),Evasion:number(0,1),EnergyShield:number(0,1),Ward:number(0,1)}),
  corruptedImplicits:array(object({id:string(160),range:{oneOf:[number(0,1),array(number(0,1),20)]}},['id','range']),2),implicits:array(object({id:string(160),side:{enum:['Exarch','Eater']},tier:integer(1,6),range:{oneOf:[number(0,1),array(number(0,1),20)]}},['id','side','tier']),2),baseImplicitRanges:array({oneOf:[number(0,1),array(number(0,1),20)]},10),baseImplicit330:{enum:[true]},vendorImplicit:string(160),harvestEnchant:string(160),
  veil:object({type:{enum:['Prefix','Suffix']},choices:{type:'array',minItems:1,maxItems:3,items:string(160)}},['type','choices'])};
const craftingState=object({...craftingStateProperties,imprint:object(craftingStateProperties,['rarity','affixes'])},['rarity','affixes']);
const craftingInventory=journeyList(object({id:journeyId,title:string(120),slot:string(80),baseItem:string(24000),at:integer(0,4102444800),state:craftingState},['id','title','slot','baseItem','at','state']));
const craftingAction=object({method:{enum:craftingMethods},modId:string(160),enchantId:string(160),essenceId:string(200),tangledOutcome:string(200),fossils:{type:'array',minItems:1,maxItems:4,items:string(200)},tag:{enum:['attack','caster','physical','fire','cold','lightning','chaos','life','defences','speed','critical','influence','minion','elemental','attribute','mana','drop']},influence,donorItem:string(24000),selectedMods:object({left:{type:'array',minItems:1,maxItems:5,items:string(160)},right:{type:'array',minItems:1,maxItems:5,items:string(160)}},['left','right']),reportedSuccessChance:number(0,100),allflame:{oneOf:[object({auto:{const:true},upgradeTier:integer(0,2),choiceIndex:integer(1,4),preferredTargets:craftingTargets},['auto']),object({outcomes:integer(1,4),gainMin:integer(0,100),gainMax:integer(0,100),sulphur:integer(0,1e9),choiceIndex:integer(1,4),preferredTargets:craftingTargets},['outcomes','gainMin','gainMax','sulphur'])]},preferredMods:array(string(160),30),count:integer(1,6),catalyst:integer(1,12),linked:boolean,side:{enum:['Exarch','Eater']},tier:integer(1,4),from:{enum:['fire','cold','lightning']},to:{enum:['fire','cold','lightning']}},['method']);
const craftingItemStats=object(Object.fromEntries(["PhysicalDPS","ElementalDPS","ChaosDPS","TotalDPS","AttackRate","CritChance","Armour","Evasion","EnergyShield","Ward"].map(key=>[key,number(0,1e7)])));
const craftingRequirements=object({nativeStats:craftingItemStats,openPrefixes:integer(0,3),openSuffixes:integer(0,3),minAffixes:integer(0,6),maxAffixes:integer(0,6),minQuality:integer(0,30),minMemoryStrands:integer(0,100),maxMemoryStrands:integer(0,100),minFractured:integer(0,6),maxFractured:integer(0,6),minIntangibility:integer(0,100),maxIntangibility:integer(0,100),sockets:integer(0,6),links:integer(0,6),socketColours:{type:'string',pattern:'^[RGBW]{1,6}$'},linkedColours:boolean,harvestEnchant:string(160),corrupted:boolean});
const craftingRecipe=object({rarity:{enum:['MAGIC','RARE']},steps:{type:'array',minItems:1,maxItems:20,items:object({...craftingAction.properties,maxAttempts:integer(1,200),untilTargets:craftingTargets,untilRequirements:craftingRequirements,onSuccess:integer(1,21),onFailure:integer(1,21),onFailureAction:{enum:['route','stop','restart','salvage']},recoveryNotes:string(1000)},['method'])},targets:{...craftingTargets,minItems:0},requirements:craftingRequirements,requiredGroups:integer(0,6),initialState:craftingState},['steps','targets']);
const craftingPriceBook=object({currency:string(24),source:string(240),quotedAt:integer(0,4102444800),values:{type:'object',maxProperties:2000,additionalProperties:number(0,1e12)}},['currency','source','quotedAt','values']);
const craftingProjectSchema = object({preferredMethod:{enum:craftingMethods},id:{type:'string',pattern:'^[A-Za-z0-9_-]{1,64}$'},title:string(120),slot:string(80),startingItem:string(24000),targetItem:string(24000),
  priceBook:craftingPriceBook,nativeRecipe:craftingRecipe,inventory:craftingInventory,goals:array(string(300),12),steps:array(object({action:string(1000),stopWhen:string(500),onFailure:string(500),done:boolean},['action']),40),notes:string(8000),estimate:quoteSchema,simulatorExport:string(128000),
  simulation:object({patch:string(40),observedAt:integer(0,4102444800),trials:integer(1,1e9),successes:integer(0,1e9),notes:string(4000)},['patch','observedAt','trials','successes'])},['id','title','slot','startingItem','goals','steps']);
const operations = [
  object({type:{const:'set_character'},level:integer(1,100),className:string(40),ascendancy:string(40)},['type']),
  object({type:{const:'allocate_passives'},add:array(integer(1,1000000),200),remove:array(integer(1,1000000),200),
    masteries:array(object({nodeId:integer(1,1000000),effectId:integer(1,65535)},['nodeId','effectId']),50)},['type']),
  object({type:{const:'equip_item'},slot:string(80),text:string(24000),active:boolean},['type','slot','text']),
  object({type:{const:'set_skills'},mainGroup:integer(1,40),groups:array(object({label:string(120),slot:string(80),enabled:boolean,includeInFullDPS:boolean,
    mainActiveSkill:integer(1,12),gems:array(object({name:string(160),level:integer(1,40),quality:integer(0,100),enabled:boolean},['name']),12)},['gems']),40)},['type','groups']),
  object({type:{const:'set_config'},values:{type:'object',maxProperties:100,additionalProperties:{type:['string','number','boolean']}}},['type','values']),
  object({type:{const:'set_notes'},text:string(64000)},['type','text']),
  object({type:{const:'set_atlas_plan'},plan:atlasPlan},['type','plan']),
  object({type:{const:'set_build_journey'},journey:journeySchema},['type','journey']),
  object({type:{const:'set_loot_filters'},filters:lootFilters},['type','filters']),
  object({type:{const:'set_crafting_project'},project:craftingProjectSchema},['type','project']),
  object({type:{const:'remove_crafting_project'},projectId:{type:'string',pattern:'^[A-Za-z0-9_-]{1,64}$'}},['type','projectId']),
];
const metricNames = ['LifeUnreserved','EnergyShield','ManaUnreserved','CombinedDPS','FullDPS','TotalEHP','PhysicalMaximumHitTaken','ChaosMaximumHitTaken','RecoverySimulationSurvivalChance','RecoverySimulationDamageDPS','RecoverySimulationAttackUptime','ManaRegen','Speed','EffectiveMovementSpeedMod','FireResist','ColdResist','LightningResist','ChaosResist','Str','Dex','Int'];
const planSchema = object({goal:{enum:['balanced','boss_damage','mapping','survival','comfort']},budget:number(0,1e12),currency:quoteSchema.properties.currency,
  minimums:object(Object.fromEntries(metricNames.map(key => [key,number(-1e12,1e12)]))),notes:string(2000)},['goal']);
const proposalSchema = object({mode:{enum:['edit','new']},title:string(120),baseRevision:{type:'string',pattern:'^[a-f0-9]{40}$'},
  quote:quoteSchema,operations:{type:'array',minItems:1,maxItems:100,items:{oneOf:operations}}},['mode','title','baseRevision','operations']);

// Validate the same closed JSON schema advertised to clients, without an extra runtime dependency.
function validate(value,schema) {
  if (schema.oneOf) return schema.oneOf.filter(s => validate(value,s)).length === 1;
  if (schema.const !== undefined && value !== schema.const) return false;
  if (schema.enum && !schema.enum.includes(value)) return false;
  const type = value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value;
  if (schema.type) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!types.includes(type) && !(types.includes('integer') && Number.isInteger(value))) return false;
  }
  if (type === 'number' && (!Number.isFinite(value) || value < (schema.minimum ?? -Infinity) || value > (schema.maximum ?? Infinity))) return false;
  if (type === 'string' && (value.length > (schema.maxLength ?? Infinity) || schema.pattern && !new RegExp(schema.pattern).test(value))) return false;
  if (type === 'array' && (value.length < (schema.minItems ?? 0) || value.length > (schema.maxItems ?? Infinity) || value.some(v => !validate(v,schema.items)))) return false;
  if (type === 'object') {
    if (Object.keys(value).length > (schema.maxProperties ?? Infinity) || (schema.required ?? []).some(k => !Object.hasOwn(value,k))) return false;
    for (const [key,entry] of Object.entries(value)) {
      const member = schema.properties && Object.hasOwn(schema.properties,key) ? schema.properties[key] : undefined;
      if (member ? !validate(entry,member) : schema.additionalProperties === false || typeof schema.additionalProperties === 'object' && !validate(entry,schema.additionalProperties)) return false;
    }
  }
  return true;
}
const readOnly = {readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:false};
const tools = [
  {name:'measure_journey_upgrades',description:'Calculate each planned wishlist target against the exact current native build without applying it. Targets come from exact item text or linked crafting targets. Poll get_proposal_status for measured deltas, constraints and ratios per supplied resource. No currency conversion or measured benefit is assumed.',inputSchema:object({baseRevision:string(40)},['baseRevision']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'get_build_journey',description:'Read the saved roadmap, gear wishlist, leveling guide, actual resource ledger, reservations and explained next actions. Prices are user supplied. No live inventory or currency conversion is inferred.',inputSchema:object({}),annotations:readOnly},
  {name:'get_loot_filters',description:'Read kept build-owned loot-filter profiles and personal rules. Bundled NeverSink templates are pinned; there is no live economy feed. Use native preview tools to test rules before proposing changes.',inputSchema:object({}),annotations:readOnly},
  {name:'propose_loot_filters',description:'Propose replacement loot-filter profiles for native desktop review. Read and preserve existing profiles first. Apply keeps the candidate; build Save persists it. This tool never exports files or publishes account filters.',inputSchema:object({title:string(120),baseRevision:string(40),filters:lootFilters},['title','baseRevision','filters']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  ...['generate_loot_filter','test_loot_filter','export_loot_filter'].map(name=>({name,description:name==='generate_loot_filter'?'Queue generation of separate pickup rules from saved crafts, planned gear, gems, budget resources and Atlas plans. Returns a draft profile; propose_loot_filters is required to keep it.':name==='test_loot_filter'?'Queue deterministic drop evaluation. Sample uses exact PoE filter property names (BaseType, Class, ItemLevel, Fated etc). Missing or unsupported information returns unknown, never a certain hide.':'Queue compilation and return .filter text plus migration diagnostics. Returns text only: no files or account filters are written. Poll get_proposal_status and match the request ID.',inputSchema:object({baseRevision:string(40),profileId:string(64),profile:lootProfile,sample:lootSample},['baseRevision',...(name==='test_loot_filter'?['sample']:[])]),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}})),
  {name:'propose_journey_plan',description:'Propose a complete replacement of the build journey against the current revision. Read get_build_journey first and preserve existing entries and spending. Native validation rejects cycles and overspending. The user reviews the candidate and saves explicitly.',inputSchema:object({title:string(120),baseRevision:string(40),journey:journeySchema},['title','baseRevision','journey']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'get_atlas_plans',description:'Read named Atlas plans and bundled tree versions from the connected build, including the 3.30 Ruthless preview. Atlas allocations are separate from character passives and do not change character DPS/EHP. Build Save persists reviewed plans.',inputSchema:object({}),annotations:readOnly},
  {name:'search_atlas_nodes',description:'Queue search over pinned official Atlas node names and stat text. Select the exact version. Returns native IDs, links, positions and stats. Decorative mastery labels are excluded. Poll get_proposal_status and match the request ID.',inputSchema:object({baseRevision:{type:'string',pattern:'^[a-f0-9]{40}$'},version:atlasVersion,query:string(160),limit:integer(1,100)},['baseRevision','version','query']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'plan_atlas_tree',description:'Connect desired Atlas node IDs to an existing plan by deterministic shortest paths, optionally avoiding nodes. Targets are processed in order unless optimize=true compares bounded alternative orders. Neither mode guarantees a global optimum. Enforces supplied budget plus native granted points and connectivity, including gateways. Returns a separate draft and verbatim stat summary; cannot apply/save. Poll get_proposal_status and match its ID.',inputSchema:object({baseRevision:{type:'string',pattern:'^[a-f0-9]{40}$'},plan:atlasPlan,targets:array(integer(1,65535),30),avoid:array(integer(1,65535),300),optimize:boolean},['baseRevision','plan','targets']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'propose_atlas_plan',description:'Submit an Atlas plan for desktop review. Only Apply in PoB keeps it in the build, and an explicit Save persists it. Version-specific allocations must be connected and within the supplied progression budget. Atlas stats do not affect character calculations; no farming profit guarantees.',inputSchema:object({baseRevision:{type:'string',pattern:'^[a-f0-9]{40}$'},plan:atlasPlan},['baseRevision','plan']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'get_build_context',description:'Read the connected desktop build: revision, character, current gear, socket groups, passives, configuration, native stats and warnings. Enable Build proposals in PoB first.',inputSchema:object({}),annotations:readOnly},
  {name:'search_build_catalog',description:'Search the desktop build\'s native gems, passive nodes (including mastery effects), configuration choices or classes. Passive paths are recomputed during a proposal; IDs are tree-version specific.',
    inputSchema:object({kind:{enum:['gems','passives','config','classes']},query:string(160),limit:integer(1,50)},['kind','query']),annotations:readOnly},
  {name:'propose_build',description:'Calculate a new build or edits in PoB for desktop review. Use the latest baseRevision from get_build_context. set_skills replaces all active socket groups; allocate_passives adds native connecting paths and removes dependent nodes. No changes are applied or saved by this tool. Read get_proposal_status for calculated results and resolved gear/gems/tree. Only the desktop Apply button commits changes.',
    inputSchema:proposalSchema,annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'get_proposal_status',description:'Read proposal status, calculated before/after stats, native warnings and review instructions. It cannot apply a proposal. Match the returned proposal ID to your queued request before consuming its result.',inputSchema:object({}),annotations:readOnly},
  {name:'get_build_analysis',description:'Read native assumption checks, equipment/gem dependencies and encounter death evidence from the connected build. Diagnosis separates observations from suggested paired tests.',inputSchema:object({}),annotations:readOnly},
  {name:'get_build_history',description:'Read up to eight calculated candidates retained in this desktop session, current goals and undo depth. Choosing or restoring one requires the desktop UI.',inputSchema:object({}),annotations:readOnly},
  {name:'get_build_connection',description:'Diagnose the desktop connection even when disabled or stale: heartbeat age, context refresh, last request/error and troubleshooting steps. This does not prove a particular AI client is connected.',inputSchema:object({}),annotations:readOnly},
  {name:'set_build_goals',description:'Set the desktop planning goal, optional budget/currency and minimum native stats. Goals rank calculated candidates using weighted percentage changes. Supplied dated total-price quotes are estimates, not live trade prices.',inputSchema:planSchema,annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'compare_build_candidates',description:'Calculate 1-5 alternative proposals against the same base, with stat deltas, dependency checks, goal ranking and optional supplied total-cost quotes. Candidates remain unapplied. Review/select in desktop Candidates. Keep encounter assumptions fixed for meaningful comparisons.',
    inputSchema:object({baseRevision:proposalSchema.properties.baseRevision,candidates:{type:'array',minItems:1,maxItems:5,items:proposalSchema}},['baseRevision','candidates']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'plan_leveling_build',description:'Calculate 1-8 increasing level milestones from the current build. Stage operations accumulate; set_skills must include the complete links at that stage. Supply level-appropriate gems/gear/passives; native checks expose unmet requirements. Each stage is a reviewable candidate, never automatically applied. For a fresh character first create/apply a starting build.',
    inputSchema:object({baseRevision:proposalSchema.properties.baseRevision,stages:{type:'array',minItems:1,maxItems:8,items:object({title:string(120),level:integer(1,100),operations:array({oneOf:operations.filter(op => op.properties.type.const !== 'set_character')},50),quote:quoteSchema},['title','level','operations'])}},['baseRevision','stages']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'get_crafting_projects',description:'Read crafting projects saved with the connected build: starting item, target modifiers, steps, stop/failure routes, supplied costs and external simulation evidence. Native simulation recipes can be saved with each project; external Craft of Exile results remain supplied data.',inputSchema:object({}),annotations:readOnly},
  {name:'inspect_crafting_item',description:'Queue native item-editor modifier lookup and a documented Craft of Exile import handoff. Provide exactly one equipped slot or itemText. Poll get_proposal_status for inspected results. Spawn weights are not probabilities; use native calculation/simulation and read the method coverage. This never changes the build.',
    inputSchema:object({baseRevision:proposalSchema.properties.baseRevision,slot:string(80),itemText:string(24000),query:string(160),limit:integer(1,100),action:craftingAction,initialState:craftingState},['baseRevision']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'propose_crafting_plan',description:'Propose a structured crafting project for native desktop review. Goals, steps, stop conditions, failure routes and supplied estimates stay with the build when explicitly saved. Optionally preview target equipment with equipTarget. A target item is a hypothetical outcome, not proof the recipe can craft it. Use nativeRecipe for our built-in simulator. Record external simulation results as supplied evidence.',
    inputSchema:object({baseRevision:proposalSchema.properties.baseRevision,project:craftingProjectSchema,equipTarget:boolean},['baseRevision','project']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'apply_crafting_action',description:'Emulate one native crafting action on a separate item. It cannot change the desktop build. Provide exactly one slot or itemText, and optionally a returned initialState with the same original itemText to continue a sequence. inspect_crafting_item supplies native modifier, bench and essence IDs. Unsupported mechanics fail explicitly. Results can become target items in a reviewed crafting plan.',
    inputSchema:object({baseRevision:proposalSchema.properties.baseRevision,slot:string(80),itemText:string(24000),action:craftingAction,seed:integer(1,2147483646),initialState:craftingState},['baseRevision','action']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'cancel_crafting_simulation',description:'Cancel the active crafting simulation or fossil optimizer whose requestId you supply. This cannot cancel a different desktop job or apply a build.',inputSchema:object({requestId:string(80)},['requestId']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'calculate_crafting',description:'Enumerate finite outcomes for next-affix draws, Talisman fractures and finite Ducat transitions, including Allflame choices. Exact only under the stated transition and selection assumptions. Socket bench crafts and Omen of Connections use one deterministic result, including property conditions. Other actions, roll thresholds, property conditions and partial target-group counts use bounded sampling with a reported interval. This runs as a cancellable job and cannot alter a build.',inputSchema:object({baseRevision:proposalSchema.properties.baseRevision,itemText:string(24000),slot:string(80),action:craftingAction,targets:{...craftingTargets,minItems:0},initialState:craftingState,options:object({trials:integer(1,2000),seed:integer(1,2147483646),requirements:craftingRequirements,requiredGroups:integer(0,6)})},['baseRevision','action','targets']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'optimize_crafting_fossils',description:'Sample every combination of 1-4 sockets from 1-8 supplied candidate fossils, bounded to 20000 total trials. Returns success intervals and supplied cost comparisons. This is exhaustive only over that subset, not a global optimality guarantee. Fossil and resonator prices can be supplied individually or as a saved priceBook. Explicit prices override book resource quotes; actionPrices override only their exact action keys. Inspection and subset results expose priceKey.',inputSchema:object({baseRevision:proposalSchema.properties.baseRevision,itemText:string(24000),slot:string(80),targets:{...craftingTargets,minItems:0},options:object({requirements:craftingRequirements,requiredGroups:integer(0,6),fossils:{type:'array',minItems:1,maxItems:8,items:string(200)},maxSockets:integer(1,4),initialState:craftingState,trials:integer(1,2000),seed:integer(1,2147481646),prices:{type:'object',maxProperties:100,additionalProperties:number(0,1e12)},actionPrices:{type:'object',maxProperties:100,additionalProperties:number(0,1e12)},priceBook:craftingPriceBook,currency:string(24)},['fossils'])},['baseRevision','targets','options']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
  {name:'simulate_crafting',description:'A saved priceBook supplies common-unit resource quotes; explicit prices override those resource quotes. actionPrices price only matching action keys, without changing ingredient quotes for other steps. Use method names for simple actions, priceKey from inspection, or stepPriceKeys from simulation results. Run native seeded Monte Carlo trials of a bounded recipe. Target groups default to AND, with optional requiredGroups, counts, exclusions, minimum normalized rolls and property conditions. Steps can repeat untilTargets, then route onSuccess/onFailure. Stop at final targets or action budget. Runs as a cancellable native background job; return modeled success frequency, Wilson interval, spending, missing prices and transition errors. resourceUsage lists modeled ingredient quantities and service uses across all trials, independent of price overrides; currencySpent retains legacy costing buckets. All supplied prices and optional baseCost must use one currency. retainSuccesses retains up to 100 successful item states; affix and property distributions cover final trial states. Limits and distribution assumptions are part of the result; this is not a complete game engine.',
    inputSchema:object({baseRevision:proposalSchema.properties.baseRevision,slot:string(80),itemText:string(24000),recipe:craftingRecipe,options:object({trials:integer(1,2000),maxActions:integer(1,2000),baseCost:number(0,1e12),retainSuccesses:integer(0,100),seed:integer(1,2147483646),prices:{type:'object',maxProperties:100,additionalProperties:number(0,1e12)},actionPrices:{type:'object',maxProperties:100,additionalProperties:number(0,1e12)},priceBook:craftingPriceBook,currency:string(24)})},['baseRevision','recipe']),annotations:{...readOnly,readOnlyHint:false,idempotentHint:false}},
];

function createBridge(reportPath, clientName = () => "MCP client") {
  const filename = name => path.join(path.dirname(reportPath || '.'),`AI-build-${name}.json`);
  const retryDelay = new Int32Array(new SharedArrayBuffer(4));
  function read(name) {
    const file = filename(name);
    // The native desktop may be refreshing this file. Retry brief incomplete reads.
    for (let attempt=0; ; attempt++) {
      try {
        if (fs.statSync(file).size > 16 * 1024 * 1024) throw new Error('Desktop build data exceeds the supported size.');
        return JSON.parse(fs.readFileSync(file,'utf8'));
      } catch (err) {
        if (attempt >= 4 || !(err instanceof SyntaxError || ['ENOENT','EBUSY'].includes(err.code))) throw err;
        Atomics.wait(retryDelay,0,0,5);
      }
    }
  }
  function state() {
    let result;
    try { result = read('state'); } catch (_) { throw new Error('Enable Build proposals in PoB > Simulation > AI tools first.'); }
    if (result.schemaVersion !== 1 || !result.enabled || typeof result.session !== 'string' || !Number.isFinite(result.heartbeat) || Math.abs(Date.now()/1000-result.heartbeat) > (result.proposal?.status === 'calculating' ? 120 : 15)) {
      throw new Error('Desktop connection is disabled or not responding. Open the build in PoB and enable Build proposals.');
    }
    return result;
  }
  let contextRead;
  function contact(current, readContext = false) {
    if (!current.enabled || typeof current.session !== 'string') return;
    const name=String(clientName() || 'MCP client').replace(/[\x00-\x1f]/g,' ').slice(0,80);
    if (readContext) contextRead={session:current.session,revision:current.revision};
    const record={schemaVersion:1,contextRevision:contextRead?.session===current.session ? contextRead.revision : undefined,session:current.session,name,seenAt:Date.now()/1000,revision:current.revision,testNonce:current.connectionTest?.nonce};
    fs.writeFileSync(filename('client'),JSON.stringify(record));
  }
  return function call(name,args) {
    const tool = tools.find(t => t.name === name);
    if (!tool || !validate(args ?? {},tool.inputSchema)) throw new Error('Invalid build tool arguments. Follow the advertised schema.');
    if (name === 'get_build_connection') {
      let current;
      try { current = read('state'); } catch (_) { return {status:'unavailable',steps:['Open a build in PoB > AI builds.','Enable build proposals.','Copy MCP configuration into your AI client and reconnect.']}; }
      contact(current);
      const heartbeatAgeSeconds = Number.isFinite(current.heartbeat) ? Math.max(0,Date.now()/1000-current.heartbeat) : null;
      const calculating = current.proposal?.status === 'calculating';
      return {status:current.schemaVersion !== 1 ? 'incompatible' : !current.enabled ? 'disabled' : heartbeatAgeSeconds === null || heartbeatAgeSeconds > (calculating ? 120 : 15) ? 'stale' : calculating ? 'calculating' : 'ready',heartbeatAgeSeconds,
        session:current.session,revision:current.revision,proposalStatus:current.proposal?.status,diagnostics:current.diagnostics,
        steps:['Keep PoB open and wait for calculations to finish.','Enable build proposals, then reconnect your AI client if tools are missing.','A ready desktop heartbeat does not verify that your AI client is connected.']};
    }
    if (name === 'propose_loot_filters') {
      args={mode:'edit',title:args.title,baseRevision:args.baseRevision,operations:[{type:'set_loot_filters',filters:args.filters}]};
      name='propose_build';
    }
    if (name === 'propose_journey_plan') {
      args={mode:'edit',title:args.title,baseRevision:args.baseRevision,operations:[{type:'set_build_journey',journey:args.journey}]};
      name='propose_build';
    }
    if (name === 'propose_atlas_plan') {
      args={mode:'edit',title:args.plan.title,baseRevision:args.baseRevision,operations:[{type:'set_atlas_plan',plan:args.plan}]};
      name='propose_build';
    }
    if (name === 'propose_crafting_plan') {
      const project=args.project;
      if (project.simulation && project.simulation.successes > project.simulation.trials) throw new Error('Simulation successes cannot exceed trials.');
      if (args.equipTarget && !project.targetItem?.trim()) throw new Error('A target item is required for equipment preview.');
      args={mode:'edit',title:project.title,baseRevision:args.baseRevision,operations:[{type:'set_crafting_project',project},...(args.equipTarget ? [{type:'equip_item',slot:project.slot,text:project.targetItem}] : [])]};
      name='propose_build';
    }
    const current = state();
    contact(current);
    if (name === 'get_build_history') return {history:current.history ?? [],plan:current.plan,undoDepth:current.diagnostics?.undoDepth ?? 0};
    if (name === 'get_proposal_status') return {session:current.session,revision:current.revision,proposal:current.proposal ?? null};
    const captured = read('context');
    if (captured.schemaVersion !== 1 || captured.session !== current.session || captured.context?.revision !== current.revision) throw new Error('Desktop context is refreshing. Try again after calculations finish.');
    if (name === 'get_atlas_plans') return {revision:current.revision,plans:captured.context.atlasPlans ?? [],versions:captured.context.atlasVersions ?? [],warning:captured.context.atlasWarning,limitations:['Atlas plans are separate from character calculations.','Budgets are supplied progression. No account completion or live farming profit is inferred.']};
    if (name === 'get_crafting_projects') return {revision:current.revision,projects:captured.context.craftingProjects ?? [],warning:captured.context.craftingWarning,limitations:['Plans and cost/simulation results are supplied data, not independently verified recipes.','Use desktop review before applying; build Save persists projects.']};
    if (name === 'get_build_journey') return {revision:current.revision,journey:captured.context.journey,budget:captured.context.journeyBudget,nextActions:captured.context.nextActions,warning:captured.context.journeyWarning};
    if (name === 'get_loot_filters') return {revision:current.revision,filters:captured.context.lootFilters,warning:captured.context.lootFilterWarning};
    if (name === 'get_build_analysis') return {revision:current.revision,capturedAt:captured.capturedAt,audit:captured.context.audit,encounter:captured.context.encounter,plan:current.plan};
    if (name === 'get_build_context') {
      contact(current,true);
      const {xml,...context} = captured.context;
      return {session:current.session,capturedAt:captured.capturedAt,context};
    }
    if (name === 'search_build_catalog') {
      const query = args.query.toLocaleLowerCase();
      const entries = captured.catalog?.[args.kind];
      if (!Array.isArray(entries)) throw new Error('Catalog unavailable. Refresh the desktop connection.');
      const matches = entries.filter(entry => JSON.stringify(entry).toLocaleLowerCase().includes(query));
      return {revision:current.revision,kind:args.kind,total:matches.length,matches:matches.slice(0,args.limit ?? 20)};
    }
    if (current.proposal?.status === 'review' || current.proposal?.status === 'calculating' && name !== 'cancel_crafting_simulation') throw new Error('Review or reject the pending proposal in PoB first.');
    if (!['set_build_goals','cancel_crafting_simulation'].includes(name) && args.baseRevision !== current.revision) throw new Error('Build revision changed. Read get_build_context and submit a fresh proposal.');
    if (['inspect_crafting_item','apply_crafting_action','simulate_crafting','calculate_crafting','optimize_crafting_fossils'].includes(name) && Number(Boolean(args.slot)) + Number(Boolean(args.itemText)) !== 1) throw new Error('Provide exactly one slot or itemText.');
    if (['simulate_crafting','optimize_crafting_fossils'].includes(name) && (args.options?.prices || args.options?.actionPrices) && !(args.options.currency ?? args.options.priceBook?.currency)?.trim()) throw new Error('Specify one price currency.');
    if (name === 'simulate_crafting') {
      if ((args.options?.trials ?? 200)*(args.options?.maxActions ?? 100) > 20000) throw new Error('Use at most 20000 total budgeted actions.');
      for (const step of args.recipe.steps) {
        if ((step.maxAttempts ?? 1) > 1 && !step.untilTargets && !step.untilRequirements) throw new Error('Repeated steps need target conditions.');
        if ((step.onSuccess ?? 1) > args.recipe.steps.length+1 || (step.onFailure ?? 1) > args.recipe.steps.length+1) throw new Error('Invalid recipe route.');
      }
    }
    const proposals = name === 'compare_build_candidates' ? args.candidates : name === 'plan_leveling_build' ? args.stages : name === 'propose_build' ? [args] : [];
    let nodeCount=0,operationCount=0,priorLevel=0;
    for (const proposal of proposals) {
      if (!proposal.title.trim() || /[\x00-\x1f\x7f]/.test(proposal.title)) throw new Error('Proposal title must be a nonempty single line.');
      if (name === 'compare_build_candidates' && proposal.baseRevision !== current.revision) throw new Error('Every candidate must use the current base revision.');
      if (name === 'plan_leveling_build') {
        if (proposal.level <= priorLevel) throw new Error('Milestone levels must increase.');
        priorLevel=proposal.level;
        operationCount+=proposal.operations.length;
        if (operationCount > 99) throw new Error('Use at most 99 cumulative milestone operations.');
      }
      if (proposal.quote && (proposal.quote.quotedAt > Date.now()/1000+300 || !proposal.quote.source.trim())) throw new Error('Price quotes need a source and a valid capture time.');
      nodeCount+=proposal.operations.reduce((n,op) => n+(op.add?.length ?? 0)+(op.remove?.length ?? 0)+(op.masteries?.length ?? 0),0);
    }
    if (nodeCount > 400) throw new Error('Use at most 400 passive changes per request.');
    if (name === 'set_build_goals' && args.budget !== undefined && !args.currency) throw new Error('Budget needs a currency.');
    const id = randomUUID();
    const payload = ['generate_loot_filter','test_loot_filter','export_loot_filter'].includes(name) ? {kind:name,...args} : name === 'measure_journey_upgrades' ? {kind:'journeyUpgrades',...args} : name === 'cancel_crafting_simulation' ? {kind:'craftCancel',...args} : name === 'calculate_crafting' ? {kind:'craftCalculate',...args} : name === 'optimize_crafting_fossils' ? {kind:'craftOptimize',...args} : name === 'search_atlas_nodes' ? {kind:'atlasSearch',...args} : name === 'plan_atlas_tree' ? {kind:'atlasConnect',...args} : name === 'apply_crafting_action' ? {kind:'craftAction',...args} : name === 'simulate_crafting' ? {kind:'craftSimulate',...args} : name === 'inspect_crafting_item' ? {kind:'craftInspect',...args} : name === 'set_build_goals' ? {kind:'plan',plan:args} : name === 'compare_build_candidates' ? {kind:'compare',...args} : name === 'plan_leveling_build' ? {kind:'leveling',...args} : {proposal:args};
    const request = JSON.stringify({id,session:current.session,...payload});
    if (Buffer.byteLength(request) > 262144) throw new Error('Proposal exceeds 256 KiB.');
    const temporary = filename(`request-${id}`);
    try {
      fs.writeFileSync(temporary,request,{flag:'wx'});
      // Publish a complete file exclusively; the desktop cannot read a half-written request.
      fs.linkSync(temporary,filename('request'));
    } catch (err) {
      if (err.code === 'EEXIST') throw new Error('A proposal is already queued. Wait for PoB to process it.');
      throw err;
    } finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
    return {id,status:'queued',instructions:'PoB will process this planning request separately. Poll get_proposal_status and match this request ID, then review it in PoB > AI tools > Build proposals. Nothing has been applied or saved.'};
  };
}
module.exports = {tools,createBridge,validate};
