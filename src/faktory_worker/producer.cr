module Faktory
  class Producer < Client
    def initialize
      super
    end

    def push(serialized_job : String)
      Faktory.log.info("PUSH " + serialized_job)
      retry_if_necessary do
        send_command("PUSH", serialized_job)
        verify_ok
      end
    end
  end
end
