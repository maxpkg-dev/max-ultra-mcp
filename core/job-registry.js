/*
 * Session-owned job lifecycle for cancellable Max Ultra MCP operations.
 * Copyright (c) 2026 Lukianenko Vasyl
 * Project website: https://3dground.net
 * Developed by Lukianenko Vasyl
 */

"use strict";

const { randomUUID } = require("node:crypto");

const TERMINAL_STATES = new Set(["completed", "failed", "cancelled"]);

function boundedInteger(value, fallback, minimum, maximum) {
  const parsed = Number(value ?? fallback);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(maximum, Math.max(minimum, Math.trunc(parsed)));
}

function elapsedMilliseconds(job) {
  const startedAt = Date.parse(job.startedAt || job.createdAt);
  const stoppedAt = job.completedAt ? Date.parse(job.completedAt) : Date.now();
  return Math.max(0, stoppedAt - startedAt);
}

function snapshotJob(job) {
  return {
    jobId: job.jobId,
    type: job.type,
    instanceId: job.instanceId,
    state: job.state,
    phase: job.phase || null,
    createdAt: job.createdAt,
    startedAt: job.startedAt || null,
    completedAt: job.completedAt || null,
    elapsedMs: elapsedMilliseconds(job),
    progress: job.progress ?? null,
    cancellable: typeof job.cancel === "function" && !TERMINAL_STATES.has(job.state),
    cancelRequested: Boolean(job.cancelRequested),
    error: job.error || null,
    warnings: [...(job.warnings || [])],
    metadata: job.metadata || {},
  };
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

class JobRegistry {
  constructor(options = {}) {
    this.maximumJobs = boundedInteger(options.maximumJobs, 100, 10, 1000);
    this.jobs = new Map();
  }

  prune() {
    if (this.jobs.size < this.maximumJobs) return;
    for (const [jobId, job] of this.jobs) {
      if (this.jobs.size < this.maximumJobs) break;
      if (TERMINAL_STATES.has(job.state)) this.jobs.delete(jobId);
    }
    if (this.jobs.size >= this.maximumJobs) throw new Error("JOB_LIMIT_REACHED: finish or reconnect the MCP client before starting more jobs");
  }

  create(options) {
    if (!options || typeof options !== "object") throw new Error("Job options are required");
    if (typeof options.type !== "string" || !options.type.trim()) throw new Error("Job type is required");
    if (typeof options.instanceId !== "string" || !options.instanceId.trim()) throw new Error("Job instanceId is required");
    this.prune();
    const job = {
      jobId: randomUUID(),
      type: options.type.trim(),
      instanceId: options.instanceId.trim(),
      state: "queued",
      phase: options.phase || null,
      createdAt: new Date().toISOString(),
      startedAt: null,
      completedAt: null,
      progress: null,
      cancelRequested: false,
      error: null,
      warnings: [],
      metadata: options.metadata || {},
      result: null,
      promise: null,
      cancel: typeof options.cancel === "function" ? options.cancel : null,
    };
    this.jobs.set(job.jobId, job);
    return job;
  }

  require(jobId) {
    const job = this.jobs.get(String(jobId || ""));
    if (!job) throw new Error(`JOB_NOT_FOUND: unknown job '${jobId}'`);
    return job;
  }

  start(job, operation) {
    if (!job || this.jobs.get(job.jobId) !== job) throw new Error("JOB_NOT_FOUND: job is not registered in this MCP session");
    if (typeof operation !== "function") throw new Error("Job operation must be a function");
    if (job.promise) throw new Error(`Job '${job.jobId}' has already started`);
    job.promise = Promise.resolve().then(async () => {
      if (job.cancelRequested || job.state === "cancelled") return snapshotJob(job);
      job.state = "running";
      job.startedAt = new Date().toISOString();
      try {
        const operationResult = await operation(job);
        job.result = operationResult ?? null;
        if (!TERMINAL_STATES.has(job.state) && job.state !== "running_interactive") {
          job.state = job.cancelRequested ? "cancelled" : "completed";
        }
      } catch (error) {
        job.error = String(error?.message || error);
        job.state = job.cancelRequested ? "cancelled" : "failed";
      } finally {
        if (TERMINAL_STATES.has(job.state)) job.completedAt = new Date().toISOString();
      }
      return snapshotJob(job);
    });
    return job;
  }

  list(filters = {}) {
    const requestedType = typeof filters.type === "string" ? filters.type.trim() : "";
    const requestedState = typeof filters.state === "string" ? filters.state.trim() : "";
    const maximum = boundedInteger(filters.limit, 50, 1, 200);
    return [...this.jobs.values()]
      .filter((job) => !requestedType || job.type === requestedType)
      .filter((job) => !requestedState || job.state === requestedState)
      .sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt))
      .slice(0, maximum)
      .map(snapshotJob);
  }

  snapshot(jobId) {
    return snapshotJob(this.require(jobId));
  }

  async wait(jobId, timeoutMs = 30000) {
    const job = this.require(jobId);
    const boundedTimeout = boundedInteger(timeoutMs, 30000, 0, 600000);
    if (!TERMINAL_STATES.has(job.state) && job.promise) await Promise.race([job.promise, delay(boundedTimeout)]);
    return snapshotJob(job);
  }

  async cancelJob(jobId) {
    const job = this.require(jobId);
    if (TERMINAL_STATES.has(job.state)) return snapshotJob(job);
    job.cancelRequested = true;
    if (job.state === "queued") {
      job.state = "cancelled";
      job.completedAt = new Date().toISOString();
    }
    if (job.cancel) {
      const cancellation = await job.cancel(job);
      if (cancellation?.warning) job.warnings.push(String(cancellation.warning));
    }
    return snapshotJob(job);
  }

  getResult(jobId) {
    const job = this.require(jobId);
    if (job.state !== "completed") throw new Error(`JOB_NOT_COMPLETE: job '${job.jobId}' is '${job.state}'`);
    return { ...snapshotJob(job), result: job.result };
  }
}

module.exports = { JobRegistry, TERMINAL_STATES, snapshotJob };
