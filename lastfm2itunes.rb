# coding: UTF-8
# This is a tiny utility script to update your iTunes Library's played counts to match your last.fm listening data
#  This is useful if you've had to rebuild your library for any reason.
#  The utility only updates tracks for which the last.fm play count is greater than the iTunes play count.
# Because of how cool the AppleScript hooks are, watch your iTunes libary as this script works!


require 'open-uri'
require 'nokogiri' rescue "This script depends on the Nokogiri gem. Please run '(sudo) gem install nokogiri'."
require 'rb-scpt' rescue "This script depends on the rb-scpt gem. Please run '(sudo) gem install rb-scpt'."
include Appscript
require 'optparse' rescue "This script depends on the optparse gem. Please run '(sudo) gem install optparse'."

Options = Struct.new(:username,:period,:maxplaycount,:addpc,:dryrun,:verbose)

class Parser
  def self.parse(options)
    args = Options.new()

    args.period = "overall"
    args.addpc = false
    args.verbose = false
    args.dryrun = false

    opt_parser = OptionParser.new do |opts|
      opts.banner = "Usage: lastfm2itunes.rb [options]"
      opts.on('-u', '--username USERNAME', 'The Last.fm username') { |o| args.username = o }
      opts.on('-p', '--period WEEKS', 'Only fetch last.fm playcounts of the last WEEKS weeks') { |o| args.period = o }
      opts.on('-m', '--max-playcount MAX', 'Do not set new playcount if greater than MAX') { |o| args.maxplaycount = o }
      opts.on('-a', '--addpc', 'Add to playcount') { |o| args.addpc = o }
      opts.on('-d', '--dry-run', 'Run without actually updating itunes') { |o| args.dryrun = o }
      opts.on('-v', '--verbose', 'Be verbose') { |o| args.verbose = o }
      opts.on("-h", "--help", "Prints this help") do
        puts opts
        exit
      end
    end

    opt_parser.parse!(options)
    return args
  end
end

options = Parser.parse(ARGV)

#p options
#p ARGV

username = options[:username]
period = options[:period] 
addpc = options[:addpc]
verbose = options[:verbose]
dryrun = options[:dryrun]
max_playcount = options[:maxplaycount].to_i

if username.nil? or username == ""
  Parser.parse %w[--help]
  exit
end

puts "Running with #{options}"

def filter_name(name)
  name.force_encoding("utf-8")
  # This is a hack until I can find out how to do true Unicode normalization in Ruby 1.9
  #  (The Unicode gem doesn't work in 1.9, String#chars.normalize is gone. WTF to do?)
  #  Credit for this goes to my coworker Jordi Bunster
  {
    ['á','à','â','ä','Ä','Â','À','Á','ã','Ã'] => 'a',
    ['é','è','ê','ë','Ë','Ê','È','É']         => 'e',
    ['í','ì','î','ï','Ï','Î','Ì','Í']         => 'i',
    ['ó','ò','ô','ö','Ö','Ô','Ò','Ó','õ','Õ'] => 'o',
    ['ú','ù','û','ü','Ü','Û','Ù','Ú']         => 'u',
    ['ñ','Ñ']                                 => 'n',
    ['ç','Ç']                                 => 'c',
  }.each do |family, replacement|
    family.each { |accent| name.gsub!(accent, replacement) }
  end
  name.downcase.gsub(/^the /, "").gsub(/ the$/, "").gsub(/[^\w]/, "")
end

filename = "cached_lastfm_data.#{period}.rbmarshal"
begin
  playcounts = Marshal.load(File.read(filename))

  puts "Reading cached playcount data from disk"
rescue
  puts "No cached playcount data, grabbing fresh data from Last.fm"
  playcounts = {}

  nowTime = Time.now
  if period != "overall"
    startTime = nowTime - (period.to_i * 7 * 24 * 60 * 60)
  end

  Nokogiri::HTML(open("http://ws.audioscrobbler.com/2.0/?method=user.getweeklychartlist&user=#{username}&api_key=97fbd8d870b557fa50abafaa179276f5")).search('weeklychartlist').search('chart').each do |chartinfo|
    from = chartinfo['from']
    to = chartinfo['to']
    time = Time.at(from.to_i)
    timeTo = Time.at(to.to_i) 
    if period == "overall" || timeTo >= startTime
      puts "Getting listening data for week of #{time.year}-#{time.month}-#{time.day}"
      # puts "http://ws.audioscrobbler.com/2.0/?method=user.getweeklytrackchart&user=#{username}&api_key=97fbd8d870b557fa50abafaa179276f5&from=#{from}&to=#{to}"
      sleep 0.1
      begin
        Nokogiri::HTML(open("http://ws.audioscrobbler.com/2.0/?method=user.getweeklytrackchart&user=#{username}&api_key=97fbd8d870b557fa50abafaa179276f5&from=#{from}&to=#{to}")).search('weeklytrackchart').search('track').each do |track|
          artist = filter_name(track.search('artist').first.content)
          name = filter_name(track.search('name').first.content)
          playcounts[artist] ||= {}
          playcounts[artist][name] ||= 0
          playcounts[artist][name] += track.search('playcount').first.content.to_i
        end
        rescue
          puts "Error getting listening data for week of #{time.year}-#{time.month}-#{time.day}"
      end
    end
  end

  puts "Saving playcount data"
  File.open(filename, "w+") do |file|
    file.puts(Marshal.dump(playcounts))
  end
end

iTunes = app('iTunes')
iTunes.tracks.get.each do |track|
  begin
    artist = playcounts[filter_name(track.artist.get)]
    if artist.nil?
      puts "Couldn't match up #{track.artist.get}" if verbose
      next
    end

    playcount = artist[filter_name(track.name.get)]
    if playcount.nil?
      puts "Couldn't match up #{track.artist.get} - #{track.name.get}" if verbose
      next
    end

    itunes_playcount = track.played_count.get

    if addpc
      new_itunes_playcount = playcount + itunes_playcount
    elsif playcount > itunes_playcount
      new_itunes_playcount = playcount
    end

    if new_itunes_playcount.nil? 
      puts "Skipping #{track.artist.get} - #{track.name.get}, new playcount smaller than existing" if verbose
    elsif (!max_playcount.nil? and new_itunes_playcount > max_playcount)
      puts "Skipping #{track.artist.get} - #{track.name.get}, new playcount #{new_itunes_playcount} > max #{max_playcount}" if verbose
    else
      puts "Setting #{track.artist.get} - #{track.name.get} playcount from #{itunes_playcount} -> #{new_itunes_playcount}"
      track.played_count.set(new_itunes_playcount) if !dryrun
    end
  rescue
    puts "Encountered some kind of error on this track"
  end
end