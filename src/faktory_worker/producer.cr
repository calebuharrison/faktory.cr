module Faktory
  class Producer < Client

    def initialize(debug : Bool = false)
      super(debug)
    end

    def push(serialized_job : String)
      retry_if_necessary do
        send_command("PUSH", serialized_job)
        verify_ok
      end
    end

  end
end