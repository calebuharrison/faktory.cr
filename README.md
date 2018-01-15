# faktory.cr

faktory.cr is a [Faktory](https://github.com/contribsys/faktory) client for Crystal. It is heavily influenced by both the
[Ruby Faktory client](https://github.com/contribsys/faktory_worker_ruby) and [sidekiq.cr](https://github.com/mperham/sidekiq.cr).
Shout out to [@mperham](https://github.com/mperham) for these fantastic projects!

Heads up - this is still a work in progress. Basic functionality is working well:

- [x] Defining jobs and their arguments
- [x] Serializing and enqueuing jobs on the Faktory server
- [x] Fetching and executing jobs via workers
- [x] Powerful configuration options
- [x] Logging

 but there are still some things missing:

- [ ] TLS Support
- [ ] Middleware/Plugin Infrastructure
- [ ] Tests

## Installation

First you'll want to make sure you've got [Faktory](https://github.com/contribsys/faktory) itself. Then add the following to your
application's shard.yml:

```yaml
dependencies:
  faktory_worker:
    github: calebuharrison/faktory.cr
```

and run:

```sh
shards install
```

One last thing - you'll need to set up a couple of environment variables:

```
export FAKTORY_PROVIDER="FAKTORY_URL"
export FAKTORY_URL="tcp://localhost:7419"
```

All set!

## Quick Start

First we spin up a local Faktory server:

```sh
faktory
```

And then we open up a file in our project called `do_thing.cr`:

```crystal
require "faktory_worker"

struct DoThing < Faktory::Job
  arg thing     : String
  arg should_do : Bool

  def perform
    if should_do
      puts thing
    end
  end
end

job_id = DoThing.perform_async(thing: "Thing1", should_do: true)
```

If we compile and run `do_thing.cr`, our job will be serialized and enqueued by Faktory. We can verify that the job has been
enqueued by visiting the Faktory Web UI (localhost:7420 in your browser).

The job has been enqueued, but now it's time to perform it. We'll create a worker for this:

```crystal
worker = Faktory::Worker.new
worker.run
```

The worker will fetch jobs from the Faktory server and perform them until it is told to stop via the Web UI.

Now you can do all the things!

## Jobs

### Job Structure

A job is a `struct` that inherits from `Faktory::Job`:

```crystal
struct DoThing < Faktory::Job
  # argument declarations and configuration options go here

  def perform
    # logic goes here
  end
end
```
  
Jobs are required to define a `perform` method that gets called when the job is fetched from the server. Arguments are defined 
using the `arg` macro and must be of a valid JSON type. These arguments are exposed inside the `struct` definition so you can use
them in your `perform` logic. Additionally, the job's unique ID (`jid`), `created_at`, and `enqueued_at` are also exposed.

### Performing a Job

You can enqueue a job to be performed by calling the `perform_async` class methd:

```crystal
job_id = DoThing.perform_async(...)
```

Whatever arguments are defined in the job definition must be passed to `perform_async`. `perform_async` returns the enqueued job's
unique ID, a String. The job is not actually performed (i.e. the `perform` method is not called) until it has been fetched from 
the Faktory server by a worker process. 

### Configuration

The following configuration options are available for jobs:

- *queue*, the default queue in which to enqueue jobs. *queue* is a String that defaults to "default".
- *priority*, the default priority of enqueued jobs. *priority* is an Int32 between 1 and 9 that defaults to 5.
- *retry*, the default number of retry attempts to make for enqueued jobs. *retry* is an Int32 that defaults to 25.
- *backtrace*, the default number of lines of backtrace to preserve if the job fails. *backtrace* is an Int32 that defaults to 0.
- *reserve_for*, the amount of time that Faktory will reserve a job for a worker that has fetched it. *reserve_for* defaults to 1800
seconds, and must not be less than 60 seconds.

There are 3 different configuration "layers": Global, Job Type, and Call Site

#### Global Configuration

Perfect for your application's config file:

```crystal
Faktory::Job.configure_defaults({
  queue       => "custom",
  priority    => 7,
  retry       => 10,
  backtrace   => 6,
  reserve_for => 60
})
```

#### Job Type Configuration

Job types can also have their own configurations that override the global config:

```crystal
struct DoThing < Faktory::Job
  queue       "custom"
  priority    7
  retry       10
  backtrace   6
  reserve_for 60

  def perform
    # do your thing
  end
end
```

#### Call Site Configuration

To take it one step further, you can also configure job instances by passing a block to `perform_async`:

```crystal
DoThing.perform_async(...) do |options|
  options.queue("custom").priority(7).retry(10).backtrace(6).reserve_for(60.seconds)
end
```

Call site configuration methods are chainable and can be called in any order. You can also configure *when* a job will be enqueued
using either `at` or `in`:

```crystal
# Both of these do the same thing.

DoThing.perform_async(...) do |options|
  options.at(30.minutes.from_now)
end

DoThing.perform_async(...) do |options|
  options.in(30.minutes)
end
```

## Workers

By default, your workers will only fetch jobs from the "default" queue. To fetch from another queue, use call site configuration:

```crystal
worker = Faktory::Worker.new

worker.run do |options|
  options.queue("custom")
end
```

You can, of course, fetch from multiple queues as well:

```crystal
worker.run do |options|
  options.queues("default", "custom", "user-waiting")
end
```

Each time a worker fetches a job, it polls its queues in random order to prevent queue starvation. You can disable this behavior:

```crystal
worker.run do |options|
  options.queues("default", "custom", "user-waiting").shuffle?(false)
end
```

You'll squeeze the most performance out of workers by running them concurrently via `spawn`. On my machine, running five
workers concurrently, I see ~8,300 jobs/sec throughput with do-nothing jobs.

## Other Stuff

You can flush Faktory's dataset:

```crystal
Faktory.flush
```

You can also get some operational info from the server as a String:

```crystal
puts Faktory.info
```

## Production

If you're a little off your rocker, you can use Faktory in production.  You'll need to include the password in the Faktory URL:

```sh
export FAKTORY_URL="tcp://:opensesame@localhost:7419"
```

Please do not use "opensesame" as your password.

## Contributing

1. Fork it ( https://github.com/calebuharrison/faktory.cr/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [calebuharrison](https://github.com/calebuharrison) Caleb Uriah Harrison - creator, maintainer
