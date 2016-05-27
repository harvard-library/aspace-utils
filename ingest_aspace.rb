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
  end

  %I|debug info warn error|.each do |level|
    define_method level, ->(&block) do
      @file.write("#{DateTime.now.to_s.sub(/-04:00\z/, '')} [#{level.to_s.upcase}] #{block.yield}\n")
      @file.flush
    end
  end

  def close
    @file.close
  end
end

$http_logger = Logger.new('httpconn.log')
$ingest_logger = Logger.new('ingestlog.log')

$http_logger.info { "Start of Processing" }
$ingest_logger.info { "Start of Processing" }

class AspaceIngester
  include ::HTTMultiParty
  persistent_connection_adapter(logger: $http_logger)

  base_uri "#{$config['backend_uri']}"

  def authorize
    res = self.class.post('/users/admin/login',
                           query: {password: $config['password']})
    if res.code == 200
      sess = JSON.parse(res.body)
      token = sess['session']
      return (@auth = token) if token
    end
    $ingest_logger.error { "Failed to aquire auth" }
    raise "Failed to aquire auth"
  end

  def json_convert(fname)
    authorize unless @auth
    $ingest_logger.info { "Converting '#{fname}'" }

    begin

      res = self.class.post('/plugins/jsonmodel_from_format/resource/ead',
                            headers: {
                              'X-ArchivesSpace-Session' => @auth,
                              'Content-Type' => 'text/xml'},
                            body: IO.read(fname))
    rescue StandardError => e
      $ingest_logger.error { "Conversion of '#{fname}' failed with error '#{e}'" }
      File.open('error_responses', 'a') do |f|
        f.puts "Backtrace for '#{fname}' at #{DateTime.now.to_s.sub(/-04:00\z/, '')} [CONVERSION]"
        f.puts '<<<<<<<<<<<<<<<<<<<<<<<<<<<'
        f.puts e.backtrace.join("\n")
        f.puts '>>>>>>>>>>>>>>>>>>>>>>>>>>>'
      end
      return nil
    end

    if res.code != 200
      $ingest_logger.warn { "Conversion of '#{fname}' failed with code '#{res.code}', body of response is in 'error_responses'" }
      File.open('error_responses', 'a') do |f|
        f.puts "Response for '#{fname}' at #{DateTime.now.to_s.sub(/-04:00\z/, '')} [CONVERSION]"
        f.puts '<<<<<<<<<<<<<<<<<<<<<<<<<<<'
        f.puts res.body
        f.puts '>>>>>>>>>>>>>>>>>>>>>>>>>>>'
      end
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
    authorize unless @auth

    begin
      res = self.class.post("/repositories/#{repo_id}/batch_imports",
                            headers: {
                              'X-ArchivesSpace-Session' => @auth,
                              'Content-type' => 'application/json'
                            },
                            body: json)
    rescue StandardError => e
      $ingest_logger.error { "Upload of '#{fname}' failed with error '#{e}'" }
       File.open('error_responses', 'a') do |f|
        f.puts "Backtrace for '#{fname}' at #{DateTime.now.to_s.sub(/-04:00\z/, '')} [UPLOAD]"
        f.puts '<<<<<<<<<<<<<<<<<<<<<<<<<<<'
        f.puts e.backtrace.join("\n")
        f.puts '>>>>>>>>>>>>>>>>>>>>>>>>>>>'
       end
       return nil
    end

    if res.code != 200
      $ingest_logger.warn { "Upload of '#{fname}' failed with code '#{res.code}', body of response is in 'error_responses'" }
      File.open('error_responses', 'a') do |f|
        f.puts "Response for '#{fname}' at #{DateTime.now.to_s.sub(/-04:00\z/, '')} [UPLOAD]"
        f.puts '<<<<<<<<<<<<<<<<<<<<<<<<<<<'
        f.puts res.body
        f.puts '>>>>>>>>>>>>>>>>>>>>>>>>>>>'
      end
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

client = AspaceIngester.new
successes = 0
total = 0
$ingest_logger.info { "BEGIN INGEST" }
ingest_files = Dir[File.join($config['ingest_dir'], '*.xml')].
               sort.
               group_by {|f| File.basename(f)[0..2]}.
               select {|k,v| $config['repositories'][k]}
ingest_files.each do |k, v|
  $ingest_logger.info { "BEGIN Ingest of finding aids for '#{k}'" }
  v.each do |fname|
    total += 1
    json = client.json_convert(fname)
    if json
      success = client.upload($config['repositories'][k],
                              json.to_json,
                              fname)
      successes += 1 if success
    end
  end
  $ingest_logger.info { "END ingest of finding aids for '#{k}'" }
end
$ingest_logger.info { "OK: #{successes} FAIL: #{total - successes} TOTAL: #{total}" }
$ingest_logger.info { "END INGEST" }

$http_logger.close
$ingest_logger.close
