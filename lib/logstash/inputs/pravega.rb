# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "stud/interval"
require "java"
# require pravega jar dependencies
require "client"
require "common"
require "contract"
require "service"

class LogStash::Inputs::Pravega < LogStash::Inputs::Base
  config_name "pravega"

  default :codec, "json"
  
  config :pravega_endpoint, :validate => :string, :require => true

  config :stream_name, :validate => :string, :require => true

  config :scope, :validate => :string, :default => "seattle"

  config :group_name, :validate => :string, :default => "default_group"

  config :consumer_threads, :validate => :number, :default => 1

  config :consumer_uuid, :validate => :string, :default => SecureRandom.uuid
  
  public
  def register
    @runner_threads = []
  end # def register

  def run(logstash_queue)
    @runner_consumers = consumer_threads.times.map { |i| create_consumer() }
    @runner_threads = @runner_consumers.map { |consumer| thread_runner(logstash_queue, consumer) }
    @runner_threads.each{ |t| t.join }
  end # def run

  def stop
  end

  public
  def pravega_consumers
    @runner_consumers
  end

  private
  def thread_runner(logstash_queue, consumer)
    Thread.new do 
      begin
        while true do
          data = consumer.readNextEvent(60000).getEvent()
          logger.debug("Receive event ", :streamName => @stream_name, :data => data)
          @codec.decode(data) do |event|
            decorate(event)
            event.set("streamName", @stream_name)
            logstash_queue << event
          end
        end
      end
    end
  end

  private
  def create_consumer()
    begin
      java_import('com.emc.pravega.stream.EventStreamReader')
      java_import('com.emc.pravega.StreamManager')
      java_import('com.emc.pravega.ClientFactory')
      java_import("com.emc.pravega.stream.EventStreamReader")
      java_import("com.emc.pravega.stream.ReaderConfig")
      java_import("com.emc.pravega.stream.ReaderGroupConfig")
      java_import("com.emc.pravega.stream.impl.JavaSerializer")
      java_import("com.emc.pravega.stream.Sequence")
      uri = java.net.URI.new(pravega_endpoint)
      clientFactory = ClientFactory.withScope(scope, uri)
      streamManager = StreamManager.withScope(scope, uri)
      streamManager.createReaderGroup(group_name, ReaderGroupConfig.builder().startingPosition(Sequence::MIN_VALUE).build(), java.util.Collections.singletonList(stream_name))
      reader = clientFactory.createReader(consumer_uuid, group_name, JavaSerializer.new(), ReaderConfig.new())
      return reader
    end
  end
end # class LogStash::Inputs::Pravega
