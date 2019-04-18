# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "stud/interval"
require "java"
require "logstash-input-pravega_jars.rb"
require "yaml"

class LogStash::Inputs::Pravega < LogStash::Inputs::Base
  config_name "pravega"

  default :codec, "plain"
  
  config :pravega_endpoint, :validate => :string, :require => true

  config :stream_name, :validate => :string, :require => true

  config :scope, :validate => :string, :default => "global"

  config :read_timeout_ms, :validate => :number, :default => 60000
  
  config :username, :validate => :string, :default => ""

  config :password, :validate => :string, :default => ""

  public
  def register
    create_readerGroup()
    @inputs = YAML.load(File.open($root_dir + "/config.yml"))
    @reader_threads = @inputs['readers_thread']
    @min_read_timeout_ms = @inputs['min_read_timeout_ms']
  end # def register

  def run(logstash_queue)
    # The pravega server will set the stream read timeout witn min(read_time_ms, 1000ms)
    # If the read_time_out is less than zero, it will throw the error. The logstash won't work.
    @read_timeout_ms = @min_read_timeout_ms if @read_timeout_ms < @min_read_timeout_ms
    logger.debug("The prechecked arguments: ", :reader_threads => @reader_threads, :read_timeout_ms => @read_timeout_ms)

    # To make the new created readers read data from segment in time, need to make the old readers offline
    @readerGroupManager.getReaderGroup(@groupName).getOnlineReaders().map { |reader| reader.close()}
    @runner_consumers = @reader_threads.times.map { |i| create_consumer() }
    @runner_threads = @runner_consumers.map { |consumer| thread_runner(logstash_queue, consumer) }
    @runner_threads.each{ |t| t.join }
  end # def run

  def stop
    @runner_consumers.times.map { |consumer| consumer.close()}
  end

  private
  def thread_runner(logstash_queue, consumer)
    Thread.new do 
      begin
        while true do
          data = consumer.readNextEvent(@read_timeout_ms).getEvent()
          logger.debug("Receive event ", :streamName => @stream_name, :data => data)
          if data.to_s.empty?
             next
          end
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
      java_import("io.pravega.client.ClientFactory")
      java_import("io.pravega.client.stream.ReaderConfig")
      java_import("io.pravega.client.stream.impl.JavaSerializer")

      clientFactory = ClientFactory.withScope(scope, @uri)
      return clientFactory.createReader(SecureRandom.uuid,
					@groupName,
					JavaSerializer.new(),
					ReaderConfig.builder().build())
    end
  end

  private
  def create_readerGroup()
    begin
      java_import("io.pravega.client.ClientConfig")
      java_import("io.pravega.client.stream.impl.DefaultCredentials")
      java_import("io.pravega.client.admin.StreamManager")
      java_import("io.pravega.client.stream.StreamConfiguration")
      java_import("io.pravega.client.stream.ReaderGroupConfig")
      java_import("io.pravega.client.admin.ReaderGroupManager")
      java_import("io.pravega.client.stream.Stream")

      @uri = java.net.URI.new(pravega_endpoint)
      clientConfig = ClientConfig.builder()
                                 .controllerURI(@uri)
                                 .credentials(DefaultCredentials.new(password, username))
                                 .validateHostName(false)
                                 .build()
      streamManager = StreamManager.create(clientConfig)
      streamManager.createScope(scope)
      streamManager.createStream(scope, stream_name, StreamConfiguration.builder().build())
      readGroupConfig = ReaderGroupConfig.builder().stream(Stream.of(scope, stream_name)).build()
      @readerGroupManager = ReaderGroupManager.withScope(scope, @uri)
      @groupName = SecureRandom.uuid.gsub('-', '')
      @readerGroupManager.createReaderGroup(@groupName, readGroupConfig)
    end
  end
end # class LogStash::Inputs::Pravega
