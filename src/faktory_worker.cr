require "./faktory_worker/**"
module Faktory

  @@producer : Producer | Nil

  protected def self.producer : Producer
    @@producer ||= Producer.new
  end

  def self.info : String
    Faktory.producer.info
  end

  def self.flush
    Faktory.producer.flush
  end

  def self.version : String
    Faktory::VERSION
  end
end
