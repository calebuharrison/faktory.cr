require "random/secure"

module Faktory

  abstract struct Job

    GLOBAL_JOB_DEFAULTS = {
      :queue => "default",
      :priority => 5,
      :reserve_for => 1800,
      :retry => 25,
      :backtrace => 0
    }
  
    macro configure_defaults(default_hash)
      {% for k, v in default_hash %}
        {% if k.is_a?(SymbolLiteral) %}
          {% if k == :queue %}
            {% if v.is_a?(StringLiteral) %}
              {% GLOBAL_JOB_DEFAULTS[:queue] = v %}
            {% else %}
              {% raise "queue must be a StringLiteral" %}
            {% end %}
          {% elsif k == :backtrace %}
            {% if v.is_a?(NumberLiteral) && v > -1 %}
              {% GLOBAL_JOB_DEFAULTS[:backtrace] = v %}
            {% else %}
              {% raise "backtrace must be a positive integer" %}
            {% end %}
          {% elsif k == :priority %}
            {% if v.is_a?(NumberLiteral) && v > 0 && v < 10 %}
              {% GLOBAL_JOB_DEFAULTS[:priority] = v %}
            {% else %}
              {% raise "priority must be between 1 and 9" %}
            {% end %}
          {% elsif k == :reserve_for %}
            {% if v.is_a?(NumberLiteral) && v >= 60 %}
              {% GLOBAL_JOB_DEFAULTS[:reserve_for] = v %}
            {% else %}
              {% raise "reserve_for must be a positive integer no less than 60, expressed in seconds" %} 
            {% end %}
          {% elsif k == :retry %}
            {% if v.is_a?(NumberLiteral) && v > -2 %}
              {% GLOBAL_JOB_DEFAULTS[:retry] = v %}
            {% else %}
              {% raise "retry must be -1, 0, or a positive integer" %}
            {% end %}
          {% else %}
            {% raise "key '#{v}' is not a valid option" %}
          {% end %}
        {% else %}
          {% raise "keys must be symbols" %}
        {% end %}
      {% end %}
    end

    # The job registry is populated at compile-time.
    REGISTRY = {} of String => Proc(JSON::Any, Faktory::Job)

    TIME_FORMAT_STRING = "%FT%T%:z"

    # job ID
    @jid          : String
    @created_at   : Time | Nil
    @enqueued_at  : Time | Nil

    protected def jid : String
      @jid
    end

    private def created_at : Time
      @created_at.as(Time)
    end

    private def enqueued_at : Time
      @enqueued_at.as(Time)
    end

    # All jobs must define a perform method.
    abstract def perform

    # Instantiates a Job from a JSON payload.
    def self.deserialize(payload : JSON::Any) : Faktory::Job
      jobtype = payload["jobtype"].as_s
      REGISTRY[jobtype].call(payload)
    end

    def initialize(jid : String = Random::Secure.hex(12))
      @jid = jid
    end

    # Registers a Job argument
    macro arg(type_decl)
      {% ARGS << type_decl %}
      @{{type_decl.var.id}} : {{type_decl.type.id}}

      private def {{type_decl.var.id}} : {{type_decl.type.id}}
        @{{type_decl.var.id}}
      end
    end

    # Sets the default queue for this job type.
    macro queue(default)
      {% if default.is_a?(StringLiteral) %}
        {% JOBTYPE_DEFAULTS[:queue] = default %}
      {% else %}
        {% raise "queue must be a StringLiteral" %}
      {% end %}
    end

    # Sets the default backtrace for this job type.
    macro backtrace(default)
      {% if default.is_a?(NumberLiteral) && default > -1 %}
        {% JOBTYPE_DEFAULTS[:backtrace] = default %}
      {% else %}
        {% raise "backtrace must be a positive integer" %}
      {% end %}
    end

    # Sets the default priority for this job type.
    macro priority(default)
      {% if default.is_a?(NumberLiteral) && default >= 0 && default <= 9 %}
        {% JOBTYPE_DEFAULTS[:priority] = default %}
      {% else %}
        {% raise "priority must be an integer between 1 and 9" %}
      {% end %}
    end

    # Sets the default reserve_for for this job type.
    macro reserve_for(default)
      {% if default.is_a?(NumberLiteral) && default > -1 %}
        {% JOBTYPE_DEFAULTS[:reserve_for] = default %}
      {% else %}
        {% raise "reserve_for must be a positive integer, expressed in seconds" %}
      {% end %}
    end

    # Sets the default retry for this job type.
    macro retry(default)
      {% if default.is_a?(NumberLiteral) && default > -1 %}
        {% JOBTYPE_DEFAULTS[:retry] = default %}
      {% else %}
        {% raise "retry must be a positive integer" %}
      {% end %}
    end

    private class OptionDeck

      @options : Hash(Symbol, Int32 | String)

      def initialize(option_hash : Hash(Symbol, Int32 | String))
        @options = option_hash
      end

      def queue(queue : String) : OptionDeck
        self.tap { @options[:queue] = queue }
      end

      def backtrace(backtrace : Int32) : OptionDeck
        self.tap { @options[:backtrace] = backtrace }
      end

      def priority(priority : Int32) : OptionDeck
        self.tap { @options[:priority] = priority }
      end

      def retry(retry : Int32) : OptionDeck
        self.tap { @options[:retry] = retry }
      end

      def reserve_for(reserve_for : Int32) : OptionDeck
        self.tap { @options[:reserve_for] = reserve_for }
      end

      def reserve_for(reserve_for : Time::Span) : OptionDeck
        self.reserve_for(reserve_for.to_i)
      end

      def at(time : Time) : OptionDeck
        self.tap { @options[:at] = time.to_utc.to_s(TIME_FORMAT_STRING) }
      end

      def in(span : Time::Span) : OptionDeck
        self.at(Time.utc_now + span)
      end

      protected def expose : Hash(Symbol, Int32 | String)
        @options
      end

    end

    macro inherited

      JOBTYPE = {{@type.id.stringify.split("::").last}}

      REGISTRY[JOBTYPE] = -> (payload : JSON::Any) { {{@type}}.deserialize(payload).as(Faktory::Job) }

      # Job arguments which are populated at compile-time.
      ARGS = [] of Nil

      # Default options for this job type, populated by their individual macros.
      JOBTYPE_DEFAULTS = {} of Symbol => Int32 | String

      macro finished

        # Create a Tuple type definition from the list of arguments.
        ARGS_TYPE_TUPLE = Tuple(\{% for t in ARGS %} \{{t.type.id}}, \{% end %})

        # Merge Faktory defaults into this job's defaults.
        \{% for k, v in GLOBAL_JOB_DEFAULTS %}
          \{% if JOBTYPE_DEFAULTS[k] == nil %}
            \{% JOBTYPE_DEFAULTS[k] = v %}
          \{% end %}
        \{% end %}

        # Push this job to the Faktory server with call site configuration.
        def self.perform_async(\{% for t in ARGS %} \{{t.var.id}} : \{{t.type.id}}, \{% end %} &block : OptionDeck -> OptionDeck) : String
          option_deck = yield OptionDeck.new(JOBTYPE_DEFAULTS)
          job = \{{@type}}.new(\{% for t in ARGS %} \{{t.var.id}}: \{{t.var.id}}, \{% end %})
          Faktory.producer.push(job.serialize(option_deck))
          job.jid
        end

        # Push this job to the Faktory server.
        def self.perform_async(\{% for t in ARGS %} \{{t.var.id}} : \{{t.type.id}}, \{% end %}) : String
          option_deck = OptionDeck.new(JOBTYPE_DEFAULTS)
          job = \{{@type}}.new(\{% for t in ARGS %} \{{t.var.id}}: \{{t.var.id}}, \{% end %})
          Faktory.producer.push(job.serialize(option_deck))
          job.jid
        end

        protected def initialize(\{% for t in ARGS %} \{{t.var.id}} : \{{t.type.id}}, \{% end %} jid : String = Random.new.hex(12), created_at : Time | Nil = nil, enqueued_at : Time | Nil = nil)
          super(jid)
          \{% for t in ARGS %}
            @\{{t.var.id}} = \{{t.var.id}}
          \{% end %}
          @created_at = created_at
          @enqueued_at = enqueued_at
        end

        private def args
          { \{% for t in ARGS %} @\{{t.var.id}}, \{% end %} }
        end

        # Serializes the job into JSON.
        protected def serialize(option_deck : OptionDeck) : String
          option_hash = option_deck.expose
          { :jid => @jid, :jobtype =>  JOBTYPE, :args => args }.merge(option_hash).to_json
        end

        # Deserializes a JSON payload into a job.
        protected def self.deserialize(payload : JSON::Any) : \{{@type}}
          jid = payload["jid"].as_s
          args_tuple = ARGS_TYPE_TUPLE.from_json(payload["args"].as_a.to_json)
          created_at = Time.parse(payload["created_at"].as_s, TIME_FORMAT_STRING).to_utc
          enqueued_at = Time.parse(payload["enqueued_at"].as_s, TIME_FORMAT_STRING).to_utc
          \{{@type}}.new(*args_tuple, jid: jid, created_at: created_at, enqueued_at: enqueued_at)
        end

      end

    end

  end

end
