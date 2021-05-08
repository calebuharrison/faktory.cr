module Faktory
  class Worker
    Log = Faktory.Log.for(self)

    private class OptionDeck
      @options : Hash(Symbol, Bool | Array(String))

      def initialize
        @options = {
          :shuffle => true,
          :queues  => ["default"],
        }
      end

      def shuffle?(shuffle : Bool) : OptionDeck
        self.tap { @options[:shuffle] = shuffle }
      end

      def queue(*target_queues : String) : OptionDeck
        self.queues(*target_queues)
      end

      def queues(*target_queues : String) : OptionDeck
        self.tap { @options[:queues] = target_queues.to_a }
      end

      protected def expose : Hash(Symbol, Bool | Array(String))
        @options
      end
    end

    @consumer : Consumer
    @shuffle : Bool
    @queues : Array(String)
    @quiet : Bool
    @terminate : Bool
    @should_heartbeat : Bool
    @running : Bool

    def initialize(debug : Bool = false)
      @consumer = Consumer.new
      @shuffle = true
      @queues = ["default"]
      @quiet = false
      @terminate = false
      @should_heartbeat = true
      @running = false
    end

    def running? : Bool
      @running
    end

    def shutdown!
      @quiet = true
      @terminate = true
    end

    def run
      @quiet = false
      @terminate = false
      @running = true

      start_heartbeat

      until terminated?
        job = nil
        if quieted?
          sleep 0.5
        else
          job = fetch
        end
        process(job.as(Job)) if job
        heartbeat if should_heartbeat?
      end
      @running = false
    end

    def run(&block : OptionDeck -> OptionDeck)
      option_deck = yield OptionDeck.new
      options = option_deck.expose
      @shuffle = options[:shuffle].as(Bool)
      @queues = options[:queues].as(Array(String))
      self.run
    end

    private def start_heartbeat
      spawn do
        until terminated?
          @should_heartbeat = true
          sleep 15
        end
      end
    end

    private def should_heartbeat? : Bool
      @should_heartbeat
    end

    private def heartbeat
      response = @consumer.beat
      if response
        state = response.as(String)
        @quiet = true
        @terminate = true if state == "terminate"
      end
      @should_heartbeat = false
    end

    private def quieted? : Bool
      @quiet
    end

    private def terminated? : Bool
      @terminate
    end

    private def shuffle? : Bool
      @shuffle
    end

    private def fetch : Job | Nil
      @queues = @queues.shuffle if shuffle?
      job_payload = @consumer.fetch(@queues)
      if job_payload
        Job.deserialize(job_payload.as(JSON::Any))
      else
        nil
      end
    end

    private def process(job : Job)
      Log.info("START " + job.jid)
      begin
        job.perform
        @consumer.ack(job.jid)
      rescue e
        @consumer.fail(job.jid, e)
      end
    end
  end
end
