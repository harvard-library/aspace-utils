#!/usr/bin/env ruby
require 'yaml'
require 'json'
require 'bundler'
Bundler.require(:default)

raise "No config" unless File.exist?('config.yml')
$config = YAML.safe_load(IO.read('config.yml'))

class Logger
  def initialize(path)
    @file = File.open(path, 'a')
    @lock = Mutex.new
  end

  %I|debug info warn error|.each do |level|
    define_method level, ->(text = nil, &block) do
      if block
        text = block.yield
      end

      @lock.synchronize do
        @file.write("#{DateTime.now.to_s.sub(/-04:00\z/, '')} [#{level.to_s.upcase}] #{text}\n")
        @file.flush
      end
    end
  end

  def close
    @file.close
  end
end

class ErrorResponseLogger
  @@start_marker = '<<<<<<<<<<<<<<<<<<<<<<<<<<<'
  @@end_marker   = '>>>>>>>>>>>>>>>>>>>>>>>>>>>'
  def initialize(path)
    @file = File.open(path, 'a')
    @lock = Mutex.new
  end

  def debug(phase, fname, object)
    is_error = object.is_a? StandardError
    @lock.synchronize do
      @file.puts "#{is_error ? "Error" : "Response"} for '#{fname}' at #{DateTime.now.to_s.sub(/-04:00\z/, '')} [#{phase.to_s.upcase}]"
      @file.puts @@start_marker
      @file.puts (is_error ? object.backtrace.join("\n") : object.body)
      @file.puts @@end_marker
      @file.flush
    end
  end

  def close
    @file.close
  end
end

$ingest_logger = Logger.new('ingestlog.log')
$httpconn_logger = Logger.new('httpconn.log')
$error_logger = ErrorResponseLogger.new('error_responses')

$ingest_logger.info { "Start of Processing" }

class AspaceIngester
  include ::HTTMultiParty
  persistent_connection_adapter(logger: $httpconn_logger)
  default_timeout 180

  base_uri "#{$config['backend_uri']}"

  @@auth = nil
  @@authlock = Mutex.new

  def authorize
    @@authlock.synchronize do
      return @@auth if @@auth
      res = self.class.post('/users/admin/login',
                            query: {password: $config['password']})
      if res.code == 200
        sess = JSON.parse(res.body)
        token = sess['session']
        return (@@auth = token) if token
      end
    end
    $ingest_logger.error { "Failed to aquire auth" }
    raise "Failed to aquire auth"
  end

  def json_convert(fname)
    authorize
    $ingest_logger.info { "Converting '#{fname}'" }

    begin

      res = self.class.post('/plugins/jsonmodel_from_format/resource/ead',
                            headers: {
                              'X-ArchivesSpace-Session' => @@auth,
                              'Content-Type' => 'text/xml'},
                            body: IO.read(fname))
    rescue StandardError => e
      $ingest_logger.error { "Conversion of '#{fname}' failed with error '#{e}'" }
      $error_logger.debug(:conversion, fname, e)
      return nil
    end

    if res.code != 200
      $ingest_logger.warn { "Conversion of '#{fname}' failed with code '#{res.code}', body of response is in 'error_responses'" }
      $error_logger.debug(:conversion, fname, res)
      nil
    elsif (payload = JSON.parse(res.body)) && payload.is_a?(Hash)
      $ingest_logger.warn { "Conversion of '#{fname}' failed with error '#{payload['error']}'" }
      nil
    else
      $ingest_logger.info { "Conversion of '#{fname}' succeeded" }
      payload
    end
  end

  def upload(repo_id, json, fname)
    $ingest_logger.info { "Uploading JSON from '#{fname}'" }
    authorize

    begin
      res = self.class.post("/repositories/#{repo_id}/batch_imports",
                            headers: {
                              'X-ArchivesSpace-Session' => @@auth,
                              'Content-type' => 'application/json'
                            },
                            body: json)
    rescue StandardError => e
      $ingest_logger.error { "Upload of '#{fname}' failed with error '#{e}'" }
      $error_logger.debug(:upload, fname, e)
      return nil
    end

    if res.code != 200
      $ingest_logger.warn { "Upload of '#{fname}' failed with code '#{res.code}', body of response is in 'error_responses'" }
      $error_logger.debug(:upload, fname, res)
      nil
    elsif (payload = JSON.parse(res.body)) &&
          payload.last.key?('errors') &&
          !payload.last['errors'].empty?
      $ingest_logger.warn { "Upload of '#{fname}' failed with error '#{payload.last['errors']}'" }
      nil
    else
      $ingest_logger.info { "Upload of '#{fname}' succeeded"}
      payload
    end
  end
end

$successes = 0
$total = 0

$succlock = Mutex.new
$totelock = Mutex.new

$ingest_logger.info { "BEGIN INGEST" }
ingest_files = Dir[File.join($config['ingest_dir'], '*.xml')].
               sort.
               group_by {|f| File.basename(f)[0..2]}.
               select {|k,v| $config['repositories'][k]}
ingest_files.each do |k, v|
  $ingest_logger.info { "BEGIN Ingest of finding aids for '#{k}'" }
  if v.count > 0
    threads = []
    v.each_slice((v.count / 4.0).ceil) do |batch|
      threads << Thread.new {
        client = AspaceIngester.new
        batch.each do |fname|
          $totelock.synchronize do
            $total += 1
          end
          json = client.json_convert(fname)
          if json
            success = client.upload($config['repositories'][k],
                                    json.to_json,
                                    fname)
            $succlock.synchronize do
              $successes += 1 if success
            end
          end
        end
      }
    end
    threads.map(&:join)
  end
  $ingest_logger.info { "END ingest of finding aids for '#{k}'" }
end

$ingest_logger.info { "OK: #{$successes} FAIL: #{$total - $successes} TOTAL: #{$total}" }
$ingest_logger.info { "END INGEST" }

$ingest_logger.close
$httpconn_logger.close
$error_logger.close
