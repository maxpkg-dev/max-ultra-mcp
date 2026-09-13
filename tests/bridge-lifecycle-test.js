/*
 * Checks bridge admission, timeout ownership, framing, and bootstrap lifetime contracts without Max.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { MaxBridge } = require("../core/server");

async function run() {
  const bridge = new MaxBridge({ controlToken: "synthetic-test-token" });
  const writes = [];
  const socket = {
    writableLength: 0, destroyed: false,
    write(line) { writes.push(line); return false; },
    destroy() { this.destroyed = true; },
  };
  bridge.instances.set("mock-max-2027-1", { instanceId: "mock-max-2027-1", socket });
  const request = (...args) => bridge.request("mock-max-2027-1", ...args);
  await assert.rejects(request("execute", "x".repeat(4 * 1024 * 1024)), /REQUEST_TOO_LARGE/);
  assert.equal(writes.length, 0);

  socket.writableLength = 8 * 1024 * 1024;
  await assert.rejects(request("execute", "synthetic"), /BRIDGE_BUSY/);
  socket.writableLength = 0;
  assert.equal(bridge.pendingRequests.size, 0);

  const before = Date.now();
  const timedRequest = request("never", "", 30);
  const fields = writes[0].trim().split("\t");
  assert.equal(fields.length, 6);
  assert.ok(Number(fields[5]) >= before + 30);
  await assert.rejects(timedRequest, /already-running work may still complete/);
  assert.equal(bridge.pendingRequests.size, 0);
  assert.deepEqual(writes.map((line) => line.split("\t")[0]), ["REQUEST", "CANCEL"]);
  // Late replies cannot resolve another request or trigger a mutation replay.
  bridge.handleWireLine({ instanceId: "mock-max-2027-1", socket }, `RESPONSE\t${fields[1]}\tok\te30=`);
  assert.equal(writes.length, 2);

  const waiting = [];
  for (let index = 0; index < 64; index += 1) waiting.push(request("never", "", 10000).catch((error) => error));
  const admittedCount = writes.length;
  await assert.rejects(request("never", "", 10000), /BRIDGE_BUSY/);
  assert.equal(writes.length, admittedCount);
  assert.equal(bridge.pendingRequests.size, 64);
  for (const entry of bridge.pendingRequests.values()) {
    clearTimeout(entry.timeoutHandle);
    entry.reject(new Error("Synthetic fixture cleanup"));
  }
  bridge.pendingRequests.clear();
  await Promise.all(waiting);

  const largeWaiting = [request("never", "x".repeat(2 * 1024 * 1024), 10000).catch((error) => error),
    request("never", "x".repeat(2 * 1024 * 1024), 10000).catch((error) => error)];
  await assert.rejects(request("never", "x".repeat(2 * 1024 * 1024), 10000), /BRIDGE_BUSY/);
  assert.equal(bridge.pendingRequests.size, 2, "Byte budget must reject before the count limit");
  for (const entry of bridge.pendingRequests.values()) {
    clearTimeout(entry.timeoutHandle);
    entry.reject(new Error("Synthetic fixture cleanup"));
  }
  bridge.pendingRequests.clear();
  await Promise.all(largeWaiting);
  for (let index = 0; index < 256; index += 1) bridge.pendingRequests.set(String(index), { instanceId: "mock-other-instance" });
  await assert.rejects(request("never"), /BRIDGE_BUSY/);
  bridge.pendingRequests.clear();

  // Exercise the actual daemon parser, with no added network data after the second line.
  const received = [];
  bridge.handleWireLine = (_connection, line) => received.push(line);
  const connection = { buffer: "", socket };
  bridge.readConnectionData(connection, "FIRST\tpar");
  assert.deepEqual(received, []);
  bridge.readConnectionData(connection, "tial\nSECOND\tcomplete\nTHIRD");
  assert.deepEqual(received, ["FIRST\tpartial", "SECOND\tcomplete"]);
  assert.equal(connection.buffer, "THIRD");
  bridge.readConnectionData(connection, "\n" + "a".repeat(4 * 1024 * 1024) + "\nLAST\n");
  assert.equal(socket.destroyed, false, "The limit applies per frame, not per coalesced chunk");
  assert.equal(received.at(-1), "LAST");
  bridge.readConnectionData(connection, "a".repeat(4 * 1024 * 1024 + 1));
  assert.equal(socket.destroyed, true);

  // These are source contracts, not execution or native-stability proof for MAXScript.
  const source = fs.readFileSync(path.join(__dirname, "../01_START_MAX_ULTRA_MCP_FIRST.ms"), "utf8");
  const worker = source.slice(source.indexOf("fn transportDoWork"), source.indexOf("fn initializeIdentity"));
  assert.ok(source.includes('sessionLaunchCount: previousLaunchCount'));
  assert.ok(source.includes('return (mod (sessionLaunchCount - 1) 3) == 0'));
  const startBridge = source.slice(source.indexOf('fn startBridge = ('), source.indexOf('bridgeClient = MaxUltraMcpBridgeClient'));
  assert.ok(startBridge.indexOf('transportWorker.IsBusy) do return true') < startBridge.indexOf('registerSessionLaunch()'));
  assert.ok(startBridge.includes('if (checkUpdatesThisLaunch and loadAutomaticUpdateSetting()) do startUpdateCheck automaticCheck: true'));
  assert.ok(source.includes('on btnCheckUpdates Click eventSender eventArgs do if (bridgeClient != undefined) do bridgeClient.startUpdateCheck automaticCheck: false'));
  assert.ok(!source.includes('setINISetting uiStateFilePath "updates" "sessionLaunchCount"'));
  assert.doesNotMatch(worker, /StreamReader|ReadLine\(|\.Connect workerHost/);
  assert.match(worker, /ConnectAsync[\s\S]*connectOperation.Wait 2000[\s\S]*ReadTimeout = 1000[\s\S]*WriteTimeout = 1000/);
  assert.match(worker, /while \(newlineIndex != undefined\)/);
  assert.match(worker, /System.IO.BinaryReader/);
  assert.match(worker, /amin #\(workerClient.Available, 8192\)[\s\S]*workerReader.ReadBytes availableBytes/);
  assert.doesNotMatch(worker, /workerStream.Read[ &]/);
  assert.match(worker, /workerInboundQueue.Count >= 64/);
  assert.match(worker, /queuedCharacters > 8388608/);
  assert.match(worker, /receivedFrame.count > 4194304/);
  assert.match(worker, /workerThreadId == workerArguments.Item\[15\]/);
  const tick = source.slice(source.indexOf("fn handleTimerTick"), source.indexOf("fn startBridge"));
  assert.match(tick, /if \(inTick\) do return true[\s\S]*inTick = true[\s\S]*inTick = false/);
  assert.match(tick, /inboundQueue.Count == 0/);
  assert.match(tick, /if \(isDisposed\) do throw/);
  const dispatch = source.slice(source.indexOf("fn handleRequestLine"), source.indexOf("fn enqueueMainThreadRequest"));
  assert.ok(dispatch.indexOf("REQUEST_EXPIRED") < dispatch.indexOf("case actionName"));
  assert.ok(dispatch.includes('(dotNetClass "System.Int64").Parse wireFields[6]'));
  assert.ok(!dispatch.includes('wireFields[6] as integer64'), 'MAXScript decimal coercion loses timestamp precision');
  assert.ok(dispatch.indexOf("requestWasCancelled requestId") < dispatch.indexOf("case actionName"));
  const update = source.slice(source.indexOf("fn pollUpdateOperation"), source.indexOf("fn handleAutomaticUpdateSettingChanged"));
  assert.doesNotMatch(update, /fileIn/);
  assert.match(update, /scheduleReload restartBootstrapPath/);
  const prepare = source.slice(source.indexOf("fn prepareReload"), source.indexOf("fn handleDeferredReload"));
  assert.match(prepare, /if \(inTick\) do return false[\s\S]*IsBusy[\s\S]*CancelAsync[\s\S]*transportClient.Close[\s\S]*return false/);
  process.stdout.write("Bridge lifecycle tests passed: admission, deadline wire field, cancellation/no replay, framing, and MAXScript source contracts.\n");
}

run().catch((error) => { process.stderr.write(error.stack + "\n"); process.exitCode = 1; });
