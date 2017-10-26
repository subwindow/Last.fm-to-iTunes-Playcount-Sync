# Last.fm to iTunes Play Count Sync

## About

This is a simple script to sync your playcount data from Last.fm to iTunes.

Say you've moved to a new laptop and didn't move your iTunes Library data over. Or, you've had to rebuild your iTunes library and lost your play count data. If you're like me not having correct play count data is pretty annoying.

All this tool does is grab all of your play count info from Last.fm's weekly charts, and then goes through your iTunes library and tries to match each track to a Last.fm play count. It isn't all that smart, so you may have to go through and change the names of some tracks to match what Last.fm has. Other than that, it seems to work pretty well.

Added bonus: Look at iTunes while the script is running and see the play counts update live. Pretty damn cool, eh?

## Prerequisites

* OS X >= 10.11
* Ruby ~2.x

## Usage

```
bundle install
bundle exec ruby lastfm2itunes.rb -u (your Last.fm username)
# Example:
bundle exec ruby lastfm2itunes.rb -u praetorian42

# Example with dry run and add playcounts of the last 4 weeks:
bundle exec ruby lastfm2itunes.rb -u praetorian42 -n -a -w 4

# See help for all options:
bundle exec ruby lastfm2itunes.rb -h
```

Note that the script will cache the listening data as a marshalled hash in case you need to re-run the script to fix naming issues, or if you just want to play around with the listening data, which is easy: `Marshal.load(File.read("cached_lastfm_data.rbmarshal"))`

Note: Tested with ruby 2.4.2 and updated Last.fm API on OSX 10.12.6

Note: Make sure to delete the cache files (*.rbmarshal) when you want to update with fresh data.

As always, if you find any bugs: fork, fix and send a pull request. Any updates / modifications are appreciated.
