# INCIDENT-001: Scheduler Capacity Race Condition (Over-Assignment)

## Severity
Medium (development environment, caught before any GKE deployment; would have caused real resource over-commitment in production)

## Summary
During local validation of the Phase 4 workload platform, a capacity-exhaustion test (three jobs each requesting 900m CPU submitted against two workers with 1000m capacity each) revealed that two jobs were assigned to the same worker within milliseconds of each other, over-committing that worker to 1800m of assigned work against its 1000m capacity.

## Detection
Detected through deliberate testing, not through the running system reporting an error. The scheduler logs showed both job 2 and job 3 assigned to the same worker ID with no requeue or capacity-rejection message for either, despite the worker's true capacity being insufficient for both after the first assignment.

## Root Cause
The scheduler read worker capacity from a Redis hash that was only updated by the worker's own heartbeat, which ran on a fixed interval independent of scheduling decisions. Between two scheduling decisions made faster than one heartbeat interval apart, the scheduler had no way to know that a worker's capacity had already been committed by an earlier decision made microseconds before. The scheduler was making decisions against stale capacity data.

## Contributing Factors
The heartbeat interval (5 seconds) was long relative to the speed at which the scheduler could make consecutive decisions (single-digit milliseconds), widening the race window. Worker capacity was tracked in two places, the worker's own in-memory counters and the Redis hash, with only one-directional, periodic synchronization between them.

## Symptom vs Root Cause
The symptom was two jobs landing on one worker. The root cause was not "the scheduler is broken" in general, since single-job scheduling worked correctly in every prior test; the specific root cause was the absence of an immediate capacity reservation at assignment time, isolated to the narrow window between consecutive scheduling decisions.

## Remediation
The scheduler now decrements the assigned worker's advertised capacity in Redis immediately upon assignment, using an atomic HINCRBY operation, rather than waiting for the worker's next heartbeat to reflect the change. This closes the race window between scheduling decisions. The worker's own heartbeat remains the eventual source of truth and continues to report real committed capacity independently, providing a second, converging confirmation rather than replacing the reservation mechanism.

## Verification
The same three-job, 900m-each capacity-exhaustion scenario was re-run after the fix. Job 1 and job 2 were correctly assigned to two different workers within 3 milliseconds of each other. Job 3 was correctly rejected six consecutive times with an explicit "No capacity" log message and requeued each time, then successfully assigned once a worker's job completed and freed capacity, with a measured scheduling latency of 6.014 seconds, consistent with the 4-second simulated job duration plus polling overhead.

## Measurement
Scheduling latency under contention: 6.014 seconds (one full job cycle of waiting), versus approximately 0.003 seconds when capacity is immediately available. This is the first real measured data point on how the system behaves under capacity pressure, ahead of formal SLO definition in a later phase.

## Lessons Learned
Any system that separates "decision" state (who gets what) from "ground truth" state (what actually has capacity) needs an explicit reservation step at decision time if decisions can be made faster than ground truth naturally updates. Relying solely on periodic reconciliation (heartbeats) is insufficient when the reconciliation interval is not tightly coupled to decision frequency. This same class of bug is worth deliberately re-testing at higher request rates in the load and capacity testing phase, since a faster decision rate could still outrun even the corrected reservation path under sufficiently extreme concurrency.
