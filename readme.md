# Ruby Condition Varaible Timeout

This example code demonstrates the unfair scheduling of threads when using a condition variable.

## Usage

```bash
$ ruby main.rb
```

The program will exit with an error like this:

```
[2023-06-07 18:57:33 +0900] worker-0: Timed out. Aborting test after 0.10053000005427748 seconds
ResourcePool::TimeoutError Unable to acquire resource after 0.10036599996965379 seconds
/Users/samuel/Developer/ioquatix/ruby-condition-variable-timeout/resource_pool.rb:45:in `acquire'
/Users/samuel/Developer/ioquatix/ruby-condition-variable-timeout/resource_pool.rb:13:in `with_resource'
./main.rb:43:in `block (2 levels) in <main>'
```

## Explanation

Each worker acquires the resource in lockstep:

```ruby
POOL.with_resource do
  Logger.debug('Sleep with resource #1')
  sleep(0.001) # simulates a DB call
end

# ConditionVariable#signal occurs here.

POOL.with_resource do
  Logger.debug('Sleep with resource #2')
  sleep(0.001) # simulates a DB call
end
```

However after signalling the condition variable, the thread immediately re-acquires the resource. During it's internal "sleep", the signalled thread tries to acquire the resource, but immediately fails. Because of this, and the sequence of events that occurs, the worker eventually times out, because it can never acquire the resource.
