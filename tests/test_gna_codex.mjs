import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { gnaArm, watchCommand, wslPath } from '../.agents/harness/codex/gna-arm.mjs';
test('Windows canonical watch always uses WSL Python and argument arrays', () => {
 const c=watchCommand({root:'C:\\repo path',home:'C:\\private',state:'C:\\private\\state',platform:'win32',env:{YMIR_WSL_DISTRO:'Ubuntu'}},'start');
 assert.equal(c.command,'wsl.exe');assert.deepEqual(c.args.slice(0,4),['-d','Ubuntu','--','env']);
 assert.ok(c.args.includes('YMIR_ENGINE_PYTHON=/usr/bin/python3'));
 assert.deepEqual(c.args.slice(-3),['bash','/mnt/c/repo path/bin/pi/syn-watch.sh','start']);
 assert.throws(()=>wslPath('relative'),/absolute/);
});
test('arm is bounded, status verified, event retained and wake not overstated', async t=>{
 const state=fs.mkdtempSync(path.join(os.tmpdir(),'gna-test-'));t.after(()=>fs.rmSync(state,{recursive:true,force:true}));
 fs.writeFileSync(path.join(state,'.arm.event'),'check: proof\n');const calls=[];
 const result=JSON.parse(await gnaArm({root:state,home:state,state,env:{CODEX_THREAD_ID:'thread-1'}},{},async(c,a,o)=>{calls.push({c,a,o});return {stdout:a.at(-1)==='status'?'idle daemon armed yes':''};}));
 assert.equal(calls.length,2);assert.equal(calls[0].a.at(-1),'start');assert.equal(calls[1].a.at(-1),'status');assert.equal(calls[0].o.timeout,30000);
 assert.equal(result.pendingEvent,'check: proof');assert.match(result.delivery,/does not prove wake/);assert.ok(fs.existsSync(path.join(state,'.arm.event')));
});
test('status is read-only and refuses unknown thread context',async()=>{
 await assert.rejects(gnaArm({env:{}},{}),/actual Codex thread/);
 const calls=[];await gnaArm({root:os.tmpdir(),home:os.tmpdir(),state:os.tmpdir(),env:{}},{action:'status',threadId:'thread-2'},async(c,a)=>{calls.push(a.at(-1));return {stdout:'idle'};});assert.deepEqual(calls,['status']);
});
