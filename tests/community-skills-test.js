/* Test community downloads and imports with synthetic packages and no network.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";
const assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const {createHash} = require('node:crypto');
const {deflateRawSync} = require('node:zlib');
const {crc32} = require('../core/skill-zip');
const {SkillStore} = require('../core/skill-store');
const {run, validateFeed, download, FEED} = require('../core/community-skills');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'community-test-'));
function zip(records, file = path.join(root, "skill.zip")) {
  const locals = [], central = []; let offset = 0;
  for (const record of records) {
    const bytes = Buffer.from(record.text || ""), name = Buffer.from(record.name), method = record.method ?? 8;
    const data = method === 0 ? bytes : deflateRawSync(bytes), flags = record.flags ?? 0x800;
    const checksum = record.crc ?? crc32(bytes), expanded = record.expanded ?? bytes.length;
    const local = Buffer.alloc(30); local.writeUInt32LE(0x04034b50); local.writeUInt16LE(20, 4); local.writeUInt16LE(flags, 6); local.writeUInt16LE(method, 8);
    local.writeUInt32LE(checksum, 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(expanded, 22); local.writeUInt16LE(name.length, 26);
    const directory = Buffer.alloc(46); directory.writeUInt32LE(0x02014b50); directory.writeUInt16LE(0x314, 4); directory.writeUInt16LE(20, 6);
    directory.writeUInt16LE(flags, 8); directory.writeUInt16LE(method, 10); directory.writeUInt32LE(checksum, 16); directory.writeUInt32LE(data.length, 20); directory.writeUInt32LE(expanded, 24); directory.writeUInt16LE(name.length, 28); directory.writeUInt32LE(record.attributes ?? 0, 38); directory.writeUInt32LE(offset, 42);
    locals.push(local, name, data); central.push(directory, name); offset += 30 + name.length + data.length;
  }
  const directory = Buffer.concat(central), end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50); end.writeUInt16LE(records.length, 8); end.writeUInt16LE(records.length, 10); end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
  fs.writeFileSync(file, Buffer.concat([...locals, directory, end])); return file;
}
async function main() {
 const store = new SkillStore({root:path.join(root,'store'), builtinRoot:path.join(root,'builtin'),clientRoots:{codex:path.join(root,'client')}});
 const manifest={schemaVersion:1,title:'Example skill',author:'Example Author',version:'1.0.0',source:'Community Skills'};
 const makeZip = (name='example-skill') => fs.readFileSync(zip([{name:'SKILL.md',text:`---\nname: ${name}\ndescription: Example workflow.\n---\nInstructions only.\n`},{name:'skill.json',text:JSON.stringify(manifest)}]));
 let archive=makeZip();
 let entry={id:'example-skill',name:'example-skill',title:manifest.title,description:'Example workflow.',author:manifest.author,version:manifest.version,downloadUrl:'https://github.com/maxpkg-dev/max-ultra-mcp-community-skills/releases/download/example-skill-v1.0.0/example-skill.zip',sha256:createHash('sha256').update(archive).digest('hex'),sizeBytes:archive.length};
 let requests=[];
 const fetch=async(url,limit)=>{requests.push(url);return url===FEED?Buffer.from(JSON.stringify({schemaVersion:1,skills:[entry]})):url.startsWith('https://api.github.com/')?Buffer.from(JSON.stringify([{tag_name:entry.id+'-v'+entry.version,published_at:'2026-06-13T12:00:00Z',draft:false,prerelease:false}])):archive;};
 assert.equal((await run('community-list',[],store,fetch)).community[0].installState,'available');
 assert.ok(requests.every(url => url === FEED || url.startsWith('https://api.github.com/repos/maxpkg-dev/max-ultra-mcp-community-skills/releases?')), 'listing never downloads or installs a package');
 const args=()=>[entry.id,entry.version,entry.sha256];
 await assert.rejects(run('community-install',[entry.id,'0.9.0',entry.sha256],store,fetch),/catalog changed/);
 const original=archive;archive=Buffer.from('corrupt');
 await assert.rejects(run('community-install',args(),store,fetch),/checksum or size/);archive=original;
 assert.equal(store.registry().skills.length,0);
 const phases=[];
 const result=await run('community-install',args(),store,fetch,state=>phases.push(state));
 assert.deepEqual(phases.map(state=>state.phase),['catalog','download','verify','install']);
 assert.equal(phases[1].total,entry.sizeBytes);
 assert.equal(result.community[0].installState,'installed');
 const installed=result.skills[0];
 assert.equal(installed.publishedAt,'2026-06-13');
 assert.equal(result.community[0].publishedAt,'2026-06-13');
 const before=fs.readFileSync(path.join(store.packagePath(installed.id.slice(5)),'SKILL.md'));
 await assert.rejects(run('community-install',args(),store,fetch),/already installed/);
 assert.deepEqual(fs.readFileSync(path.join(store.packagePath(installed.id.slice(5)),'SKILL.md')),before);
 entry={...entry,version:'1.1.0'};
 assert.equal((await run('community-list',[],store,fetch)).community[0].installState,'different-version');
 const card=result.community[0];
 assert.equal(card.installedId,installed.id);
 await assert.rejects(run('community-delete',[installed.id,entry.id,'stale'],store,fetch),/changed/);
 await assert.rejects(run('community-delete',['bundled/example-skill',entry.id,card.installedRevision],store,fetch),/changed/);
 const record=store.registry().skills[0];const adapter=store.adapterPath(record,'codex');const originalAdapter=fs.readFileSync(adapter);
 fs.appendFileSync(adapter,'\nchanged');
 const incomplete=await run('community-delete',[installed.id,entry.id,card.installedRevision],store,fetch);
 assert.match(incomplete.message,/Removal incomplete/);
 assert.equal(incomplete.community[0].installedId,installed.id);
 assert.ok(fs.existsSync(adapter),'Edited adapter must not be deleted');
 fs.writeFileSync(adapter,originalAdapter);
 const deleted=await run('community-delete',[installed.id,entry.id,card.installedRevision],store,fetch);
 assert.equal(deleted.community[0].installState,'available');
 assert.equal(deleted.community[0].installedId,'');
 assert.ok(!fs.existsSync(adapter));
 const {ownedImport}=require('../core/community-skills');
 assert.equal(ownedImport(entry,[{...installed,source:'Built-in'}]),undefined);
 assert.equal(ownedImport(entry,[{...installed,author:'Someone else'}]),undefined);
 assert.equal(ownedImport(entry,[{...installed,displaySource:'Personal'}]),undefined);
 entry={...entry,version:'1.0.0'};
 archive=makeZip('wrong-name');entry={...entry,sha256:createHash('sha256').update(archive).digest('hex'),sizeBytes:archive.length};
 await assert.rejects(run('community-install',args(),store,fetch),/metadata does not match/);
 assert.equal(store.registry().skills.length,0);
 for(const change of [{downloadUrl:'https://example.com/skill.zip'},{sizeBytes:999999999},{sha256:'bad'},{name:'../escape'}]) assert.throws(()=>validateFeed({schemaVersion:1,skills:[{...entry,...change}]}));
 assert.throws(()=>validateFeed({schemaVersion:1,skills:[entry,entry]}));
 await assert.rejects(run('community-list',[],store,async()=>{throw Error('offline')}),/offline/);
 await assert.rejects(run('community-list',[],store,async()=>Buffer.from('broken')),/valid UTF-8 JSON/);
 assert.deepEqual(validateFeed({schemaVersion:1,skills:[]}),[]);
 await assert.rejects(download('http://127.0.0.1/private',10),/Unsafe/);
 // A valid hash never makes a malformed archive safe.
 archive=Buffer.alloc(30);entry={...entry,sha256:createHash('sha256').update(archive).digest('hex'),sizeBytes:archive.length};
 await assert.rejects(run('community-install',args(),store,fetch),/ZIP/);
 assert.equal(store.registry().skills.length,0);
 const {EventEmitter}=require('node:events');const {PassThrough}=require('node:stream');
 const responseRequest=(status,headers,body)=> (url,options,callback)=>{
   const req=new EventEmitter();req.setTimeout=()=>{};req.destroy=error=>{req.emit('error',error);req.emit('close');};
   process.nextTick(()=>{const response=new PassThrough();response.statusCode=status;response.headers=headers;callback(response);response.end(body);req.emit('close');});return req;
 };
 assert.equal((await download(FEED,20,responseRequest(200,{},'example'))).toString(),'example');
 const progress=[];
 await download(FEED,20,responseRequest(200,{},'example'),state=>progress.push(state));
 assert.deepEqual(progress.at(-1),{bytes:7,total:null});
 const known=[];
 await download(FEED,20,responseRequest(200,{'content-length':'7'},'example'),state=>known.push(state));
 assert.deepEqual(known.at(-1),{bytes:7,total:7});
 await assert.rejects(download(FEED,2,responseRequest(200,{},'oversized')),/size limit/);
 await assert.rejects(download(FEED,20,responseRequest(302,{location:'http://127.0.0.1/private'},'')),/Unsafe/);
 await assert.rejects(download(FEED,20,responseRequest(302,{location:FEED},'')),/redirects/);
 await assert.rejects(download(FEED,20,responseRequest(503,{},'')),/download failed/);
 const manifests=fs.readdirSync(path.join(__dirname,'../skills')).map(name=>JSON.parse(fs.readFileSync(path.join(__dirname,'../skills',name,'skill.json'),'utf8')));
 assert.ok(!manifests.every(item=>item.author==='Lukianenko Vasyl'),'Do not infer skill authorship from product copyright');
 assert.ok(manifests.some(item=>item.author?.includes('Anastasiia Reznichenko')));
 console.log('Community feed, click-only install, checksums, metadata, conflicts, offline and validation tests passed.');
}
main().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>fs.rmSync(root,{recursive:true,force:true}));
