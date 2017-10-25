# coding: UTF-8
# This is a tiny utility script to update your iTunes Library's played counts to match your last.fm listening data
#  This is useful if you've had to rebuild your library for any reason.
#  The utility only updates tracks for which the last.fm play count is greater than the iTunes play count.
# Because of how cool the AppleScript hooks are, watch your iTunes libary as this script works!

require 'open-uri'
require 'optparse'
require 'nokogiri'
require 'rb-scpt'
require 'unidecoder'


class Util
  # Normalize artist names the best we can (For instance, "Bjork" vs "Björk",
  # "The Beatles" vs "Beatles")
  def self.filter_name(name)
    name = name.force_encoding("utf-8").to_ascii
    return name.downcase.gsub(/^the /, "").gsub(/ the$/, "").gsub(/[^\w]/, "")
  end
end

class Fetcher
  API_KEY = "97fbd8d870b557fa50abafaa179276f5"
  API_URL = "http://ws.audioscrobbler.com/2.0/"

  attr_accessor :username,
    :period,
    :verbose

  def initialize(username=nil, period="overall", verbose=false)
    self.username = username
    self.period = period
    self.verbose = verbose
  end

  # Fetch last.fm play count data
  def fetch
    puts "No username given" and return unless username

    filename = "cached_lastfm_data.#{period}.rbmarshal"
    begin
      playcounts = Marshal.load(File.read(filename))

      puts "Reading cached playcount data from disk"
    rescue
      puts "No cached playcount data, grabbing fresh data from Last.fm"
      playcounts = {}

      now_time = Time.now
      if period != "overall"
        start_time = now_time - (period.to_i * 7 * 24 * 60 * 60)
      end

      puts "Fetching #{list_url}" if verbose
      charts = Nokogiri::HTML(open(list_url)).
        search('weeklychartlist').
        search('chart')

      charts.each do |chartinfo|
        from = chartinfo['from']
        to = chartinfo['to']
        time = Time.at(from.to_i)
        time_to = Time.at(to.to_i)
        if period == "overall" || time_to >= start_time
          puts "Getting listening data for week of #{time.year}-#{time.month}-#{time.day}"
          sleep 0.1
          begin
            chart_url = chart_url(from, to)
            puts "Fetching #{chart_url}" if verbose
            tracks = Nokogiri::HTML(open(chart_url)).
              search('weeklytrackchart').
              search('track')

            tracks.each do |track|
              artist = Util.filter_name(track.search('artist').first.content)
              name = Util.filter_name(track.search('name').first.content)
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

    return playcounts
  end

  def chart_url(from, to)
    "#{API_URL}?method=user.getweeklytrackchart&user=#{username}&api_key=#{API_KEY}&from=#{from}&to=#{to}"
  end

  def list_url
    "#{API_URL}?method=user.getweeklychartlist&user=#{username}&api_key=#{API_KEY}"
  end
end

class Syncer
  attr_accessor :addpc,
    :dry_run,
    :max_play_count,
    :verbose

  def initialize(max_play_count=1000, addpc=false, dry_run=false, verbose=false)
    self.addpc = addpc
    self.dry_run = dry_run
    self.verbose = verbose
    self.max_play_count = max_play_count
  end

  # Sync play count data to iTunes
  def sync(playcounts)
    iTunes = Appscript.app('iTunes')
    iTunes.tracks.get.each do |track|
      begin
        artist = playcounts[Util.filter_name(track.artist.get)]
        if artist.nil?
          puts "Couldn't match up #{track.artist.get}" if verbose
          next
        end

        playcount = artist[Util.filter_name(track.name.get)]
        if playcount.nil?
          if verbose
            puts "Couldn't match up #{track.artist.get} - #{track.name.get}"
          end

          next
        end

        itunes_playcount = track.played_count.get || 0

        if addpc
          new_itunes_playcount = playcount + itunes_playcount
        elsif playcount > itunes_playcount
          new_itunes_playcount = playcount
        end

        if new_itunes_playcount.nil?
          if verbose
            puts "Skipping #{track.artist.get} - \"#{track.name.get}\", new playcount smaller than existing"
          end
        elsif (max_play_count > 0 && new_itunes_playcount > max_play_count)
          if verbose
            puts "Skipping #{track.artist.get} - \"#{track.name.get}\", new playcount #{new_itunes_playcount} > max #{max_play_count}"
          end
        else
          if verbose
            puts "Setting #{track.artist.get} - \"#{track.name.get}\" playcount from #{itunes_playcount} -> #{new_itunes_playcount}"
          end
          track.played_count.set(new_itunes_playcount) unless dry_run
        end
      rescue SystemExit, Interrupt
        raise
      rescue Exception => e
        puts "Encountered some kind of error on this track: #{e}: #{e.message}"
      end
    end
  end
end

if $0 == __FILE__
  syncer = Syncer.new
  fetcher = Fetcher.new

  opt_parser = OptionParser.new do |opts|
    opts.banner = "Usage: lastfm2itunes.rb [options]"
    opts.on('-u', '--username USERNAME', 'The Last.fm username') do |u|
      unless u.to_s.strip.empty?
        fetcher.username = u
      else
        puts opts
        exit
      end
    end
    opts.on('-p', '--period WEEKS', 'Only fetch last.fm playcounts of the last WEEKS weeks') do |p|
      if /\A\d+\z/.match(p)
        fetcher.period = p
      else
        puts opts
        exit
      end
    end
    opts.on('-m', '--max-playcount MAX', 'Do not set new playcount if greater than MAX') do |m|
      if /\A\d+\z/.match(m)
        syncer.max_play_count = m.to_i
      else
        puts opts
        exit
      end
    end
    opts.on('-a', '--addpc', 'Add to playcount instead of replace') do |a|
      syncer.addpc = a
    end
    opts.on('-d', '--dry-run', 'Run without actually updating itunes') do |d|
      syncer.dry_run = d
    end
    opts.on('-v', '--verbose', 'Be verbose') do |v|
      syncer.verbose = v
      fetcher.verbose = v
    end
    opts.on("-h", "--help", "Prints this help") do
      puts opts
      exit
    end
  end

  opt_parser.parse!

  if fetcher.username.nil? || fetcher.username == ""
    opt_parser.parse! %w[--help]
    exit
  end

  playcounts = fetcher.fetch
  syncer.sync(playcounts)
end
