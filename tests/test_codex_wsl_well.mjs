import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createTools } from '../.agents/harness/codex/tools.mjs';

test('explicit WSL route starts service, verifies store and uses Linux CLI', async t => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'well-route-'));
  t.after(() => fs.rmSync(tmp,{recursive:true,force:true}));
  const shim=path.join(tmp,'wsl'), log=path.join(tmp,'log');
  fs.writeFileSync(shim, '#!/bin/sh\nprintf "%s\\n" "$*" >> "$WSL_LOG"\ncase "$*" in *"realpath -e -- /chosen/home/hodd/memory/kaia.engram"*) printf "%s" "${WSL_REAL_STORE:-/chosen/home/hodd/memory/kaia.engram}";; *"realpath -e -- /chosen/home"*) printf "/chosen/home";; *curl*) printf "%s" "$WSL_HEALTH";; *) printf "route-ok\\n";; esac\n', {mode:0o755});
  let store='/chosen/home/hodd/memory/kaia.engram';
  const env={...process.env,YMIR_CODEX_WELL_ROUTE:'wsl', YMIR_WSL:shim, WSL_LOG:log,
    YMIR_WSL_DISTRO:'Synthetic', YMIR_WSL_WELL_ROOT:'/chosen/code', YMIR_WSL_WELL_HOME:'/chosen/home',
    YMIR_WSL_WELL_STORE:store, WSL_HEALTH:JSON.stringify({status:'up',store})};
  const tools=createTools({root:process.cwd(),home:tmp,env});
  assert.equal(await tools.call('ymir_recall',{query:'sentinel',limit:2}),'route-ok');
  assert.equal(await tools.call('ymir_remember',{lesson:'sentinel'}),'route-ok');
  let rows=fs.readFileSync(log,'utf8').trim().split('\n');
  assert.equal(rows.length,16);
  assert.match(rows[5], /systemctl --user start mimir\.service/);
  assert.match(rows[6], /curl -fsS --max-time 2/);
  assert.match(rows[7], /YMIR_HOME=\/chosen\/home/);
  assert.match(rows[7], /ENGRAM_DB=\/chosen\/home\/hodd\/memory\/kaia\.engram/);
  assert.match(rows[7], /MIMIR_REQUIRE_BRIDGE=1/);
  assert.match(rows[7], /MIMIR_EXPECTED_STORE=\/chosen\/home\/hodd\/memory\/kaia\.engram/);
  assert.match(rows[7], /recall sentinel --k 2/);
  assert.match(rows[15], /observe sentinel/);
  const mismatch=createTools({root:process.cwd(),home:tmp,env:{...env,WSL_HEALTH:JSON.stringify({status:'up',store:'/different/store'})}});
  await assert.rejects(mismatch.call('ymir_remember',{lesson:'must-not-write'}),/does not match/);
  rows=fs.readFileSync(log,'utf8').trim().split('\n');
  assert.equal(rows.length,23, 'mismatched store must not execute memory CLI');
  const noStore=createTools({root:process.cwd(),home:tmp,env:{...env,YMIR_WSL_WELL_STORE:''}});
  await assert.rejects(noStore.call('ymir_recall',{query:'x'}),/YMIR_WSL_WELL_STORE/);
  assert.equal(fs.readFileSync(log,'utf8').trim().split('\n').length,23);
  const wrongHome=createTools({root:process.cwd(),home:tmp,env:{...env,YMIR_WSL_WELL_HOME:'/another/home'}});
  await assert.rejects(wrongHome.call('ymir_recall',{query:'x'}),/must belong/);
  assert.equal(fs.readFileSync(log,'utf8').trim().split('\n').length,23);
  const escape=createTools({root:process.cwd(),home:tmp,env:{...env,WSL_REAL_STORE:'/outside/store'}});
  await assert.rejects(escape.call('ymir_recall',{query:'x'}),/resolves outside/);
  assert.equal(fs.readFileSync(log,'utf8').trim().split('\n').length,28);
  const remote=createTools({root:process.cwd(),home:tmp,env:{...env,MIMIRSBRUNN_URL:'http://example.com'}});
  await assert.rejects(remote.call('ymir_recall',{query:'x'}),/loopback/);
  const configFile=path.join(tmp,'hodd/data/codex-well.json');
  const requiredFile=path.join(tmp,'hodd/data/codex-well.required');
  fs.mkdirSync(path.dirname(configFile),{recursive:true});
  fs.writeFileSync(requiredFile,'');
  fs.writeFileSync(configFile,JSON.stringify({route:'wsl',distro:'Synthetic',root:'/chosen/code',home:'/chosen/home',store:env.YMIR_WSL_WELL_STORE}));
  const fromFile=createTools({root:process.cwd(),home:tmp,env:{...process.env,YMIR_WSL:shim,WSL_LOG:log,WSL_HEALTH:env.WSL_HEALTH}});
  assert.equal(await fromFile.call('ymir_well',{action:'stats'}),'route-ok');
  assert.match(fs.readFileSync(log,'utf8'),/MIMIR_REQUIRE_BRIDGE=1.*health/);
  const countBefore=fs.readFileSync(log,'utf8').trim().split('\n').length;
  fs.writeFileSync(configFile,'{"route":"wsl","unexpected":"value"}');
  await assert.rejects(fromFile.call('ymir_recall',{query:'x'}),/invalid codex-well.json fields/);
  assert.equal(fs.readFileSync(log,'utf8').trim().split('\n').length,countBefore);
  fs.writeFileSync(configFile,'not-json');
  await assert.rejects(fromFile.call('ymir_recall',{query:'x'}),/invalid codex-well.json/);
  fs.unlinkSync(configFile);
  await assert.rejects(fromFile.call('ymir_recall',{query:'x'}),/configuration is missing/);
  fs.writeFileSync(configFile,JSON.stringify({route:'local'}));
  await assert.rejects(fromFile.call('ymir_recall',{query:'x'}),/requires the WSL route/);
  fs.unlinkSync(configFile);
  fs.unlinkSync(requiredFile);
  fs.symlinkSync(path.join(tmp,'missing-marker-target'),requiredFile);
  await assert.rejects(fromFile.call('ymir_recall',{query:'x'}));
  fs.unlinkSync(requiredFile);
  fs.writeFileSync(shim, '#!/bin/sh\nprintf "%s\\n" "$*" >> "$WSL_LOG"\ncase "$*" in *"test -d /nonexistent"*) exit 6;; *) printf "ok\\n";; esac\n', {mode:0o755});
  const missingHome=createTools({root:process.cwd(),home:tmp,env:{...env,YMIR_WSL_WELL_HOME:'/nonexistent',YMIR_WSL_WELL_STORE:'/nonexistent/well.db'}});
  await assert.rejects(missingHome.call('ymir_recall',{query:'x'}),/WSL well command failed/);
  assert.equal(fs.readFileSync(log,'utf8').trim().split('\n').length,countBefore+1);
  fs.writeFileSync(shim, '#!/bin/sh\nprintf "%s\\n" "$*" >> "$WSL_LOG"\ncase "$*" in *"realpath -e -- /chosen/home/hodd/memory/kaia.engram"*) printf "/chosen/home/hodd/memory/kaia.engram";; *"realpath -e -- /chosen/home"*) printf "/chosen/home";; *systemctl*) exit 7;; *) printf "ok\\n";; esac\n', {mode:0o755});
  store=env.YMIR_WSL_WELL_STORE;
  await assert.rejects(tools.call('ymir_remember',{lesson:'must-not-write'}),/WSL well command failed/);
  assert.equal(fs.readFileSync(log,'utf8').trim().split('\n').length,countBefore+7);
});

test('required bridge never writes or reads the local fallback on connection failure', () => {
  const home=fs.mkdtempSync(path.join(os.tmpdir(),'well-required-'));
  try {
    const env={...process.env,YMIR_HOME:home,MIMIR_REQUIRE_BRIDGE:'1',MIMIRSBRUNN_URL:'http://127.0.0.1:1'};
    const script=path.join(process.cwd(),'bin/records/mimir.sh');
    for (const args of [['recall','sentinel'],['observe','sentinel'],['health']]) {
      const r=spawnSync('bash',[script,...args],{env,encoding:'utf8'});
      assert.notEqual(r.status,0,`${args[0]} must fail`);
      assert.match(r.stderr,/selected well bridge/);
      assert.equal(fs.existsSync(path.join(home,'hodd/memory/well/episodes.jsonl')),false);
    }
  } finally { fs.rmSync(home,{recursive:true,force:true}); }
});

test('required bridge keeps a valid empty response separate from a local log', () => {
  const home=fs.mkdtempSync(path.join(os.tmpdir(),'well-empty-'));
  try {
    const bin=path.join(home,'bin'); fs.mkdirSync(bin);
    fs.writeFileSync(path.join(bin,'curl'), '#!/bin/sh\ncase "$*" in */health*) printf "%s" "$FAKE_HEALTH";; *) printf "{\\"results\\":[]}";; esac\n', {mode:0o755});
    const log=path.join(home,'hodd/memory/well/episodes.jsonl'); fs.mkdirSync(path.dirname(log),{recursive:true});
    fs.writeFileSync(log,JSON.stringify({content:'sentinel local',source:'test'})+'\n');
    const env={...process.env,YMIR_HOME:home,MIMIR_REQUIRE_BRIDGE:'1',MIMIR_EXPECTED_STORE:'/chosen/store',FAKE_HEALTH:JSON.stringify({status:'up',store:'/chosen/store'}),PATH:bin+path.delimiter+process.env.PATH};
    const script=path.join(process.cwd(),'bin/records/mimir.sh');
    const r=spawnSync('bash',[script,'recall','sentinel'],{env,encoding:'utf8'});
    assert.equal(r.status,0,r.stderr);
    assert.match(r.stdout,/recall\[0\]/);
    assert.match(r.stdout,/retrieval: bridge/);
    assert.doesNotMatch(r.stdout,/sentinel local/);
    const wrong=spawnSync('bash',[script,'observe','sentinel'],{env:{...env,MIMIR_EXPECTED_STORE:'/wrong/store'},encoding:'utf8'});
    assert.notEqual(wrong.status,0);
    assert.match(wrong.stderr,/selected well bridge/);
    assert.equal(fs.readFileSync(log,'utf8'),JSON.stringify({content:'sentinel local',source:'test'})+'\n');
  } finally { fs.rmSync(home,{recursive:true,force:true}); }
});
