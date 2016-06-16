#!/usr/bin/env ruby
require 'json'
require 'nokogiri'
require 'pry'

raise "Requires two arguments - an ingestlog, and an error_responses" unless ARGV.count >= 2

$ingestlog = IO.read(File.expand_path(ARGV.shift))
$error_responses = IO.read(File.expand_path(ARGV.shift))
$interactive = ARGV.shift

(_, ok, bad, total) = *$ingestlog.
                       lines[-2].
                       match(/(?<=OK: )(\d+) (?:FAIL: )(\d+) (?:TOTAL: )(\d+)/)

def err_resp_for(eadid)
  m = $error_responses.match(/#{eadid}.xml.*?(?=>>>>>>>>>>>>>>>>>>>>>>>>>>>)/m)
  if m
    txt = m[0].
          lines.
          drop(2).
          join("\n")
    begin
      # Comes out of ASpace, uncaught errors in ASpace, interesting!
      if txt.start_with? "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01"
        Nokogiri.HTML(txt).at_css('#info').content.strip
      # Comes out of Apache, pretty much just proxy errors, less interesting.
      elsif txt.start_with? "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML 2.0//EN"
        Nokogiri.HTML(txt).xpath('//h1|//h1/following-sibling::*').map(&:content).join("\n").strip.gsub(/\r?\n+/, "\n")
      # Comes out of the JVM when it blows up, meh.
      elsif txt.start_with? "<html"
        Nokogiri.HTML(txt).at_css('body').content.strip.gsub(/\r?\n+/, "\n")
      # Errors in finding aid processing or upload, SUPER INTERESTING
      else
        JSON.parse(txt)
      end
    # If any of the various parse attempts fails, just return the txt
    rescue
      txt
    end
  end
end


five_hundreds = $ingestlog.
                lines.
                grep(/Conversion of.*failed.*code '5\d{2}/).
                map {|el| (m = el.match(/full\/(.*?).xml/)) && m[1]}.
                map {|el| [el, err_resp_for(el)]}.
                to_h

four_hundreds = $ingestlog.
                lines.
                grep(/Conversion of.*failed.*code '4\d{2}/).
                map {|el| (m = el.match(/full\/(.*?).xml/)) && m[1]}.
                map {|el| [el, err_resp_for(el)]}.
                to_h

by_error = {
  "4XX Errors" =>
  four_hundreds.reduce({}) do |agg, (k, v)|
    v['error'].each_pair do |e, x|
      canonical = "#{e.gsub(/\/\d+\//, '/$N/')}: #{x}"
      agg[canonical] ||= []
      agg[canonical] << k
    end
    agg
  end,
  "5XX Errors" =>
  five_hundreds.reduce({}) do |agg, (k, v)|
    agg[v] ? agg[v] << k : agg[v] = [k]
    agg
  end,
  "Upload Failures" =>
  $ingestlog.
    lines.
    grep(/Upload of.*failed/).
    map {|s| [(m = s.match(/full\/(.*?).xml/)) && m[1], s[(s.index('failed with error \'') + 19)...-2]]}.
    map {|(k,v)|
    m = v.match(
      /Server error: (?:Problem creating '(?<title>.*?)(?:': )(?<error_text>.*)"\]|(?<error_name>.*?: )(?<error_text>.*)"\])/)

    [k,
     m.names.map {|n| [n, m[n]] }.to_h]}.
    to_h
}

upload_failures = by_error['Upload Failures'].group_by do |eadid, mdata|
  if mdata['error_text']
    mdata['error_text'][/^(id_0.*|.*?(?=:)|.*)/] || mdata['error_text']
  end
end.map {|k, v| [k, v.to_h]}.to_h

binding.pry if $interactive

puts "Summary: OK: #{ok}, FAILED: #{bad}, TOTAL: #{total}"
puts <<-4XXHEADER << "\n";
4XX Errors (#{four_hundreds.count} total)
===========================================================================================
Errors in conversion process that come from ArchivesSpace's EAD Converter, grouped by error
===========================================================================================
4XXHEADER

by_error['4XX Errors'].each_pair do |error_name, eadids|
  puts "\n"
  puts "#{error_name} (#{eadids.count} total) :"
  puts "------------------------"
  eadids.sort.each do |eadid|
    puts "#{eadid}"
  end
end
puts "\n\n"

puts <<-UPLOADHEADER << "\n"
====================================================================
Upload Failures (#{by_error['Upload Failures'].count} total)

Errors in the upload process.  These come from the ArchivesSpace DB,
or potentially from Java.
====================================================================
UPLOADHEADER

upload_failures.each_pair do |error_type, eadid_data|
  puts "\n"
  puts "#{error_type} (#{eadid_data.count} total) :"
  puts "-------------------------"
  eadid_data.each do |eadid, data|
    puts "#{eadid}\t#{data.fetch('error_name', 'ead_error')}\t#{data['error_text']}"
  end
end
puts "\n\n"

puts <<-5XXHEADER << "\n"
5XX Errors (#{five_hundreds.count} total)
======================================================================
Errors in the conversion process that come from either Apache or Java.
These are basically Dave's problem, feel free to ignore
======================================================================
5XXHEADER

by_error['5XX Errors'].each_pair do |error_name, eadids|
  puts "\n"
  puts "#{error_name} (#{eadids.count} total) :"
  puts "-------------------------"
  eadids.sort.each do |eadid|
    puts "#{eadid}"
  end
end
